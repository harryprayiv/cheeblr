module Cheeblr.Core.Tax where

import Prelude

import Cheeblr.Core.Domain (Category, isTaxableCategory)
import Cheeblr.Core.Money (zeroCents, cents, toMoney)
import Cheeblr.Core.Money as Cheeblr.Core.Money
import Data.Array (filter, foldl)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (DiscreteMoney)
import Data.Int as Int
import Data.Newtype (unwrap)

----------------------------------------------------------------------
-- Tax Rule definitions
----------------------------------------------------------------------

-- | A tax category identifier.
data TaxCategory
  = RegularSalesTax
  | ExciseTax
  | CannabisTax
  | LocalTax
  | MedicalTax
  | NoTax

derive instance Eq TaxCategory
derive instance Ord TaxCategory

instance Show TaxCategory where
  show RegularSalesTax = "RegularSalesTax"
  show ExciseTax = "ExciseTax"
  show CannabisTax = "CannabisTax"
  show LocalTax = "LocalTax"
  show MedicalTax = "MedicalTax"
  show NoTax = "NoTax"

-- | A rule that determines whether and how much tax applies.
type TaxRule =
  { category :: TaxCategory
  , rate :: Number
  , description :: String
  , applies :: Category -> Boolean    -- predicate on product category
  }

-- | The result of applying a tax rule to an amount.
type TaxResult =
  { taxCategory :: TaxCategory
  , taxRate :: Number
  , taxAmount :: DiscreteMoney USD
  , taxDescription :: String
  }

----------------------------------------------------------------------
-- Default tax rules
----------------------------------------------------------------------

-- | Standard sales tax: applies to everything.
salesTaxRule :: TaxRule
salesTaxRule =
  { category: RegularSalesTax
  , rate: 0.08
  , description: "Sales Tax"
  , applies: const true
  }

-- | Cannabis excise tax: applies only to taxable categories.
cannabisTaxRule :: TaxRule
cannabisTaxRule =
  { category: CannabisTax
  , rate: 0.15
  , description: "Cannabis Excise Tax"
  , applies: isTaxableCategory
  }

-- | The default rule set for the dispensary.
defaultTaxRules :: Array TaxRule
defaultTaxRules = [ salesTaxRule, cannabisTaxRule ]

----------------------------------------------------------------------
-- Tax computation (pure)
----------------------------------------------------------------------

-- | Apply a single tax rule to a subtotal for a given product category.
-- | Returns Nothing if the rule doesn't apply.
applyRule :: TaxRule -> Discrete USD -> Category -> TaxResult
applyRule rule amount productCategory =
  let
    amountInCents = unwrap amount
    taxCents =
      if rule.applies productCategory
      then Int.floor (Int.toNumber amountInCents * rule.rate)
      else 0
  in
    { taxCategory: rule.category
    , taxRate: rule.rate
    , taxAmount: toMoney (Discrete taxCents)
    , taxDescription: rule.description
    }

-- | Calculate all applicable taxes for a subtotal and product category.
calculateTaxes
  :: Array TaxRule
  -> Discrete USD
  -> Category
  -> Array TaxResult
calculateTaxes rules amount category =
  rules
    <#> (\rule -> applyRule rule amount category)
    # filter (\result -> cents (fromMoney' result.taxAmount) /= 0)
  where
  fromMoney' :: DiscreteMoney USD -> Discrete USD
  fromMoney' = Cheeblr.Core.Money.fromMoney

-- | Sum the tax amounts from an array of tax results.
totalTax :: Array TaxResult -> Discrete USD
totalTax = foldl (\acc r -> acc + fromMoney' r.taxAmount) zeroCents
  where
  fromMoney' :: DiscreteMoney USD -> Discrete USD
  fromMoney' = Cheeblr.Core.Money.fromMoney

-- | Calculate taxes using the default dispensary rules.
defaultTaxes :: Discrete USD -> Category -> Array TaxResult
defaultTaxes = calculateTaxes defaultTaxRules