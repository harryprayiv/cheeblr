module Utils.Money where

import Prelude

import Data.Finance.Currency (USD)
import Data.Finance.Money (Dense, Discrete(..), Rounding(Nearest), formatDiscrete, fromDense)
import Data.Finance.Money.Extended (DiscreteMoney, fromDiscrete', toDiscrete)
import Data.Finance.Money.Format (numeric, numericC)
import Data.Int as Int
import Data.Maybe (Maybe)
import Data.Number as Number
import Data.String (trim)

formatPrice :: DiscreteMoney USD -> String
formatPrice = formatMoney'

formatDiscretePrice :: Discrete USD -> String
formatDiscretePrice = formatMoney' <<< fromDiscrete'

-- | Convert a dollar amount (as a Number) to cents (as a Discrete USD)
-- | Example: fromDollars 12.34 = Discrete 1234
fromDollars :: Number -> Discrete USD
fromDollars dollars = Discrete (Int.floor (dollars * 100.0))

-- | Convert cents (as a Discrete USD) to a dollar amount (as a Number)
-- | Example: toDollars (Discrete 1234) = 12.34
toDollars :: Discrete USD -> Number
toDollars (Discrete cents) = Int.toNumber cents / 100.0

-- | Format a DiscreteMoney USD value as a string with currency symbol
-- | Example: "$12.34"
formatMoney :: DiscreteMoney USD -> String
formatMoney money = formatDiscrete numericC (toDiscrete money)

-- | Format a DiscreteMoney USD value as a string without currency symbol
-- | Example: "12.34"
formatMoney' :: DiscreteMoney USD -> String
formatMoney' money = formatDiscrete numeric (toDiscrete money)

-- | Format a Discrete USD value as a string with currency symbol
-- | Example: "$12.34"
formatDiscreteUSD :: Discrete USD -> String
formatDiscreteUSD = formatDiscrete numericC

-- | Format a Discrete USD value as a string without currency symbol
-- | Example: "12.34"
formatDiscreteUSD' :: Discrete USD -> String
formatDiscreteUSD' = formatDiscrete numeric

-- | Format a Dense USD value as a string
formatDenseMoney :: Dense USD -> String
formatDenseMoney dense =
  let
    discrete = fromDense Nearest dense
  in
    formatDiscrete numeric discrete

-- | Convert a Discrete USD to a DiscreteMoney USD
fromDiscrete :: Discrete USD -> DiscreteMoney USD
fromDiscrete = fromDiscrete'

-- | Parse a money string (like "12.34") into a Discrete USD value
parseMoneyString :: String -> Maybe (Discrete USD)
parseMoneyString str = do
  num <- Number.fromString (trim str)
  pure (fromDollars num)