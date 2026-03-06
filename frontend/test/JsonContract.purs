module Test.JsonContract where

import Prelude

import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..), isJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Auth (UserRole(..), capabilitiesForRole)
import Types.Inventory (ItemCategory(..), Species(..), MenuItem(..), Inventory(..), StrainLineage(..))
import Types.Session (SessionResponse)
import Types.Transaction
  ( TransactionStatus(..)
  , TransactionType(..)
  , PaymentMethod(..)
  , TaxCategory(..)
  , Transaction(..)
  , TransactionItem(..)
  , PaymentTransaction(..)
  )
import Types.UUID (UUID(..))
import Yoga.JSON (readJSON_, writeJSON)

-- ──────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────

-- | The UUID strings hardcoded in the Haskell backend Auth.Simple module
adminUUID :: String
adminUUID = "d3a1f4f0-c518-4db3-aa43-e80b428d6304"

customerUUID :: String
customerUUID = "8244082f-a6bc-4d6c-9427-64a0ecdc10db"

cashierUUID :: String
cashierUUID = "0a6f2deb-892b-4411-8025-08c1a4d61229"

managerUUID :: String
managerUUID = "8b75ea4a-00a4-4a2a-a5d5-a1bab8883802"

spec :: Spec Unit
spec = describe "JSON Contract: Backend ↔ Frontend" do

  -- ═══════════════════════════════════════════════
  -- SECTION 1: Parse backend-produced enum JSON
  -- Haskell Generic ToJSON produces PascalCase strings
  -- ═══════════════════════════════════════════════

  describe "Parse backend enum formats" do

    describe "UserRole from backend" do
      it "parses Customer" do
        (readJSON_ "\"Customer\"" :: Maybe UserRole) `shouldEqual` Just Customer
      it "parses Cashier" do
        (readJSON_ "\"Cashier\"" :: Maybe UserRole) `shouldEqual` Just Cashier
      it "parses Manager" do
        (readJSON_ "\"Manager\"" :: Maybe UserRole) `shouldEqual` Just Manager
      it "parses Admin" do
        (readJSON_ "\"Admin\"" :: Maybe UserRole) `shouldEqual` Just Admin

    describe "TransactionStatus from backend" do
      it "parses Created" do
        (readJSON_ "\"Created\"" :: Maybe TransactionStatus) `shouldEqual` Just Created
      it "parses InProgress" do
        (readJSON_ "\"InProgress\"" :: Maybe TransactionStatus) `shouldEqual` Just InProgress
      it "parses Completed" do
        (readJSON_ "\"Completed\"" :: Maybe TransactionStatus) `shouldEqual` Just Completed
      it "parses Voided" do
        (readJSON_ "\"Voided\"" :: Maybe TransactionStatus) `shouldEqual` Just Voided
      it "parses Refunded" do
        (readJSON_ "\"Refunded\"" :: Maybe TransactionStatus) `shouldEqual` Just Refunded

    describe "TransactionType from backend" do
      it "parses Sale" do
        (readJSON_ "\"Sale\"" :: Maybe TransactionType) `shouldEqual` Just Sale
      it "parses Return" do
        (readJSON_ "\"Return\"" :: Maybe TransactionType) `shouldEqual` Just Return
      it "parses InventoryAdjustment" do
        (readJSON_ "\"InventoryAdjustment\"" :: Maybe TransactionType) `shouldEqual` Just InventoryAdjustment

    describe "PaymentMethod from backend" do
      it "parses Cash" do
        (readJSON_ "\"Cash\"" :: Maybe PaymentMethod) `shouldEqual` Just Cash
      it "parses Credit" do
        (readJSON_ "\"Credit\"" :: Maybe PaymentMethod) `shouldEqual` Just Credit
      it "parses Other:Crypto" do
        (readJSON_ "\"Other:Crypto\"" :: Maybe PaymentMethod) `shouldEqual` Just (Other "Crypto")

    describe "TaxCategory from backend" do
      it "parses RegularSalesTax" do
        (readJSON_ "\"RegularSalesTax\"" :: Maybe TaxCategory) `shouldEqual` Just RegularSalesTax
      it "parses ExciseTax" do
        (readJSON_ "\"ExciseTax\"" :: Maybe TaxCategory) `shouldEqual` Just ExciseTax
      it "parses NoTax" do
        (readJSON_ "\"NoTax\"" :: Maybe TaxCategory) `shouldEqual` Just NoTax

    describe "ItemCategory from backend" do
      it "parses Flower" do
        (readJSON_ "\"Flower\"" :: Maybe ItemCategory) `shouldEqual` Just Flower
      it "parses PreRolls" do
        (readJSON_ "\"PreRolls\"" :: Maybe ItemCategory) `shouldEqual` Just PreRolls

    describe "Species from backend" do
      it "parses Indica" do
        (readJSON_ "\"Indica\"" :: Maybe Species) `shouldEqual` Just Indica
      it "parses IndicaDominantHybrid" do
        (readJSON_ "\"IndicaDominantHybrid\"" :: Maybe Species) `shouldEqual` Just IndicaDominantHybrid

  -- ═══════════════════════════════════════════════
  -- SECTION 2: Parse backend-produced complex JSON
  -- ═══════════════════════════════════════════════

  describe "Parse backend complex types" do

    describe "MenuItem from backend" do
      let backendMenuItemJson = """{"sort":1,"sku":"33333333-3333-3333-3333-333333333333","brand":"TestBrand","name":"OG Kush","price":2999,"measure_unit":"g","per_package":"3.5","quantity":10,"category":"Flower","subcategory":"Indoor","description":"Classic","tags":["indica"],"effects":["relaxed"],"strain_lineage":{"thc":"25%","cbg":"0.5%","strain":"OG Kush","creator":"Unknown","species":"Indica","dominant_terpene":"Myrcene","terpenes":["Myrcene"],"lineage":["Chemdawg"],"leafly_url":"https://leafly.com","img":"https://example.com/img.jpg"}}"""

      it "parses successfully" do
        (readJSON_ backendMenuItemJson :: Maybe MenuItem) `shouldSatisfy` isJust

      it "preserves price as integer cents" do
        case (readJSON_ backendMenuItemJson :: Maybe MenuItem) of
          Just (MenuItem item) -> item.price `shouldEqual` Discrete 2999
          Nothing -> (false) `shouldEqual` true

      it "preserves category" do
        case (readJSON_ backendMenuItemJson :: Maybe MenuItem) of
          Just (MenuItem item) -> item.category `shouldEqual` Flower
          Nothing -> (false) `shouldEqual` true

      it "preserves species in strain_lineage" do
        case (readJSON_ backendMenuItemJson :: Maybe MenuItem) of
          Just (MenuItem item) -> case item.strain_lineage of
            StrainLineage sl -> sl.species `shouldEqual` Indica
          Nothing -> (false) `shouldEqual` true

    describe "Transaction from backend" do
      let backendTxJson = """{"transactionId":"33333333-3333-3333-3333-333333333333","transactionStatus":"Created","transactionCreated":"2024-06-15T10:30:00Z","transactionCompleted":null,"transactionCustomerId":null,"transactionEmployeeId":"44444444-4444-4444-4444-444444444444","transactionRegisterId":"44444444-4444-4444-4444-444444444444","transactionLocationId":"44444444-4444-4444-4444-444444444444","transactionItems":[],"transactionPayments":[],"transactionSubtotal":0,"transactionDiscountTotal":0,"transactionTaxTotal":0,"transactionTotal":0,"transactionType":"Sale","transactionIsVoided":false,"transactionVoidReason":null,"transactionIsRefunded":false,"transactionRefundReason":null,"transactionReferenceTransactionId":null,"transactionNotes":null}"""

      it "parses successfully" do
        (readJSON_ backendTxJson :: Maybe Transaction) `shouldSatisfy` isJust

      it "preserves status" do
        case (readJSON_ backendTxJson :: Maybe Transaction) of
          Just (Transaction tx) -> tx.transactionStatus `shouldEqual` Created
          Nothing -> (false) `shouldEqual` true

      it "preserves type" do
        case (readJSON_ backendTxJson :: Maybe Transaction) of
          Just (Transaction tx) -> tx.transactionType `shouldEqual` Sale
          Nothing -> (false) `shouldEqual` true

      it "handles null optional fields" do
        case (readJSON_ backendTxJson :: Maybe Transaction) of
          Just (Transaction tx) -> do
            tx.transactionCompleted `shouldEqual` Nothing
            tx.transactionCustomerId `shouldEqual` Nothing
            tx.transactionVoidReason `shouldEqual` Nothing
            tx.transactionNotes `shouldEqual` Nothing
          Nothing -> (false) `shouldEqual` true

    describe "Transaction with non-null optionals from backend" do
      let backendTxJson = """{"transactionId":"33333333-3333-3333-3333-333333333333","transactionStatus":"Completed","transactionCreated":"2024-06-15T10:30:00Z","transactionCompleted":"2024-06-15T11:00:00Z","transactionCustomerId":"44444444-4444-4444-4444-444444444444","transactionEmployeeId":"44444444-4444-4444-4444-444444444444","transactionRegisterId":"44444444-4444-4444-4444-444444444444","transactionLocationId":"44444444-4444-4444-4444-444444444444","transactionItems":[],"transactionPayments":[],"transactionSubtotal":5000,"transactionDiscountTotal":100,"transactionTaxTotal":400,"transactionTotal":5300,"transactionType":"Sale","transactionIsVoided":false,"transactionVoidReason":null,"transactionIsRefunded":false,"transactionRefundReason":null,"transactionReferenceTransactionId":null,"transactionNotes":"Test note"}"""

      it "parses completed transaction" do
        case (readJSON_ backendTxJson :: Maybe Transaction) of
          Just (Transaction tx) -> do
            tx.transactionStatus `shouldEqual` Completed
            tx.transactionCompleted `shouldSatisfy` isJust
            tx.transactionNotes `shouldEqual` Just "Test note"
          Nothing -> (false) `shouldEqual` true

    describe "TransactionItem from backend" do
      let backendItemJson = """{"transactionItemId":"33333333-3333-3333-3333-333333333333","transactionItemTransactionId":"44444444-4444-4444-4444-444444444444","transactionItemMenuItemSku":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","transactionItemQuantity":2,"transactionItemPricePerUnit":1000,"transactionItemDiscounts":[],"transactionItemTaxes":[{"taxCategory":"RegularSalesTax","taxRate":0.08,"taxAmount":160,"taxDescription":"Sales Tax"}],"transactionItemSubtotal":2000,"transactionItemTotal":2160}"""

      it "parses successfully" do
        (readJSON_ backendItemJson :: Maybe TransactionItem) `shouldSatisfy` isJust

      it "preserves quantity and price" do
        case (readJSON_ backendItemJson :: Maybe TransactionItem) of
          Just (TransactionItem item) -> do
            item.transactionItemQuantity `shouldEqual` 2
          Nothing -> (false) `shouldEqual` true

      it "parses nested TaxRecord" do
        case (readJSON_ backendItemJson :: Maybe TransactionItem) of
          Just (TransactionItem item) ->
            case item.transactionItemTaxes of
              [tax] -> do
                tax.taxCategory `shouldEqual` RegularSalesTax
                tax.taxDescription `shouldEqual` "Sales Tax"
              _ -> (false) `shouldEqual` true
          Nothing -> (false) `shouldEqual` true

    describe "PaymentTransaction from backend" do
      let backendPaymentJson = """{"paymentId":"33333333-3333-3333-3333-333333333333","paymentTransactionId":"44444444-4444-4444-4444-444444444444","paymentMethod":"Cash","paymentAmount":5000,"paymentTendered":6000,"paymentChange":1000,"paymentReference":null,"paymentApproved":true,"paymentAuthorizationCode":null}"""

      it "parses successfully" do
        (readJSON_ backendPaymentJson :: Maybe PaymentTransaction) `shouldSatisfy` isJust

      it "preserves payment method" do
        case (readJSON_ backendPaymentJson :: Maybe PaymentTransaction) of
          Just (PaymentTransaction p) -> p.paymentMethod `shouldEqual` Cash
          Nothing -> (false) `shouldEqual` true

      it "handles null reference fields" do
        case (readJSON_ backendPaymentJson :: Maybe PaymentTransaction) of
          Just (PaymentTransaction p) -> do
            p.paymentReference `shouldEqual` Nothing
            p.paymentAuthorizationCode `shouldEqual` Nothing
          Nothing -> (false) `shouldEqual` true

    -- ─────────────────────────────────────────────────────────────────────
    -- Inventory is now a plain JSON array — no type/value/capabilities
    -- wrapper. The old InventoryData/Message sum type is gone.
    -- ─────────────────────────────────────────────────────────────────────
    describe "Inventory from backend (plain array)" do
      let backendInventoryJson = """[{"sort":1,"sku":"33333333-3333-3333-3333-333333333333","brand":"TestBrand","name":"OG Kush","price":2999,"measure_unit":"g","per_package":"3.5","quantity":10,"category":"Flower","subcategory":"Indoor","description":"Classic","tags":[],"effects":[],"strain_lineage":{"thc":"25%","cbg":"0.5%","strain":"OG Kush","creator":"Unknown","species":"Indica","dominant_terpene":"Myrcene","terpenes":[],"lineage":[],"leafly_url":"https://leafly.com","img":"https://example.com/img.jpg"}}]"""

      it "parses successfully as Inventory" do
        (readJSON_ backendInventoryJson :: Maybe Inventory) `shouldSatisfy` isJust

      it "preserves item count" do
        case (readJSON_ backendInventoryJson :: Maybe Inventory) of
          Just (Inventory items) -> (items /= []) `shouldEqual` true
          Nothing -> (false) `shouldEqual` true

      it "preserves item price" do
        case (readJSON_ backendInventoryJson :: Maybe Inventory) of
          Just (Inventory [MenuItem item]) -> item.price `shouldEqual` Discrete 2999
          _ -> (false) `shouldEqual` true

      it "parses empty array" do
        (readJSON_ "[]" :: Maybe Inventory) `shouldSatisfy` isJust

    -- ─────────────────────────────────────────────────────────────────────
    -- SessionResponse — capabilities now travel on their own endpoint.
    -- The backend sends sessionCapabilities alongside role/userId.
    -- ─────────────────────────────────────────────────────────────────────
    describe "SessionResponse from backend" do
      let adminSessionJson = """{"sessionUserId":"d3a1f4f0-c518-4db3-aa43-e80b428d6304","sessionUserName":"admin-1","sessionRole":"Admin","sessionCapabilities":{"capCanViewInventory":true,"capCanCreateItem":true,"capCanEditItem":true,"capCanDeleteItem":true,"capCanProcessTransaction":true,"capCanVoidTransaction":true,"capCanRefundTransaction":true,"capCanApplyDiscount":true,"capCanManageRegisters":true,"capCanOpenRegister":true,"capCanCloseRegister":true,"capCanViewReports":true,"capCanViewAllLocations":true,"capCanManageUsers":true,"capCanViewCompliance":true}}"""

      let cashierSessionJson = """{"sessionUserId":"0a6f2deb-892b-4411-8025-08c1a4d61229","sessionUserName":"cashier-1","sessionRole":"Cashier","sessionCapabilities":{"capCanViewInventory":true,"capCanCreateItem":false,"capCanEditItem":true,"capCanDeleteItem":false,"capCanProcessTransaction":true,"capCanVoidTransaction":false,"capCanRefundTransaction":false,"capCanApplyDiscount":false,"capCanManageRegisters":false,"capCanOpenRegister":true,"capCanCloseRegister":true,"capCanViewReports":false,"capCanViewAllLocations":false,"capCanManageUsers":false,"capCanViewCompliance":true}}"""

      it "parses admin session" do
        (readJSON_ adminSessionJson :: Maybe SessionResponse) `shouldSatisfy` isJust

      it "preserves admin userId" do
        case (readJSON_ adminSessionJson :: Maybe SessionResponse) of
          Just s  -> s.sessionUserId `shouldEqual` UUID adminUUID
          Nothing -> (false) `shouldEqual` true

      it "preserves admin role" do
        case (readJSON_ adminSessionJson :: Maybe SessionResponse) of
          Just s  -> s.sessionRole `shouldEqual` Admin
          Nothing -> (false) `shouldEqual` true

      it "preserves admin capabilities: viewAllLocations = true" do
        case (readJSON_ adminSessionJson :: Maybe SessionResponse) of
          Just s  -> s.sessionCapabilities.capCanViewAllLocations `shouldEqual` true
          Nothing -> (false) `shouldEqual` true

      it "preserves admin capabilities: manageUsers = true" do
        case (readJSON_ adminSessionJson :: Maybe SessionResponse) of
          Just s  -> s.sessionCapabilities.capCanManageUsers `shouldEqual` true
          Nothing -> (false) `shouldEqual` true

      it "parses cashier session" do
        (readJSON_ cashierSessionJson :: Maybe SessionResponse) `shouldSatisfy` isJust

      it "preserves cashier userId" do
        case (readJSON_ cashierSessionJson :: Maybe SessionResponse) of
          Just s  -> s.sessionUserId `shouldEqual` UUID cashierUUID
          Nothing -> (false) `shouldEqual` true

      it "cashier capabilities: editItem = true, deleteItem = false" do
        case (readJSON_ cashierSessionJson :: Maybe SessionResponse) of
          Just s  -> do
            s.sessionCapabilities.capCanEditItem   `shouldEqual` true
            s.sessionCapabilities.capCanDeleteItem `shouldEqual` false
          Nothing -> (false) `shouldEqual` true

  -- ═══════════════════════════════════════════════
  -- SECTION 3: Frontend → Backend JSON format
  -- ═══════════════════════════════════════════════

  describe "Frontend → Backend JSON format" do

    describe "UserRole WriteForeign matches backend FromJSON" do
      it "writes Customer as string" do
        writeJSON Customer `shouldEqual` "\"Customer\""
      it "writes Admin as string" do
        writeJSON Admin `shouldEqual` "\"Admin\""

    describe "TransactionStatus WriteForeign" do
      it "writes Created (PascalCase, not UPPER_SNAKE)" do
        writeJSON Created `shouldEqual` "\"Created\""
      it "writes InProgress" do
        writeJSON InProgress `shouldEqual` "\"InProgress\""

    describe "TransactionType WriteForeign" do
      it "writes Sale" do
        writeJSON Sale `shouldEqual` "\"Sale\""
      it "writes InventoryAdjustment" do
        writeJSON InventoryAdjustment `shouldEqual` "\"InventoryAdjustment\""

    describe "PaymentMethod WriteForeign" do
      it "writes Cash" do
        writeJSON Cash `shouldEqual` "\"Cash\""
      it "writes Other with colon" do
        writeJSON (Other "Crypto") `shouldEqual` "\"Other:Crypto\""

    describe "TaxCategory WriteForeign" do
      it "writes RegularSalesTax (PascalCase)" do
        writeJSON RegularSalesTax `shouldEqual` "\"RegularSalesTax\""

    -- Inventory is written as a plain array — backend expects this.
    describe "Inventory WriteForeign" do
      it "writes as JSON array" do
        let inv = Inventory []
        let json = writeJSON inv
        -- Should start with '[' not '{', confirming no wrapper object
        json `shouldEqual` "[]"

  -- ═══════════════════════════════════════════════
  -- SECTION 4: Capability parity
  -- ═══════════════════════════════════════════════

  describe "Capability definitions match backend" do

    describe "Customer" do
      let caps = capabilitiesForRole Customer
      it "viewInventory = true" do
        caps.capCanViewInventory `shouldEqual` true
      it "createItem = false" do
        caps.capCanCreateItem `shouldEqual` false
      it "processTransaction = false" do
        caps.capCanProcessTransaction `shouldEqual` false
      it "viewCompliance = false" do
        caps.capCanViewCompliance `shouldEqual` false

    describe "Cashier" do
      let caps = capabilitiesForRole Cashier
      it "editItem = true" do
        caps.capCanEditItem `shouldEqual` true
      it "deleteItem = false" do
        caps.capCanDeleteItem `shouldEqual` false
      it "processTransaction = true" do
        caps.capCanProcessTransaction `shouldEqual` true
      it "openRegister = true" do
        caps.capCanOpenRegister `shouldEqual` true
      it "closeRegister = true" do
        caps.capCanCloseRegister `shouldEqual` true
      it "viewCompliance = true" do
        caps.capCanViewCompliance `shouldEqual` true

    describe "Manager" do
      let caps = capabilitiesForRole Manager
      it "createItem = true" do
        caps.capCanCreateItem `shouldEqual` true
      it "deleteItem = true" do
        caps.capCanDeleteItem `shouldEqual` true
      it "voidTransaction = true" do
        caps.capCanVoidTransaction `shouldEqual` true
      it "viewAllLocations = false" do
        caps.capCanViewAllLocations `shouldEqual` false
      it "manageUsers = false" do
        caps.capCanManageUsers `shouldEqual` false

    describe "Admin" do
      let caps = capabilitiesForRole Admin
      it "viewAllLocations = true" do
        caps.capCanViewAllLocations `shouldEqual` true
      it "manageUsers = true" do
        caps.capCanManageUsers `shouldEqual` true

  -- ═══════════════════════════════════════════════
  -- SECTION 5: Dev user UUID parity with backend
  -- ═══════════════════════════════════════════════

  describe "Dev user UUID parity with backend" do
    it "admin UUID matches backend" do
      show (UUID adminUUID) `shouldEqual` adminUUID
    it "customer UUID matches backend" do
      show (UUID customerUUID) `shouldEqual` customerUUID
    it "cashier UUID matches backend" do
      show (UUID cashierUUID) `shouldEqual` cashierUUID
    it "manager UUID matches backend" do
      show (UUID managerUUID) `shouldEqual` managerUUID

  -- ═══════════════════════════════════════════════
  -- SECTION 6: Roundtrip tests
  -- ═══════════════════════════════════════════════

  describe "WriteForeign → ReadForeign roundtrips" do
    it "roundtrips all UserRoles" do
      let check r = (readJSON_ (writeJSON r) :: Maybe UserRole) `shouldEqual` Just r
      check Customer
      check Cashier
      check Manager
      check Admin

    it "roundtrips all TransactionStatuses" do
      let check s = (readJSON_ (writeJSON s) :: Maybe TransactionStatus) `shouldEqual` Just s
      check Created
      check InProgress
      check Completed
      check Voided
      check Refunded

    it "roundtrips all TransactionTypes" do
      let check t = (readJSON_ (writeJSON t) :: Maybe TransactionType) `shouldEqual` Just t
      check Sale
      check Return
      check Exchange
      check InventoryAdjustment
      check ManagerComp
      check Administrative

    it "roundtrips all PaymentMethods" do
      let check m = (readJSON_ (writeJSON m) :: Maybe PaymentMethod) `shouldEqual` Just m
      check Cash
      check Debit
      check Credit
      check ACH
      check GiftCard
      check StoredValue
      check Mixed
      check (Other "Crypto")

    it "roundtrips all TaxCategories" do
      let check c = (readJSON_ (writeJSON c) :: Maybe TaxCategory) `shouldEqual` Just c
      check RegularSalesTax
      check ExciseTax
      check CannabisTax
      check LocalTax
      check MedicalTax
      check NoTax