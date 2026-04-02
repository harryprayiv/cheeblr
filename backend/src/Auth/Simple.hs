{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}

module Auth.Simple
  ( AuthHeader
  , lookupUser
  , requireAuth
  , devUsers
  , getDevUser
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe
import qualified Data.ByteString.Lazy as LBS
import Servant
import Types.Auth
import Types.Location (LocationId (..))

-- | Simple auth header - in production, this would be a JWT
type AuthHeader = Header "X-User-Id" Text

-- | Development users for testing different roles
-- UUIDs match frontend Config/Auth.purs dev users
devUsers :: Map Text AuthenticatedUser
devUsers = Map.fromList
  [ ("customer-1", AuthenticatedUser
      { auUserId     = read "8244082f-a6bc-4d6c-9427-64a0ecdc10db"
      , auUserName   = "Test Customer"
      , auEmail      = Just "customer@example.com"
      , auRole       = Customer
      , auLocationId = Nothing
      , auCreatedAt  = read "2024-01-01 00:00:00 UTC"
      })
  , ("cashier-1", AuthenticatedUser
      { auUserId     = read "0a6f2deb-892b-4411-8025-08c1a4d61229"
      , auUserName   = "Test Cashier"
      , auEmail      = Just "cashier@example.com"
      , auRole       = Cashier
      , auLocationId = Just (LocationId (read "b2bd4b3a-d50f-4c04-90b1-01266735876b"))
      , auCreatedAt  = read "2024-01-01 00:00:00 UTC"
      })
  , ("manager-1", AuthenticatedUser
      { auUserId     = read "8b75ea4a-00a4-4a2a-a5d5-a1bab8883802"
      , auUserName   = "Test Manager"
      , auEmail      = Just "manager@example.com"
      , auRole       = Manager
      , auLocationId = Just (LocationId (read "b2bd4b3a-d50f-4c04-90b1-01266735876b"))
      , auCreatedAt  = read "2024-01-01 00:00:00 UTC"
      })
  , ("admin-1", AuthenticatedUser
      { auUserId     = read "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
      , auUserName   = "Test Admin"
      , auEmail      = Just "admin@example.com"
      , auRole       = Admin
      , auLocationId = Nothing
      , auCreatedAt  = read "2024-01-01 00:00:00 UTC"
      })
  ]

-- | Map from UUID string to user, for when frontend sends UUID as X-User-Id
devUsersByUUID :: Map Text AuthenticatedUser
devUsersByUUID = Map.fromList
  [ ("8244082f-a6bc-4d6c-9427-64a0ecdc10db", devUsers Map.! "customer-1")
  , ("0a6f2deb-892b-4411-8025-08c1a4d61229", devUsers Map.! "cashier-1")
  , ("8b75ea4a-00a4-4a2a-a5d5-a1bab8883802", devUsers Map.! "manager-1")
  , ("d3a1f4f0-c518-4db3-aa43-e80b428d6304", devUsers Map.! "admin-1")
  ]

-- | Default dev user (for when no header is provided)
-- Note: key must match exactly (case-sensitive) — "cashier-1" not "Cashier-1"
defaultDevUser :: AuthenticatedUser
defaultDevUser = devUsers Map.! "cashier-1"

-- | Look up a user by their ID header value
-- Supports both name-based ("cashier-1") and UUID-based ("0a6f2deb-...") lookup
lookupUser :: Maybe Text -> AuthenticatedUser
lookupUser Nothing = defaultDevUser
lookupUser (Just userId) =
  -- Try name-based lookup first, then UUID-based, then fall back to default
  case Map.lookup (T.toLower userId) devUsers of
    Just user -> user
    Nothing -> Data.Maybe.fromMaybe defaultDevUser (Map.lookup userId devUsersByUUID)

-- | Get a specific dev user by key
getDevUser :: Text -> Maybe AuthenticatedUser
getDevUser = flip Map.lookup devUsers

-- | Require authentication and a specific capability
requireAuth
  :: Maybe Text
  -> (UserCapabilities -> Bool)
  -> Text
  -> Handler AuthenticatedUser
requireAuth mUserId capCheck errMsg = do
  let user = lookupUser mUserId
  let caps = capabilitiesForRole (auRole user)
  if capCheck caps
    then return user
    else throwError err403 { errBody = LBS.fromStrict $ TE.encodeUtf8 $ "Forbidden: " <> errMsg }