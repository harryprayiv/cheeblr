{-# LANGUAGE OverloadedStrings #-}

module Test.Types.Transaction.ConversionSpec (spec) where

import Data.Scientific (Scientific, fromFloatDigits)
import Data.Text (Text)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import Types.Primitives.Money (
  SaleMoney,
  mkSaleMoney,
  refundMoneyCents,
  saleMoneyCents,
 )
import Types.Primitives.Quantity (
  SaleQuantity,
  mkSaleQuantity,
  refundQuantityCount,
  saleQuantityCount,
 )
import Types.Transaction (
  DiscountType (..),
  PaymentMethod (..),
  TaxCategory (..),
 )
import Types.Transaction.Conversion (
  toRefundDiscount,
  toRefundItem,
  toRefundPayment,
  toRefundTax,
 )
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale

--------------------------------------------------------------------------------
-- Generators
--
-- Move to Test.Gen alongside the existing transaction-domain generators
-- in a future pass; kept inline here so this spec is self-contained.
--------------------------------------------------------------------------------

genUUID :: Gen UUID
genUUID =
  UUID.fromWords64
    <$> Gen.word64 Range.linearBounded
    <*> Gen.word64 Range.linearBounded

genText :: Gen Text
genText = Gen.text (Range.linear 0 20) Gen.alphaNum

-- | A non-negative fractional rate in [0, 1], representing a tax or
-- discount percentage as a decimal.
genRate :: Gen Scientific
genRate =
  fromFloatDigits <$> Gen.double (Range.linearFrac (0 :: Double) 1)

genSaleMoney :: Gen SaleMoney
genSaleMoney = do
  n <- Gen.int (Range.linear 0 1000000)
  case mkSaleMoney n of
    Just s  -> pure s
    Nothing -> error "genSaleMoney: invariant violated"

genSaleQuantity :: Gen SaleQuantity
genSaleQuantity = do
  n <- Gen.int (Range.linear 0 10000)
  case mkSaleQuantity n of
    Just q  -> pure q
    Nothing -> error "genSaleQuantity: invariant violated"

genDiscountType :: Gen DiscountType
genDiscountType =
  Gen.choice
    [ PercentOff <$> genRate
    , AmountOff <$> Gen.int (Range.linear 0 10000)
    , pure BuyOneGetOne
    , Custom <$> genText <*> Gen.int (Range.linear 0 10000)
    ]

genTaxCategory :: Gen TaxCategory
genTaxCategory =
  Gen.element
    [ RegularSalesTax
    , ExciseTax
    , CannabisTax
    , LocalTax
    , MedicalTax
    , NoTax
    ]

genPaymentMethod :: Gen PaymentMethod
genPaymentMethod =
  Gen.choice
    [ pure Cash
    , pure Debit
    , pure Credit
    , pure ACH
    , pure GiftCard
    , pure StoredValue
    , pure Mixed
    , Other <$> genText
    ]

genSaleDiscount :: Gen Sale.Discount
genSaleDiscount = do
  ty     <- genDiscountType
  amount <- genSaleMoney
  reason <- genText
  appr   <- Gen.maybe genUUID
  pure
    Sale.Discount
      { Sale.discountType       = ty
      , Sale.discountAmount     = amount
      , Sale.discountReason     = reason
      , Sale.discountApprovedBy = appr
      }

genSaleTax :: Gen Sale.Tax
genSaleTax = do
  cat    <- genTaxCategory
  rate   <- genRate
  amount <- genSaleMoney
  descr  <- genText
  pure
    Sale.Tax
      { Sale.taxCategory    = cat
      , Sale.taxRate        = rate
      , Sale.taxAmount      = amount
      , Sale.taxDescription = descr
      }

genSaleItem :: Gen Sale.Item
genSaleItem = do
  iid       <- genUUID
  txid      <- genUUID
  sku       <- genUUID
  qty       <- genSaleQuantity
  ppu       <- genSaleMoney
  discounts <- Gen.list (Range.linear 0 3) genSaleDiscount
  taxes     <- Gen.list (Range.linear 0 3) genSaleTax
  subtotal  <- genSaleMoney
  total     <- genSaleMoney
  pure
    Sale.Item
      { Sale.itemId            = iid
      , Sale.itemTransactionId = txid
      , Sale.itemMenuItemSku   = sku
      , Sale.itemQuantity      = qty
      , Sale.itemPricePerUnit  = ppu
      , Sale.itemDiscounts     = discounts
      , Sale.itemTaxes         = taxes
      , Sale.itemSubtotal      = subtotal
      , Sale.itemTotal         = total
      }

genSalePayment :: Gen Sale.Payment
genSalePayment = do
  pid       <- genUUID
  txid      <- genUUID
  method    <- genPaymentMethod
  amount    <- genSaleMoney
  tendered  <- genSaleMoney
  change    <- genSaleMoney
  reference <- Gen.maybe genText
  approved  <- Gen.bool
  authCode  <- Gen.maybe genText
  pure
    Sale.Payment
      { Sale.paymentId                = pid
      , Sale.paymentTransactionId     = txid
      , Sale.paymentMethod            = method
      , Sale.paymentAmount            = amount
      , Sale.paymentTendered          = tendered
      , Sale.paymentChange            = change
      , Sale.paymentReference         = reference
      , Sale.paymentApproved          = approved
      , Sale.paymentAuthorizationCode = authCode
      }

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------

spec :: Spec
spec = describe "Types.Transaction.Conversion" $ do

  describe "toRefundItem" $ do
    it "preserves itemId" $ hedgehog $ do
      s <- forAll genSaleItem
      Refund.itemId (toRefundItem s) === Sale.itemId s

    it "preserves itemTransactionId" $ hedgehog $ do
      s <- forAll genSaleItem
      Refund.itemTransactionId (toRefundItem s) === Sale.itemTransactionId s

    it "preserves itemMenuItemSku" $ hedgehog $ do
      s <- forAll genSaleItem
      Refund.itemMenuItemSku (toRefundItem s) === Sale.itemMenuItemSku s

    it "preserves the quantity count (only the type tag changes)" $ hedgehog $ do
      s <- forAll genSaleItem
      refundQuantityCount (Refund.itemQuantity (toRefundItem s))
        === saleQuantityCount (Sale.itemQuantity s)

    it "preserves itemPricePerUnit (rate is unchanged)" $ hedgehog $ do
      s <- forAll genSaleItem
      Refund.itemPricePerUnit (toRefundItem s) === Sale.itemPricePerUnit s

    it "flips sign of itemSubtotal" $ hedgehog $ do
      s <- forAll genSaleItem
      refundMoneyCents (Refund.itemSubtotal (toRefundItem s))
        === negate (saleMoneyCents (Sale.itemSubtotal s))

    it "flips sign of itemTotal" $ hedgehog $ do
      s <- forAll genSaleItem
      refundMoneyCents (Refund.itemTotal (toRefundItem s))
        === negate (saleMoneyCents (Sale.itemTotal s))

    it "preserves the discount list length" $ hedgehog $ do
      s <- forAll genSaleItem
      length (Refund.itemDiscounts (toRefundItem s))
        === length (Sale.itemDiscounts s)

    it "preserves the tax list length" $ hedgehog $ do
      s <- forAll genSaleItem
      length (Refund.itemTaxes (toRefundItem s))
        === length (Sale.itemTaxes s)

  describe "toRefundDiscount" $ do
    it "preserves discountType" $ hedgehog $ do
      d <- forAll genSaleDiscount
      Refund.discountType (toRefundDiscount d) === Sale.discountType d

    it "flips sign of discountAmount" $ hedgehog $ do
      d <- forAll genSaleDiscount
      refundMoneyCents (Refund.discountAmount (toRefundDiscount d))
        === negate (saleMoneyCents (Sale.discountAmount d))

    it "preserves discountReason" $ hedgehog $ do
      d <- forAll genSaleDiscount
      Refund.discountReason (toRefundDiscount d) === Sale.discountReason d

    it "preserves discountApprovedBy" $ hedgehog $ do
      d <- forAll genSaleDiscount
      Refund.discountApprovedBy (toRefundDiscount d) === Sale.discountApprovedBy d

  describe "toRefundTax" $ do
    it "preserves taxCategory" $ hedgehog $ do
      t <- forAll genSaleTax
      Refund.taxCategory (toRefundTax t) === Sale.taxCategory t

    it "preserves taxRate" $ hedgehog $ do
      t <- forAll genSaleTax
      Refund.taxRate (toRefundTax t) === Sale.taxRate t

    it "flips sign of taxAmount" $ hedgehog $ do
      t <- forAll genSaleTax
      refundMoneyCents (Refund.taxAmount (toRefundTax t))
        === negate (saleMoneyCents (Sale.taxAmount t))

    it "preserves taxDescription" $ hedgehog $ do
      t <- forAll genSaleTax
      Refund.taxDescription (toRefundTax t) === Sale.taxDescription t

  describe "toRefundPayment" $ do
    it "preserves paymentId" $ hedgehog $ do
      p <- forAll genSalePayment
      Refund.paymentId (toRefundPayment p) === Sale.paymentId p

    it "preserves paymentTransactionId" $ hedgehog $ do
      p <- forAll genSalePayment
      Refund.paymentTransactionId (toRefundPayment p) === Sale.paymentTransactionId p

    it "preserves paymentMethod" $ hedgehog $ do
      p <- forAll genSalePayment
      Refund.paymentMethod (toRefundPayment p) === Sale.paymentMethod p

    it "flips sign of paymentAmount" $ hedgehog $ do
      p <- forAll genSalePayment
      refundMoneyCents (Refund.paymentAmount (toRefundPayment p))
        === negate (saleMoneyCents (Sale.paymentAmount p))

    it "flips sign of paymentTendered" $ hedgehog $ do
      p <- forAll genSalePayment
      refundMoneyCents (Refund.paymentTendered (toRefundPayment p))
        === negate (saleMoneyCents (Sale.paymentTendered p))

    it "flips sign of paymentChange" $ hedgehog $ do
      p <- forAll genSalePayment
      refundMoneyCents (Refund.paymentChange (toRefundPayment p))
        === negate (saleMoneyCents (Sale.paymentChange p))

    it "preserves paymentReference" $ hedgehog $ do
      p <- forAll genSalePayment
      Refund.paymentReference (toRefundPayment p) === Sale.paymentReference p

    it "preserves paymentApproved" $ hedgehog $ do
      p <- forAll genSalePayment
      Refund.paymentApproved (toRefundPayment p) === Sale.paymentApproved p

    it "preserves paymentAuthorizationCode" $ hedgehog $ do
      p <- forAll genSalePayment
      Refund.paymentAuthorizationCode (toRefundPayment p)
        === Sale.paymentAuthorizationCode p
