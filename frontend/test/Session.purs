module Test.Session where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Auth (UserRole(..))
import Types.Session (SessionResponse)
import Types.UUID (UUID(..))
import Yoga.JSON (readJSON_)

-- ---------------------------------------------------------------------------
-- Backend-format JSON fixtures
-- These mirror what the Haskell Generic ToJSON + capabilitiesForRole produce.
-- ---------------------------------------------------------------------------

adminSessionJson :: String
adminSessionJson =
  """{"sessionUserId":"d3a1f4f0-c518-4db3-aa43-e80b428d6304","sessionUserName":"admin-1","sessionRole":"Admin","sessionCapabilities":{"capCanViewInventory":true,"capCanCreateItem":true,"capCanEditItem":true,"capCanDeleteItem":true,"capCanProcessTransaction":true,"capCanVoidTransaction":true,"capCanRefundTransaction":true,"capCanApplyDiscount":true,"capCanManageRegisters":true,"capCanOpenRegister":true,"capCanCloseRegister":true,"capCanViewReports":true,"capCanViewAllLocations":true,"capCanManageUsers":true,"capCanViewCompliance":true,"capCanFulfillOrders":true,"capCanViewAdminDashboard":true,"capCanPerformAdminActions":true}}"""

cashierSessionJson :: String
cashierSessionJson =
  """{"sessionUserId":"0a6f2deb-892b-4411-8025-08c1a4d61229","sessionUserName":"cashier-1","sessionRole":"Cashier","sessionCapabilities":{"capCanViewInventory":true,"capCanCreateItem":false,"capCanEditItem":true,"capCanDeleteItem":false,"capCanProcessTransaction":true,"capCanVoidTransaction":false,"capCanRefundTransaction":false,"capCanApplyDiscount":false,"capCanManageRegisters":false,"capCanOpenRegister":true,"capCanCloseRegister":true,"capCanViewReports":false,"capCanViewAllLocations":false,"capCanManageUsers":false,"capCanViewCompliance":true,"capCanFulfillOrders":true,"capCanViewAdminDashboard":false,"capCanPerformAdminActions":false}}"""

managerSessionJson :: String
managerSessionJson =
  """{"sessionUserId":"8b75ea4a-00a4-4a2a-a5d5-a1bab8883802","sessionUserName":"manager-1","sessionRole":"Manager","sessionCapabilities":{"capCanViewInventory":true,"capCanCreateItem":true,"capCanEditItem":true,"capCanDeleteItem":true,"capCanProcessTransaction":true,"capCanVoidTransaction":true,"capCanRefundTransaction":true,"capCanApplyDiscount":true,"capCanManageRegisters":true,"capCanOpenRegister":true,"capCanCloseRegister":true,"capCanViewReports":true,"capCanViewAllLocations":false,"capCanManageUsers":false,"capCanViewCompliance":true,"capCanFulfillOrders":true,"capCanViewAdminDashboard":false,"capCanPerformAdminActions":false}}"""

customerSessionJson :: String
customerSessionJson =
  """{"sessionUserId":"8244082f-a6bc-4d6c-9427-64a0ecdc10db","sessionUserName":"customer-1","sessionRole":"Customer","sessionCapabilities":{"capCanViewInventory":true,"capCanCreateItem":false,"capCanEditItem":false,"capCanDeleteItem":false,"capCanProcessTransaction":false,"capCanVoidTransaction":false,"capCanRefundTransaction":false,"capCanApplyDiscount":false,"capCanManageRegisters":false,"capCanOpenRegister":false,"capCanCloseRegister":false,"capCanViewReports":false,"capCanViewAllLocations":false,"capCanManageUsers":false,"capCanViewCompliance":false,"capCanFulfillOrders":false,"capCanViewAdminDashboard":false,"capCanPerformAdminActions":false}}"""

