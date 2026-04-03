{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Service.Transaction (
  createTransactionSvc,
  addItem,
  removeItem,
  addPayment,
  removePayment,
  finalizeTx,
  voidTx,
  refundTx,
) where

import Control.Monad (void)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text, pack)
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import Effectful
import Effectful.Error.Static
import Servant (ServerError (..), err400, err404, err409)

import DB.Transaction (InventoryException (..))
import Effect.Clock
import Effect.EventEmitter
import Effect.GenUUID
import Effect.TransactionDb
import State.TransactionMachine
import Types.Events.Domain
import Types.Events.Transaction
import Types.Transaction

loadTx ::
  (TransactionDb :> es, Error ServerError :> es) =>
  UUID ->
  Eff es (Transaction, SomeTxState)
loadTx txId = do
  maybeTx <- getTransactionById txId
  case maybeTx of
    Nothing -> throwError err404 {errBody = "Transaction not found"}
    Just tx -> pure (tx, fromTransaction tx)

guardTxEvent :: (Error ServerError :> es) => TxEvent -> Eff es ()
guardTxEvent (InvalidTxCommand msg) =
  throwError err409 {errBody = LBS.fromStrict (TE.encodeUtf8 msg)}
guardTxEvent _ = pure ()

requireTxId ::
  (Error ServerError :> es) =>
  (UUID -> Eff es (Maybe UUID)) ->
  LBS.ByteString ->
  UUID ->
  Eff es UUID
requireTxId lookupFn notFoundMsg entityId = do
  mTxId <- lookupFn entityId
  case mTxId of
    Nothing -> throwError err404 {errBody = notFoundMsg}
    Just txId -> pure txId

persistStatusChange ::
  (TransactionDb :> es) =>
  Transaction ->
  SomeTxState ->
  Eff es ()
persistStatusChange tx nextState = do
  let nextStatus = someTxStatus nextState
  if transactionStatus tx == nextStatus
    then pure ()
    else void $ updateTransaction (transactionId tx) tx {transactionStatus = nextStatus}

createTransactionSvc ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  ) =>
  Transaction ->
  Eff es Transaction
createTransactionSvc tx = do
  result <- createTransaction tx
  now <- currentTime
  emit $
    TransactionEvt $
      TransactionCreated
        { teTx = result
        , teTimestamp = now
        }
  pure result

addItem ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  TransactionItem ->
  Eff es TransactionItem
addItem item = do
  (tx, someState) <- loadTx (transactionItemTransactionId item)
  let (evt, nextState) = runTxCommand someState (AddItemCmd item)
  guardTxEvent evt
  persistStatusChange tx nextState
  result <- addTransactionItem item
  case result of
    Right ti -> do
      now <- currentTime
      emit $
        TransactionEvt $
          TransactionItemAdded
            { teTxId = transactionItemTransactionId item
            , teItem = ti
            , teTimestamp = now
            }
      pure ti
    Left (ItemNotFound sku) ->
      throwError
        err404
          { errBody =
              LBS.fromStrict . TE.encodeUtf8 $
                "Item not found: " <> pack (show sku)
          }
    Left (InsufficientInventory sku requested available) ->
      throwError
        err400
          { errBody =
              LBS.fromStrict . TE.encodeUtf8 $
                "Insufficient inventory for "
                  <> pack (show sku)
                  <> ": "
                  <> pack (show available)
                  <> " available, "
                  <> pack (show requested)
                  <> " requested"
          }

removeItem ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es ()
removeItem itemId = do
  txId <- requireTxId getTxIdByItemId "Item not found" itemId
  (_, someState) <- loadTx txId
  -- fetch item before deletion for the event payload
  mTx <- getTransactionById txId
  let mItem =
        mTx >>= \t ->
          foldr
            (\i acc -> if transactionItemId i == itemId then Just i else acc)
            Nothing
            (transactionItems t)
  let (evt, _) = runTxCommand someState (RemoveItemCmd itemId)
  guardTxEvent evt
  deleteTransactionItem itemId
  now <- currentTime
  case mItem of
    Just item ->
      emit $
        TransactionEvt $
          TransactionItemRemoved
            { teTxId = txId
            , teItemId = itemId
            , teItemSku = transactionItemMenuItemSku item
            , teQty = transactionItemQuantity item
            , teTimestamp = now
            }
    Nothing -> pure ()

addPayment ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  PaymentTransaction ->
  Eff es PaymentTransaction
addPayment payment = do
  (_, someState) <- loadTx (paymentTransactionId payment)
  let (evt, _) = runTxCommand someState (AddPaymentCmd payment)
  guardTxEvent evt
  result <- addPaymentTransaction payment
  now <- currentTime
  emit $
    TransactionEvt $
      TransactionPaymentAdded
        { teTxId = paymentTransactionId payment
        , tePayment = result
        , teTimestamp = now
        }
  pure result

removePayment ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es ()
removePayment pymtId = do
  txId <- requireTxId getTxIdByPaymentId "Payment not found" pymtId
  (_, someState) <- loadTx txId
  let (evt, _) = runTxCommand someState (RemovePaymentCmd pymtId)
  guardTxEvent evt
  deletePaymentTransaction pymtId
  now <- currentTime
  emit $
    TransactionEvt $
      TransactionPaymentRemoved
        { teTxId = txId
        , tePaymentId = pymtId
        , teTimestamp = now
        }

finalizeTx ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es Transaction
finalizeTx txId = do
  (_, someState) <- loadTx txId
  let (evt, _) = runTxCommand someState FinalizeCmd
  guardTxEvent evt
  result <- finalizeTransaction txId
  now <- currentTime
  emit $
    TransactionEvt $
      TransactionFinalized
        { teTxId = txId
        , teTx = result
        , teTimestamp = now
        }
  pure result

voidTx ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Text ->
  Eff es Transaction
voidTx txId reason = do
  (tx, someState) <- loadTx txId
  let (evt, _) = runTxCommand someState (VoidCmd reason)
  guardTxEvent evt
  result <- voidTransaction txId reason
  now <- currentTime
  emit $
    TransactionEvt $
      TransactionVoided
        { teTxId = txId
        , teReason = reason
        , teActorId = transactionEmployeeId tx
        , teTimestamp = now
        }
  pure result

refundTx ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Text ->
  Eff es Transaction
refundTx txId reason = do
  (tx, someState) <- loadTx txId
  refundId <- nextUUID
  let (evt, _) = runTxCommand someState (RefundCmd reason refundId)
  guardTxEvent evt
  result <- refundTransaction txId reason
  now <- currentTime
  emit $
    TransactionEvt $
      TransactionRefunded
        { teTxId = txId
        , teReason = reason
        , teActorId = transactionEmployeeId tx
        , teRefTxId = transactionId result
        , teTimestamp = now
        }
  pure result
