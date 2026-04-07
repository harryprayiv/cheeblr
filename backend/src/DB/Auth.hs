{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module DB.Auth (
  NewUser (..),
  SessionToken,
  createAuthTables,
  createUser,
  lookupUserByUsername,
  createSession,
  lookupSession,
  revokeSession,
  revokeAllUserSessions,
  recordLoginAttempt,
  recentFailedAttempts,
  recentFailedAttemptsByIp,
  hashPassword,
  verifyPassword,
  userRowToAuthUser,
  listActiveSessions,
  getSessionById,
  clearRateLimitForIp,
  getSessionRotatedAt,
  rotateSessionToken,
  cleanupExpiredSessions,
) where

import Crypto.Error (
  CryptoFailable (..),
  throwCryptoErrorIO,
 )
import qualified Crypto.Hash as CH
import qualified Crypto.KDF.Argon2 as Argon2
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (
  Base (Base16, Base64),
  convertFromBase,
  convertToBase,
 )
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64.URL as B64U
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (
  NominalDiffTime,
  UTCTime,
  addUTCTime,
  getCurrentTime,
 )
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import qualified Hasql.Session as Session
import Rel8
import System.Entropy (getEntropy)

import DB.Database (DBPool, ddl, runSession)
import DB.Schema
import Types.Auth (
  AuthenticatedUser (..),
  UserRole (..),
  parseUserRole,
 )
import Types.Location (
  LocationId (..),
  locationIdToUUID,
 )

data NewUser = NewUser
  { newUserName    :: Text
  , newDisplayName :: Text
  , newEmail       :: Maybe Text
  , newRole        :: UserRole
  , newLocationId  :: Maybe LocationId
  , newPassword    :: Text
  }

type SessionToken = Text

argonOpts :: Argon2.Options
argonOpts =
  Argon2.Options
    { Argon2.iterations  = 3
    , Argon2.memory      = 65536
    , Argon2.parallelism = 4
    , Argon2.variant     = Argon2.Argon2id
    , Argon2.version     = Argon2.Version13
    }

argonOutputLen :: Int
argonOutputLen = 32

b64Enc :: ByteString -> Text
b64Enc = T.dropWhileEnd (== '=') . TE.decodeUtf8 . convertToBase Base64

b64Dec :: Text -> Either String ByteString
b64Dec t =
  let padded = T.unpack t <> replicate ((4 - T.length t `mod` 4) `mod` 4) '='
   in convertFromBase Base64 (TE.encodeUtf8 (T.pack padded))

buildPHC :: ByteString -> ByteString -> Text
buildPHC salt h =
  T.concat
    [ "$argon2id$v=19$m="
    , T.pack (show (Argon2.memory argonOpts))
    , ",t="
    , T.pack (show (Argon2.iterations argonOpts))
    , ",p="
    , T.pack (show (Argon2.parallelism argonOpts))
    , "$"
    , b64Enc salt
    , "$"
    , b64Enc h
    ]

hashPassword :: Text -> IO Text
hashPassword plaintext = do
  salt <- getEntropy 16
  let pw = TE.encodeUtf8 plaintext
  hashBytes <-
    throwCryptoErrorIO
      (Argon2.hash argonOpts pw salt argonOutputLen :: CryptoFailable ByteString)
  pure $ buildPHC salt hashBytes

verifyPassword :: Text -> Text -> Bool
verifyPassword stored plaintext =
  case T.splitOn "$" stored of
    ["", "argon2id", _v, _params, b64Salt, b64Hash] ->
      case (b64Dec b64Salt, b64Dec b64Hash) of
        (Right salt, Right expected) ->
          let pw = TE.encodeUtf8 plaintext
           in case (Argon2.hash argonOpts pw salt argonOutputLen :: CryptoFailable ByteString) of
                CryptoPassed derived -> (derived :: ByteString) == expected
                CryptoFailed _       -> False
        _ -> False
    _ -> False

hashTokenBytes :: ByteString -> Text
hashTokenBytes raw =
  let digest = CH.hash raw :: CH.Digest CH.SHA256
   in TE.decodeUtf8 $ convertToBase Base16 (convert digest :: ByteString)

encodeTokenBytes :: ByteString -> Text
encodeTokenBytes =
  T.dropWhileEnd (== '=') . TE.decodeUtf8 . B64U.encode

decodeTokenText :: Text -> Either String ByteString
decodeTokenText t =
  let padded = T.unpack t <> replicate ((4 - T.length t `mod` 4) `mod` 4) '='
   in B64U.decode (TE.encodeUtf8 (T.pack padded))

-- | Convert a DB user row to the domain AuthenticatedUser.
-- Uses Types.Auth.parseUserRole (the single canonical parser) instead of a
-- local duplicate.
userRowToAuthUser :: UserRow Result -> AuthenticatedUser
userRowToAuthUser row =
  AuthenticatedUser
    { auUserId     = userId row
    , auUserName   = displayName row
    , auEmail      = email row
    , auRole       = parseUserRole (userRole row)
    , auLocationId = fmap LocationId (userLocationId row)
    , auCreatedAt  = userCreatedAt row
    }

createAuthTables :: DBPool -> IO ()
createAuthTables pool = runSession pool $ do
  Session.statement () $
    ddl
      "CREATE TABLE IF NOT EXISTS users (\
      \  id            UUID PRIMARY KEY,\
      \  username      TEXT NOT NULL UNIQUE,\
      \  display_name  TEXT NOT NULL,\
      \  email         TEXT,\
      \  role          TEXT NOT NULL,\
      \  location_id   UUID,\
      \  password_hash TEXT NOT NULL,\
      \  is_active     BOOLEAN NOT NULL DEFAULT TRUE,\
      \  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
      \  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()\
      \)"
  Session.statement () $
    ddl
      "CREATE TABLE IF NOT EXISTS sessions (\
      \  id               UUID PRIMARY KEY,\
      \  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,\
      \  token_hash       TEXT NOT NULL UNIQUE,\
      \  register_id      UUID,\
      \  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
      \  last_seen_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),\
      \  expires_at       TIMESTAMPTZ NOT NULL,\
      \  revoked          BOOLEAN NOT NULL DEFAULT FALSE,\
      \  revoked_at       TIMESTAMPTZ,\
      \  revoked_by       UUID REFERENCES users(id),\
      \  user_agent       TEXT,\
      \  ip_address       TEXT,\
      \  token_rotated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()\
      \)"
  Session.statement () $
    ddl
      "ALTER TABLE sessions \
      \ADD COLUMN IF NOT EXISTS \
      \token_rotated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()"
  Session.statement () $
    ddl
      "CREATE INDEX IF NOT EXISTS sessions_token_hash_idx \
      \ON sessions (token_hash) WHERE NOT revoked"
  Session.statement () $
    ddl
      "CREATE INDEX IF NOT EXISTS sessions_user_id_idx ON sessions (user_id)"
  Session.statement () $
    ddl
      "CREATE TABLE IF NOT EXISTS login_attempts (\
      \  id            UUID PRIMARY KEY,\
      \  username      TEXT NOT NULL,\
      \  ip_address    TEXT NOT NULL,\
      \  success       BOOLEAN NOT NULL,\
      \  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()\
      \)"
  Session.statement () $
    ddl
      "CREATE INDEX IF NOT EXISTS login_attempts_ip_idx \
      \ON login_attempts (ip_address, attempted_at DESC)"
  Session.statement () $
    ddl
      "CREATE INDEX IF NOT EXISTS login_attempts_username_idx \
      \ON login_attempts (username, attempted_at DESC)"

