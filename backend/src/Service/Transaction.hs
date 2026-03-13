{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

-- Service layer: validates state-machine transitions, then delegates to DB.
-- The state machine is always consulted before any DB write that changes
-- transaction lifecycle state.

module Service.Transaction
  ( addItem
  , removeItem
  , addPayment
  , removePayment
  , finalizeTx
  , voidTx
  , refundTx
  ) where

import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Data.Pool (Pool)
import Data.Text (Text, pack)
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import qualified Data.ByteString.Lazy as LBS
import Database.PostgreSQL.Simple (Connection)
import Servant

import qualified DB.Transaction as DB
import State.TransactionMachine
import Types.Transaction

-- ── Helpers ──────────────────────────────────────────────────────────────────

loadTx :: Pool Connection -> UUID -> Handler (Transaction, SomeTxState)
loadTx pool txId = do
  maybeTx <- liftIO $ DB.getTransactionById pool txId
  case maybeTx of
    Nothing -> throwError err404 { errBody = "Transaction not found" }
    Just tx -> pure (tx, fromTransaction tx)

-- State machine violations are 409 Conflict: the request conflicts with the
-- current state of the resource.
guardEvent :: TxEvent -> Handler ()
guardEvent (InvalidTxCommand msg) =
  throwError err409 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
guardEvent _ = pure ()

-- ── Handlers ─────────────────────────────────────────────────────────────────

addItem :: Pool Connection -> TransactionItem -> Handler TransactionItem
addItem pool item = do
  let txId = transactionItemTransactionId item
  (_, someState) <- loadTx pool txId
  let (evt, _) = runTxCommand someState (AddItemCmd item)
  guardEvent evt

  result <- liftIO $ try (DB.addTransactionItem pool item)
  case result of
    Right added    -> pure added
    Left (e :: SomeException) ->
      throwError err400 { errBody = LBS.fromStrict . TE.encodeUtf8 $
        "Inventory error: " <> pack (Prelude.show e) }

removeItem :: Pool Connection -> UUID -> Handler NoContent
removeItem pool itemId = do
  txId <- lookupTxIdByItemId pool itemId
  (_, someState) <- loadTx pool txId
  let (evt, _) = runTxCommand someState (RemoveItemCmd itemId)
  guardEvent evt
  liftIO $ DB.deleteTransactionItem pool itemId
  pure NoContent

addPayment :: Pool Connection -> PaymentTransaction -> Handler PaymentTransaction
addPayment pool payment = do
  let txId = paymentTransactionId payment
  (_, someState) <- loadTx pool txId
  let (evt, _) = runTxCommand someState (AddPaymentCmd payment)
  guardEvent evt
  liftIO $ DB.addPaymentTransaction pool payment

removePayment :: Pool Connection -> UUID -> Handler NoContent
removePayment pool paymentId = do
  txId <- lookupTxIdByPaymentId pool paymentId
  (_, someState) <- loadTx pool txId
  let (evt, _) = runTxCommand someState (RemovePaymentCmd paymentId)
  guardEvent evt
  liftIO $ DB.deletePaymentTransaction pool paymentId
  pure NoContent

finalizeTx :: Pool Connection -> UUID -> Handler Transaction
finalizeTx pool txId = do
  (_, someState) <- loadTx pool txId
  let (evt, _) = runTxCommand someState FinalizeCmd
  guardEvent evt
  liftIO $ DB.finalizeTransaction pool txId

voidTx :: Pool Connection -> UUID -> Text -> Handler Transaction
voidTx pool txId reason = do
  (_, someState) <- loadTx pool txId
  let (evt, _) = runTxCommand someState (VoidCmd reason)
  guardEvent evt
  liftIO $ DB.voidTransaction pool txId reason

refundTx :: Pool Connection -> UUID -> Text -> Handler Transaction
refundTx pool txId reason = do
  (_, someState) <- loadTx pool txId
  refundId <- liftIO nextRandom
  let (evt, _) = runTxCommand someState (RefundCmd reason refundId)
  guardEvent evt
  liftIO $ DB.refundTransaction pool txId reason

-- ── Private ──────────────────────────────────────────────────────────────────

lookupTxIdByItemId :: Pool Connection -> UUID -> Handler UUID
lookupTxIdByItemId pool itemId = do
  mTxId <- liftIO $ DB.getTransactionIdByItemId pool itemId
  maybe (throwError err404 { errBody = "Item not found" }) pure mTxId

lookupTxIdByPaymentId :: Pool Connection -> UUID -> Handler UUID
lookupTxIdByPaymentId pool paymentId = do
  mTxId <- liftIO $ DB.getTransactionIdByPaymentId pool paymentId
  maybe (throwError err404 { errBody = "Payment not found" }) pure mTxId