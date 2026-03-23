module Test.Auth where

import Prelude

import Config.Auth (allDevUsers, devAdmin, devCashier, devCustomer, devManager, findDevUserById, findDevUserByRole, toAuthenticatedUser)
import Data.Array (length)
import Data.Maybe (Maybe(..), isJust)
import Services.AuthService
  ( AuthState(..)
  , canViewInventory
  , canCreateItem
  , canEditItem
  , canDeleteItem
  , canProcessTransaction
  , canVoidTransaction
  , canRefundTransaction
  , canApplyDiscount
  , canManageRegisters
  , canOpenRegister
  , canCloseRegister
  , canViewReports
  , canViewAllLocations
  , canManageUsers
  , canViewCompliance
  , getUserId
  , userIdFromAuth
  , isSignedIn
  , getRole
  , defaultAuthState
  )
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Auth (UserRole(..), capabilitiesForRole)

-- In tests the token is the UUID string of the dev user, matching what
-- devModeAuthState uses and what Auth.Simple.lookupUser accepts.
customerState :: AuthState
customerState = SignedIn devCustomer (show devCustomer.userId)

cashierState :: AuthState
cashierState = SignedIn devCashier (show devCashier.userId)

managerState :: AuthState
managerState = SignedIn devManager (show devManager.userId)

adminState :: AuthState
adminState = SignedIn devAdmin (show devAdmin.userId)

signedOut :: AuthState
signedOut = SignedOut

