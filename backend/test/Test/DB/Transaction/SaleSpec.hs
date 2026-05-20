{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.DB.Transaction.SaleSpec (spec) where

import Data.Scientific (fromFloatDigits)
import Data.UUID (UUID)
import Test.Hspec

import DB.Schema (
  DiscountRow (..),
  PaymentRow (..),
  TaxRow (..),
  TransactionItemRow (..),
 )
import qualified DB.Transaction.Sale as SaleDb
import Types.Primitives.Money (saleMoneyCents)
import Types.Primitives.Quantity (saleQuantityCount)
import Types.Transaction (
  DiscountType (..),
  PaymentMethod (Cash),
  TaxCategory (RegularSalesTax),
 )
import Rel8 (Result)
import qualified Types.Transaction.Sale as Sale

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testItemId, testTxId, testSkuId :: UUID
testItemId = read "11111111-1111-1111-1111-111111111111"
testTxId   = read "22222222-2222-2222-2222-222222222222"
testSkuId  = read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

testApproverId :: UUID
testApproverId = read "33333333-3333-3333-3333-333333333333"

testDiscId, testTaxId, testPaymentId :: UUID
testDiscId    = read "44444444-4444-4444-4444-444444444444"
testTaxId     = read "55555555-5555-5555-5555-555555555555"
testPaymentId = read "66666666-6666-6666-6666-666666666666"

testItemRow :: TransactionItemRow Result
testItemRow =
  TransactionItemRow
    { tiId            = testItemId
    , tiTransactionId = testTxId
    , tiMenuItemSku   = testSkuId
    , tiQuantity      = 3
    , tiPricePerUnit  = 500
    , tiSubtotal      = 1500
    , tiTotal         = 1620
    }

testDiscountRow :: DiscountRow Result
testDiscountRow =
  DiscountRow
    { discRowId                = testDiscId
    , discRowTransactionItemId = Just testItemId
    , discRowTransactionId     = Nothing
    , discRowType              = "AMOUNT_OFF"
    , discRowAmount            = 100
    , discRowPercent           = Nothing
    , discRowReason            = "Employee"
    , discRowApprovedBy        = Just testApproverId
    }

testTaxRow :: TaxRow Result
testTaxRow =
  TaxRow
    { taxRowId                = testTaxId
    , taxRowTransactionItemId = testItemId
    , taxRowCategory          = "REGULAR_SALES_TAX"
    , taxRowRate              = 0.08
    , taxRowAmount            = 120
    , taxRowDescription       = "Sales tax"
    }

testPaymentRow :: PaymentRow Result
testPaymentRow =
  PaymentRow
    { pymtId                = testPaymentId
    , pymtTransactionId     = testTxId
    , pymtMethod            = "CASH"
    , pymtAmount            = 1620
    , pymtTendered          = 2000
    , pymtChange            = 380
    , pymtReference         = Nothing
    , pymtApproved          = True
    , pymtAuthorizationCode = Nothing
    }

spec :: Spec
spec = describe "DB.Transaction.Sale" $ do

  -- ──────────────────────────────────────────────
  -- Item decoder
  -- ──────────────────────────────────────────────
  describe "itemRowToDomain" $ do
    let item = SaleDb.itemRowToDomain testItemRow [] []

    it "preserves itemId" $
      Sale.itemId item `shouldBe` testItemId

    it "preserves itemTransactionId" $
      Sale.itemTransactionId item `shouldBe` testTxId

    it "preserves itemMenuItemSku" $
      Sale.itemMenuItemSku item `shouldBe` testSkuId

    it "decodes quantity as a non-negative SaleQuantity" $
      saleQuantityCount (Sale.itemQuantity item) `shouldBe` 3

    it "decodes pricePerUnit as a non-negative SaleMoney" $
      saleMoneyCents (Sale.itemPricePerUnit item) `shouldBe` 500

    it "decodes subtotal as a non-negative SaleMoney" $
      saleMoneyCents (Sale.itemSubtotal item) `shouldBe` 1500

    it "decodes total as a non-negative SaleMoney" $
      saleMoneyCents (Sale.itemTotal item) `shouldBe` 1620

    it "passes through the supplied discount list" $
      Sale.itemDiscounts item `shouldBe` []

    it "passes through the supplied tax list" $
      Sale.itemTaxes item `shouldBe` []

    it "handles a zero-quantity, zero-money row" $ do
      let zeroRow = testItemRow {tiQuantity = 0, tiSubtotal = 0, tiTotal = 0}
          zeroItem = SaleDb.itemRowToDomain zeroRow [] []
      saleQuantityCount (Sale.itemQuantity zeroItem) `shouldBe` 0
      saleMoneyCents (Sale.itemSubtotal zeroItem) `shouldBe` 0
      saleMoneyCents (Sale.itemTotal zeroItem) `shouldBe` 0

  -- ──────────────────────────────────────────────
  -- Discount decoder
  -- ──────────────────────────────────────────────
  describe "discountRowToDomain" $ do
    let d = SaleDb.discountRowToDomain testDiscountRow

    it "decodes discountType from row text" $
      Sale.discountType d `shouldBe` AmountOff 100

    it "decodes discountAmount as a non-negative SaleMoney" $
      saleMoneyCents (Sale.discountAmount d) `shouldBe` 100

    it "preserves discountReason" $
      Sale.discountReason d `shouldBe` "Employee"

    it "preserves discountApprovedBy" $
      Sale.discountApprovedBy d `shouldBe` Just testApproverId

  -- ──────────────────────────────────────────────
  -- Tax decoder
  -- ──────────────────────────────────────────────
  describe "taxRowToDomain" $ do
    let t = SaleDb.taxRowToDomain testTaxRow

    it "decodes taxCategory from row text" $
      Sale.taxCategory t `shouldBe` RegularSalesTax

    it "decodes taxRate" $
      Sale.taxRate t `shouldBe` fromFloatDigits (0.08 :: Double)

    it "decodes taxAmount as a non-negative SaleMoney" $
      saleMoneyCents (Sale.taxAmount t) `shouldBe` 120

    it "preserves taxDescription" $
      Sale.taxDescription t `shouldBe` "Sales tax"

  -- ──────────────────────────────────────────────
  -- Payment decoder
  -- ──────────────────────────────────────────────
  describe "paymentRowToDomain" $ do
    let p = SaleDb.paymentRowToDomain testPaymentRow

    it "preserves paymentId" $
      Sale.paymentId p `shouldBe` testPaymentId

    it "preserves paymentTransactionId" $
      Sale.paymentTransactionId p `shouldBe` testTxId

    it "decodes paymentMethod from row text" $
      Sale.paymentMethod p `shouldBe` Cash

    it "decodes paymentAmount as a non-negative SaleMoney" $
      saleMoneyCents (Sale.paymentAmount p) `shouldBe` 1620

    it "decodes paymentTendered as a non-negative SaleMoney" $
      saleMoneyCents (Sale.paymentTendered p) `shouldBe` 2000

    it "decodes paymentChange as a non-negative SaleMoney" $
      saleMoneyCents (Sale.paymentChange p) `shouldBe` 380

    it "preserves paymentApproved" $
      Sale.paymentApproved p `shouldBe` True

    it "preserves paymentReference" $
      Sale.paymentReference p `shouldBe` Nothing

    it "preserves paymentAuthorizationCode" $
      Sale.paymentAuthorizationCode p `shouldBe` Nothing