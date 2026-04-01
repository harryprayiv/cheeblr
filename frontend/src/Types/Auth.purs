module Types.Auth where

import Prelude

import Data.DateTime (DateTime)
import Data.Enum (class BoundedEnum, class Enum, Cardinality(..))
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..))
import Data.Show.Generic (genericShow)
import Foreign (ForeignError(..), fail)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

data UserRole
  = Customer
  | Cashier
  | Manager
  | Admin

derive instance eqUserRole      :: Eq UserRole
derive instance ordUserRole     :: Ord UserRole
derive instance genericUserRole :: Generic UserRole _

instance showUserRole :: Show UserRole where
  show = genericShow

instance Enum UserRole where
  succ Customer = Just Cashier
  succ Cashier  = Just Manager
  succ Manager  = Just Admin
  succ Admin    = Nothing
  pred Cashier  = Just Customer
  pred Manager  = Just Cashier
  pred Admin    = Just Manager
  pred Customer = Nothing

instance Bounded UserRole where
  bottom = Customer
  top    = Admin

instance BoundedEnum UserRole where
  cardinality = Cardinality 4
  fromEnum Customer = 0
  fromEnum Cashier  = 1
  fromEnum Manager  = 2
  fromEnum Admin    = 3
  toEnum 0 = Just Customer
  toEnum 1 = Just Cashier
  toEnum 2 = Just Manager
  toEnum 3 = Just Admin
  toEnum _ = Nothing

instance writeForeignUserRole :: WriteForeign UserRole where
  writeImpl Customer = writeImpl "Customer"
  writeImpl Cashier  = writeImpl "Cashier"
  writeImpl Manager  = writeImpl "Manager"
  writeImpl Admin    = writeImpl "Admin"

instance readForeignUserRole :: ReadForeign UserRole where
  readImpl f = do
    role <- readImpl f
    case role of
      "Customer" -> pure Customer
      "Cashier"  -> pure Cashier
      "Manager"  -> pure Manager
      "Admin"    -> pure Admin
      _          -> fail (ForeignError $ "Invalid UserRole: " <> role)

------------------------------------------------------------------------
-- AuthenticatedUser
------------------------------------------------------------------------

type AuthenticatedUser =
  { auUserId     :: UUID
  , auUserName   :: String
  , auEmail      :: Maybe String
  , auRole       :: UserRole
  , auLocationId :: Maybe UUID
  , auCreatedAt  :: DateTime
  }

type UserCapabilities =
  { capCanViewInventory       :: Boolean
  , capCanCreateItem          :: Boolean
  , capCanEditItem            :: Boolean
  , capCanDeleteItem          :: Boolean
  , capCanProcessTransaction  :: Boolean
  , capCanVoidTransaction     :: Boolean
  , capCanRefundTransaction   :: Boolean
  , capCanApplyDiscount       :: Boolean
  , capCanManageRegisters     :: Boolean
  , capCanOpenRegister        :: Boolean
  , capCanCloseRegister       :: Boolean
  , capCanViewReports         :: Boolean
  , capCanViewAllLocations    :: Boolean
  , capCanManageUsers         :: Boolean
  , capCanViewCompliance      :: Boolean
  -- New in Phase 1
  , capCanFulfillOrders       :: Boolean
  , capCanViewAdminDashboard  :: Boolean
  , capCanPerformAdminActions :: Boolean
  }

emptyCapabilities :: UserCapabilities
emptyCapabilities =
  { capCanViewInventory:       false
  , capCanCreateItem:          false
  , capCanEditItem:            false
  , capCanDeleteItem:          false
  , capCanProcessTransaction:  false
  , capCanVoidTransaction:     false
  , capCanRefundTransaction:   false
  , capCanApplyDiscount:       false
  , capCanManageRegisters:     false
  , capCanOpenRegister:        false
  , capCanCloseRegister:       false
  , capCanViewReports:         false
  , capCanViewAllLocations:    false
  , capCanManageUsers:         false
  , capCanViewCompliance:      false
  , capCanFulfillOrders:       false
  , capCanViewAdminDashboard:  false
  , capCanPerformAdminActions: false
  }

customerCapabilities :: UserCapabilities
customerCapabilities = emptyCapabilities
  { capCanViewInventory = true
  }

cashierCapabilities :: UserCapabilities
cashierCapabilities = emptyCapabilities
  { capCanViewInventory      = true
  , capCanEditItem           = true
  , capCanProcessTransaction = true
  , capCanOpenRegister       = true
  , capCanCloseRegister      = true
  , capCanViewCompliance     = true
  , capCanFulfillOrders      = true
  }

managerCapabilities :: UserCapabilities
managerCapabilities = emptyCapabilities
  { capCanViewInventory      = true
  , capCanCreateItem         = true
  , capCanEditItem           = true
  , capCanDeleteItem         = true
  , capCanProcessTransaction = true
  , capCanVoidTransaction    = true
  , capCanRefundTransaction  = true
  , capCanApplyDiscount      = true
  , capCanManageRegisters    = true
  , capCanOpenRegister       = true
  , capCanCloseRegister      = true
  , capCanViewReports        = true
  , capCanViewCompliance     = true
  , capCanFulfillOrders      = true
  }

adminCapabilities :: UserCapabilities
adminCapabilities =
  { capCanViewInventory:       true
  , capCanCreateItem:          true
  , capCanEditItem:            true
  , capCanDeleteItem:          true
  , capCanProcessTransaction:  true
  , capCanVoidTransaction:     true
  , capCanRefundTransaction:   true
  , capCanApplyDiscount:       true
  , capCanManageRegisters:     true
  , capCanOpenRegister:        true
  , capCanCloseRegister:       true
  , capCanViewReports:         true
  , capCanViewAllLocations:    true
  , capCanManageUsers:         true
  , capCanViewCompliance:      true
  , capCanFulfillOrders:       true
  , capCanViewAdminDashboard:  true
  , capCanPerformAdminActions: true
  }

capabilitiesForRole :: UserRole -> UserCapabilities
capabilitiesForRole Customer = customerCapabilities
capabilitiesForRole Cashier  = cashierCapabilities
capabilitiesForRole Manager  = managerCapabilities
capabilitiesForRole Admin    = adminCapabilities

hasCapability :: (UserCapabilities -> Boolean) -> UserCapabilities -> Boolean
hasCapability capFn caps = capFn caps