spec :: Spec Unit
spec = describe "Auth" do

  describe "UserRole ordering" do
    it "Customer < Cashier" do
      (Customer < Cashier) `shouldEqual` true
    it "Cashier < Manager" do
      (Cashier < Manager) `shouldEqual` true
    it "Manager < Admin" do
      (Manager < Admin) `shouldEqual` true
    it "Admin is top" do
      (Admin >= Customer) `shouldEqual` true
    it "roles are equal to themselves" do
      (Customer == Customer) `shouldEqual` true
      (Admin == Admin) `shouldEqual` true

  describe "Raw capabilities for Customer" do
    let caps = capabilitiesForRole Customer
    it "can view inventory" do
      caps.capCanViewInventory `shouldEqual` true
    it "cannot create items" do
      caps.capCanCreateItem `shouldEqual` false
    it "cannot edit items" do
      caps.capCanEditItem `shouldEqual` false
    it "cannot delete items" do
      caps.capCanDeleteItem `shouldEqual` false
    it "cannot process transactions" do
      caps.capCanProcessTransaction `shouldEqual` false
    it "cannot void transactions" do
      caps.capCanVoidTransaction `shouldEqual` false
    it "cannot refund transactions" do
      caps.capCanRefundTransaction `shouldEqual` false
    it "cannot apply discounts" do
      caps.capCanApplyDiscount `shouldEqual` false
    it "cannot manage registers" do
      caps.capCanManageRegisters `shouldEqual` false
    it "cannot open register" do
      caps.capCanOpenRegister `shouldEqual` false
    it "cannot close register" do
      caps.capCanCloseRegister `shouldEqual` false
    it "cannot view reports" do
      caps.capCanViewReports `shouldEqual` false
    it "cannot view all locations" do
      caps.capCanViewAllLocations `shouldEqual` false
    it "cannot manage users" do
      caps.capCanManageUsers `shouldEqual` false
    it "cannot view compliance" do
      caps.capCanViewCompliance `shouldEqual` false

  describe "Raw capabilities for Cashier" do
    let caps = capabilitiesForRole Cashier
    it "can view inventory" do
      caps.capCanViewInventory `shouldEqual` true
    it "cannot create items" do
      caps.capCanCreateItem `shouldEqual` false
    it "can edit items" do
      caps.capCanEditItem `shouldEqual` true
    it "cannot delete items" do
      caps.capCanDeleteItem `shouldEqual` false
    it "can process transactions" do
      caps.capCanProcessTransaction `shouldEqual` true
    it "cannot void transactions" do
      caps.capCanVoidTransaction `shouldEqual` false
    it "cannot refund transactions" do
      caps.capCanRefundTransaction `shouldEqual` false
    it "cannot apply discounts" do
      caps.capCanApplyDiscount `shouldEqual` false
    it "cannot manage registers" do
      caps.capCanManageRegisters `shouldEqual` false
    it "can open register" do
      caps.capCanOpenRegister `shouldEqual` true
    it "can close register" do
      caps.capCanCloseRegister `shouldEqual` true
    it "cannot view reports" do
      caps.capCanViewReports `shouldEqual` false
    it "cannot view all locations" do
      caps.capCanViewAllLocations `shouldEqual` false
    it "cannot manage users" do
      caps.capCanManageUsers `shouldEqual` false
    it "can view compliance" do
      caps.capCanViewCompliance `shouldEqual` true

  describe "Raw capabilities for Manager" do
    let caps = capabilitiesForRole Manager
    it "can view inventory" do
      caps.capCanViewInventory `shouldEqual` true
    it "can create items" do
      caps.capCanCreateItem `shouldEqual` true
    it "can edit items" do
      caps.capCanEditItem `shouldEqual` true
    it "can delete items" do
      caps.capCanDeleteItem `shouldEqual` true
    it "can process transactions" do
      caps.capCanProcessTransaction `shouldEqual` true
    it "can void transactions" do
      caps.capCanVoidTransaction `shouldEqual` true
    it "can refund transactions" do
      caps.capCanRefundTransaction `shouldEqual` true
    it "can apply discounts" do
      caps.capCanApplyDiscount `shouldEqual` true
    it "can manage registers" do
      caps.capCanManageRegisters `shouldEqual` true
    it "can open register" do
      caps.capCanOpenRegister `shouldEqual` true
    it "can close register" do
      caps.capCanCloseRegister `shouldEqual` true
    it "can view reports" do
      caps.capCanViewReports `shouldEqual` true
    it "cannot view all locations" do
      caps.capCanViewAllLocations `shouldEqual` false
    it "cannot manage users" do
      caps.capCanManageUsers `shouldEqual` false
    it "can view compliance" do
      caps.capCanViewCompliance `shouldEqual` true

  describe "Raw capabilities for Admin" do
    let caps = capabilitiesForRole Admin
    it "can view inventory" do
      caps.capCanViewInventory `shouldEqual` true
    it "can create items" do
      caps.capCanCreateItem `shouldEqual` true
    it "can edit items" do
      caps.capCanEditItem `shouldEqual` true
    it "can delete items" do
      caps.capCanDeleteItem `shouldEqual` true
    it "can process transactions" do
      caps.capCanProcessTransaction `shouldEqual` true
    it "can void transactions" do
      caps.capCanVoidTransaction `shouldEqual` true
    it "can refund transactions" do
      caps.capCanRefundTransaction `shouldEqual` true
    it "can apply discounts" do
      caps.capCanApplyDiscount `shouldEqual` true
    it "can manage registers" do
      caps.capCanManageRegisters `shouldEqual` true
    it "can open register" do
      caps.capCanOpenRegister `shouldEqual` true
    it "can close register" do
      caps.capCanCloseRegister `shouldEqual` true
    it "can view reports" do
      caps.capCanViewReports `shouldEqual` true
    it "can view all locations" do
      caps.capCanViewAllLocations `shouldEqual` true
    it "can manage users" do
      caps.capCanManageUsers `shouldEqual` true
    it "can view compliance" do
      caps.capCanViewCompliance `shouldEqual` true

  describe "canViewInventory wiring" do
    it "customer can" do
      canViewInventory customerState `shouldEqual` true
    it "cashier can" do
      canViewInventory cashierState `shouldEqual` true
    it "manager can" do
      canViewInventory managerState `shouldEqual` true
    it "admin can" do
      canViewInventory adminState `shouldEqual` true
    it "signed out cannot" do
      canViewInventory signedOut `shouldEqual` false

  describe "canCreateItem wiring" do
    it "customer cannot" do
      canCreateItem customerState `shouldEqual` false
    it "cashier cannot" do
      canCreateItem cashierState `shouldEqual` false
    it "manager can" do
      canCreateItem managerState `shouldEqual` true
    it "admin can" do
      canCreateItem adminState `shouldEqual` true
    it "signed out cannot" do
      canCreateItem signedOut `shouldEqual` false

  describe "canEditItem wiring" do
    it "customer cannot" do
      canEditItem customerState `shouldEqual` false
    it "cashier can" do
      canEditItem cashierState `shouldEqual` true
    it "manager can" do
      canEditItem managerState `shouldEqual` true
    it "admin can" do
      canEditItem adminState `shouldEqual` true
    it "signed out cannot" do
      canEditItem signedOut `shouldEqual` false

  describe "canDeleteItem wiring" do
    it "customer cannot" do
      canDeleteItem customerState `shouldEqual` false
    it "cashier cannot" do
      canDeleteItem cashierState `shouldEqual` false
    it "manager can" do
      canDeleteItem managerState `shouldEqual` true
    it "admin can" do
      canDeleteItem adminState `shouldEqual` true
    it "signed out cannot" do
      canDeleteItem signedOut `shouldEqual` false

  describe "canProcessTransaction wiring" do
    it "customer cannot" do
      canProcessTransaction customerState `shouldEqual` false
    it "cashier can" do
      canProcessTransaction cashierState `shouldEqual` true
    it "manager can" do
      canProcessTransaction managerState `shouldEqual` true
    it "admin can" do
      canProcessTransaction adminState `shouldEqual` true
    it "signed out cannot" do
      canProcessTransaction signedOut `shouldEqual` false

  describe "canVoidTransaction wiring" do
    it "customer cannot" do
      canVoidTransaction customerState `shouldEqual` false
    it "cashier cannot" do
      canVoidTransaction cashierState `shouldEqual` false
    it "manager can" do
      canVoidTransaction managerState `shouldEqual` true
    it "admin can" do
      canVoidTransaction adminState `shouldEqual` true
    it "signed out cannot" do
      canVoidTransaction signedOut `shouldEqual` false

  describe "canRefundTransaction wiring" do
    it "customer cannot" do
      canRefundTransaction customerState `shouldEqual` false
    it "cashier cannot" do
      canRefundTransaction cashierState `shouldEqual` false
    it "manager can" do
      canRefundTransaction managerState `shouldEqual` true
    it "admin can" do
      canRefundTransaction adminState `shouldEqual` true
    it "signed out cannot" do
      canRefundTransaction signedOut `shouldEqual` false

  describe "canApplyDiscount wiring" do
    it "customer cannot" do
      canApplyDiscount customerState `shouldEqual` false
    it "cashier cannot" do
      canApplyDiscount cashierState `shouldEqual` false
    it "manager can" do
      canApplyDiscount managerState `shouldEqual` true
    it "admin can" do
      canApplyDiscount adminState `shouldEqual` true
    it "signed out cannot" do
      canApplyDiscount signedOut `shouldEqual` false

  describe "canManageRegisters wiring" do
    it "customer cannot" do
      canManageRegisters customerState `shouldEqual` false
    it "cashier cannot" do
      canManageRegisters cashierState `shouldEqual` false
    it "manager can" do
      canManageRegisters managerState `shouldEqual` true
    it "admin can" do
      canManageRegisters adminState `shouldEqual` true
    it "signed out cannot" do
      canManageRegisters signedOut `shouldEqual` false

  describe "canOpenRegister wiring" do
    it "customer cannot" do
      canOpenRegister customerState `shouldEqual` false
    it "cashier can" do
      canOpenRegister cashierState `shouldEqual` true
    it "manager can" do
      canOpenRegister managerState `shouldEqual` true
    it "admin can" do
      canOpenRegister adminState `shouldEqual` true
    it "signed out cannot" do
      canOpenRegister signedOut `shouldEqual` false

  describe "canCloseRegister wiring" do
    it "customer cannot" do
      canCloseRegister customerState `shouldEqual` false
    it "cashier can" do
      canCloseRegister cashierState `shouldEqual` true
    it "manager can" do
      canCloseRegister managerState `shouldEqual` true
    it "admin can" do
      canCloseRegister adminState `shouldEqual` true
    it "signed out cannot" do
      canCloseRegister signedOut `shouldEqual` false

  describe "canViewReports wiring" do
    it "customer cannot" do
      canViewReports customerState `shouldEqual` false
    it "cashier cannot" do
      canViewReports cashierState `shouldEqual` false
    it "manager can" do
      canViewReports managerState `shouldEqual` true
    it "admin can" do
      canViewReports adminState `shouldEqual` true
    it "signed out cannot" do
      canViewReports signedOut `shouldEqual` false

  describe "canViewAllLocations wiring" do
    it "customer cannot" do
      canViewAllLocations customerState `shouldEqual` false
    it "cashier cannot" do
      canViewAllLocations cashierState `shouldEqual` false
    it "manager cannot" do
      canViewAllLocations managerState `shouldEqual` false
    it "admin can" do
      canViewAllLocations adminState `shouldEqual` true
    it "signed out cannot" do
      canViewAllLocations signedOut `shouldEqual` false

  describe "canManageUsers wiring" do
    it "customer cannot" do
      canManageUsers customerState `shouldEqual` false
    it "cashier cannot" do
      canManageUsers cashierState `shouldEqual` false
    it "manager cannot" do
      canManageUsers managerState `shouldEqual` false
    it "admin can" do
      canManageUsers adminState `shouldEqual` true
    it "signed out cannot" do
      canManageUsers signedOut `shouldEqual` false

  describe "canViewCompliance wiring" do
    it "customer cannot" do
      canViewCompliance customerState `shouldEqual` false
    it "cashier can" do
      canViewCompliance cashierState `shouldEqual` true
    it "manager can" do
      canViewCompliance managerState `shouldEqual` true
    it "admin can" do
      canViewCompliance adminState `shouldEqual` true
    it "signed out cannot" do
      canViewCompliance signedOut `shouldEqual` false

  describe "AuthState helpers" do
    it "isSignedIn returns true for signed in" do
      isSignedIn adminState `shouldEqual` true
    it "isSignedIn returns false for signed out" do
      isSignedIn signedOut `shouldEqual` false

    it "getUserId returns Just for signed in" do
      getUserId adminState `shouldSatisfy` isJust
    it "getUserId returns Nothing for signed out" do
      getUserId signedOut `shouldEqual` Nothing

    it "userIdFromAuth returns non-empty for signed in" do
      (userIdFromAuth adminState /= "") `shouldEqual` true
    it "userIdFromAuth returns empty for signed out" do
      userIdFromAuth signedOut `shouldEqual` ""

    it "getRole returns correct role for each user" do
      getRole customerState `shouldEqual` Just Customer
      getRole cashierState `shouldEqual` Just Cashier
      getRole managerState `shouldEqual` Just Manager
      getRole adminState `shouldEqual` Just Admin
    it "getRole returns Nothing when signed out" do
      getRole signedOut `shouldEqual` Nothing

    -- defaultAuthState is SignedOut in production mode so the login page
    -- is shown on first load. devModeAuthState is SignedIn.
    it "defaultAuthState is signed out" do
      isSignedIn defaultAuthState `shouldEqual` false

  describe "Dev user lookup" do
    it "allDevUsers has 4 users" do
      length allDevUsers `shouldEqual` 4

    it "finds admin by id" do
      findDevUserById devAdmin.userId `shouldSatisfy` isJust

    it "finds customer by id" do
      findDevUserById devCustomer.userId `shouldSatisfy` isJust

    it "finds cashier by role" do
      findDevUserByRole Cashier `shouldSatisfy` isJust

    it "finds manager by role" do
      findDevUserByRole Manager `shouldSatisfy` isJust

  describe "toAuthenticatedUser" do
    it "preserves userId" do
      let au = toAuthenticatedUser devAdmin
      au.auUserId `shouldEqual` devAdmin.userId

    it "preserves role for each dev user" do
      (toAuthenticatedUser devCustomer).auRole `shouldEqual` Customer
      (toAuthenticatedUser devCashier).auRole `shouldEqual` Cashier
      (toAuthenticatedUser devManager).auRole `shouldEqual` Manager
      (toAuthenticatedUser devAdmin).auRole `shouldEqual` Admin

    it "preserves email" do
      let au = toAuthenticatedUser devManager
      au.auEmail `shouldEqual` devManager.email

    it "preserves userName" do
      let au = toAuthenticatedUser devCashier
      au.auUserName `shouldEqual` devCashier.userName