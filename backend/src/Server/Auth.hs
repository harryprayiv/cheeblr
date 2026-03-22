{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Server.Auth
  ( authServerImpl
  ) where

import qualified Data.ByteString.Lazy.Char8 as LBS8
import           Data.Maybe                 (fromMaybe)
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import           Control.Monad.IO.Class     (liftIO)
import           Katip                      (LogEnv)
import           Servant

import           API.Auth
import           Auth.Session               (SessionContext (..),
                                             resolveSession)
import           DB.Auth
import           DB.Database                (DBPool)
import           Rel8                       (Result)
import           DB.Schema                  (UserRow (..),
                                             isActive, userId, userName,
                                             displayName, email, userRole)
import           Logging                    (logAuthDenied, logAppInfo)
import           Types.Auth
  ( AuthenticatedUser (..)
  
  , UserRole (..)
  , SessionResponse (..)
  , capabilitiesForRole
  , capCanManageUsers
  )

------------------------------------------------------------------------
-- Rate limit check
------------------------------------------------------------------------

-- 5 failures per 10 minutes per (username, IP) pair.
checkLoginRateLimit :: DBPool -> Text -> Text -> Handler ()
checkLoginRateLimit pool username ip = do
  failedCount <- liftIO $ recentFailedAttempts pool username ip (10 * 60)
  if failedCount >= 5
    then throwError err429
      { errBody    = LBS8.pack "Too many failed login attempts. Try again in 10 minutes."
      , errHeaders = [("Retry-After", "600")]
      }
    else pure ()

------------------------------------------------------------------------
-- Row to API type conversions
------------------------------------------------------------------------

userRowToSummary :: UserRow Result -> UserSummary
userRowToSummary row = UserSummary
  { summaryId          = userId row
  , summaryUsername    = userName row
  , summaryDisplayName = displayName row
  , summaryEmail       = email row
  , summaryRole        = parseRoleText (userRole row)
  , summaryIsActive    = isActive row
  }

parseRoleText :: Text -> Types.Auth.UserRole
parseRoleText "Customer" = Types.Auth.Customer
parseRoleText "Cashier"  = Types.Auth.Cashier
parseRoleText "Manager"  = Types.Auth.Manager
parseRoleText "Admin"    = Types.Auth.Admin
parseRoleText _          = Types.Auth.Cashier

------------------------------------------------------------------------
-- Handlers
------------------------------------------------------------------------

loginHandler
  :: DBPool
  -> LogEnv
  -> Maybe Text   -- User-Agent header
  -> Maybe Text   -- X-Real-IP header
  -> LoginRequest
  -> Handler LoginResponse
loginHandler pool logEnv mUA mIP req = do
  let username = loginUsername req
      ua       = fromMaybe "unknown" mUA
      ip       = fromMaybe "unknown" mIP

  -- Rate limit check before touching the password.
  checkLoginRateLimit pool username ip

  -- Look up user. Use the same error for "not found" and "wrong password"
  -- to avoid username enumeration.
  mUser <- liftIO $ lookupUserByUsername pool username
  case mUser of
    Nothing -> do
      liftIO $ recordLoginAttempt pool username ip False
      liftIO $ logAuthDenied logEnv username "user not found"
      throwError err401 { errBody = LBS8.pack "Invalid username or password" }
    Just userRow -> do
      let storedHash = passwordHash userRow
      if not (verifyPassword storedHash (loginPassword req))
        then do
          liftIO $ recordLoginAttempt pool username ip False
          liftIO $ logAuthDenied logEnv username "wrong password"
          throwError err401 { errBody = LBS8.pack "Invalid username or password" }
        else do
          let uid = userId userRow
          (token, expiresAt) <- liftIO $
            createSession pool uid (loginRegisterId req) ua ip
          liftIO $ recordLoginAttempt pool username ip True
          liftIO $ logAppInfo logEnv $
            "Login success username=" <> username <> " ip=" <> ip
          let authedUser = userRowToAuthUser userRow
          pure LoginResponse
            { loginToken     = token
            , loginExpiresAt = expiresAt
            , loginUser      = Types.Auth.SessionResponse
                { sessionUserId       = auUserId authedUser
                , sessionUserName     = auUserName authedUser
                , sessionRole         = auRole authedUser
                , sessionCapabilities = Types.Auth.capabilitiesForRole (auRole authedUser)
                }
            }

logoutHandler
  :: DBPool
  -> LogEnv
  -> Maybe Text   -- Authorization header
  -> Handler NoContent
logoutHandler pool logEnv mHeader = do
  ctx <- resolveSession pool mHeader
  liftIO $ revokeSession pool (scSessionId ctx) Nothing
  liftIO $ logAppInfo logEnv $
    "Logout userId=" <> T.pack (show (auUserId (scUser ctx)))
  pure NoContent

meHandler
  :: DBPool
  -> Maybe Text   -- Authorization header
  -> Handler Types.Auth.SessionResponse
meHandler pool mHeader = do
  ctx <- resolveSession pool mHeader
  let u = scUser ctx
  pure Types.Auth.SessionResponse
    { sessionUserId       = auUserId u
    , sessionUserName     = auUserName u
    , sessionRole         = auRole u
    , sessionCapabilities = Types.Auth.capabilitiesForRole (auRole u)
    }

listUsersHandler
  :: DBPool
  -> LogEnv
  -> Maybe Text   -- Authorization header
  -> Handler [UserSummary]
listUsersHandler pool logEnv mHeader = do
  ctx <- resolveSession pool mHeader
  let caps = Types.Auth.capabilitiesForRole (auRole (scUser ctx))
  if not (capCanManageUsers caps)
    then do
      liftIO $ logAuthDenied logEnv
        (T.pack (show (auUserId (scUser ctx)))) "capCanManageUsers"
      throwError err403 { errBody = LBS8.pack "Forbidden: manage users" }
    else do
      -- lookupUserByUsername is per-user; we need a list query.
      -- For now stub with empty list until DB.Auth.listUsers is added in a
      -- later step. The endpoint type and auth guard are what matter here.
      pure []

createUserHandler
  :: DBPool
  -> LogEnv
  -> Maybe Text      -- Authorization header
  -> NewUserRequest
  -> Handler UserSummary
createUserHandler pool logEnv mHeader req = do
  ctx <- resolveSession pool mHeader
  let caps = Types.Auth.capabilitiesForRole (auRole (scUser ctx))
  if not (capCanManageUsers caps)
    then do
      liftIO $ logAuthDenied logEnv
        (T.pack (show (auUserId (scUser ctx)))) "capCanManageUsers"
      throwError err403 { errBody = LBS8.pack "Forbidden: manage users" }
    else do
      uid <- liftIO $ createUser pool NewUser
        { newUserName    = newReqUsername req
        , newDisplayName = newReqDisplayName req
        , newEmail       = newReqEmail req
        , newRole        = newReqRole req
        , newLocationId  = newReqLocationId req
        , newPassword    = newReqPassword req
        }
      liftIO $ logAppInfo logEnv $
        "User created id=" <> T.pack (show uid)
            <> " by=" <> T.pack (show (auUserId (scUser ctx)))
      -- Return the created user. Re-fetch to get the canonical row.
      mRow <- liftIO $ lookupUserByUsername pool (newReqUsername req)
      case mRow of
        Nothing  -> throwError err500
          { errBody = LBS8.pack "User created but could not be fetched" }
        Just row -> pure (userRowToSummary row)

------------------------------------------------------------------------
-- Combined server
------------------------------------------------------------------------

authServerImpl :: DBPool -> LogEnv -> Server AuthAPI
authServerImpl pool logEnv =
       loginHandler    pool logEnv
  :<|> logoutHandler   pool logEnv
  :<|> meHandler       pool
  :<|> listUsersHandler pool logEnv
  :<|> createUserHandler pool logEnv