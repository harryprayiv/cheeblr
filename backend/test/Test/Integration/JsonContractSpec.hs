{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Integration.JsonContractSpec (spec) where

import Test.Hspec
    ( Spec, describe, it, shouldBe, expectationFailure )
import Data.Aeson
    ( Result(..),
      ToJSON(toJSON),
      Value(..),
      encode,
      decode,
      fromJSON,
      object,
      KeyValue((.=)) )
import Data.Aeson.KeyMap (member)
import qualified Data.Aeson.KeyMap as KM
import Data.Scientific (fromFloatDigits)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Data.Text as T
import qualified Data.Vector as V
import Types.Location (LocationId (..))

import Types.Auth
    ( capabilitiesForRole,
      AuthenticatedUser(auRole),
      SessionResponse(SessionResponse, sessionUserId, sessionUserName,
                      sessionRole, sessionCapabilities),
      UserCapabilities(capCanViewCompliance, capCanOpenRegister,
                       capCanCloseRegister, capCanEditItem, capCanProcessTransaction,
                       capCanRefundTransaction, capCanViewInventory, capCanCreateItem,
                       capCanDeleteItem, capCanVoidTransaction, capCanApplyDiscount,
                       capCanViewAllLocations, capCanManageUsers),
      UserRole(Admin, Customer, Cashier, Manager) )
import Types.Inventory
    ( Inventory(Inventory),
      ItemCategory(Flower, PreRolls, Vaporizers, Edibles),
      MenuItem(..),
      MutationResponse(MutationResponse),
      Species(Indica, IndicaDominantHybrid, Hybrid, Sativa),
      StrainLineage(species, thc, cbg, strain, creator, dominant_terpene,
                    terpenes, lineage, leafly_url, img, StrainLineage) )
import Types.Transaction
    ( TaxRecord(taxDescription, TaxRecord, taxCategory, taxRate,
                taxAmount),
      TaxCategory(RegularSalesTax, ExciseTax, CannabisTax, LocalTax,
                  MedicalTax, NoTax),
      DiscountType(..),
      TransactionItem(..),
      PaymentTransaction(..),
      PaymentMethod(..),
      Transaction(..),
      TransactionStatus(..),
      TransactionType(Sale, Return, Exchange, InventoryAdjustment,
                      ManagerComp, Administrative),
      parsePaymentMethod )
import API.Transaction
  ( Register(..)
  
  
  )
import Auth.Simple (lookupUser)
import DB.Transaction (showPaymentMethod)

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testUUID :: UUID
testUUID = read "33333333-3333-3333-3333-333333333333"

testUUID2 :: UUID
testUUID2 = read "44444444-4444-4444-4444-444444444444"

testTime :: UTCTime
testTime = read "2024-06-15 10:30:00 UTC"

spec :: Spec
spec = describe "Integration: JSON Contract Tests" $ do

  -- ═══════════════════════════════════════════════
  -- SECTION 1: Enum wire format compatibility
  -- Backend ToJSON ↔ Frontend ReadForeign
  -- ═══════════════════════════════════════════════

  describe "Enum wire formats (Backend → Frontend)" $ do

    describe "UserRole" $ do
      it "serializes as bare strings matching PureScript expectation" $ do
        toJSON Customer `shouldBe` String "Customer"
        toJSON Cashier  `shouldBe` String "Cashier"
        toJSON Manager  `shouldBe` String "Manager"
        toJSON Admin    `shouldBe` String "Admin"

    describe "TransactionStatus" $ do
      it "serializes as PascalCase strings" $ do
        toJSON Created    `shouldBe` String "Created"
        toJSON InProgress `shouldBe` String "InProgress"
        toJSON Completed  `shouldBe` String "Completed"
        toJSON Voided     `shouldBe` String "Voided"
        toJSON Refunded   `shouldBe` String "Refunded"

      it "PascalCase strings parse in backend" $ do
        fromJSON (String "Created")    `shouldBe` (Success Created    :: Result TransactionStatus)
        fromJSON (String "InProgress") `shouldBe` (Success InProgress :: Result TransactionStatus)
        fromJSON (String "Completed")  `shouldBe` (Success Completed  :: Result TransactionStatus)

    describe "TransactionType" $ do
      it "serializes as PascalCase strings" $ do
        toJSON Sale                `shouldBe` String "Sale"
        toJSON Return              `shouldBe` String "Return"
        toJSON Exchange            `shouldBe` String "Exchange"
        toJSON InventoryAdjustment `shouldBe` String "InventoryAdjustment"
        toJSON ManagerComp         `shouldBe` String "ManagerComp"
        toJSON Administrative      `shouldBe` String "Administrative"

    describe "PaymentMethod" $ do
      it "serializes standard methods as PascalCase" $ do
        toJSON Cash        `shouldBe` String "Cash"
        toJSON Debit       `shouldBe` String "Debit"
        toJSON Credit      `shouldBe` String "Credit"
        toJSON ACH         `shouldBe` String "ACH"
        toJSON GiftCard    `shouldBe` String "GiftCard"
        toJSON StoredValue `shouldBe` String "StoredValue"
        toJSON Mixed       `shouldBe` String "Mixed"

      it "serializes Other with colon prefix preserving payload" $ do
        -- PureScript reads "Other:..." and "OTHER:..." via isPrefixOf
        toJSON (Other "Crypto") `shouldBe` String "Other:Crypto"

      it "parses PureScript-produced Other format" $ do
        fromJSON (String "Other:Bitcoin") `shouldBe` (Success (Other "Bitcoin") :: Result PaymentMethod)
        fromJSON (String "OTHER:Check")   `shouldBe` (Success (Other "Check")   :: Result PaymentMethod)

    describe "TaxCategory" $ do
      it "serializes as PascalCase strings" $ do
        toJSON RegularSalesTax `shouldBe` String "RegularSalesTax"
        toJSON ExciseTax       `shouldBe` String "ExciseTax"
        toJSON CannabisTax     `shouldBe` String "CannabisTax"
        toJSON LocalTax        `shouldBe` String "LocalTax"
        toJSON MedicalTax      `shouldBe` String "MedicalTax"
        toJSON NoTax           `shouldBe` String "NoTax"

    describe "ItemCategory" $ do
      it "serializes as PascalCase strings matching frontend Show" $ do
        toJSON Flower    `shouldBe` String "Flower"
        toJSON PreRolls  `shouldBe` String "PreRolls"
        toJSON Vaporizers `shouldBe` String "Vaporizers"
        toJSON Edibles   `shouldBe` String "Edibles"

    describe "Species" $ do
      it "serializes as PascalCase strings matching frontend Show" $ do
        toJSON Indica              `shouldBe` String "Indica"
        toJSON IndicaDominantHybrid `shouldBe` String "IndicaDominantHybrid"
        toJSON Hybrid              `shouldBe` String "Hybrid"
        toJSON Sativa              `shouldBe` String "Sativa"

  -- ═══════════════════════════════════════════════
  -- SECTION 2: Complex type wire format
  -- ═══════════════════════════════════════════════

  describe "Complex type wire formats" $ do

    describe "MenuItem JSON structure" $ do
      it "has field names matching PureScript record fields" $ do
        let item = MenuItem
              { sort = 1, sku = testUUID, brand = "TestBrand", name = "OG Kush"
              , price = 2999, measure_unit = "g", per_package = "3.5"
              , quantity = 10, category = Flower, subcategory = "Indoor"
              , description = "Classic", tags = V.fromList ["indica"]
              , effects = V.fromList ["relaxed"]
              , strain_lineage = StrainLineage
                  { thc = "25%", cbg = "0.5%", strain = "OG Kush"
                  , creator = "Unknown", species = Indica
                  , dominant_terpene = "Myrcene"
                  , terpenes = V.fromList ["Myrcene"]
                  , lineage = V.fromList ["Chemdawg"]
                  , leafly_url = "https://leafly.com"
                  , img = "https://example.com/img.jpg"
                  }
              }
        case toJSON item of
          Object obj -> do
            member "sort"          obj `shouldBe` True
            member "sku"           obj `shouldBe` True
            member "brand"         obj `shouldBe` True
            member "name"          obj `shouldBe` True
            member "price"         obj `shouldBe` True
            member "measure_unit"  obj `shouldBe` True
            member "per_package"   obj `shouldBe` True
            member "quantity"      obj `shouldBe` True
            member "category"      obj `shouldBe` True
            member "subcategory"   obj `shouldBe` True
            member "description"   obj `shouldBe` True
            member "tags"          obj `shouldBe` True
            member "effects"       obj `shouldBe` True
            member "strain_lineage" obj `shouldBe` True
          _ -> expectationFailure "MenuItem should serialize as object"

      it "serializes price as plain integer (cents)" $ do
        let item = MenuItem 0 testUUID "B" "N" 2999 "g" "3.5" 10
                     Flower "Sub" "Desc" V.empty V.empty
                     (StrainLineage "25%" "0.5%" "S" "C" Indica "M"
                       V.empty V.empty "https://l.com" "https://i.com")
        case toJSON item of
          Object obj -> case KM.lookup "price" obj of
            Just (Number n) -> n `shouldBe` 2999
            _ -> expectationFailure "price should be a number"
          _ -> expectationFailure "Expected object"

    describe "Inventory JSON structure" $ do
      -- FIX: Inventory uses a custom ToJSON that serializes as a plain array,
      -- NOT as {"items": [...]}. The PureScript frontend reads it as an array.
      it "serializes as a plain JSON array (not a wrapped object)" $ do
        let inv = Inventory (V.fromList [])
        case toJSON inv of
          Array _ -> pure ()  -- correct: plain array
          Object _ -> expectationFailure "Inventory should NOT be an object wrapper"
          _ -> expectationFailure "Inventory should be a JSON array"

      it "frontend receives array it can decode as MenuItem[]" $ do
        let inv = Inventory (V.fromList [])
        -- If this decodes back to Inventory, the array format is self-consistent
        decode (encode inv) `shouldBe` Just inv

    describe "MutationResponse JSON structure" $ do
      -- Field names: "success" and "message" — PureScript reads both via .:
      it "has 'success' and 'message' fields" $ do
        let r = MutationResponse True "Item added successfully"
        case toJSON r of
          Object obj -> do
            member "success" obj `shouldBe` True
            member "message" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

      it "success field is boolean" $ do
        let r = MutationResponse True "ok"
        case toJSON r of
          Object obj -> case KM.lookup "success" obj of
            Just (Bool True) -> pure ()
            _ -> expectationFailure "success should be boolean true"
          _ -> expectationFailure "Expected object"

    describe "Transaction JSON structure" $ do
      it "has all field names matching PureScript Transaction newtype" $ do
        let tx = Transaction
              { transactionId = testUUID, transactionStatus = Created
              , transactionCreated = testTime, transactionCompleted = Nothing
              , transactionCustomerId = Nothing, transactionEmployeeId = testUUID2
              , transactionRegisterId = testUUID2, transactionLocationId = LocationId testUUID2
              , transactionItems = [], transactionPayments = []
              , transactionSubtotal = 0, transactionDiscountTotal = 0
              , transactionTaxTotal = 0, transactionTotal = 0
              , transactionType = Sale, transactionIsVoided = False
              , transactionVoidReason = Nothing, transactionIsRefunded = False
              , transactionRefundReason = Nothing
              , transactionReferenceTransactionId = Nothing
              , transactionNotes = Nothing
              }
        case toJSON tx of
          Object obj -> do
            member "transactionId"             obj `shouldBe` True
            member "transactionStatus"         obj `shouldBe` True
            member "transactionCreated"        obj `shouldBe` True
            member "transactionEmployeeId"     obj `shouldBe` True
            member "transactionRegisterId"     obj `shouldBe` True
            member "transactionLocationId"     obj `shouldBe` True
            member "transactionItems"          obj `shouldBe` True
            member "transactionPayments"       obj `shouldBe` True
            member "transactionSubtotal"       obj `shouldBe` True
            member "transactionDiscountTotal"  obj `shouldBe` True
            member "transactionTaxTotal"       obj `shouldBe` True
            member "transactionTotal"          obj `shouldBe` True
            member "transactionType"           obj `shouldBe` True
            member "transactionIsVoided"       obj `shouldBe` True
            member "transactionIsRefunded"     obj `shouldBe` True
          _ -> expectationFailure "Transaction should serialize as object"

      it "serializes monetary fields as plain integers" $ do
        let tx = Transaction testUUID Created testTime Nothing Nothing
                   testUUID2 testUUID2 (LocationId testUUID2) [] []
                   5000 100 400 5300 Sale False Nothing False Nothing Nothing Nothing
        case toJSON tx of
          Object obj -> do
            KM.lookup "transactionSubtotal"      obj `shouldBe` Just (Number 5000)
            KM.lookup "transactionDiscountTotal" obj `shouldBe` Just (Number 100)
            KM.lookup "transactionTaxTotal"      obj `shouldBe` Just (Number 400)
            KM.lookup "transactionTotal"         obj `shouldBe` Just (Number 5300)
          _ -> expectationFailure "Expected object"

    describe "TransactionItem JSON structure" $ do
      it "has matching field names" $ do
        let item = TransactionItem
              { transactionItemId = testUUID
              , transactionItemTransactionId = testUUID2
              , transactionItemMenuItemSku = testUUID
              , transactionItemQuantity = 2
              , transactionItemPricePerUnit = 1000
              , transactionItemDiscounts = []
              , transactionItemTaxes = []
              , transactionItemSubtotal = 2000
              , transactionItemTotal = 2160
              }
        case toJSON item of
          Object obj -> do
            member "transactionItemId"            obj `shouldBe` True
            member "transactionItemTransactionId" obj `shouldBe` True
            member "transactionItemMenuItemSku"   obj `shouldBe` True
            member "transactionItemQuantity"      obj `shouldBe` True
            member "transactionItemPricePerUnit"  obj `shouldBe` True
            member "transactionItemDiscounts"     obj `shouldBe` True
            member "transactionItemTaxes"         obj `shouldBe` True
            member "transactionItemSubtotal"      obj `shouldBe` True
            member "transactionItemTotal"         obj `shouldBe` True
          _ -> expectationFailure "Expected object"

    describe "PaymentTransaction JSON structure" $ do
      it "has all expected field names" $ do
        let payment = PaymentTransaction
              { paymentId = testUUID, paymentTransactionId = testUUID2
              , paymentMethod = Cash, paymentAmount = 5000
              , paymentTendered = 6000, paymentChange = 1000
              , paymentReference = Nothing, paymentApproved = True
              , paymentAuthorizationCode = Nothing
              }
        case toJSON payment of
          Object obj -> do
            member "paymentId"                obj `shouldBe` True
            member "paymentTransactionId"     obj `shouldBe` True
            member "paymentMethod"            obj `shouldBe` True
            member "paymentAmount"            obj `shouldBe` True
            member "paymentTendered"          obj `shouldBe` True
            member "paymentChange"            obj `shouldBe` True
            member "paymentApproved"          obj `shouldBe` True
          _ -> expectationFailure "Expected object"

    describe "TaxRecord JSON structure" $ do
      it "has matching field names" $ do
        let tax = TaxRecord
              { taxCategory = RegularSalesTax
              , taxRate = fromFloatDigits (0.08 :: Double)
              , taxAmount = 80
              , taxDescription = "Sales Tax"
              }
        case toJSON tax of
          Object obj -> do
            member "taxCategory"    obj `shouldBe` True
            member "taxRate"        obj `shouldBe` True
            member "taxAmount"      obj `shouldBe` True
            member "taxDescription" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

    describe "DiscountType JSON structure" $ do
      -- The custom ToJSON instance produces a flat object with a "discountType"
      -- discriminator — matching what PureScript WriteForeign produces.
      -- This was formerly documented as a "KNOWN MISMATCH" but has been resolved.
      it "PercentOff uses 'discountType' discriminator field (not 'tag')" $ do
        let dt = PercentOff (fromFloatDigits (10.0 :: Double))
        case toJSON dt of
          Object obj -> do
            member "discountType" obj `shouldBe` True   -- present: custom instance
            member "tag"          obj `shouldBe` False  -- absent: not Generic-derived
          _ -> expectationFailure "Expected object"

      it "AmountOff uses 'discountType' discriminator field" $ do
        let dt = AmountOff 500
        case toJSON dt of
          Object obj -> do
            member "discountType" obj `shouldBe` True
            member "tag"          obj `shouldBe` False
          _ -> expectationFailure "Expected object"

      it "PercentOff discriminator value is PERCENT_OFF" $ do
        let dt = PercentOff (fromFloatDigits (10.0 :: Double))
        case toJSON dt of
          Object obj -> KM.lookup "discountType" obj `shouldBe` Just (String "PERCENT_OFF")
          _ -> expectationFailure "Expected object"

      it "AmountOff discriminator value is AMOUNT_OFF" $ do
        case toJSON (AmountOff 500) of
          Object obj -> KM.lookup "discountType" obj `shouldBe` Just (String "AMOUNT_OFF")
          _ -> expectationFailure "Expected object"

      it "BuyOneGetOne discriminator value is BUY_ONE_GET_ONE" $ do
        case toJSON BuyOneGetOne of
          Object obj -> KM.lookup "discountType" obj `shouldBe` Just (String "BUY_ONE_GET_ONE")
          _ -> expectationFailure "Expected object"

      it "Custom discriminator value is CUSTOM" $ do
        case toJSON (Custom "Employee" 250) of
          Object obj -> KM.lookup "discountType" obj `shouldBe` Just (String "CUSTOM")
          _ -> expectationFailure "Expected object"

      it "PercentOff includes 'percent' payload field" $ do
        let dt = PercentOff (fromFloatDigits (15.0 :: Double))
        case toJSON dt of
          Object obj -> member "percent" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

      it "AmountOff includes 'amount' payload field" $ do
        case toJSON (AmountOff 500) of
          Object obj -> member "amount" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

      it "Custom includes 'name' and 'amount' fields" $ do
        case toJSON (Custom "Employee" 250) of
          Object obj -> do
            member "name"   obj `shouldBe` True
            member "amount" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

      it "parses PureScript-format DiscountType JSON" $ do
        -- This is what PureScript WriteForeign produces
        let frontendJson = object
              [ "discountType" .= String "PERCENT_OFF"
              , "percent" .= (10.0 :: Double)
              ]
        let result = fromJSON frontendJson :: Result DiscountType
        case result of
          Success (PercentOff _) -> pure ()
          Success other -> expectationFailure $ "Got wrong constructor: " ++ show other
          Error err -> expectationFailure $ "Failed to parse: " ++ err

    describe "Register JSON structure" $ do
      it "has field names matching PureScript Register type" $ do
        let reg = Register
              { registerId = testUUID, registerName = "Register 1"
              , registerLocationId = LocationId testUUID2, registerIsOpen = True
              , registerCurrentDrawerAmount = 50000
              , registerExpectedDrawerAmount = 50000
              , registerOpenedAt = Just testTime
              , registerOpenedBy = Just testUUID
              , registerLastTransactionTime = Nothing
              }
        case toJSON reg of
          Object obj -> do
            member "registerId"                 obj `shouldBe` True
            member "registerName"               obj `shouldBe` True
            member "registerLocationId"         obj `shouldBe` True
            member "registerIsOpen"             obj `shouldBe` True
            member "registerCurrentDrawerAmount" obj `shouldBe` True
            member "registerExpectedDrawerAmount" obj `shouldBe` True
            member "registerOpenedAt"           obj `shouldBe` True
            member "registerOpenedBy"           obj `shouldBe` True
            member "registerLastTransactionTime" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

    describe "SessionResponse JSON structure" $ do
      -- NEW: GET /session returns this. PureScript reads all four fields.
      it "has all fields the frontend expects" $ do
        let sess = SessionResponse
              { sessionUserId       = testUUID
              , sessionUserName     = "Test Cashier"
              , sessionRole         = Cashier
              , sessionCapabilities = capabilitiesForRole Cashier
              }
        case toJSON sess of
          Object obj -> do
            member "sessionUserId"       obj `shouldBe` True
            member "sessionUserName"     obj `shouldBe` True
            member "sessionRole"         obj `shouldBe` True
            member "sessionCapabilities" obj `shouldBe` True
          _ -> expectationFailure "SessionResponse should serialize as object"

      it "sessionCapabilities is a nested object with capability flags" $ do
        let sess = SessionResponse
              { sessionUserId = testUUID, sessionUserName = "Test"
              , sessionRole = Admin, sessionCapabilities = capabilitiesForRole Admin
              }
        case toJSON sess of
          Object obj -> case KM.lookup "sessionCapabilities" obj of
            Just (Object caps) -> do
              member "capCanViewInventory"  caps `shouldBe` True
              member "capCanCreateItem"     caps `shouldBe` True
              member "capCanManageUsers"    caps `shouldBe` True
              member "capCanViewCompliance" caps `shouldBe` True
            _ -> expectationFailure "sessionCapabilities should be an object"
          _ -> expectationFailure "Expected object"

      it "sessionRole serializes as a bare string" $ do
        let sess = SessionResponse testUUID "Test" Manager (capabilitiesForRole Manager)
        case toJSON sess of
          Object obj -> case KM.lookup "sessionRole" obj of
            Just (String "Manager") -> pure ()
            Just other -> expectationFailure $ "Expected String Manager, got: " ++ show other
            Nothing -> expectationFailure "sessionRole field missing"
          _ -> expectationFailure "Expected object"

      it "roundtrips through JSON for all roles" $ do
        let roles = [Customer, Cashier, Manager, Admin]
        mapM_ (\r ->
          let sess = SessionResponse testUUID "Test" r (capabilitiesForRole r)
          in decode (encode sess) `shouldBe` Just sess
          ) roles

  -- ═══════════════════════════════════════════════
  -- SECTION 3: Frontend → Backend parsing
  -- ═══════════════════════════════════════════════

  describe "Frontend → Backend JSON parsing" $ do

    describe "Transaction from PureScript" $ do
      it "parses PureScript-produced Transaction JSON" $ do
        let json = object
              [ "transactionId"                    .= testUUID
              , "transactionStatus"                .= String "Created"
              , "transactionCreated"               .= testTime
              , "transactionCompleted"             .= Null
              , "transactionCustomerId"            .= Null
              , "transactionEmployeeId"            .= testUUID2
              , "transactionRegisterId"            .= testUUID2
              , "transactionLocationId"            .= testUUID2
              , "transactionItems"                 .= ([] :: [Value])
              , "transactionPayments"              .= ([] :: [Value])
              , "transactionSubtotal"              .= (0 :: Int)
              , "transactionDiscountTotal"         .= (0 :: Int)
              , "transactionTaxTotal"              .= (0 :: Int)
              , "transactionTotal"                 .= (0 :: Int)
              , "transactionType"                  .= String "Sale"
              , "transactionIsVoided"              .= False
              , "transactionVoidReason"            .= Null
              , "transactionIsRefunded"            .= False
              , "transactionRefundReason"          .= Null
              , "transactionReferenceTransactionId" .= Null
              , "transactionNotes"                 .= Null
              ]
        let result = fromJSON json :: Result Transaction
        case result of
          Success tx -> do
            transactionStatus tx `shouldBe` Created
            transactionType tx `shouldBe` Sale
            transactionCompleted tx `shouldBe` Nothing
          Error err -> expectationFailure $ "Failed to parse: " ++ err

    describe "TransactionItem from PureScript" $ do
      it "parses PureScript-produced TransactionItem JSON" $ do
        let json = object
              [ "transactionItemId"            .= testUUID
              , "transactionItemTransactionId" .= testUUID2
              , "transactionItemMenuItemSku"   .= testUUID
              , "transactionItemQuantity"      .= (2 :: Int)
              , "transactionItemPricePerUnit"  .= (1000 :: Int)
              , "transactionItemDiscounts"     .= ([] :: [Value])
              , "transactionItemTaxes"         .= ([] :: [Value])
              , "transactionItemSubtotal"      .= (2000 :: Int)
              , "transactionItemTotal"         .= (2160 :: Int)
              ]
        let result = fromJSON json :: Result TransactionItem
        case result of
          Success item -> do
            transactionItemQuantity item `shouldBe` 2
            transactionItemPricePerUnit item `shouldBe` 1000
          Error err -> expectationFailure $ "Failed to parse: " ++ err

    describe "PaymentTransaction from PureScript" $ do
      it "parses PureScript-produced Payment JSON with null optionals" $ do
        let json = object
              [ "paymentId"                .= testUUID
              , "paymentTransactionId"     .= testUUID2
              , "paymentMethod"            .= String "Cash"
              , "paymentAmount"            .= (5000 :: Int)
              , "paymentTendered"          .= (6000 :: Int)
              , "paymentChange"            .= (1000 :: Int)
              , "paymentReference"         .= Null
              , "paymentApproved"          .= True
              , "paymentAuthorizationCode" .= Null
              ]
        let result = fromJSON json :: Result PaymentTransaction
        case result of
          Success p -> do
            paymentMethod p `shouldBe` Cash
            paymentAmount p `shouldBe` 5000
            paymentReference p `shouldBe` Nothing
          Error err -> expectationFailure $ "Failed to parse: " ++ err

      it "parses Payment with reference and auth code" $ do
        let json = object
              [ "paymentId"                .= testUUID
              , "paymentTransactionId"     .= testUUID2
              , "paymentMethod"            .= String "Credit"
              , "paymentAmount"            .= (5000 :: Int)
              , "paymentTendered"          .= (5000 :: Int)
              , "paymentChange"            .= (0 :: Int)
              , "paymentReference"         .= String "VISA-1234"
              , "paymentApproved"          .= True
              , "paymentAuthorizationCode" .= String "AUTH456"
              ]
        let result = fromJSON json :: Result PaymentTransaction
        case result of
          Success p -> do
            paymentMethod p `shouldBe` Credit
            paymentReference p `shouldBe` Just "VISA-1234"
            paymentAuthorizationCode p `shouldBe` Just "AUTH456"
          Error err -> expectationFailure $ "Failed to parse: " ++ err

    describe "MenuItem from PureScript" $ do
      it "parses PureScript-produced MenuItem JSON" $ do
        let json = object
              [ "sort"         .= (1 :: Int)
              , "sku"          .= testUUID
              , "brand"        .= String "TestBrand"
              , "name"         .= String "OG Kush"
              , "price"        .= (2999 :: Int)
              , "measure_unit" .= String "g"
              , "per_package"  .= String "3.5"
              , "quantity"     .= (10 :: Int)
              , "category"     .= String "Flower"
              , "subcategory"  .= String "Indoor"
              , "description"  .= String "Classic"
              , "tags"         .= (["indica", "classic"] :: [String])
              , "effects"      .= (["relaxed"] :: [String])
              , "strain_lineage" .= object
                  [ "thc"              .= String "25%"
                  , "cbg"              .= String "0.5%"
                  , "strain"           .= String "OG Kush"
                  , "creator"          .= String "Unknown"
                  , "species"          .= String "Indica"
                  , "dominant_terpene" .= String "Myrcene"
                  , "terpenes"         .= (["Myrcene"] :: [String])
                  , "lineage"          .= (["Chemdawg"] :: [String])
                  , "leafly_url"       .= String "https://leafly.com"
                  , "img"              .= String "https://example.com/img.jpg"
                  ]
              ]
        let result = fromJSON json :: Result MenuItem
        case result of
          Success item -> do
            name item `shouldBe` "OG Kush"
            price item `shouldBe` 2999
            category item `shouldBe` Flower
            species (strain_lineage item) `shouldBe` Indica
          Error err -> expectationFailure $ "Failed to parse: " ++ err

    describe "DiscountType from PureScript" $ do
      -- PureScript WriteForeign produces flat objects with "discountType" key.
      -- The custom FromJSON instance handles this format.
      it "parses PureScript PERCENT_OFF format" $ do
        let json = object
              [ "discountType" .= String "PERCENT_OFF"
              , "percent"      .= (10.0 :: Double)
              ]
        fromJSON json `shouldBe` (Success (PercentOff 10.0) :: Result DiscountType)

      it "parses PureScript AMOUNT_OFF format" $ do
        let json = object
              [ "discountType" .= String "AMOUNT_OFF"
              , "amount"       .= (500 :: Int)
              ]
        fromJSON json `shouldBe` (Success (AmountOff 500) :: Result DiscountType)

      it "parses PureScript BUY_ONE_GET_ONE format" $ do
        let json = object
              [ "discountType" .= String "BUY_ONE_GET_ONE"
              ]
        fromJSON json `shouldBe` (Success BuyOneGetOne :: Result DiscountType)

      it "parses PureScript CUSTOM format" $ do
        let json = object
              [ "discountType" .= String "CUSTOM"
              , "name"         .= String "Employee"
              , "amount"       .= (250 :: Int)
              ]
        fromJSON json `shouldBe` (Success (Custom "Employee" 250) :: Result DiscountType)

    describe "Register from PureScript" $ do
      it "parses PureScript-produced Register JSON" $ do
        let json = object
              [ "registerId"                  .= testUUID
              , "registerName"                .= String "Register 1"
              , "registerLocationId"          .= testUUID2
              , "registerIsOpen"              .= False
              , "registerCurrentDrawerAmount" .= (0 :: Int)
              , "registerExpectedDrawerAmount" .= (0 :: Int)
              , "registerOpenedAt"            .= Null
              , "registerOpenedBy"            .= Null
              , "registerLastTransactionTime" .= Null
              ]
        let result = fromJSON json :: Result Register
        case result of
          Success r -> do
            registerName r `shouldBe` "Register 1"
            registerIsOpen r `shouldBe` False
            registerOpenedAt r `shouldBe` Nothing
          Error err -> expectationFailure $ "Failed to parse: " ++ err

  -- ═══════════════════════════════════════════════
  -- SECTION 4: Auth contract — devUser UUIDs match
  -- ═══════════════════════════════════════════════

  describe "Auth contract: dev user UUIDs" $ do
    it "admin UUID matches"    $ auRole (lookupUser (Just "d3a1f4f0-c518-4db3-aa43-e80b428d6304")) `shouldBe` Admin
    it "customer UUID matches" $ auRole (lookupUser (Just "8244082f-a6bc-4d6c-9427-64a0ecdc10db")) `shouldBe` Customer
    it "cashier UUID matches"  $ auRole (lookupUser (Just "0a6f2deb-892b-4411-8025-08c1a4d61229")) `shouldBe` Cashier
    it "manager UUID matches"  $ auRole (lookupUser (Just "8b75ea4a-00a4-4a2a-a5d5-a1bab8883802")) `shouldBe` Manager

  -- ═══════════════════════════════════════════════
  -- SECTION 5: Capability definitions match frontend
  -- ═══════════════════════════════════════════════

  describe "Capability parity: backend == frontend definitions" $ do
    let caps = capabilitiesForRole

    describe "Customer" $ do
      it "viewInventory=T createItem=F editItem=F deleteItem=F" $ do
        capCanViewInventory (caps Customer) `shouldBe` True
        capCanCreateItem    (caps Customer) `shouldBe` False
        capCanEditItem      (caps Customer) `shouldBe` False
        capCanDeleteItem    (caps Customer) `shouldBe` False
      it "processTransaction=F voidTransaction=F refundTransaction=F" $ do
        capCanProcessTransaction (caps Customer) `shouldBe` False
        capCanVoidTransaction    (caps Customer) `shouldBe` False
        capCanRefundTransaction  (caps Customer) `shouldBe` False
      it "openRegister=F closeRegister=F viewCompliance=F" $ do
        capCanOpenRegister  (caps Customer) `shouldBe` False
        capCanCloseRegister (caps Customer) `shouldBe` False
        capCanViewCompliance (caps Customer) `shouldBe` False

    describe "Cashier" $ do
      it "editItem=T processTransaction=T openRegister=T closeRegister=T viewCompliance=T" $ do
        capCanEditItem           (caps Cashier) `shouldBe` True
        capCanProcessTransaction (caps Cashier) `shouldBe` True
        capCanOpenRegister       (caps Cashier) `shouldBe` True
        capCanCloseRegister      (caps Cashier) `shouldBe` True
        capCanViewCompliance     (caps Cashier) `shouldBe` True
      it "createItem=F deleteItem=F voidTransaction=F applyDiscount=F" $ do
        capCanCreateItem      (caps Cashier) `shouldBe` False
        capCanDeleteItem      (caps Cashier) `shouldBe` False
        capCanVoidTransaction (caps Cashier) `shouldBe` False
        capCanApplyDiscount   (caps Cashier) `shouldBe` False

    describe "Manager" $ do
      it "has all item and transaction permissions" $ do
        capCanCreateItem         (caps Manager) `shouldBe` True
        capCanEditItem           (caps Manager) `shouldBe` True
        capCanDeleteItem         (caps Manager) `shouldBe` True
        capCanProcessTransaction (caps Manager) `shouldBe` True
        capCanVoidTransaction    (caps Manager) `shouldBe` True
        capCanRefundTransaction  (caps Manager) `shouldBe` True
        capCanApplyDiscount      (caps Manager) `shouldBe` True
      it "lacks user management and multi-location access" $ do
        capCanViewAllLocations (caps Manager) `shouldBe` False
        capCanManageUsers      (caps Manager) `shouldBe` False

    describe "Admin" $ do
      it "has all capabilities" $ do
        let c = caps Admin
        capCanViewInventory      c `shouldBe` True
        capCanCreateItem         c `shouldBe` True
        capCanDeleteItem         c `shouldBe` True
        capCanVoidTransaction    c `shouldBe` True
        capCanApplyDiscount      c `shouldBe` True
        capCanViewAllLocations   c `shouldBe` True
        capCanManageUsers        c `shouldBe` True
        capCanViewCompliance      c `shouldBe` True

  -- ═══════════════════════════════════════════════
  -- SECTION 6: showPaymentMethod Other payload preservation
  -- (was "KNOWN ISSUE" — now fixed and verified)
  -- ═══════════════════════════════════════════════

  describe "PaymentMethod Other payload preservation" $ do
    it "JSON roundtrip preserves Other text" $
      fromJSON (toJSON (Other "Crypto")) `shouldBe` (Success (Other "Crypto") :: Result PaymentMethod)

    it "JSON roundtrip preserves Other with special characters" $
      fromJSON (toJSON (Other "Store-Credit")) `shouldBe` (Success (Other "Store-Credit") :: Result PaymentMethod)

    -- This documents that the DB roundtrip (via showPaymentMethod/parsePaymentMethod)
    -- also preserves the payload now that showPaymentMethod produces "OTHER:<text>".
    -- See Test.DB.PureFunctionsSpec for the unit-level verification.
    it "showPaymentMethod produces parseable string for Other" $ do
      let method = Other "DigitalWallet"
      let serialized = T.unpack $ showPaymentMethod method
      parsePaymentMethod serialized `shouldBe` method