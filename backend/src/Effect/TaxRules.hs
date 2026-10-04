{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.TaxRules (
  TaxRules (..),
  getActiveTaxRules,
  runTaxRulesIO,
  runTaxRulesPure,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Effectful
import Effectful.Dispatch.Dynamic

import DB.Database (DBPool)
import qualified DB.TaxRule as DB
import Domain.Pricing (TaxRule)
import Domain.TaxRule (StoredTaxRule, activeRules)
import Types.Location (LocationId)

data TaxRules :: Effect where
  GetActiveTaxRules :: LocationId -> UTCTime -> TaxRules m (Either Text [TaxRule])

type instance DispatchOf TaxRules = Dynamic

-- | The tax rules in force at a location at a moment. 'Left' means a stored
-- rule could not be read, and the caller must refuse to price the sale.
getActiveTaxRules ::
  (TaxRules :> es) =>
  LocationId ->
  UTCTime ->
  Eff es (Either Text [TaxRule])
getActiveTaxRules location now = send (GetActiveTaxRules location now)

runTaxRulesIO :: (IOE :> es) => DBPool -> Eff (TaxRules : es) a -> Eff es a
runTaxRulesIO pool = interpret $ \_ -> \case
  GetActiveTaxRules location now ->
    liftIO $ fmap (activeRules location now) <$> DB.getStoredTaxRules pool

runTaxRulesPure :: [StoredTaxRule] -> Eff (TaxRules : es) a -> Eff es a
runTaxRulesPure stored = interpret $ \_ -> \case
  GetActiveTaxRules location now ->
    pure (Right (activeRules location now stored))
