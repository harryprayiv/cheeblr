{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE StandaloneDeriving #-}

module Types.Auth where

import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import Types.Location (LocationId)

------------------------------------------------------------------------
-- UserRole
------------------------------------------------------------------------

data UserRole
  = Customer
  | Cashier
  | Manager
  | Admin
  deriving (Show, Read, Eq, Ord, Generic)

instance ToJSON UserRole
instance FromJSON UserRole

------------------------------------------------------------------------
-- Capability sum type
-- Every constructor added here is automatically granted to Admin
-- via capabilitiesForRole (see below). No other role definition needs
-- to change when a new capability is added.
------------------------------------------------------------------------

data Capability
  = CanViewInventory
  | CanCreateItem
  | CanEditItem
  | CanDeleteItem
  | CanProcessTransaction
  | CanVoidTransaction
  | CanRefundTransaction
  | CanApplyDiscount
  | CanManageRegisters
  | CanOpenRegister
  | CanCloseRegister
  | CanViewReports
  | CanViewAllLocations
  | CanManageUsers
  | CanViewCompliance
  | CanFulfillOrders -- Phase 8: stock room
  | CanViewAdminDashboard -- Phase 6: admin dashboard
  | CanPerformAdminActions -- Phase 6: admin actions
  deriving (Show, Read, Eq, Ord, Enum, Bounded, Generic)

instance ToJSON Capability
instance FromJSON Capability

------------------------------------------------------------------------
-- UserCapabilities record
-- The wire format (capCanX boolean keys) is unchanged.
-- Three new fields are added for capabilities introduced by later phases;
-- existing clients ignore unknown JSON keys, so this is non-breaking.
------------------------------------------------------------------------

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

------------------------------------------------------------------------
-- capabilityToField
-- Maps each Capability constructor to its record field accessor.
-- This is the bridge between the sum type and the record:
-- it means capabilitiesForRole Admin never needs updating — adding a
-- new Capability constructor and a new record field, plus one line here,
-- is the complete change required for a new capability.
------------------------------------------------------------------------

capabilityToField :: Capability -> (UserCapabilities -> Bool)
capabilityToField CanViewInventory = capCanViewInventory
capabilityToField CanCreateItem = capCanCreateItem
capabilityToField CanEditItem = capCanEditItem
capabilityToField CanDeleteItem = capCanDeleteItem
capabilityToField CanProcessTransaction = capCanProcessTransaction
capabilityToField CanVoidTransaction = capCanVoidTransaction
capabilityToField CanRefundTransaction = capCanRefundTransaction
capabilityToField CanApplyDiscount = capCanApplyDiscount
capabilityToField CanManageRegisters = capCanManageRegisters
capabilityToField CanOpenRegister = capCanOpenRegister
capabilityToField CanCloseRegister = capCanCloseRegister
capabilityToField CanViewReports = capCanViewReports
capabilityToField CanViewAllLocations = capCanViewAllLocations
capabilityToField CanManageUsers = capCanManageUsers
capabilityToField CanViewCompliance = capCanViewCompliance
capabilityToField CanFulfillOrders = capCanFulfillOrders
capabilityToField CanViewAdminDashboard = capCanViewAdminDashboard
capabilityToField CanPerformAdminActions = capCanPerformAdminActions

------------------------------------------------------------------------
-- hasCapabilityFor
-- Check a specific Capability constructor against a UserCapabilities record.
------------------------------------------------------------------------

hasCapabilityFor :: Capability -> UserCapabilities -> Bool
hasCapabilityFor cap caps = capabilityToField cap caps

------------------------------------------------------------------------
-- capabilitiesForRole
-- Admin is defined by allCapabilities so it never needs manual updating.
------------------------------------------------------------------------

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

------------------------------------------------------------------------
-- AuthenticatedUser
------------------------------------------------------------------------

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

------------------------------------------------------------------------
-- hasCapability / requireCapability
-- Signatures unchanged — all existing call sites compile without edits.
------------------------------------------------------------------------

hasCapability :: (UserCapabilities -> Bool) -> AuthenticatedUser -> Bool
hasCapability capFn user = capFn (capabilitiesForRole (auRole user))

requireCapability ::
  (UserCapabilities -> Bool) ->
  String ->
  AuthenticatedUser ->
  Either String ()
requireCapability capFn errMsg user
  | hasCapability capFn user = Right ()
  | otherwise = Left errMsg

------------------------------------------------------------------------
-- SessionResponse
------------------------------------------------------------------------

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