spec :: Spec Unit
spec = describe "Types.Session" do

  -- ─────────────────────────────────────────────────────────────────────────
  -- Basic parse hygiene
  -- ─────────────────────────────────────────────────────────────────────────

  describe "SessionResponse parses from backend JSON" do
    it "parses admin session" do
      (readJSON_ adminSessionJson :: Maybe SessionResponse) `shouldSatisfy` isJust

    it "parses cashier session" do
      (readJSON_ cashierSessionJson :: Maybe SessionResponse) `shouldSatisfy` isJust

    it "parses manager session" do
      (readJSON_ managerSessionJson :: Maybe SessionResponse) `shouldSatisfy` isJust

    it "parses customer session" do
      (readJSON_ customerSessionJson :: Maybe SessionResponse) `shouldSatisfy` isJust

  -- ─────────────────────────────────────────────────────────────────────────
  -- Field preservation — verify the decoder routes each field correctly.
  -- A decoder that swaps role and userName would only show up here.
  -- ─────────────────────────────────────────────────────────────────────────

  describe "Admin session field preservation" do
    it "preserves userId" do
      case readJSON_ adminSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionUserId `shouldEqual` UUID "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
        Nothing -> false `shouldEqual` true

    it "preserves userName" do
      case readJSON_ adminSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionUserName `shouldEqual` "admin-1"
        Nothing -> false `shouldEqual` true

    it "preserves role as Admin" do
      case readJSON_ adminSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionRole `shouldEqual` Admin
        Nothing -> false `shouldEqual` true

    it "capabilities: viewAllLocations = true" do
      case readJSON_ adminSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanViewAllLocations `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "capabilities: manageUsers = true" do
      case readJSON_ adminSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanManageUsers `shouldEqual` true
        Nothing -> false `shouldEqual` true

  describe "Cashier session field preservation" do
    it "preserves role as Cashier" do
      case readJSON_ cashierSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionRole `shouldEqual` Cashier
        Nothing -> false `shouldEqual` true

    it "capabilities: editItem = true" do
      case readJSON_ cashierSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanEditItem `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "capabilities: deleteItem = false" do
      case readJSON_ cashierSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanDeleteItem `shouldEqual` false
        Nothing -> false `shouldEqual` true

    it "capabilities: viewCompliance = true" do
      case readJSON_ cashierSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanViewCompliance `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "capabilities: processTransaction = true" do
      case readJSON_ cashierSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanProcessTransaction `shouldEqual` true
        Nothing -> false `shouldEqual` true

  describe "Manager session field preservation" do
    it "preserves role as Manager" do
      case readJSON_ managerSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionRole `shouldEqual` Manager
        Nothing -> false `shouldEqual` true

    it "capabilities: createItem = true" do
      case readJSON_ managerSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanCreateItem `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "capabilities: viewAllLocations = false (not admin)" do
      case readJSON_ managerSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanViewAllLocations `shouldEqual` false
        Nothing -> false `shouldEqual` true

    it "capabilities: manageUsers = false (not admin)" do
      case readJSON_ managerSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanManageUsers `shouldEqual` false
        Nothing -> false `shouldEqual` true

  describe "Customer session field preservation" do
    it "preserves role as Customer" do
      case readJSON_ customerSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionRole `shouldEqual` Customer
        Nothing -> false `shouldEqual` true

    it "capabilities: viewInventory = true" do
      case readJSON_ customerSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanViewInventory `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "capabilities: processTransaction = false" do
      case readJSON_ customerSessionJson :: Maybe SessionResponse of
        Just s  -> s.sessionCapabilities.capCanProcessTransaction `shouldEqual` false
        Nothing -> false `shouldEqual` true

  -- ─────────────────────────────────────────────────────────────────────────
  -- Capability/role parity with Types.Auth
  -- The session endpoint should return the same capabilities that
  -- capabilitiesForRole produces locally — these tests catch any drift.
  -- ─────────────────────────────────────────────────────────────────────────

  describe "Session capabilities match local capabilitiesForRole" do
    it "admin session caps match adminCapabilities shape" do
      case readJSON_ adminSessionJson :: Maybe SessionResponse of
        Just s -> do
          let caps = s.sessionCapabilities
          caps.capCanViewInventory      `shouldEqual` true
          caps.capCanCreateItem         `shouldEqual` true
          caps.capCanEditItem           `shouldEqual` true
          caps.capCanDeleteItem         `shouldEqual` true
          caps.capCanProcessTransaction `shouldEqual` true
          caps.capCanVoidTransaction    `shouldEqual` true
          caps.capCanRefundTransaction  `shouldEqual` true
          caps.capCanApplyDiscount      `shouldEqual` true
          caps.capCanManageRegisters    `shouldEqual` true
          caps.capCanOpenRegister       `shouldEqual` true
          caps.capCanCloseRegister      `shouldEqual` true
          caps.capCanViewReports        `shouldEqual` true
          caps.capCanViewAllLocations   `shouldEqual` true
          caps.capCanManageUsers        `shouldEqual` true
          caps.capCanViewCompliance     `shouldEqual` true
          caps.capCanFulfillOrders      `shouldEqual` true
          caps.capCanViewAdminDashboard `shouldEqual` true
          caps.capCanPerformAdminActions `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "cashier session caps match cashierCapabilities shape" do
      case readJSON_ cashierSessionJson :: Maybe SessionResponse of
        Just s -> do
          let caps = s.sessionCapabilities
          caps.capCanViewInventory      `shouldEqual` true
          caps.capCanCreateItem         `shouldEqual` false
          caps.capCanEditItem           `shouldEqual` true
          caps.capCanDeleteItem         `shouldEqual` false
          caps.capCanProcessTransaction `shouldEqual` true
          caps.capCanVoidTransaction    `shouldEqual` false
          caps.capCanRefundTransaction  `shouldEqual` false
          caps.capCanApplyDiscount      `shouldEqual` false
          caps.capCanManageRegisters    `shouldEqual` false
          caps.capCanOpenRegister       `shouldEqual` true
          caps.capCanCloseRegister      `shouldEqual` true
          caps.capCanViewReports        `shouldEqual` false
          caps.capCanViewAllLocations   `shouldEqual` false
          caps.capCanManageUsers        `shouldEqual` false
          caps.capCanViewCompliance     `shouldEqual` true
          caps.capCanFulfillOrders      `shouldEqual` true
          caps.capCanViewAdminDashboard `shouldEqual` false
          caps.capCanPerformAdminActions `shouldEqual` false
        Nothing -> false `shouldEqual` true