createUser :: DBPool -> NewUser -> IO UUID
createUser pool nu = do
  uid    <- nextRandom
  now    <- getCurrentTime
  hashed <- hashPassword (newPassword nu)
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = userSchema
            , rows =
                values
                  [ UserRow
                      { userId         = lit uid
                      , userName       = lit (newUserName nu)
                      , displayName    = lit (newDisplayName nu)
                      , email          = lit (newEmail nu)
                      , userRole       = lit $ T.pack $ show (newRole nu)
                      , userLocationId = lit (fmap locationIdToUUID (newLocationId nu))
                      , passwordHash   = lit hashed
                      , isActive       = lit True
                      , userCreatedAt  = lit now
                      , userUpdatedAt  = lit now
                      }
                  ]
            , onConflict = Abort
            , returning  = NoReturning
            }
  pure uid

lookupUserByUsername :: DBPool -> Text -> IO (Maybe (UserRow Result))
lookupUserByUsername pool username = do
  userRows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    u <- each userSchema
    where_ $ userName u ==. lit username &&. isActive u
    pure u
  case userRows of
    [u] -> pure (Just u)
    _   -> pure Nothing

createSession ::
  DBPool ->
  UUID ->
  Maybe UUID ->
  Text ->
  Text ->
  IO (SessionToken, UTCTime)
