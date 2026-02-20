module Cheeblr.Core.Money where

import Prelude

import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..), formatDiscrete)
import Data.Finance.Money.Extended (DiscreteMoney, fromDiscrete', toDiscrete)
import Data.Finance.Money.Format (numeric, numericC)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.String (trim)

----------------------------------------------------------------------
-- Conversions
----------------------------------------------------------------------

-- | Convert a dollar amount (e.g. 12.99) to cents.
fromDollars :: Number -> Discrete USD
fromDollars dollars = Discrete (Int.floor (dollars * 100.0))

-- | Convert cents to a dollar amount.
toDollars :: Discrete USD -> Number
toDollars (Discrete c) = Int.toNumber c / 100.0

-- | Parse a string like "12.99" into cents.
parseDollars :: String -> Maybe (Discrete USD)
parseDollars str = do
  num <- Number.fromString (trim str)
  pure (fromDollars num)

-- | Get the raw cent value.
cents :: Discrete USD -> Int
cents (Discrete c) = c

-- | Zero money value.
zeroCents :: Discrete USD
zeroCents = Discrete 0

----------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------

-- | Format as "$12.99"
formatCurrency :: Discrete USD -> String
formatCurrency = formatDiscrete numericC

-- | Format as "12.99" (no currency symbol)
formatAmount :: Discrete USD -> String
formatAmount = formatDiscrete numeric

-- | Format cents integer as "12.99" string.
formatCentsAsDecimal :: Int -> String
formatCentsAsDecimal c =
  let
    dollars = c / 100
    rem = c `mod` 100
    remStr = if rem < 10 then "0" <> show rem else show rem
  in
    show dollars <> "." <> remStr

-- | Format cents for display with dollar sign: "$12.99"
formatCentsAsDollars :: Int -> String
formatCentsAsDollars c = "$" <> formatCentsAsDecimal c

-- | Convert cents string (from backend) to display dollars.
-- | "1299" -> "12.99"
formatCentsStrToDecimal :: String -> String
formatCentsStrToDecimal centsStr =
  case Int.fromString centsStr of
    Just c -> show (Int.toNumber c / 100.0)
    Nothing -> centsStr

----------------------------------------------------------------------
-- DiscreteMoney interop
----------------------------------------------------------------------

-- | Wrap Discrete in the DiscreteMoney wrapper used by transaction types.
toMoney :: Discrete USD -> DiscreteMoney USD
toMoney = fromDiscrete'

-- | Unwrap DiscreteMoney to Discrete for calculations.
fromMoney :: DiscreteMoney USD -> Discrete USD
fromMoney = toDiscrete

-- | Format DiscreteMoney with currency symbol.
formatMoney :: DiscreteMoney USD -> String
formatMoney money = formatCurrency (fromMoney money)

-- | Format DiscreteMoney without currency symbol.
formatMoney' :: DiscreteMoney USD -> String
formatMoney' money = formatAmount (fromMoney money)