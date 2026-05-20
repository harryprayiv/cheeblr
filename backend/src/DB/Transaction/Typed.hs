-- src/DB/Transaction/Typed.hs

-- {-# LANGUAGE OverloadedStrings #-}

-- | Typed hydration wrappers for transaction reads.
--
-- This module sits on top of 'DB.Transaction' and pipes the legacy
-- 'Types.Transaction.Transaction' values produced by the existing hydration
-- path through 'Types.Transaction.Conversion.fromLegacyTransaction',
-- returning the typed sale-or-refund split.
--
-- The functions here mirror the read paths in 'DB.Transaction'
-- ('hydrateTx', 'getTransactionById', 'getAllTransactions') with a typed
-- result. Nothing in 'Service.Transaction' calls them yet; 2E-5 switches
-- the service layer over.
--
-- Conversion failure surfaces as 'Left Text' rather than an exception.
-- Callers decide what to do: log and skip on batch reads, return a 500 on
-- single reads, or treat it as a hard invariant violation. The current
-- 'DB.Transaction.hydrateTx' still raises on missing rows; this module
-- preserves that semantic for the lookup wrappers (a missing row is
-- 'Nothing', not 'Just (Left ...)') and only uses 'Left' for conversion
-- failures on rows that do exist.
module DB.Transaction.Typed
  ( hydrateTxTyped
  , getTransactionByIdTyped
  , getAllTransactionsTyped
  ) where

import Data.Text (Text)
import Data.UUID (UUID)
import qualified Hasql.Session as Session
import Rel8

import DB.Database (DBPool, runSession)
import DB.Schema
import DB.Transaction (hydrateTx)
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale
import Types.Transaction.Conversion (fromLegacyTransaction)

-- | Typed counterpart to 'DB.Transaction.hydrateTx'.
--
-- Loads the row through the existing untyped hydration, then runs
-- 'fromLegacyTransaction' on the assembled aggregate. The discriminator is
-- the 'txTransactionType' column, handled inside the converter.
hydrateTxTyped ::
  DBPool ->
  TransactionRow Result ->
  IO (Either Text (Either Sale.SaleTransaction Refund.RefundTransaction))
hydrateTxTyped pool txRow = do
  tx <- hydrateTx pool txRow
  pure $ fromLegacyTransaction tx

-- | Typed counterpart to 'DB.Transaction.getTransactionById'.
--
-- 'Nothing' means the row does not exist. 'Just (Left e)' means the row
-- exists but failed conversion (e.g. a sale-shaped row with a negative
-- subtotal, or a refund row missing 'referenceTransactionId'); the
-- diagnostic 'e' identifies which invariant was violated.
getTransactionByIdTyped ::
  DBPool ->
  UUID ->
  IO (Maybe (Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)))
getTransactionByIdTyped pool txId = do
  rows <-
    runSession pool $
      Session.statement () $
        run $
          Rel8.select $ do
            tx <- each transactionSchema
            where_ $ DB.Schema.txId tx ==. lit txId
            pure tx
  case rows of
    [row] -> Just <$> hydrateTxTyped pool row
    _     -> pure Nothing

-- | Typed counterpart to 'DB.Transaction.getAllTransactions'.
--
-- Each row is independently 'Right' or 'Left'; one corrupt row does not
-- discard the rest of the batch. Callers that need a hard-fail semantics
-- can 'sequence' the list at the call site.
getAllTransactionsTyped ::
  DBPool ->
  IO [Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)]
getAllTransactionsTyped pool = do
  txRows <-
    runSession pool $
      Session.statement () $
        run $
          Rel8.select (each transactionSchema)
  mapM (hydrateTxTyped pool) txRows