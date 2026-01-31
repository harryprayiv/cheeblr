{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}
-- {-# LANGUAGE TypeOperators #-}

module Auth.Simple 
  ( AuthHeader
  , lookupUser
  , requireAuth
  , devUsers
  , getDevUser
  ) where

import Data.Text (Text)
-- import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
-- import Data.UUID (UUID)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.ByteString.Lazy as LBS
import Servant
import Types.Auth

-- | Simple auth header - in production, this would be a JWT
type AuthHeader = Header "X-User-Id" Text

-- | Development users for testing different roles
devUsers :: Map Text AuthenticatedUser
devUsers = Map.fromList
  [ ("customer-1", AuthenticatedUser
      { auUserId = read "11111111-1111-1111-1111-111111111111"
      , auUserName = "Test Customer"
      , auEmail = Just "customer@test.com"
      , auRole = Customer
      , auLocationId = Nothing
      , auCreatedAt = read "2024-01-01 00:00:00 UTC"
      })
  , ("Cashier-1", AuthenticatedUser
      { auUserId = read "22222222-2222-2222-2222-222222222222"
      , auUserName = "Test Cashier"
      , auEmail = Just "Cashier@test.com"
      , auRole = Cashier
      , auLocationId = Just (read "b2bd4b3a-d50f-4c04-90b1-01266735876b")
      , auCreatedAt = read "2024-01-01 00:00:00 UTC"
      })
  , ("manager-1", AuthenticatedUser
      { auUserId = read "33333333-3333-3333-3333-333333333333"
      , auUserName = "Test Manager"
      , auEmail = Just "manager@test.com"
      , auRole = Manager
      , auLocationId = Just (read "b2bd4b3a-d50f-4c04-90b1-01266735876b")
      , auCreatedAt = read "2024-01-01 00:00:00 UTC"
      })
  , ("admin-1", AuthenticatedUser
      { auUserId = read "44444444-4444-4444-4444-444444444444"
      , auUserName = "Test Admin"
      , auEmail = Just "admin@test.com"
      , auRole = Admin
      , auLocationId = Nothing  -- Admin can see all locations
      , auCreatedAt = read "2024-01-01 00:00:00 UTC"
      })
  ]

-- | Default dev user (for when no header is provided)
defaultDevUser :: AuthenticatedUser
defaultDevUser = devUsers Map.! "Cashier-1"

-- | Look up a user by their ID header value
lookupUser :: Maybe Text -> AuthenticatedUser
lookupUser Nothing = defaultDevUser
lookupUser (Just userId) = 
  Map.findWithDefault defaultDevUser userId devUsers

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