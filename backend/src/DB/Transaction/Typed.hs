{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Typed read path for transactions.
--
-- Phase 2G: hydrate 'TransactionRow' values into the Sale/Refund split.
-- The existing @transaction_type@ column is the discriminator: 'Return'
-- decodes as 'Refund.RefundTransaction', everything else as
-- 'Sale.SaleTransaction'. No new column, no migration.
--
-- Implementation routes through the legacy 'DBT.hydrateTx' so that the
-- smart constructors in 'Types.Transaction.Conversion' catch sign and
-- format violations: a 'Return' row with positive 'transactionTotal' is
-- a 'Left Text', not a silently-wrong refund. The extra legacy
-- allocation is irrelevant at POS scale; correctness is not negotiable.
-- The dispatch in 'fromLegacyTransaction' is by 'transactionType', so
-- only one of the Sale or Refund decoders runs per row, not both.
module DB.Transaction.Typed
  ( hydrateTxTyped
  , getTransactionByIdTyped
  , getAllTransactionsTyped
  , getTransactionsByLocationTyped
  ) where

import Data.Text (Text)
import Data.UUID (UUID)
import Rel8 (Result)

import DB.Database (DBPool)
import DB.Schema (TransactionRow)
import qualified DB.Transaction as DBT
import Types.Location (LocationId)
import qualified Types.Transaction as Legacy
import Types.Transaction.Conversion (fromLegacyTransaction)
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale

-- | Hydrate a 'TransactionRow' into the typed Sale/Refund split.
--
-- @Left Text@ means the row was hydrated but failed typed-validation
-- (a 'Return' with positive amounts, missing 'referenceTransactionId',
-- a malformed enum string, etc). @Right (Left sale)@ is a sale-side
-- transaction; @Right (Right refund)@ is a refund.
--
-- Decoding cost is dominated by the same N+1 child-table queries as
-- 'DBT.hydrateTx'. This wrapper adds one pure pass through
-- 'fromLegacyTransaction', bounded by items + payments.
hydrateTxTyped
  :: DBPool
  -> TransactionRow Result
  -> IO (Either Text (Either Sale.SaleTransaction Refund.RefundTransaction))
hydrateTxTyped pool row = do
  legacy <- DBT.hydrateTx pool row
  pure (fromLegacyTransaction legacy)

-- | Look up a transaction by id and return the typed view.
--
-- @Nothing@ means no row exists. @Just (Left e)@ means the row exists
-- but failed typed-validation. @Just (Right ...)@ is the typed value.
getTransactionByIdTyped
  :: DBPool
  -> UUID
  -> IO (Maybe (Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)))
getTransactionByIdTyped pool uuid = do
  mTx <- DBT.getTransactionById pool uuid
  pure (fmap fromLegacyTransaction mTx)

-- | All transactions, typed. Rows that fail validation appear as
-- 'Left' in the result list; they are NOT silently dropped. Callers
-- that want only successfully-decoded rows should filter.
getAllTransactionsTyped
  :: DBPool
  -> IO [Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)]
getAllTransactionsTyped pool = do
  txs <- DBT.getAllTransactions pool
  pure (fmap fromLegacyTransaction txs)

-- | Transactions at a location, typed. Filtering is post-hoc in
-- Haskell, matching the pre-existing pattern in
-- 'Effect.TransactionDb.runTransactionDbIO'. This is wasteful at scale.
-- Add a SQL @WHERE location_id = ?@ before this becomes a hot path.
getTransactionsByLocationTyped
  :: DBPool
  -> LocationId
  -> IO [Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)]
getTransactionsByLocationTyped pool locId = do
  txs <- DBT.getAllTransactions pool
  pure
    [ fromLegacyTransaction tx
    | tx <- txs
    , Legacy.transactionLocationId tx == locId
    ]