createSession pool uid mRegisterId ua ip = do
  sid <- nextRandom
  now <- getCurrentTime
  raw <- getEntropy 32
  let
    tokenText = encodeTokenBytes raw
    tHash     = hashTokenBytes raw
    expiresAt = addUTCTime (8 * 3600) now
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = sessionSchema
            , rows =
                values
                  [ SessionRow
                      { sessId             = lit sid
                      , sessUserId         = lit uid
                      , sessTokenHash      = lit tHash
                      , sessRegisterId     = lit mRegisterId
                      , sessCreatedAt      = lit now
                      , sessLastSeenAt     = lit now
                      , sessExpiresAt      = lit expiresAt
                      , sessRevoked        = lit False
                      , sessRevokedAt      = lit Nothing
                      , sessRevokedBy      = lit Nothing
                      , sessUserAgent      = lit (Just ua)
                      , sessIpAddress      = lit (Just ip)
                      , sessTokenRotatedAt = lit now
                      }
                  ]
            , onConflict = Abort
            , returning  = NoReturning
            }
  pure (tokenText, expiresAt)

lookupSession ::
  DBPool ->
  Text ->
  IO (Maybe (SessionRow Result, UserRow Result))
lookupSession pool rawToken = do
  now <- getCurrentTime
  case decodeTokenText rawToken of
    Left _ -> pure Nothing
    Right raw -> do
      let tHash = hashTokenBytes raw
      sessRows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
        sess <- each sessionSchema
        user <- each userSchema
        where_ $
          sessTokenHash sess ==. lit tHash
            &&. sessUserId sess ==. userId user
            &&. Rel8.not_ (sessRevoked sess)
            &&. sessExpiresAt sess >. lit now
            &&. isActive user
        pure (sess, user)
      case sessRows of
        [(sess, user)] -> do
          runSession pool $
            Session.statement () $
              run_ $
                Rel8.update $
                  Update
                    { target      = sessionSchema
                    , from        = pure ()
                    , set         = \() row -> row {sessLastSeenAt = lit now}
                    , updateWhere = \() row -> sessTokenHash row ==. lit tHash
                    , returning   = NoReturning
                    }
          pure (Just (sess, user))
        _ -> pure Nothing

getSessionRotatedAt :: DBPool -> Text -> IO (Maybe (UUID, UTCTime))
getSessionRotatedAt pool rawToken = do
  now <- getCurrentTime
  case decodeTokenText rawToken of
    Left _ -> pure Nothing
    Right raw -> do
      let tHash = hashTokenBytes raw
      rotRows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
        sess <- each sessionSchema
        where_ $
          sessTokenHash sess ==. lit tHash
            &&. Rel8.not_ (sessRevoked sess)
            &&. sessExpiresAt sess >. lit now
        pure (sessId sess, sessTokenRotatedAt sess)
      case rotRows of
        [(sid, rotatedAt)] -> pure (Just (sid, rotatedAt))
        _                  -> pure Nothing

rotateSessionToken :: DBPool -> UUID -> IO (SessionToken, UTCTime)
rotateSessionToken pool sid = do
  now <- getCurrentTime
  raw <- getEntropy 32
  let
    tokenText = encodeTokenBytes raw
    tHash     = hashTokenBytes raw
    expiresAt = addUTCTime (8 * 3600) now
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = sessionSchema
            , from   = pure ()
            , set    = \() row ->
                row
                  { sessTokenHash      = lit tHash
                  , sessExpiresAt      = lit expiresAt
                  , sessTokenRotatedAt = lit now
                  , sessLastSeenAt     = lit now
                  }
            , updateWhere = \() row -> sessId row ==. lit sid
            , returning   = NoReturning
            }
  pure (tokenText, expiresAt)

