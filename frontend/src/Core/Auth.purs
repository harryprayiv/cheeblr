module Cheeblr.Core.Auth where

import Prelude

import Foreign (ForeignError(..), fail)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

----------------------------------------------------------------------
-- User Roles
----------------------------------------------------------------------

-- | User roles are kept as an ADT because they form a small,
-- | stable lattice with genuine semantic ordering (Customer < Cashier
-- | < Manager < Admin). Unlike product categories, roles don't change
-- | as the business adds inventory.
data Role
  = Customer
  | Cashier
  | Manager
  | Admin

derive instance Eq Role
derive instance Ord Role

instance Show Role where
  show Customer = "Customer"
  show Cashier = "Cashier"
  show Manager = "Manager"
  show Admin = "Admin"

instance WriteForeign Role where
  writeImpl = writeImpl <<< show

instance ReadForeign Role where
  readImpl f = do
    str <- readImpl f
    case str of
      "Customer" -> pure Customer
      "Cashier" -> pure Cashier
      "Manager" -> pure Manager
      "Admin" -> pure Admin
      _ -> fail (ForeignError $ "Invalid Role: " <> str)

-- | All roles in order.
allRoles :: Array Role
allRoles = [ Customer, Cashier, Manager, Admin ]

-- | Check if a role meets a minimum threshold.
roleAtLeast :: Role -> Role -> Boolean
roleAtLeast minimum actual = actual >= minimum

----------------------------------------------------------------------
-- Capabilities
----------------------------------------------------------------------

-- | Capabilities are a flat record of booleans.
-- | Each represents a specific permission.
type Capabilities =
  { canViewInventory :: Boolean
  , canCreateItem :: Boolean
  , canEditItem :: Boolean
  , canDeleteItem :: Boolean
  , canProcessTransaction :: Boolean
  , canVoidTransaction :: Boolean
  , canRefundTransaction :: Boolean
  , canApplyDiscount :: Boolean
  , canManageRegisters :: Boolean
  , canOpenRegister :: Boolean
  , canCloseRegister :: Boolean
  , canViewReports :: Boolean
  , canViewAllLocations :: Boolean
  , canManageUsers :: Boolean
  , canViewCompliance :: Boolean
  }

-- | No permissions at all.
noCapabilities :: Capabilities
noCapabilities =
  { canViewInventory: false
  , canCreateItem: false
  , canEditItem: false
  , canDeleteItem: false
  , canProcessTransaction: false
  , canVoidTransaction: false
  , canRefundTransaction: false
  , canApplyDiscount: false
  , canManageRegisters: false
  , canOpenRegister: false
  , canCloseRegister: false
  , canViewReports: false
  , canViewAllLocations: false
  , canManageUsers: false
  , canViewCompliance: false
  }

-- | Full access.
allCapabilities :: Capabilities
allCapabilities =
  { canViewInventory: true
  , canCreateItem: true
  , canEditItem: true
  , canDeleteItem: true
  , canProcessTransaction: true
  , canVoidTransaction: true
  , canRefundTransaction: true
  , canApplyDiscount: true
  , canManageRegisters: true
  , canOpenRegister: true
  , canCloseRegister: true
  , canViewReports: true
  , canViewAllLocations: true
  , canManageUsers: true
  , canViewCompliance: true
  }

-- | Capabilities for each role.
capabilitiesFor :: Role -> Capabilities
capabilitiesFor Customer = noCapabilities
  { canViewInventory = true }

capabilitiesFor Cashier = noCapabilities
  { canViewInventory = true
  , canEditItem = true
  , canProcessTransaction = true
  , canOpenRegister = true
  , canCloseRegister = true
  , canViewCompliance = true
  }

capabilitiesFor Manager = noCapabilities
  { canViewInventory = true
  , canCreateItem = true
  , canEditItem = true
  , canDeleteItem = true
  , canProcessTransaction = true
  , canVoidTransaction = true
  , canRefundTransaction = true
  , canApplyDiscount = true
  , canManageRegisters = true
  , canOpenRegister = true
  , canCloseRegister = true
  , canViewReports = true
  , canViewCompliance = true
  }

capabilitiesFor Admin = allCapabilities

-- | Check a specific capability.
hasCapability :: (Capabilities -> Boolean) -> Capabilities -> Boolean
hasCapability f caps = f caps

----------------------------------------------------------------------
-- Display helpers (pure, no UI dependency)
----------------------------------------------------------------------

roleLabel :: Role -> String
roleLabel Customer = "Customer"
roleLabel Cashier  = "Cashier"
roleLabel Manager  = "Manager"
roleLabel Admin    = "Admin"

roleIcon :: Role -> String
roleIcon Customer = "👤"
roleIcon Cashier  = "💵"
roleIcon Manager  = "👔"
roleIcon Admin    = "🔑"

roleBadgeClass :: Role -> String
roleBadgeClass Customer = "bg-blue-100 text-blue-800"
roleBadgeClass Cashier  = "bg-green-100 text-green-800"
roleBadgeClass Manager  = "bg-yellow-100 text-yellow-800"
roleBadgeClass Admin    = "bg-red-100 text-red-800"

-- | Summary of what a role can do (for dev UI).
capabilitySummary :: Role -> Array String
capabilitySummary Customer = ["View Inventory"]
capabilitySummary Cashier  = ["View Inventory", "Edit Item", "Process Transaction", "Open/Close Register", "View Compliance"]
capabilitySummary Manager  = ["View Inventory", "Create/Edit/Delete Items", "All Transactions", "Manage Registers", "View Reports", "View Compliance"]
capabilitySummary Admin    = ["Full Access"]