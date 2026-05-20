-- src/Service/Transaction.hs
--
-- Service layer for transactions. Phase 2F: refundTx no longer discards the
-- typed Refund.RefundTransaction; it passes it to writeRefund.
--
-- Everything else is unchanged from 2E-5: typed internals, legacy I/O at
-- the service boundary. Mutating ops on refund-shaped rows are rejected as
-- 409 (loadSaleAndLegacy). Conversion failures split across 400 (input not
-- coercible to Sale.Item / Sale.Payment) and 500 (loaded DB row not
-- coercible by fromLegacyTransaction).

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

import Control.Monad (forM_, void, when)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text, pack)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Data.Vector as V
import Effectful
import Effectful.Error.Static
import Servant (ServerError (..), err400, err404, err409, err500)

import DB.Transaction (InventoryException (..))
import Effect.Clock
import Effect.EventEmitter
import Effect.GenUUID
import qualified Effect.InventoryDb as EffInv
import qualified Effect.StockDb as StockDb
import Effect.TransactionDb
import State.SaleTransactionMachine
  ( SaleTxCommand (..)
  , SaleTxEvent (..)
  , SomeSaleTxState
  , fromSaleTransaction
  , runTxCommand
  , someTxStatus
  )
import State.StockPullMachine (PullVertex (..))
import qualified Types.Transaction.Sale as Sale
import Types.Transaction.Conversion
  ( fromLegacyTransaction
  , saleItemFromLegacy
  , salePaymentFromLegacy
  , toRefundTransaction
  )
import Types.Events.Domain
import Types.Events
import Types.Inventory (Inventory (..))
import qualified Types.Inventory as TI
import Types.Stock (PullRequest (..))
import Types.Transaction

loadSaleAndLegacy ::
  (TransactionDb :> es, Error ServerError :> es) =>
  UUID ->
  Eff es (Transaction, Sale.SaleTransaction)
loadSaleAndLegacy txId = do
  maybeTx <- getTransactionById txId
  case maybeTx of
    Nothing -> throwError err404 {errBody = "Transaction not found"}
    Just legacy -> case fromLegacyTransaction legacy of
      Left reason ->
        throwError
          err500
            { errBody =
                LBS.fromStrict . TE.encodeUtf8 $
                  "Transaction failed typed conversion: " <> reason
            }
      Right (Left sale) -> pure (legacy, sale)
      Right (Right _refund) ->
        throwError err409 {errBody = "Cannot modify a refund transaction"}

guardSaleTxEvent :: (Error ServerError :> es) => SaleTxEvent -> Eff es ()
guardSaleTxEvent (InvalidTxCommand msg) =
  throwError err409 {errBody = LBS.fromStrict (TE.encodeUtf8 msg)}
guardSaleTxEvent _ = pure ()

requireTxId ::
  (Error ServerError :> es) =>
  (UUID -> Eff es (Maybe UUID)) ->
  LBS.ByteString ->
  UUID ->
  Eff es UUID
requireTxId lookupFn notFoundMsg entityId = do
  mTxId <- lookupFn entityId
  case mTxId of
    Nothing   -> throwError err404 {errBody = notFoundMsg}
    Just txId -> pure txId

persistStatusChange ::
  (TransactionDb :> es) =>
  Transaction ->
  SomeSaleTxState ->
  Eff es ()
persistStatusChange legacy nextState = do
  let nextStatus = someTxStatus nextState
  if transactionStatus legacy == nextStatus
    then pure ()
    else
      void $
        updateTransaction
          (transactionId legacy)
          legacy {transactionStatus = nextStatus}

requireSaleItem ::
  (Error ServerError :> es) =>
  TransactionItem ->
  Eff es Sale.Item
requireSaleItem ti = case saleItemFromLegacy ti of
  Right item -> pure item
  Left reason ->
    throwError
      err400
        { errBody =
            LBS.fromStrict . TE.encodeUtf8 $
              "Invalid sale item: " <> reason
        }

