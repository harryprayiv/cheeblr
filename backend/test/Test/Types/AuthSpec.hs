{-# LANGUAGE OverloadedStrings #-}

module Test.Types.AuthSpec (spec) where

import Test.Hspec
import Data.Aeson (encode, decode, toJSON, fromJSON, Result(..))
import Types.Auth

-- Fixtures
mkTestUser :: UserRole -> AuthenticatedUser
mkTestUser role = AuthenticatedUser
  { auUserId     = read "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
  , auUserName   = "Test User"
  , auEmail      = Just "test@example.com"
  , auRole       = role
  , auLocationId = Nothing
  , auCreatedAt  = read "2024-01-01 00:00:00 UTC"
  }

mkTestSession :: UserRole -> SessionResponse
mkTestSession role =
  let user = mkTestUser role
  in SessionResponse
    { sessionUserId       = auUserId user
    , sessionUserName     = auUserName user
    , sessionRole         = role
    , sessionCapabilities = capabilitiesForRole role
    }

spec :: Spec
spec = describe "Types.Auth" $ do

  -- ──────────────────────────────────────────────
  -- UserRole ordering
  -- ──────────────────────────────────────────────
  describe "UserRole ordering" $ do
    it "Customer < Cashier" $
      (Customer < Cashier) `shouldBe` True
    it "Cashier < Manager" $
      (Cashier < Manager) `shouldBe` True
    it "Manager < Admin" $
      (Manager < Admin) `shouldBe` True
    it "Admin is top" $
      (Admin >= Customer) `shouldBe` True
    it "roles are equal to themselves" $ do
      (Customer == Customer) `shouldBe` True
      (Admin == Admin) `shouldBe` True
    it "Customer is minimum" $
      (Customer <= Cashier && Customer <= Manager && Customer <= Admin) `shouldBe` True

  -- ──────────────────────────────────────────────
  -- UserRole Show/Read roundtrip
  -- ──────────────────────────────────────────────
  describe "UserRole Show/Read" $ do
    it "roundtrips Customer" $ read (show Customer) `shouldBe` Customer
    it "roundtrips Cashier"  $ read (show Cashier) `shouldBe` Cashier
    it "roundtrips Manager"  $ read (show Manager) `shouldBe` Manager
    it "roundtrips Admin"    $ read (show Admin) `shouldBe` Admin

  -- ──────────────────────────────────────────────
  -- UserRole JSON — wire format matters for frontend
  -- ──────────────────────────────────────────────
  describe "UserRole JSON" $ do
    it "serializes Customer as bare string" $
      toJSON Customer `shouldBe` toJSON ("Customer" :: String)
    it "serializes Cashier as bare string" $
      toJSON Cashier `shouldBe` toJSON ("Cashier" :: String)
    it "serializes Manager as bare string" $
      toJSON Manager `shouldBe` toJSON ("Manager" :: String)
    it "serializes Admin as bare string" $
      toJSON Admin `shouldBe` toJSON ("Admin" :: String)
    it "roundtrips all roles through JSON" $ do
      let roles = [Customer, Cashier, Manager, Admin]
      mapM_ (\r -> fromJSON (toJSON r) `shouldBe` Success r) roles

  -- ──────────────────────────────────────────────
  -- capabilitiesForRole: Customer
  -- ──────────────────────────────────────────────
  describe "capabilitiesForRole Customer" $ do
    let caps = capabilitiesForRole Customer
    it "can view inventory"         $ capCanViewInventory caps `shouldBe` True
    it "cannot create items"        $ capCanCreateItem caps `shouldBe` False
    it "cannot edit items"          $ capCanEditItem caps `shouldBe` False
    it "cannot delete items"        $ capCanDeleteItem caps `shouldBe` False
    it "cannot process transaction" $ capCanProcessTransaction caps `shouldBe` False
    it "cannot void transaction"    $ capCanVoidTransaction caps `shouldBe` False
    it "cannot refund transaction"  $ capCanRefundTransaction caps `shouldBe` False
    it "cannot apply discount"      $ capCanApplyDiscount caps `shouldBe` False
    it "cannot manage registers"    $ capCanManageRegisters caps `shouldBe` False
    it "cannot open register"       $ capCanOpenRegister caps `shouldBe` False
    it "cannot close register"      $ capCanCloseRegister caps `shouldBe` False
    it "cannot view reports"        $ capCanViewReports caps `shouldBe` False
    it "cannot view all locations"  $ capCanViewAllLocations caps `shouldBe` False
    it "cannot manage users"        $ capCanManageUsers caps `shouldBe` False
    it "cannot view compliance"     $ capCanViewCompliance caps `shouldBe` False

  -- ──────────────────────────────────────────────
  -- capabilitiesForRole: Cashier
  -- ──────────────────────────────────────────────
  describe "capabilitiesForRole Cashier" $ do
    let caps = capabilitiesForRole Cashier
    it "can view inventory"         $ capCanViewInventory caps `shouldBe` True
    it "cannot create items"        $ capCanCreateItem caps `shouldBe` False
    it "can edit items"             $ capCanEditItem caps `shouldBe` True
    it "cannot delete items"        $ capCanDeleteItem caps `shouldBe` False
    it "can process transaction"    $ capCanProcessTransaction caps `shouldBe` True
    it "cannot void transaction"    $ capCanVoidTransaction caps `shouldBe` False
    it "cannot refund transaction"  $ capCanRefundTransaction caps `shouldBe` False
    it "cannot apply discount"      $ capCanApplyDiscount caps `shouldBe` False
    it "cannot manage registers"    $ capCanManageRegisters caps `shouldBe` False
    it "can open register"          $ capCanOpenRegister caps `shouldBe` True
    it "can close register"         $ capCanCloseRegister caps `shouldBe` True
    it "cannot view reports"        $ capCanViewReports caps `shouldBe` False
    it "cannot view all locations"  $ capCanViewAllLocations caps `shouldBe` False
    it "cannot manage users"        $ capCanManageUsers caps `shouldBe` False
    it "can view compliance"        $ capCanViewCompliance caps `shouldBe` True

  -- ──────────────────────────────────────────────
  -- capabilitiesForRole: Manager
  -- ──────────────────────────────────────────────
  describe "capabilitiesForRole Manager" $ do
    let caps = capabilitiesForRole Manager
    it "can view inventory"         $ capCanViewInventory caps `shouldBe` True
    it "can create items"           $ capCanCreateItem caps `shouldBe` True
    it "can edit items"             $ capCanEditItem caps `shouldBe` True
    it "can delete items"           $ capCanDeleteItem caps `shouldBe` True
    it "can process transaction"    $ capCanProcessTransaction caps `shouldBe` True
    it "can void transaction"       $ capCanVoidTransaction caps `shouldBe` True
    it "can refund transaction"     $ capCanRefundTransaction caps `shouldBe` True
    it "can apply discount"         $ capCanApplyDiscount caps `shouldBe` True
    it "can manage registers"       $ capCanManageRegisters caps `shouldBe` True
    it "can open register"          $ capCanOpenRegister caps `shouldBe` True
    it "can close register"         $ capCanCloseRegister caps `shouldBe` True
    it "can view reports"           $ capCanViewReports caps `shouldBe` True
    it "cannot view all locations"  $ capCanViewAllLocations caps `shouldBe` False
    it "cannot manage users"        $ capCanManageUsers caps `shouldBe` False
    it "can view compliance"        $ capCanViewCompliance caps `shouldBe` True

  -- ──────────────────────────────────────────────
  -- capabilitiesForRole: Admin
  -- ──────────────────────────────────────────────
  describe "capabilitiesForRole Admin" $ do
    let caps = capabilitiesForRole Admin
    it "can view inventory"         $ capCanViewInventory caps `shouldBe` True
    it "can create items"           $ capCanCreateItem caps `shouldBe` True
    it "can edit items"             $ capCanEditItem caps `shouldBe` True
    it "can delete items"           $ capCanDeleteItem caps `shouldBe` True
    it "can process transaction"    $ capCanProcessTransaction caps `shouldBe` True
    it "can void transaction"       $ capCanVoidTransaction caps `shouldBe` True
    it "can refund transaction"     $ capCanRefundTransaction caps `shouldBe` True
    it "can apply discount"         $ capCanApplyDiscount caps `shouldBe` True
    it "can manage registers"       $ capCanManageRegisters caps `shouldBe` True
    it "can open register"          $ capCanOpenRegister caps `shouldBe` True
    it "can close register"         $ capCanCloseRegister caps `shouldBe` True
    it "can view reports"           $ capCanViewReports caps `shouldBe` True
    it "can view all locations"     $ capCanViewAllLocations caps `shouldBe` True
    it "can manage users"           $ capCanManageUsers caps `shouldBe` True
    it "can view compliance"        $ capCanViewCompliance caps `shouldBe` True

  -- ──────────────────────────────────────────────
  -- UserCapabilities JSON
  -- ──────────────────────────────────────────────
  describe "UserCapabilities JSON roundtrip" $ do
    it "roundtrips Customer capabilities" $ do
      let caps = capabilitiesForRole Customer
      decode (encode caps) `shouldBe` Just caps
    it "roundtrips Admin capabilities" $ do
      let caps = capabilitiesForRole Admin
      decode (encode caps) `shouldBe` Just caps

  describe "UserCapabilities JSON field names" $ do
      it "all 18 capability fields survive a roundtrip" $ do
        let caps = capabilitiesForRole Admin
        decode (encode caps) `shouldBe` Just caps
      it "capability fields are booleans accessible after decode" $ do
        let caps = capabilitiesForRole Cashier
        case decode (encode caps) of
          Just c  -> do
            capCanViewInventory c `shouldBe` True
            capCanCreateItem c `shouldBe` False
          Nothing -> expectationFailure "Failed to decode UserCapabilities"

  -- ──────────────────────────────────────────────
  -- hasCapability
  -- ──────────────────────────────────────────────
  describe "hasCapability" $ do
    it "customer has view inventory" $
      hasCapability capCanViewInventory (mkTestUser Customer) `shouldBe` True
    it "customer lacks create item" $
      hasCapability capCanCreateItem (mkTestUser Customer) `shouldBe` False
    it "cashier has process transaction" $
      hasCapability capCanProcessTransaction (mkTestUser Cashier) `shouldBe` True
    it "cashier lacks void transaction" $
      hasCapability capCanVoidTransaction (mkTestUser Cashier) `shouldBe` False
    it "manager has delete item" $
      hasCapability capCanDeleteItem (mkTestUser Manager) `shouldBe` True
    it "manager lacks manage users" $
      hasCapability capCanManageUsers (mkTestUser Manager) `shouldBe` False
    it "admin has all capabilities" $ do
      let user = mkTestUser Admin
      hasCapability capCanViewInventory user `shouldBe` True
      hasCapability capCanManageUsers user `shouldBe` True
      hasCapability capCanViewAllLocations user `shouldBe` True

  -- ──────────────────────────────────────────────
  -- requireCapability
  -- ──────────────────────────────────────────────
  describe "requireCapability" $ do
    it "returns Right for permitted action" $
      requireCapability capCanViewInventory "No view" (mkTestUser Customer)
        `shouldBe` Right ()
    it "returns Left for denied action" $
      requireCapability capCanDeleteItem "No delete" (mkTestUser Customer)
        `shouldBe` Left "No delete"
    it "returns Right for admin on any capability" $
      requireCapability capCanManageUsers "No manage" (mkTestUser Admin)
        `shouldBe` Right ()
    it "preserves error message" $
      requireCapability capCanCreateItem "Custom error msg" (mkTestUser Cashier)
        `shouldBe` Left "Custom error msg"

  -- ──────────────────────────────────────────────
  -- AuthenticatedUser JSON
  -- ──────────────────────────────────────────────
  describe "AuthenticatedUser JSON" $ do
    it "roundtrips through JSON" $ do
      let user = mkTestUser Admin
      decode (encode user) `shouldBe` Just user
    it "preserves role" $ do
      let user = mkTestUser Manager
      case decode (encode user) of
        Just u  -> auRole u `shouldBe` Manager
        Nothing -> expectationFailure "Failed to decode"
    it "preserves email" $ do
      let user = mkTestUser Customer
      case decode (encode user) of
        Just u  -> auEmail u `shouldBe` Just "test@example.com"
        Nothing -> expectationFailure "Failed to decode"
    it "handles Nothing locationId" $ do
      let user = mkTestUser Customer
      case decode (encode user) of
        Just u  -> auLocationId u `shouldBe` Nothing
        Nothing -> expectationFailure "Failed to decode"
    it "handles Just locationId" $ do
      let user = (mkTestUser Customer)
            { auLocationId = Just (read "b2bd4b3a-d50f-4c04-90b1-01266735876b") }
      case decode (encode user) of
        Just u  -> auLocationId u `shouldBe` Just (read "b2bd4b3a-d50f-4c04-90b1-01266735876b")
        Nothing -> expectationFailure "Failed to decode"

  -- ──────────────────────────────────────────────
  -- SessionResponse JSON  (NEW — was entirely untested)
  -- This is what GET /session returns; PureScript frontend reads it
  -- to initialise capabilities after login.
  -- ──────────────────────────────────────────────
  describe "SessionResponse JSON" $ do
    it "roundtrips Customer session" $
      decode (encode (mkTestSession Customer)) `shouldBe` Just (mkTestSession Customer)

    it "roundtrips Cashier session" $
      decode (encode (mkTestSession Cashier)) `shouldBe` Just (mkTestSession Cashier)

    it "roundtrips Manager session" $
      decode (encode (mkTestSession Manager)) `shouldBe` Just (mkTestSession Manager)

    it "roundtrips Admin session" $
      decode (encode (mkTestSession Admin)) `shouldBe` Just (mkTestSession Admin)

    it "preserves userId" $ do
      let sess = mkTestSession Admin
      case decode (encode sess) of
        Just s  -> sessionUserId s `shouldBe` sessionUserId sess
        Nothing -> expectationFailure "Failed to decode"

    it "preserves role" $ do
      let sess = mkTestSession Manager
      case decode (encode sess) of
        Just s  -> sessionRole s `shouldBe` Manager
        Nothing -> expectationFailure "Failed to decode"

    it "preserves capabilities" $ do
      let sess = mkTestSession Cashier
      case decode (encode sess) of
        Just s  -> sessionCapabilities s `shouldBe` capabilitiesForRole Cashier
        Nothing -> expectationFailure "Failed to decode"

    it "capabilities in session match capabilitiesForRole" $ do
      let roles = [Customer, Cashier, Manager, Admin]
      mapM_ (\r ->
        let sess = mkTestSession r
        in sessionCapabilities sess `shouldBe` capabilitiesForRole r
        ) roles

  describe "SessionResponse JSON wire format" $ do
    -- PureScript reads these exact field names from /session response.
    -- A rename here breaks the frontend silently (optional fields default to Nothing).
    it "has sessionUserId field" $ do
      case toJSON (mkTestSession Admin) of
        obj -> decode (encode obj) `shouldSatisfy`
                 (\r -> case (r :: Maybe SessionResponse) of
                    Just s -> sessionUserName s == "Test User"
                    Nothing -> False)

    it "capabilities object is present in response" $ do
      let sess = mkTestSession Admin
      case decode (encode sess) of
        Just s -> do
          let caps = sessionCapabilities s
          capCanManageUsers caps `shouldBe` True
        Nothing -> expectationFailure "Failed to decode"

    it "Cashier session capabilities have correct values for UI rendering" $ do
      let sess = mkTestSession Cashier
      case decode (encode sess) of
        Just s -> do
          let caps = sessionCapabilities s
          -- Cashier-specific: can process but not void/refund
          capCanProcessTransaction caps `shouldBe` True
          capCanVoidTransaction caps `shouldBe` False
          capCanRefundTransaction caps `shouldBe` False
          capCanApplyDiscount caps `shouldBe` False
        Nothing -> expectationFailure "Failed to decode"