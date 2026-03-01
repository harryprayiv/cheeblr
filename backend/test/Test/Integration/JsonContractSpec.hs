{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Integration.JsonContractSpec (spec) where

import Test.Hspec
import Data.Aeson
import Data.Aeson.KeyMap (member)
import qualified Data.Aeson.KeyMap as KM
import Data.Scientific (fromFloatDigits)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Data.Vector as V

import Types.Auth
import Types.Inventory
import Types.Transaction
import API.Transaction
  ( Register(..)
  
  
  )
import Auth.Simple (lookupUser)

-- ──────────────────────────────────────────────
-- Fixtures matching what PureScript frontend sends
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
        -- PureScript ReadForeign expects: "Customer", "Cashier", "Manager", "Admin"
        toJSON Customer `shouldBe` String "Customer"
        toJSON Cashier `shouldBe` String "Cashier"
        toJSON Manager `shouldBe` String "Manager"
        toJSON Admin `shouldBe` String "Admin"

    describe "TransactionStatus" $ do
      it "serializes as PascalCase strings" $ do
        -- PureScript ReadForeign accepts both PascalCase and UPPER_SNAKE_CASE
        toJSON Created `shouldBe` String "Created"
        toJSON InProgress `shouldBe` String "InProgress"
        toJSON Completed `shouldBe` String "Completed"
        toJSON Voided `shouldBe` String "Voided"
        toJSON Refunded `shouldBe` String "Refunded"

      it "frontend PascalCase strings parse in backend" $ do
        fromJSON (String "Created") `shouldBe` (Success Created :: Result TransactionStatus)
        fromJSON (String "InProgress") `shouldBe` (Success InProgress :: Result TransactionStatus)
        fromJSON (String "Completed") `shouldBe` (Success Completed :: Result TransactionStatus)

    describe "TransactionType" $ do
      it "serializes as PascalCase strings" $ do
        toJSON Sale `shouldBe` String "Sale"
        toJSON Return `shouldBe` String "Return"
        toJSON Exchange `shouldBe` String "Exchange"
        toJSON InventoryAdjustment `shouldBe` String "InventoryAdjustment"
        toJSON ManagerComp `shouldBe` String "ManagerComp"
        toJSON Administrative `shouldBe` String "Administrative"

    describe "PaymentMethod" $ do
      it "serializes standard methods as PascalCase" $ do
        toJSON Cash `shouldBe` String "Cash"
        toJSON Debit `shouldBe` String "Debit"
        toJSON Credit `shouldBe` String "Credit"
        toJSON ACH `shouldBe` String "ACH"
        toJSON GiftCard `shouldBe` String "GiftCard"
        toJSON StoredValue `shouldBe` String "StoredValue"
        toJSON Mixed `shouldBe` String "Mixed"

      it "serializes Other with colon prefix" $ do
        -- PureScript writes: "Other:Crypto" and reads: "Other:..." or "OTHER:..."
        toJSON (Other "Crypto") `shouldBe` String "Other:Crypto"

      it "parses PureScript-produced Other format" $ do
        fromJSON (String "Other:Bitcoin") `shouldBe` (Success (Other "Bitcoin") :: Result PaymentMethod)
        fromJSON (String "OTHER:Check") `shouldBe` (Success (Other "Check") :: Result PaymentMethod)

    describe "TaxCategory" $ do
      it "serializes as PascalCase strings" $ do
        -- PureScript ReadForeign accepts both PascalCase and UPPER_SNAKE_CASE
        toJSON RegularSalesTax `shouldBe` String "RegularSalesTax"
        toJSON ExciseTax `shouldBe` String "ExciseTax"
        toJSON CannabisTax `shouldBe` String "CannabisTax"
        toJSON LocalTax `shouldBe` String "LocalTax"
        toJSON MedicalTax `shouldBe` String "MedicalTax"
        toJSON NoTax `shouldBe` String "NoTax"

    describe "ItemCategory" $ do
      it "serializes as PascalCase strings matching frontend Show" $ do
        toJSON Flower `shouldBe` String "Flower"
        toJSON PreRolls `shouldBe` String "PreRolls"
        toJSON Vaporizers `shouldBe` String "Vaporizers"
        toJSON Edibles `shouldBe` String "Edibles"

    describe "Species" $ do
      it "serializes as PascalCase strings matching frontend Show" $ do
        toJSON Indica `shouldBe` String "Indica"
        toJSON IndicaDominantHybrid `shouldBe` String "IndicaDominantHybrid"
        toJSON Hybrid `shouldBe` String "Hybrid"
        toJSON Sativa `shouldBe` String "Sativa"

  -- ═══════════════════════════════════════════════
  -- SECTION 2: Complex type wire format
  -- ═══════════════════════════════════════════════

  describe "Complex type wire formats" $ do

    describe "MenuItem JSON structure" $ do
      it "has field names matching PureScript record fields" $ do
        let item = MenuItem
              { sort = 1
              , sku = testUUID
              , brand = "TestBrand"
              , name = "OG Kush"
              , price = 2999
              , measure_unit = "g"
              , per_package = "3.5"
              , quantity = 10
              , category = Flower
              , subcategory = "Indoor"
              , description = "Classic"
              , tags = V.fromList ["indica"]
              , effects = V.fromList ["relaxed"]
              , strain_lineage = StrainLineage
                  { thc = "25%", cbg = "0.5%"
                  , strain = "OG Kush", creator = "Unknown"
                  , species = Indica
                  , dominant_terpene = "Myrcene"
                  , terpenes = V.fromList ["Myrcene"]
                  , lineage = V.fromList ["Chemdawg"]
                  , leafly_url = "https://leafly.com"
                  , img = "https://example.com/img.jpg"
                  }
              }
        let val = toJSON item
        -- PureScript readImpl reads these field names
        case val of
          Object obj -> do
            member "sort" obj `shouldBe` True
            member "sku" obj `shouldBe` True
            member "brand" obj `shouldBe` True
            member "name" obj `shouldBe` True
            member "price" obj `shouldBe` True
            member "measure_unit" obj `shouldBe` True
            member "per_package" obj `shouldBe` True
            member "quantity" obj `shouldBe` True
            member "category" obj `shouldBe` True
            member "subcategory" obj `shouldBe` True
            member "description" obj `shouldBe` True
            member "tags" obj `shouldBe` True
            member "effects" obj `shouldBe` True
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

    describe "Transaction JSON structure" $ do
      it "has all field names matching PureScript Transaction newtype" $ do
        let tx = Transaction
              { transactionId = testUUID
              , transactionStatus = Created
              , transactionCreated = testTime
              , transactionCompleted = Nothing
              , transactionCustomerId = Nothing
              , transactionEmployeeId = testUUID2
              , transactionRegisterId = testUUID2
              , transactionLocationId = testUUID2
              , transactionItems = []
              , transactionPayments = []
              , transactionSubtotal = 0
              , transactionDiscountTotal = 0
              , transactionTaxTotal = 0
              , transactionTotal = 0
              , transactionType = Sale
              , transactionIsVoided = False
              , transactionVoidReason = Nothing
              , transactionIsRefunded = False
              , transactionRefundReason = Nothing
              , transactionReferenceTransactionId = Nothing
              , transactionNotes = Nothing
              }
        case toJSON tx of
          Object obj -> do
            -- Every field that PureScript reads via .: or .:?
            member "transactionId" obj `shouldBe` True
            member "transactionStatus" obj `shouldBe` True
            member "transactionCreated" obj `shouldBe` True
            member "transactionEmployeeId" obj `shouldBe` True
            member "transactionRegisterId" obj `shouldBe` True
            member "transactionLocationId" obj `shouldBe` True
            member "transactionItems" obj `shouldBe` True
            member "transactionPayments" obj `shouldBe` True
            member "transactionSubtotal" obj `shouldBe` True
            member "transactionDiscountTotal" obj `shouldBe` True
            member "transactionTaxTotal" obj `shouldBe` True
            member "transactionTotal" obj `shouldBe` True
            member "transactionType" obj `shouldBe` True
            member "transactionIsVoided" obj `shouldBe` True
            member "transactionIsRefunded" obj `shouldBe` True
          _ -> expectationFailure "Transaction should serialize as object"

      it "serializes monetary fields as plain integers" $ do
        let tx = Transaction testUUID Created testTime Nothing Nothing
                   testUUID2 testUUID2 testUUID2 [] []
                   5000 100 400 5300 Sale False Nothing False Nothing Nothing Nothing
        case toJSON tx of
          Object obj -> do
            KM.lookup "transactionSubtotal" obj `shouldBe` Just (Number 5000)
            KM.lookup "transactionDiscountTotal" obj `shouldBe` Just (Number 100)
            KM.lookup "transactionTaxTotal" obj `shouldBe` Just (Number 400)
            KM.lookup "transactionTotal" obj `shouldBe` Just (Number 5300)
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
            member "transactionItemId" obj `shouldBe` True
            member "transactionItemTransactionId" obj `shouldBe` True
            member "transactionItemMenuItemSku" obj `shouldBe` True
            member "transactionItemQuantity" obj `shouldBe` True
            member "transactionItemPricePerUnit" obj `shouldBe` True
            member "transactionItemDiscounts" obj `shouldBe` True
            member "transactionItemTaxes" obj `shouldBe` True
            member "transactionItemSubtotal" obj `shouldBe` True
            member "transactionItemTotal" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

    describe "PaymentTransaction JSON structure" $ do
      it "serializes with nullable optional fields" $ do
        let payment = PaymentTransaction
              { paymentId = testUUID
              , paymentTransactionId = testUUID2
              , paymentMethod = Cash
              , paymentAmount = 5000
              , paymentTendered = 6000
              , paymentChange = 1000
              , paymentReference = Nothing
              , paymentApproved = True
              , paymentAuthorizationCode = Nothing
              }
        case toJSON payment of
          Object obj -> do
            member "paymentId" obj `shouldBe` True
            member "paymentTransactionId" obj `shouldBe` True
            member "paymentMethod" obj `shouldBe` True
            member "paymentAmount" obj `shouldBe` True
            member "paymentTendered" obj `shouldBe` True
            member "paymentChange" obj `shouldBe` True
            member "paymentApproved" obj `shouldBe` True
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
            member "taxCategory" obj `shouldBe` True
            member "taxRate" obj `shouldBe` True
            member "taxAmount" obj `shouldBe` True
            member "taxDescription" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

    describe "Register JSON structure" $ do
      it "has field names matching PureScript Register type alias" $ do
        let reg = API.Transaction.Register
              { registerId = testUUID
              , registerName = "Register 1"
              , registerLocationId = testUUID2
              , registerIsOpen = True
              , registerCurrentDrawerAmount = 50000
              , registerExpectedDrawerAmount = 50000
              , registerOpenedAt = Just testTime
              , registerOpenedBy = Just testUUID
              , registerLastTransactionTime = Nothing
              }
        case toJSON reg of
          Object obj -> do
            member "registerId" obj `shouldBe` True
            member "registerName" obj `shouldBe` True
            member "registerLocationId" obj `shouldBe` True
            member "registerIsOpen" obj `shouldBe` True
            member "registerCurrentDrawerAmount" obj `shouldBe` True
            member "registerExpectedDrawerAmount" obj `shouldBe` True
            member "registerOpenedAt" obj `shouldBe` True
            member "registerOpenedBy" obj `shouldBe` True
            member "registerLastTransactionTime" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

    describe "InventoryResponse JSON structure" $ do
      it "InventoryData has type, value, and capabilities fields" $ do
        let inv = Inventory (V.fromList [])
        let caps = capabilitiesForRole Admin
        let resp = InventoryData inv caps
        case toJSON resp of
          Object obj -> do
            KM.lookup "type" obj `shouldBe` Just (String "data")
            member "value" obj `shouldBe` True
            member "capabilities" obj `shouldBe` True
          _ -> expectationFailure "Expected object"

      it "Message has type and value fields" $ do
        case toJSON (Message "hello") of
          Object obj -> do
            KM.lookup "type" obj `shouldBe` Just (String "message")
            KM.lookup "value" obj `shouldBe` Just (String "hello")
          _ -> expectationFailure "Expected object"

  -- ═══════════════════════════════════════════════
  -- SECTION 3: Frontend → Backend parsing
  -- Simulate JSON the PureScript WriteForeign produces
  -- ═══════════════════════════════════════════════

  describe "Frontend → Backend JSON parsing" $ do

    describe "Transaction from PureScript" $ do
      it "parses PureScript-produced Transaction JSON" $ do
        -- PureScript WriteForeign for Transaction produces these field names
        -- with status as "Created", type as "Sale", nullable optionals as null
        let json = object
              [ "transactionId" .= testUUID
              , "transactionStatus" .= String "Created"
              , "transactionCreated" .= testTime
              , "transactionCompleted" .= Null
              , "transactionCustomerId" .= Null
              , "transactionEmployeeId" .= testUUID2
              , "transactionRegisterId" .= testUUID2
              , "transactionLocationId" .= testUUID2
              , "transactionItems" .= ([] :: [Value])
              , "transactionPayments" .= ([] :: [Value])
              , "transactionSubtotal" .= (0 :: Int)
              , "transactionDiscountTotal" .= (0 :: Int)
              , "transactionTaxTotal" .= (0 :: Int)
              , "transactionTotal" .= (0 :: Int)
              , "transactionType" .= String "Sale"
              , "transactionIsVoided" .= False
              , "transactionVoidReason" .= Null
              , "transactionIsRefunded" .= False
              , "transactionRefundReason" .= Null
              , "transactionReferenceTransactionId" .= Null
              , "transactionNotes" .= Null
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
              [ "transactionItemId" .= testUUID
              , "transactionItemTransactionId" .= testUUID2
              , "transactionItemMenuItemSku" .= testUUID
              , "transactionItemQuantity" .= (2 :: Int)
              , "transactionItemPricePerUnit" .= (1000 :: Int)
              , "transactionItemDiscounts" .= ([] :: [Value])
              , "transactionItemTaxes" .= ([] :: [Value])
              , "transactionItemSubtotal" .= (2000 :: Int)
              , "transactionItemTotal" .= (2160 :: Int)
              ]
        let result = fromJSON json :: Result TransactionItem
        case result of
          Success item -> do
            transactionItemQuantity item `shouldBe` 2
            transactionItemPricePerUnit item `shouldBe` 1000
          Error err -> expectationFailure $ "Failed to parse: " ++ err

    describe "PaymentTransaction from PureScript" $ do
      it "parses PureScript-produced Payment JSON with null optionals" $ do
        -- PureScript uses Nullable for Maybe fields via maybeToNullable
        let json = object
              [ "paymentId" .= testUUID
              , "paymentTransactionId" .= testUUID2
              , "paymentMethod" .= String "Cash"
              , "paymentAmount" .= (5000 :: Int)
              , "paymentTendered" .= (6000 :: Int)
              , "paymentChange" .= (1000 :: Int)
              , "paymentReference" .= Null
              , "paymentApproved" .= True
              , "paymentAuthorizationCode" .= Null
              ]
        let result = fromJSON json :: Result PaymentTransaction
        case result of
          Success p -> do
            paymentMethod p `shouldBe` Cash
            paymentAmount p `shouldBe` 5000
            paymentReference p `shouldBe` Nothing
          Error err -> expectationFailure $ "Failed to parse: " ++ err

      it "parses PureScript-produced Payment with reference" $ do
        let json = object
              [ "paymentId" .= testUUID
              , "paymentTransactionId" .= testUUID2
              , "paymentMethod" .= String "Credit"
              , "paymentAmount" .= (5000 :: Int)
              , "paymentTendered" .= (5000 :: Int)
              , "paymentChange" .= (0 :: Int)
              , "paymentReference" .= String "VISA-1234"
              , "paymentApproved" .= True
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
              [ "sort" .= (1 :: Int)
              , "sku" .= testUUID
              , "brand" .= String "TestBrand"
              , "name" .= String "OG Kush"
              , "price" .= (2999 :: Int)
              , "measure_unit" .= String "g"
              , "per_package" .= String "3.5"
              , "quantity" .= (10 :: Int)
              , "category" .= String "Flower"
              , "subcategory" .= String "Indoor"
              , "description" .= String "Classic"
              , "tags" .= (["indica", "classic"] :: [String])
              , "effects" .= (["relaxed"] :: [String])
              , "strain_lineage" .= object
                  [ "thc" .= String "25%"
                  , "cbg" .= String "0.5%"
                  , "strain" .= String "OG Kush"
                  , "creator" .= String "Unknown"
                  , "species" .= String "Indica"
                  , "dominant_terpene" .= String "Myrcene"
                  , "terpenes" .= (["Myrcene"] :: [String])
                  , "lineage" .= (["Chemdawg"] :: [String])
                  , "leafly_url" .= String "https://leafly.com"
                  , "img" .= String "https://example.com/img.jpg"
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

    describe "Register from PureScript" $ do
      it "parses PureScript-produced Register JSON" $ do
        let json = object
              [ "registerId" .= testUUID
              , "registerName" .= String "Register 1"
              , "registerLocationId" .= testUUID2
              , "registerIsOpen" .= False
              , "registerCurrentDrawerAmount" .= (0 :: Int)
              , "registerExpectedDrawerAmount" .= (0 :: Int)
              , "registerOpenedAt" .= Null
              , "registerOpenedBy" .= Null
              , "registerLastTransactionTime" .= Null
              ]
        let result = fromJSON json :: Result API.Transaction.Register
        case result of
          Success r -> do
            registerName r `shouldBe` "Register 1"
            registerIsOpen r `shouldBe` False
            registerOpenedAt r `shouldBe` Nothing
          Error err -> expectationFailure $ "Failed to parse: " ++ err

  -- ═══════════════════════════════════════════════
  -- SECTION 4: Known mismatch documentation
  -- These tests document the DiscountType mismatch
  -- ═══════════════════════════════════════════════

  describe "KNOWN MISMATCH: DiscountType serialization" $ do
    -- Backend uses Generic-derived tagged union format
    -- Frontend uses flat discriminated object format
    -- These tests document the incompatibility

    it "backend serializes PercentOff as tagged union" $ do
      let dt = PercentOff (fromFloatDigits (10.0 :: Double))
      -- Generic produces: {"tag":"PercentOff","contents":10.0}
      case toJSON dt of
        Object obj -> do
          -- This is what the backend sends
          member "tag" obj `shouldBe` True
          -- But PureScript expects: {discountType: "PERCENT_OFF", percent: 10.0}
          member "discountType" obj `shouldBe` False  -- MISMATCH!
        _ -> expectationFailure "Expected object"

    it "backend serializes AmountOff as tagged union" $ do
      let dt = AmountOff 500
      case toJSON dt of
        Object obj -> do
          member "tag" obj `shouldBe` True
          member "discountType" obj `shouldBe` False  -- MISMATCH!
        _ -> expectationFailure "Expected object"

    it "backend cannot parse PureScript DiscountType format" $ do
      -- This is what PureScript WriteForeign produces:
      let frontendJson = object
            [ "discountType" .= String "PERCENT_OFF"
            , "percent" .= (10.0 :: Double)
            , "amount" .= (0.0 :: Double)
            ]
      let result = fromJSON frontendJson :: Result DiscountType
      case result of
        Error _ -> pure ()  -- Expected: backend can't parse frontend format
        Success _ -> expectationFailure
          "Backend unexpectedly parsed frontend DiscountType format - mismatch may be resolved"

    it "frontend cannot parse backend DiscountType format" $ do
      -- This is what Haskell Generic ToJSON produces:
      let backendJson = toJSON (PercentOff (fromFloatDigits (10.0 :: Double)))
      -- PureScript readImpl looks for "discountType" key which won't exist
      -- We document this by verifying the JSON structure
      case backendJson of
        Object obj -> do
          member "tag" obj `shouldBe` True       -- backend sends this
          member "discountType" obj `shouldBe` False  -- frontend looks for this
        _ -> expectationFailure "Expected object"

  -- ═══════════════════════════════════════════════
  -- SECTION 5: Auth contract — devUser UUIDs match
  -- ═══════════════════════════════════════════════

  describe "Auth contract: dev user UUIDs" $ do
    -- PureScript Config.Auth hardcodes these UUIDs; they must match Auth.Simple
    it "admin UUID matches" $ do
      let user = lookupUser (Just "d3a1f4f0-c518-4db3-aa43-e80b428d6304")
      auRole user `shouldBe` Admin

    it "customer UUID matches" $ do
      let user = lookupUser (Just "8244082f-a6bc-4d6c-9427-64a0ecdc10db")
      auRole user `shouldBe` Customer

    it "cashier UUID matches" $ do
      let user = lookupUser (Just "0a6f2deb-892b-4411-8025-08c1a4d61229")
      auRole user `shouldBe` Cashier

    it "manager UUID matches" $ do
      let user = lookupUser (Just "8b75ea4a-00a4-4a2a-a5d5-a1bab8883802")
      auRole user `shouldBe` Manager

  -- ═══════════════════════════════════════════════
  -- SECTION 6: Capability definitions match
  -- ═══════════════════════════════════════════════

  describe "Capability parity: backend == frontend definitions" $ do
    -- If these ever drift, the frontend shows UI for actions the backend rejects
    -- (or hides UI for actions the backend allows)

    let backendCaps role = capabilitiesForRole role

    describe "Customer capabilities" $ do
      let caps = backendCaps Customer
      it "viewInventory = True"         $ capCanViewInventory caps `shouldBe` True
      it "createItem = False"           $ capCanCreateItem caps `shouldBe` False
      it "editItem = False"             $ capCanEditItem caps `shouldBe` False
      it "deleteItem = False"           $ capCanDeleteItem caps `shouldBe` False
      it "processTransaction = False"   $ capCanProcessTransaction caps `shouldBe` False
      it "voidTransaction = False"      $ capCanVoidTransaction caps `shouldBe` False
      it "refundTransaction = False"    $ capCanRefundTransaction caps `shouldBe` False
      it "applyDiscount = False"        $ capCanApplyDiscount caps `shouldBe` False
      it "manageRegisters = False"      $ capCanManageRegisters caps `shouldBe` False
      it "openRegister = False"         $ capCanOpenRegister caps `shouldBe` False
      it "closeRegister = False"        $ capCanCloseRegister caps `shouldBe` False
      it "viewReports = False"          $ capCanViewReports caps `shouldBe` False
      it "viewAllLocations = False"     $ capCanViewAllLocations caps `shouldBe` False
      it "manageUsers = False"          $ capCanManageUsers caps `shouldBe` False
      it "viewCompliance = False"       $ capCanViewCompliance caps `shouldBe` False

    describe "Cashier capabilities" $ do
      let caps = backendCaps Cashier
      it "viewInventory = True"         $ capCanViewInventory caps `shouldBe` True
      it "createItem = False"           $ capCanCreateItem caps `shouldBe` False
      it "editItem = True"              $ capCanEditItem caps `shouldBe` True
      it "deleteItem = False"           $ capCanDeleteItem caps `shouldBe` False
      it "processTransaction = True"    $ capCanProcessTransaction caps `shouldBe` True
      it "voidTransaction = False"      $ capCanVoidTransaction caps `shouldBe` False
      it "refundTransaction = False"    $ capCanRefundTransaction caps `shouldBe` False
      it "applyDiscount = False"        $ capCanApplyDiscount caps `shouldBe` False
      it "manageRegisters = False"      $ capCanManageRegisters caps `shouldBe` False
      it "openRegister = True"          $ capCanOpenRegister caps `shouldBe` True
      it "closeRegister = True"         $ capCanCloseRegister caps `shouldBe` True
      it "viewReports = False"          $ capCanViewReports caps `shouldBe` False
      it "viewAllLocations = False"     $ capCanViewAllLocations caps `shouldBe` False
      it "manageUsers = False"          $ capCanManageUsers caps `shouldBe` False
      it "viewCompliance = True"        $ capCanViewCompliance caps `shouldBe` True

    describe "Manager capabilities" $ do
      let caps = backendCaps Manager
      it "viewInventory = True"         $ capCanViewInventory caps `shouldBe` True
      it "createItem = True"            $ capCanCreateItem caps `shouldBe` True
      it "editItem = True"              $ capCanEditItem caps `shouldBe` True
      it "deleteItem = True"            $ capCanDeleteItem caps `shouldBe` True
      it "processTransaction = True"    $ capCanProcessTransaction caps `shouldBe` True
      it "voidTransaction = True"       $ capCanVoidTransaction caps `shouldBe` True
      it "refundTransaction = True"     $ capCanRefundTransaction caps `shouldBe` True
      it "applyDiscount = True"         $ capCanApplyDiscount caps `shouldBe` True
      it "manageRegisters = True"       $ capCanManageRegisters caps `shouldBe` True
      it "openRegister = True"          $ capCanOpenRegister caps `shouldBe` True
      it "closeRegister = True"         $ capCanCloseRegister caps `shouldBe` True
      it "viewReports = True"           $ capCanViewReports caps `shouldBe` True
      it "viewAllLocations = False"     $ capCanViewAllLocations caps `shouldBe` False
      it "manageUsers = False"          $ capCanManageUsers caps `shouldBe` False
      it "viewCompliance = True"        $ capCanViewCompliance caps `shouldBe` True

    describe "Admin capabilities" $ do
      let caps = backendCaps Admin
      it "all capabilities = True" $ do
        capCanViewInventory caps `shouldBe` True
        capCanCreateItem caps `shouldBe` True
        capCanEditItem caps `shouldBe` True
        capCanDeleteItem caps `shouldBe` True
        capCanProcessTransaction caps `shouldBe` True
        capCanVoidTransaction caps `shouldBe` True
        capCanRefundTransaction caps `shouldBe` True
        capCanApplyDiscount caps `shouldBe` True
        capCanManageRegisters caps `shouldBe` True
        capCanOpenRegister caps `shouldBe` True
        capCanCloseRegister caps `shouldBe` True
        capCanViewReports caps `shouldBe` True
        capCanViewAllLocations caps `shouldBe` True
        capCanManageUsers caps `shouldBe` True
        capCanViewCompliance caps `shouldBe` True

  -- ═══════════════════════════════════════════════
  -- SECTION 7: showPaymentMethod loses Other payload
  -- ═══════════════════════════════════════════════

  describe "KNOWN ISSUE: showPaymentMethod drops Other payload" $ do
    it "JSON roundtrip preserves Other text" $ do
      fromJSON (toJSON (Other "Crypto")) `shouldBe` (Success (Other "Crypto") :: Result PaymentMethod)

    -- Note: DB.Transaction.showPaymentMethod (Other "Crypto") == "OTHER"
    -- This means after a DB roundtrip, Other "Crypto" becomes Other ""
    -- This is tested in Test.DB.PureFunctionsSpec; documented here for context.