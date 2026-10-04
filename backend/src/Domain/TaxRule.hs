{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Tax rules as they are stored, and the pure selection of the rules that
-- are in force for one location at one moment.
--
-- A stored rule adds two things to 'Domain.Pricing.TaxRule': where it
-- applies and when. A rule with no location applies at every location. A
-- rule is in force from 'storedEffectiveFrom' (inclusive) until
-- 'storedEffectiveTo' (exclusive), or indefinitely when there is no end.
--
-- The text codes in this module are the values written to the tax_rule
-- table. Decoding is strict: an unknown code is an error, because skipping
-- an unreadable rule would silently charge less tax.
module Domain.TaxRule
  ( StoredTaxRule (..)
  , inForce
  , activeRules
  , roundingCode
  , parseRoundingCode
  , taxCategoryCode
  , parseTaxCategoryCode
  , itemCategoryCode
  , parseItemCategoryCode
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Text.Read (readMaybe)

import Domain.Pricing (RoundingMode (..), TaxRule)
import Types.Inventory (ItemCategory)
import Types.Location (LocationId)
import Types.Transaction (TaxCategory (..))

data StoredTaxRule = StoredTaxRule
  { storedRuleId        :: UUID
  , storedLocation      :: Maybe LocationId
  , storedEffectiveFrom :: UTCTime
  , storedEffectiveTo   :: Maybe UTCTime
  , storedRule          :: TaxRule
  }
  deriving stock (Eq, Show)

-- | Whether a stored rule applies at a location at a moment.
inForce :: LocationId -> UTCTime -> StoredTaxRule -> Bool
inForce location now stored = atLocation && started && notEnded
  where
    atLocation = case storedLocation stored of
      Nothing -> True
      Just l  -> l == location
    started  = storedEffectiveFrom stored <= now
    notEnded = case storedEffectiveTo stored of
      Nothing  -> True
      Just end -> now < end

-- | The pricing rules in force at a location at a moment, in stored order.
activeRules :: LocationId -> UTCTime -> [StoredTaxRule] -> [TaxRule]
activeRules location now = map storedRule . filter (inForce location now)

roundingCode :: RoundingMode -> Text
roundingCode RoundHalfUp   = "HALF_UP"
roundingCode RoundHalfEven = "HALF_EVEN"
roundingCode RoundDown     = "DOWN"

parseRoundingCode :: Text -> Either Text RoundingMode
parseRoundingCode "HALF_UP"   = Right RoundHalfUp
parseRoundingCode "HALF_EVEN" = Right RoundHalfEven
parseRoundingCode "DOWN"      = Right RoundDown
parseRoundingCode other       = Left ("Unknown rounding mode: " <> other)

taxCategoryCode :: TaxCategory -> Text
taxCategoryCode RegularSalesTax = "REGULAR_SALES_TAX"
taxCategoryCode ExciseTax       = "EXCISE_TAX"
taxCategoryCode CannabisTax     = "CANNABIS_TAX"
taxCategoryCode LocalTax        = "LOCAL_TAX"
taxCategoryCode MedicalTax      = "MEDICAL_TAX"
taxCategoryCode NoTax           = "NO_TAX"

parseTaxCategoryCode :: Text -> Either Text TaxCategory
parseTaxCategoryCode "REGULAR_SALES_TAX" = Right RegularSalesTax
parseTaxCategoryCode "EXCISE_TAX"        = Right ExciseTax
parseTaxCategoryCode "CANNABIS_TAX"      = Right CannabisTax
parseTaxCategoryCode "LOCAL_TAX"         = Right LocalTax
parseTaxCategoryCode "MEDICAL_TAX"       = Right MedicalTax
parseTaxCategoryCode "NO_TAX"            = Right NoTax
parseTaxCategoryCode other               = Left ("Unknown tax category: " <> other)

-- | Item categories are stored by constructor name, the same text the
-- menu_items table uses.
itemCategoryCode :: ItemCategory -> Text
itemCategoryCode = T.pack . show

parseItemCategoryCode :: Text -> Either Text ItemCategory
parseItemCategoryCode code = case readMaybe (T.unpack code) of
  Just category -> Right category
  Nothing       -> Left ("Unknown item category: " <> code)
