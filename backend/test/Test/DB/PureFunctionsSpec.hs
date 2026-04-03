{-# LANGUAGE OverloadedStrings #-}

module Test.DB.PureFunctionsSpec (spec) where

import DB.Transaction
import Data.Scientific (fromFloatDigits)
import Data.UUID (UUID)
import Test.Hspec
import Types.Transaction

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testUUID :: UUID
testUUID = read "33333333-3333-3333-3333-333333333333"

testUUID2 :: UUID
testUUID2 = read "44444444-4444-4444-4444-444444444444"

mkItem :: TransactionItem
mkItem =
  TransactionItem
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
mkDiscount =
  DiscountRecord
    { discountType = AmountOff 200
    , discountAmount = 200
    , discountReason = "Employee"
    , discountApprovedBy = Just testUUID
    }

mkTax :: TaxRecord
mkTax =
  TaxRecord
    { taxCategory = RegularSalesTax
    , taxRate = fromFloatDigits (0.08 :: Double)
    , taxAmount = 80
    , taxDescription = "Sales Tax"
    }

mkPayment :: PaymentTransaction
mkPayment =
  PaymentTransaction
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
    it "shows Created" $ showStatus Created `shouldBe` "CREATED"
    it "shows InProgress" $ showStatus InProgress `shouldBe` "IN_PROGRESS"
    it "shows Completed" $ showStatus Completed `shouldBe` "COMPLETED"
    it "shows Voided" $ showStatus Voided `shouldBe` "VOIDED"
    it "shows Refunded" $ showStatus Refunded `shouldBe` "REFUNDED"

  -- ──────────────────────────────────────────────
  -- showTransactionType
  -- ──────────────────────────────────────────────
  describe "showTransactionType" $ do
    it "shows Sale" $ showTransactionType Sale `shouldBe` "SALE"
    it "shows Return" $ showTransactionType Return `shouldBe` "RETURN"
    it "shows Exchange" $ showTransactionType Exchange `shouldBe` "EXCHANGE"
    it "shows InventoryAdjustment" $ showTransactionType InventoryAdjustment `shouldBe` "INVENTORY_ADJUSTMENT"
    it "shows ManagerComp" $ showTransactionType ManagerComp `shouldBe` "MANAGER_COMP"
    it "shows Administrative" $ showTransactionType Administrative `shouldBe` "ADMINISTRATIVE"

  -- ──────────────────────────────────────────────
  -- showPaymentMethod
  -- ──────────────────────────────────────────────
  describe "showPaymentMethod" $ do
    it "shows Cash" $ showPaymentMethod Cash `shouldBe` "CASH"
    it "shows Debit" $ showPaymentMethod Debit `shouldBe` "DEBIT"
    it "shows Credit" $ showPaymentMethod Credit `shouldBe` "CREDIT"
    it "shows ACH" $ showPaymentMethod ACH `shouldBe` "ACH"
    it "shows GiftCard" $ showPaymentMethod GiftCard `shouldBe` "GIFT_CARD"
    it "shows StoredValue" $ showPaymentMethod StoredValue `shouldBe` "STORED_VALUE"
    it "shows Mixed" $ showPaymentMethod Mixed `shouldBe` "MIXED"
    it "shows Other" $ showPaymentMethod (Other "Crypto") `shouldBe` "OTHER:Crypto"

  -- ──────────────────────────────────────────────
  -- showTaxCategory
  -- ──────────────────────────────────────────────
  describe "showTaxCategory" $ do
    it "shows RegularSalesTax" $ showTaxCategory RegularSalesTax `shouldBe` "REGULAR_SALES_TAX"
    it "shows ExciseTax" $ showTaxCategory ExciseTax `shouldBe` "EXCISE_TAX"
    it "shows CannabisTax" $ showTaxCategory CannabisTax `shouldBe` "CANNABIS_TAX"
    it "shows LocalTax" $ showTaxCategory LocalTax `shouldBe` "LOCAL_TAX"
    it "shows MedicalTax" $ showTaxCategory MedicalTax `shouldBe` "MEDICAL_TAX"
    it "shows NoTax" $ showTaxCategory NoTax `shouldBe` "NO_TAX"

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

    it "preserves sku" $
      transactionItemMenuItemSku negated `shouldBe` transactionItemMenuItemSku mkItem

    it "negates nested discounts" $ do
      case (transactionItemDiscounts mkItem, transactionItemDiscounts negated) of
        (origDiscount : _, negDiscount : _) ->
          discountAmount negDiscount `shouldBe` negate (discountAmount origDiscount)
        _ -> expectationFailure "Expected at least one discount"

    it "negates nested taxes" $ do
      case (transactionItemTaxes mkItem, transactionItemTaxes negated) of
        (origTax : _, negTax : _) ->
          taxAmount negTax `shouldBe` negate (taxAmount origTax)
        _ -> expectationFailure "Expected at least one tax"

  -- ──────────────────────────────────────────────
  -- negateDiscountRecord
  -- ──────────────────────────────────────────────
  describe "negateDiscountRecord" $ do
    let negated = negateDiscountRecord mkDiscount

    it "preserves approved_by" $
      discountApprovedBy negated `shouldBe` discountApprovedBy mkDiscount

  -- ──────────────────────────────────────────────
  -- negateTaxRecord
  -- ──────────────────────────────────────────────
  describe "negateTaxRecord" $ do
    let negated = negateTaxRecord mkTax

    it "preserves description" $
      taxDescription negated `shouldBe` taxDescription mkTax

  -- ──────────────────────────────────────────────
  -- negatePaymentTransaction
  -- ──────────────────────────────────────────────
  describe "negatePaymentTransaction" $ do
    let negated = negatePaymentTransaction mkPayment

    it "preserves id" $
      paymentId negated `shouldBe` paymentId mkPayment

    it "preserves reference" $
      paymentReference negated `shouldBe` paymentReference mkPayment

    -- ──────────────────────────────────────────────
    -- Double negate is identity (for amounts)
    -- ──────────────────────────────────────────────
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