requireSalePayment ::
  (Error ServerError :> es) =>
  PaymentTransaction ->
  Eff es Sale.Payment
requireSalePayment p = case salePaymentFromLegacy p of
  Right payment -> pure payment
  Left reason ->
    throwError
      err400
        { errBody =
            LBS.fromStrict . TE.encodeUtf8 $
              "Invalid sale payment: " <> reason
        }

createStockPull ::
  ( StockDb.StockDb :> es
  , EffInv.InventoryDb :> es
  , EventEmitter :> es
  , GenUUID :> es
  ) =>
  Transaction ->
  TransactionItem ->
  UTCTime ->
  Eff es ()
createStockPull tx ti now = do
  pullId <- nextUUID
  Inventory invVec <- EffInv.getAllMenuItems
  let
    itemSku  = transactionItemMenuItemSku ti
    itemName =
      maybe (T.pack $ show itemSku) TI.name $
        V.find (\m -> TI.sku m == itemSku) invVec
    pr =
      PullRequest
        { prId             = pullId
        , prTransactionId  = transactionItemTransactionId ti
        , prItemSku        = itemSku
        , prItemName       = itemName
        , prQuantityNeeded = transactionItemQuantity ti
        , prStatus         = PullPending
        , prCashierId      = Just (transactionEmployeeId tx)
        , prRegisterId     = Just (transactionRegisterId tx)
        , prLocationId     = transactionLocationId tx
        , prCreatedAt      = now
        , prUpdatedAt      = now
        , prFulfilledAt    = Nothing
        }
  prResult <- StockDb.createPullRequest pr
  case prResult of
    Right () -> emit $ StockEvt $ PullRequestCreated {sePull = pr, seTimestamp = now}
    Left _   -> pure ()

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
        { teTx        = result
        , teTimestamp = now
        }
  pure result

