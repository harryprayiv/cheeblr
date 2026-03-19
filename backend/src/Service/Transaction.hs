{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Service.Transaction
  ( addItem
  , removeItem
  , addPayment
  , removePayment
  , finalizeTx
  , voidTx
  , refundTx
  ) where

import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text, pack)
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import Effectful
import Effectful.Error.Static
import Servant (ServerError(..), err400, err404, err409)
import Control.Monad (void)
import DB.Transaction (InventoryException (..))
import Effect.GenUUID
import Effect.TransactionDb
import State.TransactionMachine
import Types.Transaction

loadTx
  :: (TransactionDb :> es, Error ServerError :> es)
  => UUID
  -> Eff es (Transaction, SomeTxState)
loadTx txId = do
  maybeTx <- getTransactionById txId
  case maybeTx of
    Nothing -> throwError err404 { errBody = "Transaction not found" }
    Just tx -> pure (tx, fromTransaction tx)

guardTxEvent :: Error ServerError :> es => TxEvent -> Eff es ()
guardTxEvent (InvalidTxCommand msg) =
  throwError err409 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
guardTxEvent _ = pure ()

requireTxId
  :: Error ServerError :> es
  => (UUID -> Eff es (Maybe UUID))
  -> LBS.ByteString
  -> UUID
  -> Eff es UUID
requireTxId lookupFn notFoundMsg entityId = do
  mTxId <- lookupFn entityId
  case mTxId of
    Nothing   -> throwError err404 { errBody = notFoundMsg }
    Just txId -> pure txId

-- Persist any status change produced by the state machine transition so that
-- subsequent operations see the correct state when they call loadTx.
persistStatusChange
  :: (TransactionDb :> es)
  => Transaction
  -> SomeTxState
  -> Eff es ()
persistStatusChange tx nextState = do
  let nextStatus = someTxStatus nextState
  if transactionStatus tx == nextStatus
    then pure ()
    else void $ updateTransaction (transactionId tx) tx { transactionStatus = nextStatus }

addItem
  :: (TransactionDb :> es, Error ServerError :> es)
  => TransactionItem
  -> Eff es TransactionItem
addItem item = do
  (tx, someState) <- loadTx (transactionItemTransactionId item)
  let (evt, nextState) = runTxCommand someState (AddItemCmd item)
  guardTxEvent evt
  persistStatusChange tx nextState
  result <- addTransactionItem item
  case result of
    Right ti -> pure ti
    Left (ItemNotFound sku) ->
      throwError err404 { errBody = LBS.fromStrict . TE.encodeUtf8 $
        "Item not found: " <> pack (show sku) }
    Left (InsufficientInventory sku requested available) ->
      throwError err400 { errBody = LBS.fromStrict . TE.encodeUtf8 $
        "Insufficient inventory for " <> pack (show sku)
        <> ": " <> pack (show available) <> " available, "
        <> pack (show requested) <> " requested" }

removeItem
  :: (TransactionDb :> es, Error ServerError :> es)
  => UUID
  -> Eff es ()
removeItem itemId = do
  txId <- requireTxId getTxIdByItemId "Item not found" itemId
  (_, someState) <- loadTx txId
  let (evt, _) = runTxCommand someState (RemoveItemCmd itemId)
  guardTxEvent evt
  deleteTransactionItem itemId

addPayment
  :: (TransactionDb :> es, Error ServerError :> es)
  => PaymentTransaction
  -> Eff es PaymentTransaction
addPayment payment = do
  (_, someState) <- loadTx (paymentTransactionId payment)
  let (evt, _) = runTxCommand someState (AddPaymentCmd payment)
  guardTxEvent evt
  addPaymentTransaction payment

removePayment
  :: (TransactionDb :> es, Error ServerError :> es)
  => UUID
  -> Eff es ()
removePayment pymtId = do
  txId <- requireTxId getTxIdByPaymentId "Payment not found" pymtId
  (_, someState) <- loadTx txId
  let (evt, _) = runTxCommand someState (RemovePaymentCmd pymtId)
  guardTxEvent evt
  deletePaymentTransaction pymtId

finalizeTx
  :: (TransactionDb :> es, Error ServerError :> es)
  => UUID
  -> Eff es Transaction
finalizeTx txId = do
  (_, someState) <- loadTx txId
  let (evt, _) = runTxCommand someState FinalizeCmd
  guardTxEvent evt
  finalizeTransaction txId

voidTx
  :: (TransactionDb :> es, Error ServerError :> es)
  => UUID
  -> Text
  -> Eff es Transaction
voidTx txId reason = do
  (_, someState) <- loadTx txId
  let (evt, _) = runTxCommand someState (VoidCmd reason)
  guardTxEvent evt
  voidTransaction txId reason

refundTx
  :: (TransactionDb :> es, Error ServerError :> es, GenUUID :> es)
  => UUID
  -> Text
  -> Eff es Transaction
refundTx txId reason = do
  (_, someState) <- loadTx txId
  refundId <- nextUUID
  let (evt, _) = runTxCommand someState (RefundCmd reason refundId)
  guardTxEvent evt
  refundTransaction txId reason