{-# LANGUAGE DerivingStrategies #-}

-- | Quantity primitives for the sale/refund split.
--
-- Both 'SaleQuantity' and 'RefundQuantity' wrap a non-negative 'Int'.
-- They represent counts of units, which are never less than zero.
-- The two types are distinct purely to prevent context mixing at the
-- type level: a function that expects "units returned in a refund"
-- must not be accidentally called with "units sold in a sale," and
-- vice versa.
--
-- This is the asymmetric counterpart to 'Types.Primitives.Money',
-- where the underlying sign actually differs ('RefundMoney' is
-- non-positive because refunds owe money out). The asymmetry exists
-- because in this codebase, refund records in the database store
-- positive quantities and negative monetary amounts. A refund of 3
-- units at $5/unit appears in the DB as @quantity = 3@,
-- @subtotal = -15@, @total = -15@. The "direction" of a transaction
-- is carried entirely by the money signs; the unit counts are
-- always positive. See 'negateTransactionItem' in 'DB.Transaction'
-- and the matching invariant in 'Test.Props.NegateSpec' for the
-- original convention.
--
-- Conversion between 'SaleQuantity' and 'RefundQuantity' is purely
-- nominal: 'toRefundQuantity' and 'toSaleQuantity' preserve the
-- underlying count and only change the type tag. This contrasts
-- with 'negateToRefund' \/ 'negateFromRefund' for Money, which flip
-- the sign as well as the type.
--
-- Known vulnerabilities (see project hardening notes):
--   * V1: 'unsafeMkSaleQuantity' and 'unsafeMkRefundQuantity' bypass
--     validation and should be restricted to the DB row decoder.
--   * V2: arithmetic uses raw 'Int' without overflow detection.
--   * V3: no upper bound on construction.
module Types.Primitives.Quantity
  ( -- * Sale quantity
    SaleQuantity
  , mkSaleQuantity
  , unsafeMkSaleQuantity
  , saleQuantityCount
  , zeroSaleQuantity
  , oneSaleQuantity
  , addSaleQuantity
  , subtractSaleQuantity
  , sumSaleQuantity
    -- * Refund quantity
  , RefundQuantity
  , mkRefundQuantity
  , unsafeMkRefundQuantity
  , refundQuantityCount
  , zeroRefundQuantity
  , addRefundQuantity
  , subtractRefundQuantity
  , sumRefundQuantity
    -- * Conversion (nominal; values preserved)
  , toRefundQuantity
  , toSaleQuantity
  ) where


-- | A non-negative count of units transacted in a sale.
newtype SaleQuantity = SaleQuantity Int
  deriving stock (Eq, Ord, Show)

-- | A non-negative count of units returned in a refund.
--
-- Distinct from 'SaleQuantity' to prevent context mixing at the type
-- level, but with the same underlying invariant (counts are always
-- non-negative). See module documentation for the reasoning.
newtype RefundQuantity = RefundQuantity Int
  deriving stock (Eq, Ord, Show)

--------------------------------------------------------------------------------
-- Sale quantity

mkSaleQuantity :: Int -> Maybe SaleQuantity
mkSaleQuantity n
  | n >= 0    = Just (SaleQuantity n)
  | otherwise = Nothing

unsafeMkSaleQuantity :: Int -> SaleQuantity
unsafeMkSaleQuantity = SaleQuantity

saleQuantityCount :: SaleQuantity -> Int
saleQuantityCount (SaleQuantity n) = n

zeroSaleQuantity :: SaleQuantity
zeroSaleQuantity = SaleQuantity 0

oneSaleQuantity :: SaleQuantity
oneSaleQuantity = SaleQuantity 1

addSaleQuantity :: SaleQuantity -> SaleQuantity -> SaleQuantity
addSaleQuantity (SaleQuantity a) (SaleQuantity b) = SaleQuantity (a + b)

subtractSaleQuantity :: SaleQuantity -> SaleQuantity -> Maybe SaleQuantity
subtractSaleQuantity (SaleQuantity a) (SaleQuantity b)
  | a >= b    = Just (SaleQuantity (a - b))
  | otherwise = Nothing

sumSaleQuantity :: (Foldable f) => f SaleQuantity -> SaleQuantity
sumSaleQuantity = foldl' addSaleQuantity zeroSaleQuantity

--------------------------------------------------------------------------------
-- Refund quantity (same invariant as Sale; distinct type for context)

mkRefundQuantity :: Int -> Maybe RefundQuantity
mkRefundQuantity n
  | n >= 0    = Just (RefundQuantity n)
  | otherwise = Nothing

unsafeMkRefundQuantity :: Int -> RefundQuantity
unsafeMkRefundQuantity = RefundQuantity

refundQuantityCount :: RefundQuantity -> Int
refundQuantityCount (RefundQuantity n) = n

zeroRefundQuantity :: RefundQuantity
zeroRefundQuantity = RefundQuantity 0

addRefundQuantity :: RefundQuantity -> RefundQuantity -> RefundQuantity
addRefundQuantity (RefundQuantity a) (RefundQuantity b) = RefundQuantity (a + b)

subtractRefundQuantity :: RefundQuantity -> RefundQuantity -> Maybe RefundQuantity
subtractRefundQuantity (RefundQuantity a) (RefundQuantity b)
  | a >= b    = Just (RefundQuantity (a - b))
  | otherwise = Nothing

sumRefundQuantity :: (Foldable f) => f RefundQuantity -> RefundQuantity
sumRefundQuantity = foldl' addRefundQuantity zeroRefundQuantity

--------------------------------------------------------------------------------
-- Conversion (nominal: type changes, value is preserved)

-- | Convert a 'SaleQuantity' to a 'RefundQuantity'. The underlying
-- count is preserved unchanged; only the type tag changes. This
-- contrasts with 'negateToRefund' on Money, which flips the sign.
--
-- Called by the refund construction path in 'Service.Transaction'
-- when building a 'RefundTransactionItem' from the corresponding
-- 'SaleTransactionItem'.
toRefundQuantity :: SaleQuantity -> RefundQuantity
toRefundQuantity (SaleQuantity n) = RefundQuantity n

-- | The inverse of 'toRefundQuantity'. Used by reporting code that
-- wants to display refund counts as sale-equivalent quantities for
-- aggregation alongside sales data.
toSaleQuantity :: RefundQuantity -> SaleQuantity
toSaleQuantity (RefundQuantity n) = SaleQuantity n