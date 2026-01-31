module Components.AuthGuard where

import Prelude

import Deku.Core (Nut, fixed)
import Deku.Hooks (guard)
import FRP.Poll (Poll)
import Types.Auth (UserCapabilities, UserRole(..))

-- | Render children only if capability check passes
whenCapable :: Poll UserCapabilities -> (UserCapabilities -> Boolean) -> Nut -> Nut
whenCapable capsPoll checkFn children =
  guard (capsPoll <#> checkFn) children

-- | Render children only if user can view inventory
whenCanViewInventory :: Poll UserCapabilities -> Nut -> Nut
whenCanViewInventory caps = whenCapable caps _.capCanViewInventory

-- | Render children only if user can create items
whenCanCreateItem :: Poll UserCapabilities -> Nut -> Nut
whenCanCreateItem caps = whenCapable caps _.capCanCreateItem

-- | Render children only if user can edit items
whenCanEditItem :: Poll UserCapabilities -> Nut -> Nut
whenCanEditItem caps = whenCapable caps _.capCanEditItem

-- | Render children only if user can delete items
whenCanDeleteItem :: Poll UserCapabilities -> Nut -> Nut
whenCanDeleteItem caps = whenCapable caps _.capCanDeleteItem

-- | Render children only if user can process transactions
whenCanProcessTransaction :: Poll UserCapabilities -> Nut -> Nut
whenCanProcessTransaction caps = whenCapable caps _.capCanProcessTransaction

-- | Render children only if user can void transactions
whenCanVoidTransaction :: Poll UserCapabilities -> Nut -> Nut
whenCanVoidTransaction caps = whenCapable caps _.capCanVoidTransaction

-- | Render children only if user can refund transactions
whenCanRefundTransaction :: Poll UserCapabilities -> Nut -> Nut
whenCanRefundTransaction caps = whenCapable caps _.capCanRefundTransaction

-- | Render children only if user can apply discounts
whenCanApplyDiscount :: Poll UserCapabilities -> Nut -> Nut
whenCanApplyDiscount caps = whenCapable caps _.capCanApplyDiscount

-- | Render children only if user can manage registers
whenCanManageRegisters :: Poll UserCapabilities -> Nut -> Nut
whenCanManageRegisters caps = whenCapable caps _.capCanManageRegisters

-- | Render children only if user can open register
whenCanOpenRegister :: Poll UserCapabilities -> Nut -> Nut
whenCanOpenRegister caps = whenCapable caps _.capCanOpenRegister

-- | Render children only if user can close register
whenCanCloseRegister :: Poll UserCapabilities -> Nut -> Nut
whenCanCloseRegister caps = whenCapable caps _.capCanCloseRegister

-- | Render children only if user can view reports
whenCanViewReports :: Poll UserCapabilities -> Nut -> Nut
whenCanViewReports caps = whenCapable caps _.capCanViewReports

-- | Render children only if user can view all locations
whenCanViewAllLocations :: Poll UserCapabilities -> Nut -> Nut
whenCanViewAllLocations caps = whenCapable caps _.capCanViewAllLocations

-- | Render children only if user can manage users
whenCanManageUsers :: Poll UserCapabilities -> Nut -> Nut
whenCanManageUsers caps = whenCapable caps _.capCanManageUsers

-- | Render children only if user can view compliance
whenCanViewCompliance :: Poll UserCapabilities -> Nut -> Nut
whenCanViewCompliance caps = whenCapable caps _.capCanViewCompliance

-- | Render children only if user has specific role or higher
whenRoleAtLeast :: Poll UserRole -> UserRole -> Nut -> Nut
whenRoleAtLeast rolePoll minRole children =
  guard (rolePoll <#> (_ >= minRole)) children

-- | Render children only if user is a Cashier or higher
whenCashierOrAbove :: Poll UserRole -> Nut -> Nut
whenCashierOrAbove role = whenRoleAtLeast role Cashier

-- | Render children only if user is a Manager or higher
whenManagerOrAbove :: Poll UserRole -> Nut -> Nut
whenManagerOrAbove role = whenRoleAtLeast role Manager

-- | Render children only if user is Admin
whenAdmin :: Poll UserRole -> Nut -> Nut
whenAdmin role = whenRoleAtLeast role Admin

-- | Render with fallback for unauthorized users
-- Uses two guards to show either authorized or unauthorized content
withFallback :: Poll UserCapabilities -> (UserCapabilities -> Boolean) -> Nut -> Nut -> Nut
withFallback capsPoll checkFn authorized unauthorized =
  fixed
    [ guard (capsPoll <#> checkFn) authorized
    , guard (capsPoll <#> (checkFn >>> not)) unauthorized
    ]

-- | Simple disabled wrapper - for now just renders children
-- TODO: implement actual disabled styling based on capability
disabledUnless :: Poll UserCapabilities -> (UserCapabilities -> Boolean) -> Nut -> Nut
disabledUnless _capsPoll _checkFn children = children