cleanupExpiredSessions :: DBPool -> IO ()
cleanupExpiredSessions pool = runSession pool $ do
  Session.statement () $
    ddl "DELETE FROM sessions WHERE expires_at < NOW()"
  Session.statement () $
    ddl
      "DELETE FROM sessions \
      \WHERE revoked = TRUE \
      \  AND revoked_at < NOW() - INTERVAL '24 hours'"

revokeSession :: DBPool -> UUID -> Maybe UUID -> IO ()
revokeSession pool sid mRevokedBy = do
  now <- getCurrentTime
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = sessionSchema
            , from   = pure ()
            , set    = \() row ->
                row
                  { sessRevoked   = lit True
                  , sessRevokedAt = lit (Just now)
                  , sessRevokedBy = lit mRevokedBy
                  }
            , updateWhere = \() row -> sessId row ==. lit sid
            , returning   = NoReturning
            }

revokeAllUserSessions :: DBPool -> UUID -> IO ()
revokeAllUserSessions pool uid = do
  now <- getCurrentTime
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = sessionSchema
            , from   = pure ()
            , set    = \() row ->
                row
                  { sessRevoked   = lit True
                  , sessRevokedAt = lit (Just now)
                  }
            , updateWhere = \() row ->
                sessUserId row ==. lit uid
                  &&. Rel8.not_ (sessRevoked row)
            , returning = NoReturning
            }

recordLoginAttempt :: DBPool -> Text -> Text -> Bool -> IO ()
recordLoginAttempt pool username ip success = do
  aid <- nextRandom
  now <- getCurrentTime
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = loginAttemptSchema
            , rows =
                values
                  [ LoginAttemptRow
                      { attemptId        = lit aid
                      , attemptUsername  = lit username
                      , attemptIpAddress = lit ip
                      , attemptSuccess   = lit success
                      , attemptedAt      = lit now
                      }
                  ]
            , onConflict = Abort
            , returning  = NoReturning
            }

recentFailedAttempts :: DBPool -> Text -> Text -> NominalDiffTime -> IO Int
recentFailedAttempts pool username ip windowSecs = do
  now <- getCurrentTime
  let cutoff = addUTCTime (negate windowSecs) now
  rowses <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    a <- each loginAttemptSchema
    where_ $
      attemptUsername a ==. lit username
        &&. attemptIpAddress a ==. lit ip
        &&. Rel8.not_ (attemptSuccess a)
        &&. attemptedAt a >. lit cutoff
    pure a
  pure (length rowses)

recentFailedAttemptsByIp :: DBPool -> Text -> NominalDiffTime -> IO Int
recentFailedAttemptsByIp pool ip windowSecs = do
  now <- getCurrentTime
  let cutoff = addUTCTime (negate windowSecs) now
  rowses <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    a <- each loginAttemptSchema
    where_ $
      attemptIpAddress a ==. lit ip
        &&. Rel8.not_ (attemptSuccess a)
        &&. attemptedAt a >. lit cutoff
    pure a
  pure (length rowses)

getSessionById :: DBPool -> UUID -> IO (Maybe (SessionRow Result))
getSessionById pool sid = do
  sessRows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    sess <- each sessionSchema
    where_ $ sessId sess ==. lit sid
    pure sess
  case sessRows of
    [s] -> pure (Just s)
    _   -> pure Nothing

listActiveSessions :: DBPool -> IO [(SessionRow Result, UserRow Result)]
listActiveSessions pool = do
  now <- getCurrentTime
  runSession pool $ Session.statement () $ run $ Rel8.select $ do
    sess <- each sessionSchema
    user <- each userSchema
    where_ $
      sessUserId sess ==. userId user
        &&. Rel8.not_ (sessRevoked sess)
        &&. sessExpiresAt sess >. lit now
        &&. isActive user
    pure (sess, user)

clearRateLimitForIp :: DBPool -> Text -> IO ()
clearRateLimitForIp pool ip =
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.delete $
          Delete
            { from        = loginAttemptSchema
            , using       = pure ()
            , deleteWhere = \() row -> attemptIpAddress row ==. lit ip
            , returning   = NoReturning
            }