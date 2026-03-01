{-# LANGUAGE OverloadedStrings #-}

module Test.DB.PureFunctionsSpec (spec) where

import Test.Hspec
import Data.Scientific (fromFloatDigits)
import Data.UUID (UUID)
import qualified Data.Text as T
import Types.Transaction
import DB.Transaction

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testUUID :: UUID
testUUID = read "33333333-3333-3333-3333-333333333333"

testUUID2 :: UUID
testUUID2 = read "44444444-4444-4444-4444-444444444444"

mkItem :: TransactionItem
mkItem = TransactionItem
  { transactionItemId = testUUID
  , transactionItemTransactionId = testUUID2
  , transactionItemMenuItemSku = read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  , transactionItemQuantity = 2
  , transactionItemPricePerUnit = 1000
  , transactionItemDiscounts = [mkDiscount]
  , transactionItemTaxes = [mkTax]
  , transactionItemSubtotal = 2000
  , transactionItemTotal = 2080
  }

mkDiscount :: DiscountRecord
mkDiscount = DiscountRecord
  { discountType = AmountOff 200
  , discountAmount = 200
  , discountReason = "Employee"
  , discountApprovedBy = Just testUUID
  }

mkTax :: TaxRecord
mkTax = TaxRecord
  { taxCategory = RegularSalesTax
  , taxRate = fromFloatDigits (0.08 :: Double)
  , taxAmount = 80
  , taxDescription = "Sales Tax"
  }

mkPayment :: PaymentTransaction
mkPayment = PaymentTransaction
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

spec :: Spec
spec = describe "DB.Transaction pure functions" $ do

  -- ──────────────────────────────────────────────
  -- showStatus
  -- ──────────────────────────────────────────────
  describe "showStatus" $ do
    it "shows Created"    $ showStatus Created `shouldBe` "CREATED"
    it "shows InProgress" $ showStatus InProgress `shouldBe` "IN_PROGRESS"
    it "shows Completed"  $ showStatus Completed `shouldBe` "COMPLETED"
    it "shows Voided"     $ showStatus Voided `shouldBe` "VOIDED"
    it "shows Refunded"   $ showStatus Refunded `shouldBe` "REFUNDED"

  -- showStatus/parseTransactionStatus roundtrip
  describe "showStatus/parseTransactionStatus roundtrip" $ do
    it "roundtrips all statuses" $ do
      let statuses = [Created, InProgress, Completed, Voided, Refunded]
      mapM_ (\s -> parseTransactionStatus (T.unpack $ showStatus s) `shouldBe` s) statuses

  -- showTransactionType/parseTransactionType roundtrip
  describe "showTransactionType/parseTransactionType roundtrip" $ do
    it "roundtrips all types" $ do
      let types = [Sale, Return, Exchange, InventoryAdjustment, ManagerComp, Administrative]
      mapM_ (\t -> parseTransactionType (T.unpack $ showTransactionType t) `shouldBe` t) types

  -- showPaymentMethod/parsePaymentMethod roundtrip
  describe "showPaymentMethod/parsePaymentMethod roundtrip" $ do
    it "roundtrips standard methods" $ do
      let methods = [Cash, Debit, Credit, ACH, GiftCard, StoredValue, Mixed]
      mapM_ (\m -> parsePaymentMethod (T.unpack $ showPaymentMethod m) `shouldBe` m) methods

  -- showTaxCategory/parseTaxCategory roundtrip
  describe "showTaxCategory/parseTaxCategory roundtrip" $ do
    it "roundtrips all categories" $ do
      let cats = [RegularSalesTax, ExciseTax, CannabisTax, LocalTax, MedicalTax, NoTax]
      mapM_ (\c -> parseTaxCategory (T.unpack $ showTaxCategory c) `shouldBe` c) cats

  -- ──────────────────────────────────────────────
  -- showTransactionType
  -- ──────────────────────────────────────────────
  describe "showTransactionType" $ do
    it "shows Sale"                 $ showTransactionType Sale `shouldBe` "SALE"
    it "shows Return"               $ showTransactionType Return `shouldBe` "RETURN"
    it "shows Exchange"             $ showTransactionType Exchange `shouldBe` "EXCHANGE"
    it "shows InventoryAdjustment"  $ showTransactionType InventoryAdjustment `shouldBe` "INVENTORY_ADJUSTMENT"
    it "shows ManagerComp"          $ showTransactionType ManagerComp `shouldBe` "MANAGER_COMP"
    it "shows Administrative"       $ showTransactionType Administrative `shouldBe` "ADMINISTRATIVE"

  -- ──────────────────────────────────────────────
  -- showPaymentMethod
  -- ──────────────────────────────────────────────
  describe "showPaymentMethod" $ do
    it "shows Cash"        $ showPaymentMethod Cash `shouldBe` "CASH"
    it "shows Debit"       $ showPaymentMethod Debit `shouldBe` "DEBIT"
    it "shows Credit"      $ showPaymentMethod Credit `shouldBe` "CREDIT"
    it "shows ACH"         $ showPaymentMethod ACH `shouldBe` "ACH"
    it "shows GiftCard"    $ showPaymentMethod GiftCard `shouldBe` "GIFT_CARD"
    it "shows StoredValue" $ showPaymentMethod StoredValue `shouldBe` "STORED_VALUE"
    it "shows Mixed"       $ showPaymentMethod Mixed `shouldBe` "MIXED"
    it "shows Other"       $ showPaymentMethod (Other "Crypto") `shouldBe` "OTHER"

  -- ──────────────────────────────────────────────
  -- showTaxCategory
  -- ──────────────────────────────────────────────
  describe "showTaxCategory" $ do
    it "shows RegularSalesTax" $ showTaxCategory RegularSalesTax `shouldBe` "REGULAR_SALES_TAX"
    it "shows ExciseTax"       $ showTaxCategory ExciseTax `shouldBe` "EXCISE_TAX"
    it "shows CannabisTax"     $ showTaxCategory CannabisTax `shouldBe` "CANNABIS_TAX"
    it "shows LocalTax"        $ showTaxCategory LocalTax `shouldBe` "LOCAL_TAX"
    it "shows MedicalTax"      $ showTaxCategory MedicalTax `shouldBe` "MEDICAL_TAX"
    it "shows NoTax"           $ showTaxCategory NoTax `shouldBe` "NO_TAX"

  -- ──────────────────────────────────────────────
  -- showDiscountType
  -- ──────────────────────────────────────────────
  describe "showDiscountType" $ do
    it "shows PercentOff" $
      showDiscountType (PercentOff 10.0) `shouldBe` "PERCENT_OFF"
    it "shows AmountOff" $
      showDiscountType (AmountOff 500) `shouldBe` "AMOUNT_OFF"
    it "shows BuyOneGetOne" $
      showDiscountType BuyOneGetOne `shouldBe` "BUY_ONE_GET_ONE"
    it "shows Custom" $
      showDiscountType (Custom "Employee" 100) `shouldBe` "CUSTOM"

  -- ──────────────────────────────────────────────
  -- getDiscountPercent
  -- ──────────────────────────────────────────────
  describe "getDiscountPercent" $ do
    it "returns Just for PercentOff" $
      getDiscountPercent (PercentOff 15.0) `shouldBe` Just 15.0
    it "returns Nothing for AmountOff" $
      getDiscountPercent (AmountOff 500) `shouldBe` Nothing
    it "returns Nothing for BuyOneGetOne" $
      getDiscountPercent BuyOneGetOne `shouldBe` Nothing
    it "returns Nothing for Custom" $
      getDiscountPercent (Custom "test" 100) `shouldBe` Nothing

  -- ──────────────────────────────────────────────
  -- negateTransactionItem
  -- ──────────────────────────────────────────────
  describe "negateTransactionItem" $ do
    let negated = negateTransactionItem mkItem

    it "preserves id" $
      transactionItemId negated `shouldBe` transactionItemId mkItem

    it "preserves transaction id" $
      transactionItemTransactionId negated `shouldBe` transactionItemTransactionId mkItem

    it "preserves sku" $
      transactionItemMenuItemSku negated `shouldBe` transactionItemMenuItemSku mkItem

    it "preserves quantity (not negated)" $
      transactionItemQuantity negated `shouldBe` transactionItemQuantity mkItem

    it "preserves price per unit (not negated)" $
      transactionItemPricePerUnit negated `shouldBe` transactionItemPricePerUnit mkItem

    it "negates subtotal" $
      transactionItemSubtotal negated `shouldBe` negate (transactionItemSubtotal mkItem)

    it "negates total" $
      transactionItemTotal negated `shouldBe` negate (transactionItemTotal mkItem)

    it "negates nested discounts" $ do
      let origDiscount = head (transactionItemDiscounts mkItem)
      let negDiscount = head (transactionItemDiscounts negated)
      discountAmount negDiscount `shouldBe` negate (discountAmount origDiscount)

    it "negates nested taxes" $ do
      let origTax = head (transactionItemTaxes mkItem)
      let negTax = head (transactionItemTaxes negated)
      taxAmount negTax `shouldBe` negate (taxAmount origTax)

  -- ──────────────────────────────────────────────
  -- negateDiscountRecord
  -- ──────────────────────────────────────────────
  describe "negateDiscountRecord" $ do
    let negated = negateDiscountRecord mkDiscount

    it "negates amount" $
      discountAmount negated `shouldBe` -200

    it "preserves type" $
      discountType negated `shouldBe` discountType mkDiscount

    it "preserves reason" $
      discountReason negated `shouldBe` discountReason mkDiscount

    it "preserves approved_by" $
      discountApprovedBy negated `shouldBe` discountApprovedBy mkDiscount

  -- ──────────────────────────────────────────────
  -- negateTaxRecord
  -- ──────────────────────────────────────────────
  describe "negateTaxRecord" $ do
    let negated = negateTaxRecord mkTax

    it "negates amount" $
      taxAmount negated `shouldBe` -80

    it "preserves category" $
      taxCategory negated `shouldBe` taxCategory mkTax

    it "preserves rate" $
      taxRate negated `shouldBe` taxRate mkTax

    it "preserves description" $
      taxDescription negated `shouldBe` taxDescription mkTax

  -- ──────────────────────────────────────────────
  -- negatePaymentTransaction
  -- ──────────────────────────────────────────────
  describe "negatePaymentTransaction" $ do
    let negated = negatePaymentTransaction mkPayment

    it "preserves id" $
      paymentId negated `shouldBe` paymentId mkPayment

    it "negates amount" $
      paymentAmount negated `shouldBe` -5000

    it "negates tendered" $
      paymentTendered negated `shouldBe` -6000

    it "negates change" $
      paymentChange negated `shouldBe` -1000

    it "preserves method" $
      paymentMethod negated `shouldBe` paymentMethod mkPayment

    it "preserves reference" $
      paymentReference negated `shouldBe` paymentReference mkPayment

    it "preserves approved flag" $
      paymentApproved negated `shouldBe` paymentApproved mkPayment

  -- ──────────────────────────────────────────────
  -- Double negate is identity (for amounts)
  -- ──────────────────────────────────────────────
  describe "double negate is identity" $ do
    it "transaction item subtotal" $ do
      let item = negateTransactionItem (negateTransactionItem mkItem)
      transactionItemSubtotal item `shouldBe` transactionItemSubtotal mkItem

    it "transaction item total" $ do
      let item = negateTransactionItem (negateTransactionItem mkItem)
      transactionItemTotal item `shouldBe` transactionItemTotal mkItem

    it "payment amount" $ do
      let p = negatePaymentTransaction (negatePaymentTransaction mkPayment)
      paymentAmount p `shouldBe` paymentAmount mkPayment

    it "discount amount" $ do
      let d = negateDiscountRecord (negateDiscountRecord mkDiscount)
      discountAmount d `shouldBe` discountAmount mkDiscount

    it "tax amount" $ do
      let t = negateTaxRecord (negateTaxRecord mkTax)
      taxAmount t `shouldBe` taxAmount mkTax