addItem ::
  ( TransactionDb :> es
  , StockDb.StockDb :> es
  , EffInv.InventoryDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  TransactionItem ->
  Eff es TransactionItem
addItem item = do
  saleItem <- requireSaleItem item
  (legacy, sale) <- loadSaleAndLegacy (transactionItemTransactionId item)
  let someState        = fromSaleTransaction sale
      (evt, nextState) = runTxCommand someState (AddItemCmd saleItem)
  guardSaleTxEvent evt
  persistStatusChange legacy nextState
  result <- addTransactionItem item
  case result of
    Right ti -> do
      now <- currentTime
      emit $
        TransactionEvt $
          TransactionItemAdded
            { teTxId      = transactionItemTransactionId item
            , teItem      = ti
            , teTimestamp = now
            }
      createStockPull legacy ti now
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
  , StockDb.StockDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es ()
removeItem itemId = do
  txId <- requireTxId getTxIdByItemId "Item not found" itemId
  (legacy, sale) <- loadSaleAndLegacy txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (RemoveItemCmd itemId)
  guardSaleTxEvent evt
  let mItem =
        foldr
          (\i acc -> if transactionItemId i == itemId then Just i else acc)
          Nothing
          (transactionItems legacy)
  deleteTransactionItem itemId
  now <- currentTime
  case mItem of
    Just item -> do
      let itemSku = transactionItemMenuItemSku item
      emit $
        TransactionEvt $
          TransactionItemRemoved
            { teTxId      = txId
            , teItemId    = itemId
            , teItemSku   = itemSku
            , teQty       = transactionItemQuantity item
            , teTimestamp = now
            }
      pulls <- StockDb.getPullsByTransaction txId
      let itemPulls =
            filter
              ( \pr ->
                  prItemSku pr == itemSku
                    && prStatus pr `notElem` [PullFulfilled, PullCancelled]
              )
              pulls
      StockDb.cancelPullsForItem txId itemSku "Item removed from transaction"
      forM_ itemPulls $ \pr ->
        emit $
          StockEvt $
            PullRequestCancelled
              { sePullId    = prId pr
              , seReason    = "Item removed from transaction"
              , seTimestamp = now
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
  salePayment <- requireSalePayment payment
  (_, sale)   <- loadSaleAndLegacy (paymentTransactionId payment)
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (AddPaymentCmd salePayment)
  guardSaleTxEvent evt
  result <- addPaymentTransaction payment
  now    <- currentTime
  emit $
    TransactionEvt $
      TransactionPaymentAdded
        { teTxId      = paymentTransactionId payment
        , tePayment   = result
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
  txId      <- requireTxId getTxIdByPaymentId "Payment not found" pymtId
  (_, sale) <- loadSaleAndLegacy txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (RemovePaymentCmd pymtId)
  guardSaleTxEvent evt
  deletePaymentTransaction pymtId
  now <- currentTime
  emit $
    TransactionEvt $
      TransactionPaymentRemoved
        { teTxId      = txId
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
  (_, sale) <- loadSaleAndLegacy txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState FinalizeCmd
  guardSaleTxEvent evt
  result <- finalizeTransaction txId
  now    <- currentTime
  emit $
    TransactionEvt $
      TransactionFinalized
        { teTxId      = txId
        , teTx        = result
        , teTimestamp = now
        }
  pure result

voidTx ::
  ( TransactionDb :> es
  , StockDb.StockDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Text ->
  Eff es Transaction
voidTx txId reason = do
  (_, sale) <- loadSaleAndLegacy txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (VoidCmd reason)
  guardSaleTxEvent evt
  pulls  <- StockDb.getPullsByTransaction txId
  result <- voidTransaction txId reason
  now    <- currentTime
  emit $
    TransactionEvt $
      TransactionVoided
        { teTxId      = txId
        , teReason    = reason
        , teActorId   = Sale.saleEmployeeId sale
        , teTimestamp = now
        }
  StockDb.cancelPullsForTransaction txId reason
  forM_ pulls $ \pr ->
    when (prStatus pr `notElem` [PullFulfilled, PullCancelled]) $
      emit $
        StockEvt $
          PullRequestCancelled
            { sePullId    = prId pr
            , seReason    = reason
            , seTimestamp = now
            }
  pure result

-- | Refund a sale.
--
-- Phase 2F: typed conversion result now flows downstream.
--
-- toRefundTransaction produces a Refund.RefundTransaction value, which is
-- passed to writeRefund. The previous "compute then discard" pattern is gone.
-- The IO interpreter for WriteRefund still calls the legacy DBT.refundTransaction
-- under the hood; the SQL hasn't changed yet. What HAS changed is that the
-- typed value is now a first-class participant in the call graph rather than
-- a validation-only side-effect.
--
-- Conversion failures (toRefundTransaction returns Left) surface as 500
-- because they indicate the sale-as-loaded cannot be coherently expressed
-- as a refund, which is data-shape failure rather than user error.
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
  (_, sale)     <- loadSaleAndLegacy txId
  refundId      <- nextUUID
  refundItemIds <- mapM (const nextUUID) (Sale.saleItems sale)
  refundPymtIds <- mapM (const nextUUID) (Sale.salePayments sale)
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (RefundCmd reason refundId)
  guardSaleTxEvent evt
  now <- currentTime
  case toRefundTransaction now refundId refundItemIds refundPymtIds reason sale of
    Left convErr ->
      throwError
        err500
          { errBody =
              LBS.fromStrict . TE.encodeUtf8 $
                "Refund conversion failed: " <> convErr
          }
    Right refundTyped -> do
      result <- writeRefund refundTyped
      emit $
        TransactionEvt $
          TransactionRefunded
            { teTxId      = txId
            , teReason    = reason
            , teActorId   = Sale.saleEmployeeId sale
            , teRefTxId   = refundId
            , teTimestamp = now
            }
      pure result