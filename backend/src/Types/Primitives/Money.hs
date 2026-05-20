{-# LANGUAGE DerivingStrategies #-}

-- | Money primitives for the sale/refund split.
--
-- 'SaleMoney' represents an amount received in a sale; the underlying
-- 'Int' (cents) is non-negative. 'RefundMoney' represents an amount
-- returned in a refund; the underlying 'Int' is non-positive. Refunds
-- carry a negative value rather than a positive "magnitude" so that
-- summing across all transaction rows yields net revenue directly.
--
-- The two types are distinct, with no 'Num' instance and no automatic
-- coercion. The only path between them is 'negateToRefund' (and its
-- inverse 'negateFromRefund' for reporting). Any code that crosses
-- this boundary is visible at the call site.
--
-- No JSON or OpenAPI instances are exported yet; those land in a
-- later phase when these types are wired into the API surface. The
-- current module is internal Haskell only.
module Types.Primitives.Money
  ( -- * Sale money
    SaleMoney
  , mkSaleMoney
  , unsafeMkSaleMoney
  , saleMoneyCents
  , zeroSale
  , addSale
  , subtractSale
  , scaleSale
  , sumSale
    -- * Refund money
  , RefundMoney
  , mkRefundMoney
  , unsafeMkRefundMoney
  , refundMoneyCents
  , zeroRefund
  , addRefund
  , scaleRefund
  , sumRefund
    -- * Conversion between sale and refund
  , negateToRefund
  , negateFromRefund
  ) where


-- | A non-negative amount of money in cents, received in a sale.
--
-- Invariant: the underlying 'Int' is @>= 0@. Constructed only via
-- 'mkSaleMoney' (validating) or 'unsafeMkSaleMoney' (DB-decoding).
newtype SaleMoney = SaleMoney Int
  deriving stock (Eq, Ord, Show)

-- | A non-positive amount of money in cents, paid out in a refund.
--
-- Invariant: the underlying 'Int' is @<= 0@. Constructed only via
-- 'mkRefundMoney' (validating) or 'unsafeMkRefundMoney' (DB-decoding).
newtype RefundMoney = RefundMoney Int
  deriving stock (Eq, Ord, Show)

--------------------------------------------------------------------------------
-- Sale money

-- | Construct a 'SaleMoney' from cents. Returns 'Nothing' for negative
-- input, which would violate the non-negativity invariant.
mkSaleMoney :: Int -> Maybe SaleMoney
mkSaleMoney n
  | n >= 0    = Just (SaleMoney n)
  | otherwise = Nothing

-- | Construct a 'SaleMoney' without validation. Use only at trusted
-- boundaries (DB row decoding, internal arithmetic). Named ugly to
-- discourage casual use.
unsafeMkSaleMoney :: Int -> SaleMoney
unsafeMkSaleMoney = SaleMoney

-- | Extract the underlying cents value. Always @>= 0@.
saleMoneyCents :: SaleMoney -> Int
saleMoneyCents (SaleMoney n) = n

-- | The identity for 'addSale'. @addSale zeroSale x == x@.
zeroSale :: SaleMoney
zeroSale = SaleMoney 0

-- | Add two sale amounts. The result is always non-negative, so this
-- operation is total.
addSale :: SaleMoney -> SaleMoney -> SaleMoney
addSale (SaleMoney a) (SaleMoney b) = SaleMoney (a + b)

-- | Subtract one sale amount from another. Returns 'Nothing' if the
-- result would be negative (e.g. subtracting a discount larger than
-- the subtotal). Callers must handle the failure explicitly, typically
-- as a 400 from the API or a refusal to finalize the transaction.
subtractSale :: SaleMoney -> SaleMoney -> Maybe SaleMoney
subtractSale (SaleMoney a) (SaleMoney b)
  | a >= b    = Just (SaleMoney (a - b))
  | otherwise = Nothing

-- | Multiply a sale amount by a non-negative integer scalar (e.g.
-- price-per-unit times quantity). Returns 'Nothing' for negative
-- scalars, which would violate the invariant.
--
-- Does not check for overflow; callers must bound inputs appropriately
-- for their domain (a POS will never see a single line item over
-- @maxBound \`div\` 1000@ cents in practice).
scaleSale :: SaleMoney -> Int -> Maybe SaleMoney
scaleSale (SaleMoney n) k
  | k >= 0    = Just (SaleMoney (n * k))
  | otherwise = Nothing

-- | Sum a list of sale amounts. Total over an empty list is 'zeroSale'.
sumSale :: (Foldable f) => f SaleMoney -> SaleMoney
sumSale = foldl' addSale zeroSale

--------------------------------------------------------------------------------
-- Refund money

-- | Construct a 'RefundMoney' from cents. Returns 'Nothing' for
-- positive input, which would violate the non-positivity invariant.
mkRefundMoney :: Int -> Maybe RefundMoney
mkRefundMoney n
  | n <= 0    = Just (RefundMoney n)
  | otherwise = Nothing

-- | Construct a 'RefundMoney' without validation. Use only at trusted
-- boundaries (DB row decoding, internal arithmetic).
unsafeMkRefundMoney :: Int -> RefundMoney
unsafeMkRefundMoney = RefundMoney

-- | Extract the underlying cents value. Always @<= 0@.
refundMoneyCents :: RefundMoney -> Int
refundMoneyCents (RefundMoney n) = n

-- | The identity for 'addRefund'.
zeroRefund :: RefundMoney
zeroRefund = RefundMoney 0

-- | Add two refund amounts. The result is always non-positive.
addRefund :: RefundMoney -> RefundMoney -> RefundMoney
addRefund (RefundMoney a) (RefundMoney b) = RefundMoney (a + b)

-- | Multiply a refund amount by a non-negative integer scalar.
-- Returns 'Nothing' for negative scalars.
scaleRefund :: RefundMoney -> Int -> Maybe RefundMoney
scaleRefund (RefundMoney n) k
  | k >= 0    = Just (RefundMoney (n * k))
  | otherwise = Nothing

-- | Sum a list of refund amounts.
sumRefund :: (Foldable f) => f RefundMoney -> RefundMoney
sumRefund = foldl' addRefund zeroRefund

--------------------------------------------------------------------------------
-- Conversion

-- | Cross the sale-to-refund boundary by negating the underlying
-- cents value. This is the only path from 'SaleMoney' to
-- 'RefundMoney' and should be called exactly once per refund, in
-- 'Service.Transaction.refundTx' (or its successor).
negateToRefund :: SaleMoney -> RefundMoney
negateToRefund (SaleMoney n) = RefundMoney (negate n)

-- | The inverse of 'negateToRefund'. Used by reporting code that
-- wants to display refund magnitudes as positive numbers (e.g.
-- "you refunded $15.00" rather than "you refunded -$15.00").
negateFromRefund :: RefundMoney -> SaleMoney
negateFromRefund (RefundMoney n) = SaleMoney (negate n)
