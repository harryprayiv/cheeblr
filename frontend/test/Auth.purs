module Test.Auth where

import Prelude

import Data.Maybe (Maybe(..))
import Route (Route, visibleLinks)
import Route as Route
import Services.AuthService (AuthState(..), can, capabilities, isSignedIn, session)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Types.Auth (UserCapabilities, UserRole(..), capabilitiesForRole, emptyCapabilities)
import Types.Session (SessionResponse)
import Types.UUID (UUID(..))

-- A session as the backend would send it for a user of this role.
sessionFor :: UserRole -> SessionResponse
sessionFor role =
  { sessionUserId: UUID "0a6f2deb-892b-4411-8025-08c1a4d61229"
  , sessionUserName: "someone"
  , sessionRole: role
  , sessionCapabilities: capabilitiesForRole role
  }

linksFor :: UserCapabilities -> Array Route
linksFor caps = _.route <$> visibleLinks caps

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

  describe "AuthState" do
    it "a browser with a session is signed in" do
      isSignedIn (SignedIn (sessionFor Admin)) `shouldEqual` true
    it "a browser without one is signed out" do
      isSignedIn SignedOut `shouldEqual` false

    it "session returns the session held" do
      (session (SignedIn (sessionFor Cashier)) <#> _.sessionRole)
        `shouldEqual` Just Cashier
    it "session is Nothing when signed out" do
      (session SignedOut <#> _.sessionRole) `shouldEqual` Nothing

    it "a signed-out browser has no capabilities" do
      capabilities SignedOut `shouldEqual` emptyCapabilities

    it "capabilities are the ones the backend sent, not ones derived from the role" do
      let
        sent = (sessionFor Customer)
          { sessionCapabilities = capabilitiesForRole Manager }
      capabilities (SignedIn sent) `shouldEqual` capabilitiesForRole Manager

    it "can reads one capability of the session" do
      can _.capCanVoidTransaction (SignedIn (sessionFor Manager))
        `shouldEqual` true
      can _.capCanVoidTransaction (SignedIn (sessionFor Cashier))
        `shouldEqual` false
    it "can is false for every capability when signed out" do
      can _.capCanViewInventory SignedOut `shouldEqual` false

  describe "Navigation links by capability" do
    it "a customer sees the live view and the feed" do
      linksFor (capabilitiesForRole Customer)
        `shouldEqual` [ Route.LiveView, Route.Feed ]

    it "a cashier sees selling, sales, registers and the stock room" do
      linksFor (capabilitiesForRole Cashier) `shouldEqual`
        [ Route.LiveView, Route.CreateTransaction, Route.TransactionHistory, Route.Registers, Route.Stock, Route.Feed ]

    it "a manager also sees item creation and the manager dashboard" do
      linksFor (capabilitiesForRole Manager) `shouldEqual`
        [ Route.LiveView
        , Route.Create
        , Route.CreateTransaction
        , Route.TransactionHistory
        , Route.Registers
        , Route.Manager
        , Route.Stock
        , Route.Feed
        ]

    it "an admin sees every link" do
      linksFor (capabilitiesForRole Admin) `shouldEqual`
        [ Route.LiveView
        , Route.Create
        , Route.CreateTransaction
        , Route.TransactionHistory
        , Route.Registers
        , Route.Admin
        , Route.Manager
        , Route.Stock
        , Route.Feed
        ]

    it "no capabilities leaves only the feed" do
      linksFor emptyCapabilities `shouldEqual` [ Route.Feed ]
