{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module Types.Auth where

import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import Types.Location (LocationId)

data UserRole
  = Customer
  | Cashier
  | Manager
  | Admin
  deriving (Show, Read, Eq, Ord, Generic)

instance ToJSON UserRole
instance FromJSON UserRole

{- | Single authoritative parser for UserRole from DB/JSON text.
Defaults to Customer (least privileged) on unrecognised values so an
unknown role from the DB never silently grants elevated access.
-}
parseUserRole :: Text -> UserRole
parseUserRole "Admin" = Admin
parseUserRole "Manager" = Manager
parseUserRole "Cashier" = Cashier
parseUserRole "Customer" = Customer
parseUserRole _ = Customer

data UserCapabilities = UserCapabilities
  { capCanViewInventory :: Bool
  , capCanCreateItem :: Bool
  , capCanEditItem :: Bool
  , capCanDeleteItem :: Bool
  , capCanProcessTransaction :: Bool
  , capCanVoidTransaction :: Bool
  , capCanRefundTransaction :: Bool
  , capCanApplyDiscount :: Bool
  , capCanManageRegisters :: Bool
  , capCanOpenRegister :: Bool
  , capCanCloseRegister :: Bool
  , capCanViewReports :: Bool
  , capCanViewAllLocations :: Bool
  , capCanManageUsers :: Bool
  , capCanViewCompliance :: Bool
  , capCanFulfillOrders :: Bool
  , capCanViewAdminDashboard :: Bool
  , capCanPerformAdminActions :: Bool
  }
  deriving (Show, Eq, Generic)

instance ToJSON UserCapabilities
instance FromJSON UserCapabilities

allCapabilities :: UserCapabilities
allCapabilities =
  UserCapabilities
    { capCanViewInventory = True
    , capCanCreateItem = True
    , capCanEditItem = True
    , capCanDeleteItem = True
    , capCanProcessTransaction = True
    , capCanVoidTransaction = True
    , capCanRefundTransaction = True
    , capCanApplyDiscount = True
    , capCanManageRegisters = True
    , capCanOpenRegister = True
    , capCanCloseRegister = True
    , capCanViewReports = True
    , capCanViewAllLocations = True
    , capCanManageUsers = True
    , capCanViewCompliance = True
    , capCanFulfillOrders = True
    , capCanViewAdminDashboard = True
    , capCanPerformAdminActions = True
    }

noCapabilities :: UserCapabilities
noCapabilities =
  UserCapabilities
    { capCanViewInventory = False
    , capCanCreateItem = False
    , capCanEditItem = False
    , capCanDeleteItem = False
    , capCanProcessTransaction = False
    , capCanVoidTransaction = False
    , capCanRefundTransaction = False
    , capCanApplyDiscount = False
    , capCanManageRegisters = False
    , capCanOpenRegister = False
    , capCanCloseRegister = False
    , capCanViewReports = False
    , capCanViewAllLocations = False
    , capCanManageUsers = False
    , capCanViewCompliance = False
    , capCanFulfillOrders = False
    , capCanViewAdminDashboard = False
    , capCanPerformAdminActions = False
    }

capabilitiesForRole :: UserRole -> UserCapabilities
capabilitiesForRole Admin = allCapabilities
capabilitiesForRole Manager =
  noCapabilities
    { capCanViewInventory = True
    , capCanCreateItem = True
    , capCanEditItem = True
    , capCanDeleteItem = True
    , capCanProcessTransaction = True
    , capCanVoidTransaction = True
    , capCanRefundTransaction = True
    , capCanApplyDiscount = True
    , capCanManageRegisters = True
    , capCanOpenRegister = True
    , capCanCloseRegister = True
    , capCanViewReports = True
    , capCanViewCompliance = True
    , capCanFulfillOrders = True
    }
capabilitiesForRole Cashier =
  noCapabilities
    { capCanViewInventory = True
    , capCanEditItem = True
    , capCanProcessTransaction = True
    , capCanOpenRegister = True
    , capCanCloseRegister = True
    , capCanViewCompliance = True
    , capCanFulfillOrders = True
    }
capabilitiesForRole Customer =
  noCapabilities
    { capCanViewInventory = True
    }

data AuthenticatedUser = AuthenticatedUser
  { auUserId :: UUID
  , auUserName :: Text
  , auEmail :: Maybe Text
  , auRole :: UserRole
  , auLocationId :: Maybe LocationId
  , auCreatedAt :: UTCTime
  }
  deriving (Show, Eq, Generic)

instance ToJSON AuthenticatedUser
instance FromJSON AuthenticatedUser

hasCapability :: (UserCapabilities -> Bool) -> AuthenticatedUser -> Bool
hasCapability capFn user = capFn (capabilitiesForRole (auRole user))

data SessionResponse = SessionResponse
  { sessionUserId :: UUID
  , sessionUserName :: Text
  , sessionRole :: UserRole
  , sessionCapabilities :: UserCapabilities
  }
  deriving (Show, Eq, Generic)

instance ToJSON SessionResponse
instance FromJSON SessionResponse

deriving instance ToSchema UserRole
deriving instance ToSchema UserCapabilities
deriving instance ToSchema SessionResponse
