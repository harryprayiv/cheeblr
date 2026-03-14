{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StandaloneDeriving #-}

module Types.Auth where

import Data.Aeson (ToJSON, FromJSON)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

data UserRole
  = Customer
  | Cashier
  | Manager
  | Admin
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON UserRole
instance FromJSON UserRole

data AuthenticatedUser = AuthenticatedUser
  { auUserId     :: UUID
  , auUserName   :: Text
  , auEmail      :: Maybe Text
  , auRole       :: UserRole
  , auLocationId :: Maybe UUID
  , auCreatedAt  :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON AuthenticatedUser
instance FromJSON AuthenticatedUser

data UserCapabilities = UserCapabilities
  { capCanViewInventory      :: Bool
  , capCanCreateItem         :: Bool
  , capCanEditItem           :: Bool
  , capCanDeleteItem         :: Bool
  , capCanProcessTransaction :: Bool
  , capCanVoidTransaction    :: Bool
  , capCanRefundTransaction  :: Bool
  , capCanApplyDiscount      :: Bool
  , capCanManageRegisters    :: Bool
  , capCanOpenRegister       :: Bool
  , capCanCloseRegister      :: Bool
  , capCanViewReports        :: Bool
  , capCanViewAllLocations   :: Bool
  , capCanManageUsers        :: Bool
  , capCanViewCompliance     :: Bool
  } deriving (Show, Eq, Generic)

instance ToJSON UserCapabilities
instance FromJSON UserCapabilities

-- | Returned by GET /session.  Capabilities travel here rather than
--   bundled into every inventory response.
data SessionResponse = SessionResponse
  { sessionUserId       :: UUID
  , sessionUserName     :: Text
  , sessionRole         :: UserRole
  , sessionCapabilities :: UserCapabilities
  } deriving (Show, Eq, Generic)

instance ToJSON SessionResponse
instance FromJSON SessionResponse

-- OpenAPI3 instances
deriving instance ToSchema UserRole
deriving instance ToSchema UserCapabilities
deriving instance ToSchema SessionResponse

capabilitiesForRole :: UserRole -> UserCapabilities
capabilitiesForRole Customer = UserCapabilities
  { capCanViewInventory      = True
  , capCanCreateItem         = False
  , capCanEditItem           = False
  , capCanDeleteItem         = False
  , capCanProcessTransaction = False
  , capCanVoidTransaction    = False
  , capCanRefundTransaction  = False
  , capCanApplyDiscount      = False
  , capCanManageRegisters    = False
  , capCanOpenRegister       = False
  , capCanCloseRegister      = False
  , capCanViewReports        = False
  , capCanViewAllLocations   = False
  , capCanManageUsers        = False
  , capCanViewCompliance     = False
  }

capabilitiesForRole Cashier = UserCapabilities
  { capCanViewInventory      = True
  , capCanCreateItem         = False
  , capCanEditItem           = True
  , capCanDeleteItem         = False
  , capCanProcessTransaction = True
  , capCanVoidTransaction    = False
  , capCanRefundTransaction  = False
  , capCanApplyDiscount      = False
  , capCanManageRegisters    = False
  , capCanOpenRegister       = True
  , capCanCloseRegister      = True
  , capCanViewReports        = False
  , capCanViewAllLocations   = False
  , capCanManageUsers        = False
  , capCanViewCompliance     = True
  }

capabilitiesForRole Manager = UserCapabilities
  { capCanViewInventory      = True
  , capCanCreateItem         = True
  , capCanEditItem           = True
  , capCanDeleteItem         = True
  , capCanProcessTransaction = True
  , capCanVoidTransaction    = True
  , capCanRefundTransaction  = True
  , capCanApplyDiscount      = True
  , capCanManageRegisters    = True
  , capCanOpenRegister       = True
  , capCanCloseRegister      = True
  , capCanViewReports        = True
  , capCanViewAllLocations   = False
  , capCanManageUsers        = False
  , capCanViewCompliance     = True
  }

capabilitiesForRole Admin = UserCapabilities
  { capCanViewInventory      = True
  , capCanCreateItem         = True
  , capCanEditItem           = True
  , capCanDeleteItem         = True
  , capCanProcessTransaction = True
  , capCanVoidTransaction    = True
  , capCanRefundTransaction  = True
  , capCanApplyDiscount      = True
  , capCanManageRegisters    = True
  , capCanOpenRegister       = True
  , capCanCloseRegister      = True
  , capCanViewReports        = True
  , capCanViewAllLocations   = True
  , capCanManageUsers        = True
  , capCanViewCompliance     = True
  }

hasCapability :: (UserCapabilities -> Bool) -> AuthenticatedUser -> Bool
hasCapability capFn user = capFn $ capabilitiesForRole (auRole user)

requireCapability :: (UserCapabilities -> Bool) -> String -> AuthenticatedUser -> Either String ()
requireCapability capFn errMsg user
  | hasCapability capFn user = Right ()
  | otherwise = Left errMsg