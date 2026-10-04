{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

-- | The tax_rule table. Reads return every stored rule; choosing the rules
-- in force for a location and time is done in 'Domain.TaxRule', which is
-- pure and tested.
module DB.TaxRule
  ( TaxRuleRow (..)
  , taxRuleSchema
  , createTaxRuleTables
  , getStoredTaxRules
  , decodeTaxRuleRow
  ) where

import Data.Bifunctor (first)
import Data.Int (Int32)
import Data.List (sortOn)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import GHC.Generics (Generic)
import qualified Hasql.Session as Session
import Rel8 (Column, Name, Rel8able, Result, TableSchema (..), each, run, select)

import DB.Database (DBPool, ddl, runSession)
import Domain.Pricing (TaxRule (..), mkTaxRate)
import Domain.TaxRule
  ( StoredTaxRule (..)
  , parseItemCategoryCode
  , parseRoundingCode
  , parseTaxCategoryCode
  )
import Types.Location (LocationId (..))

data TaxRuleRow f = TaxRuleRow
  { trId            :: Column f UUID
  , trLocationId    :: Column f (Maybe UUID)
  , trItemCategory  :: Column f (Maybe Text)
  , trTaxCategory   :: Column f Text
  , trRatePpm       :: Column f Int32
  , trRounding      :: Column f Text
  , trDescription   :: Column f Text
  , trEffectiveFrom :: Column f UTCTime
  , trEffectiveTo   :: Column f (Maybe UTCTime)
  }
  deriving stock (Generic)
  deriving anyclass (Rel8able)

deriving stock instance (f ~ Result) => Show (TaxRuleRow f)

taxRuleSchema :: TableSchema (TaxRuleRow Name)
taxRuleSchema =
  TableSchema
    { name = "tax_rule"
    , columns =
        TaxRuleRow
          { trId            = "id"
          , trLocationId    = "location_id"
          , trItemCategory  = "item_category"
          , trTaxCategory   = "tax_category"
          , trRatePpm       = "rate_ppm"
          , trRounding      = "rounding"
          , trDescription   = "description"
          , trEffectiveFrom = "effective_from"
          , trEffectiveTo   = "effective_to"
          }
    }

-- | Creates the table. When the table is empty it also inserts one
-- placeholder rule so that development sales carry a tax line. The
-- placeholder is the 8% rate the browser used to apply. It is not a real
-- tax rule and must be replaced before the system takes real sales.
createTaxRuleTables :: DBPool -> IO ()
createTaxRuleTables pool = runSession pool $ do
  Session.statement () $
    ddl
      "CREATE TABLE IF NOT EXISTS tax_rule (\
      \  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),\
      \  location_id     UUID,\
      \  item_category   TEXT,\
      \  tax_category    TEXT         NOT NULL,\
      \  rate_ppm        INTEGER      NOT NULL CHECK (rate_ppm >= 0),\
      \  rounding        TEXT         NOT NULL,\
      \  description     TEXT         NOT NULL,\
      \  effective_from  TIMESTAMPTZ  NOT NULL,\
      \  effective_to    TIMESTAMPTZ,\
      \  CHECK (effective_to IS NULL OR effective_to > effective_from)\
      \)"
  Session.statement () $
    ddl
      "INSERT INTO tax_rule \
      \  (id, location_id, item_category, tax_category, rate_ppm, rounding, description, effective_from, effective_to) \
      \SELECT gen_random_uuid(), NULL, NULL, 'REGULAR_SALES_TAX', 80000, 'HALF_UP', \
      \  'PLACEHOLDER 8 percent sales tax. Replace with real rules.', \
      \  TIMESTAMPTZ '1970-01-01 00:00:00+00', NULL \
      \WHERE NOT EXISTS (SELECT 1 FROM tax_rule)"

-- | Every stored rule, in a stable order. One unreadable row makes the
-- whole read fail with a message naming that row.
getStoredTaxRules :: DBPool -> IO (Either Text [StoredTaxRule])
getStoredTaxRules pool = do
  rows <- runSession pool $ Session.statement () $ run $ select (each taxRuleSchema)
  pure (traverse decodeTaxRuleRow (sortOn ordering rows))
  where
    ordering row = (trTaxCategory row, trId row)

decodeTaxRuleRow :: TaxRuleRow Result -> Either Text StoredTaxRule
decodeTaxRuleRow row = first prefix $ do
  itemCategory <- traverse parseItemCategoryCode (trItemCategory row)
  taxCategory  <- parseTaxCategoryCode (trTaxCategory row)
  rounding     <- parseRoundingCode (trRounding row)
  rate         <- case mkTaxRate (fromIntegral (trRatePpm row)) of
    Just r  -> Right r
    Nothing -> Left "Negative rate"
  pure
    StoredTaxRule
      { storedRuleId        = trId row
      , storedLocation      = LocationId <$> trLocationId row
      , storedEffectiveFrom = trEffectiveFrom row
      , storedEffectiveTo   = trEffectiveTo row
      , storedRule          =
          TaxRule
            { ruleItemCategory = itemCategory
            , ruleTaxCategory  = taxCategory
            , ruleRate         = rate
            , ruleRounding     = rounding
            , ruleDescription  = trDescription row
            }
      }
  where
    prefix err = "tax_rule " <> UUID.toText (trId row) <> ": " <> err
