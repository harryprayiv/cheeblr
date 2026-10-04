{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Pure pricing for one sale line. No database, no clock, no floating
-- point. The service layer picks the tax rules that are in force for the
-- location and time, and this module turns a unit price, a quantity and
-- those rules into the amounts that get stored.
--
-- All money is integer cents. All rates are integer parts per million, so
-- 6.25% is 62500 and 8.875% is 88750. Each tax is rounded once, to the
-- cent, by the rounding mode its rule names, and the rounded amount is what
-- is stored. Totals are sums of stored amounts.
module Domain.Pricing
  ( TaxRate
  , mkTaxRate
  , taxRatePpm
  , ratePerMillion
  , RoundingMode (..)
  , TaxRule (..)
  , LineTax (..)
  , LinePricing (..)
  , PricingError (..)
  , roundDiv
  , taxOn
  , rulesFor
  , priceLine
  ) where

import Data.Text (Text)

import Types.Inventory (ItemCategory)
import Types.Transaction (TaxCategory)

-- | A tax rate in parts per million. Never negative.
newtype TaxRate = TaxRate Int
  deriving stock (Eq, Ord, Show)

mkTaxRate :: Int -> Maybe TaxRate
mkTaxRate ppm
  | ppm >= 0  = Just (TaxRate ppm)
  | otherwise = Nothing

taxRatePpm :: TaxRate -> Int
taxRatePpm (TaxRate ppm) = ppm

-- | The denominator for 'TaxRate'.
ratePerMillion :: Integer
ratePerMillion = 1000000

-- | How a fractional cent is resolved.
--
-- * 'RoundHalfUp': a fraction of exactly half a cent goes up. The common
--   commercial rule.
-- * 'RoundHalfEven': a fraction of exactly half a cent goes to the even
--   cent. Used where the policy calls for unbiased rounding.
-- * 'RoundDown': any fraction is dropped.
data RoundingMode
  = RoundHalfUp
  | RoundHalfEven
  | RoundDown
  deriving stock (Eq, Ord, Show, Read)

-- | One tax that applies to a line.
--
-- 'ruleItemCategory' of 'Nothing' means the rule applies to every item
-- category. Location and effective dates are not here: the caller passes
-- only the rules already selected for the sale's location and time.
data TaxRule = TaxRule
  { ruleItemCategory :: Maybe ItemCategory
  , ruleTaxCategory  :: TaxCategory
  , ruleRate         :: TaxRate
  , ruleRounding     :: RoundingMode
  , ruleDescription  :: Text
  }
  deriving stock (Eq, Show)

-- | One computed tax on a line, ready to store.
data LineTax = LineTax
  { lineTaxCategory    :: TaxCategory
  , lineTaxRate        :: TaxRate
  , lineTaxAmount      :: Int
  , lineTaxDescription :: Text
  }
  deriving stock (Eq, Show)

-- | Everything stored for one sale line. Amounts are cents.
data LinePricing = LinePricing
  { lineUnitPrice :: Int
  , lineQuantity  :: Int
  , lineSubtotal  :: Int
  , lineTaxes     :: [LineTax]
  , lineTaxTotal  :: Int
  , lineTotal     :: Int
  }
  deriving stock (Eq, Show)

data PricingError
  = NonPositiveQuantity Int
  | NegativeUnitPrice Int
  deriving stock (Eq, Show)

-- | Divide a non-negative numerator by a positive denominator and round the
-- result to an integer by the given mode.
roundDiv :: RoundingMode -> Integer -> Integer -> Integer
roundDiv mode numerator denominator =
  case mode of
    RoundDown -> whole
    RoundHalfUp
      | twiceRest >= denominator -> whole + 1
      | otherwise                -> whole
    RoundHalfEven
      | twiceRest > denominator                 -> whole + 1
      | twiceRest == denominator && odd whole   -> whole + 1
      | otherwise                               -> whole
  where
    (whole, rest) = numerator `quotRem` denominator
    twiceRest     = 2 * rest

-- | The tax in cents on a base amount in cents.
taxOn :: RoundingMode -> TaxRate -> Int -> Int
taxOn mode (TaxRate ppm) baseCents =
  fromInteger $
    roundDiv mode (toInteger baseCents * toInteger ppm) ratePerMillion

-- | The rules that apply to an item category, in the order given.
rulesFor :: ItemCategory -> [TaxRule] -> [TaxRule]
rulesFor category = filter applies
  where
    applies rule = case ruleItemCategory rule of
      Nothing -> True
      Just c  -> c == category

-- | Price one line. Every applicable rule is charged on the line subtotal.
-- A tax is not charged on another tax.
priceLine
  :: [TaxRule]
  -> ItemCategory
  -> Int
  -- ^ unit price in cents
  -> Int
  -- ^ quantity
  -> Either PricingError LinePricing
priceLine rules category unitPrice quantity
  | quantity <= 0 = Left (NonPositiveQuantity quantity)
  | unitPrice < 0 = Left (NegativeUnitPrice unitPrice)
  | otherwise     =
      Right
        LinePricing
          { lineUnitPrice = unitPrice
          , lineQuantity  = quantity
          , lineSubtotal  = subtotal
          , lineTaxes     = taxes
          , lineTaxTotal  = taxTotal
          , lineTotal     = subtotal + taxTotal
          }
  where
    subtotal = unitPrice * quantity
    taxes    = map charge (rulesFor category rules)
    taxTotal = sum (map lineTaxAmount taxes)
    charge rule =
      LineTax
        { lineTaxCategory    = ruleTaxCategory rule
        , lineTaxRate        = ruleRate rule
        , lineTaxAmount      = taxOn (ruleRounding rule) (ruleRate rule) subtotal
        , lineTaxDescription = ruleDescription rule
        }
