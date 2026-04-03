{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Server.Auth (
  authServerImpl,
) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy.Char8 as LBS8
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Katip (LogEnv)
import Servant

import API.Auth
import Auth.Session (
  SessionContext (..),
  resolveSession,
 )
import DB.Auth
import DB.Database (DBPool)
import DB.Schema (
  UserRow (..),
  displayName,
  email,
  isActive,
  userId,
  userName,
  userRole,
 )
import Data.Time (NominalDiffTime)
import Logging (logAppInfo, logAuthDenied)
import Rel8 (Result)
import Types.Auth (
  AuthenticatedUser (..),
  SessionResponse (..),
  UserRole (..),
  capCanManageUsers,
  capabilitiesForRole,
 )

{- | Thresholds for login rate limiting.
Per username+IP: blocks credential stuffing against a single account.
Per IP: blocks an attacker who rotates across multiple usernames from the
same source address to stay under the per-credential limit.
-}
perCredentialLimit :: Int
perCredentialLimit = 5

perIpLimit :: Int
perIpLimit = 20

rateLimitWindow :: NominalDiffTime
rateLimitWindow = 10 * 60 -- 10 minutes

checkLoginRateLimit :: DBPool -> Text -> Text -> Handler ()
checkLoginRateLimit pool username ip = do
  credentialCount <- liftIO $ recentFailedAttempts pool username ip rateLimitWindow
  if credentialCount >= perCredentialLimit
    then
      throwError
        err429
          { errBody = LBS8.pack "Too many failed login attempts. Try again in 10 minutes."
          , errHeaders = [("Retry-After", "600")]
          }
    else do
      ipCount <- liftIO $ recentFailedAttemptsByIp pool ip rateLimitWindow
      when (ipCount >= perIpLimit) $
        throwError
          err429
            { errBody = LBS8.pack "Too many failed login attempts from this address. Try again in 10 minutes."
            , errHeaders = [("Retry-After", "600")]
            }

userRowToSummary :: UserRow Result -> UserSummary
userRowToSummary row =
  UserSummary
    { summaryId = userId row
    , summaryUsername = userName row
    , summaryDisplayName = displayName row
    , summaryEmail = email row
    , summaryRole = parseRoleText (userRole row)
    , summaryIsActive = isActive row
    }

parseRoleText :: Text -> UserRole
parseRoleText "Customer" = Customer
parseRoleText "Cashier" = Cashier
parseRoleText "Manager" = Manager
parseRoleText "Admin" = Admin
parseRoleText _ = Cashier

loginHandler ::
  DBPool ->
  LogEnv ->
  Maybe Text ->
  Maybe Text ->
  LoginRequest ->
  Handler LoginResponse
loginHandler pool logEnv mUA mIP req = do
  let
    username = loginUsername req
    ua = fromMaybe "unknown" mUA
    ip = fromMaybe "unknown" mIP

  checkLoginRateLimit pool username ip

  mUser <- liftIO $ lookupUserByUsername pool username
  case mUser of
    Nothing -> do
      liftIO $ recordLoginAttempt pool username ip False
      liftIO $ logAuthDenied logEnv username "user not found"
      throwError err401 {errBody = LBS8.pack "Invalid username or password"}
    Just userRow -> do
      let storedHash = passwordHash userRow
      if not (verifyPassword storedHash (loginPassword req))
        then do
          liftIO $ recordLoginAttempt pool username ip False
          liftIO $ logAuthDenied logEnv username "wrong password"
          throwError err401 {errBody = LBS8.pack "Invalid username or password"}
        else do
          let uid = userId userRow
          (token, expiresAt) <-
            liftIO $
              createSession pool uid (loginRegisterId req) ua ip
          liftIO $ recordLoginAttempt pool username ip True
          liftIO $
            logAppInfo logEnv $
              "Login success username=" <> username <> " ip=" <> ip
          let authedUser = userRowToAuthUser userRow
          pure
            LoginResponse
              { loginToken = token
              , loginExpiresAt = expiresAt
              , loginUser =
                  SessionResponse
                    { sessionUserId = auUserId authedUser
                    , sessionUserName = auUserName authedUser
                    , sessionRole = auRole authedUser
                    , sessionCapabilities = capabilitiesForRole (auRole authedUser)
                    }
              }

logoutHandler ::
  DBPool ->
  LogEnv ->
  Maybe Text ->
  Handler NoContent
logoutHandler pool logEnv mHeader = do
  ctx <- resolveSession pool mHeader
  liftIO $ revokeSession pool (scSessionId ctx) Nothing
  liftIO $
    logAppInfo logEnv $
      "Logout userId=" <> T.pack (show (auUserId (scUser ctx)))
  pure NoContent

meHandler ::
  DBPool ->
  Maybe Text ->
  Handler SessionResponse
meHandler pool mHeader = do
  ctx <- resolveSession pool mHeader
  let u = scUser ctx
  pure
    SessionResponse
      { sessionUserId = auUserId u
      , sessionUserName = auUserName u
      , sessionRole = auRole u
      , sessionCapabilities = capabilitiesForRole (auRole u)
      }

listUsersHandler ::
  DBPool ->
  LogEnv ->
  Maybe Text ->
  Handler [UserSummary]
listUsersHandler pool logEnv mHeader = do
  ctx <- resolveSession pool mHeader
  let caps = capabilitiesForRole (auRole (scUser ctx))
  if not (capCanManageUsers caps)
    then do
      liftIO $
        logAuthDenied
          logEnv
          (T.pack (show (auUserId (scUser ctx))))
          "capCanManageUsers"
      throwError err403 {errBody = LBS8.pack "Forbidden: manage users"}
    else
      pure []

createUserHandler ::
  DBPool ->
  LogEnv ->
  Maybe Text ->
  NewUserRequest ->
  Handler UserSummary
createUserHandler pool logEnv mHeader req = do
  ctx <- resolveSession pool mHeader
  let caps = capabilitiesForRole (auRole (scUser ctx))
  if not (capCanManageUsers caps)
    then do
      liftIO $
        logAuthDenied
          logEnv
          (T.pack (show (auUserId (scUser ctx))))
          "capCanManageUsers"
      throwError err403 {errBody = LBS8.pack "Forbidden: manage users"}
    else do
      uid <-
        liftIO $
          createUser
            pool
            NewUser
              { newUserName = newReqUsername req
              , newDisplayName = newReqDisplayName req
              , newEmail = newReqEmail req
              , newRole = newReqRole req
              , newLocationId = newReqLocationId req
              , newPassword = newReqPassword req
              }
      liftIO $
        logAppInfo logEnv $
          "User created id="
            <> T.pack (show uid)
            <> " by="
            <> T.pack (show (auUserId (scUser ctx)))

      mRow <- liftIO $ lookupUserByUsername pool (newReqUsername req)
      case mRow of
        Nothing ->
          throwError
            err500
              { errBody = LBS8.pack "User created but could not be fetched"
              }
        Just row -> pure (userRowToSummary row)

authServerImpl :: DBPool -> LogEnv -> Server AuthAPI
authServerImpl pool logEnv =
  loginHandler pool logEnv
    :<|> logoutHandler pool logEnv
    :<|> meHandler pool
    :<|> listUsersHandler pool logEnv
    :<|> createUserHandler pool logEnv
