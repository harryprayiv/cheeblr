{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Service.Transaction (
  createSaleSvc,
  addItem,
  removeItem,
  addPayment,
  removePayment,
  finalizeTx,
  voidTx,
  refundTx,
  refuseWrite,
) where

import Control.Monad (forM_, when)
import qualified Data.ByteString.Lazy as LBS
import Data.List (find)
import Data.Text (Text)
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
  , fromSaleTransaction
  , runTxCommand
  )
import State.StockPullMachine (PullVertex (..))

import Types.Primitives.Quantity (saleQuantityCount)
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale
import Types.Transaction.Conversion
  ( saleItemToLegacy
  , salePaymentToLegacy
  , saleToLegacyTransaction
  , toRefundTransaction
  )
import Types.Events.Domain
import Types.Events
import Types.Inventory (Inventory (..))
import qualified Types.Inventory as TI
import Types.Stock (PullRequest (..))

loadSale ::
  (TransactionDb :> es, Error ServerError :> es) =>
  UUID ->
  Eff es Sale.SaleTransaction
loadSale txId = do
  result <- getSaleById txId
  case result of
    Right sale -> pure sale
    Left TypedNotFound ->
      throwError err404 {errBody = "Transaction not found"}
    Left (TypedDecodeFailed e) ->
      throwError
        err500
          { errBody =
              LBS.fromStrict . TE.encodeUtf8 $
                "Transaction failed typed conversion: " <> e
          }
    Left TypedWrongKind ->
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

failText :: (Error ServerError :> es) => ServerError -> Text -> Eff es a
failText base message =
  throwError base {errBody = LBS.fromStrict (TE.encodeUtf8 message)}

-- | The HTTP answer for a write the database layer refused. This is the
-- only place that maps 'InventoryException' to a status code.
refuseWrite :: (Error ServerError :> es) => InventoryException -> Eff es a
refuseWrite (ItemNotFound missingSku) =
  failText err404 ("Item not found: " <> T.pack (show missingSku))
refuseWrite (InsufficientInventory shortSku requested available) =
  failText err400 $
    "Insufficient inventory for "
      <> T.pack (show shortSku)
      <> ": "
      <> T.pack (show available)
      <> " available, "
      <> T.pack (show requested)
      <> " requested"
refuseWrite (SaleNotOpen _) =
  failText err409 "The sale is no longer open"
refuseWrite (LineRejected message) =
  failText err400 message
refuseWrite (FinalizeRefused problems) =
  failText err409 (T.intercalate "; " problems)

createStockPull ::
  ( StockDb.StockDb :> es
  , EffInv.InventoryDb :> es
  , EventEmitter :> es
  , GenUUID :> es
  ) =>
  Sale.SaleTransaction ->
  Sale.Item ->
  Int ->
  UTCTime ->
  Eff es ()
createStockPull sale item quantityNeeded now = do
  pullId <- nextUUID
  Inventory invVec <- EffInv.getAllMenuItems
  let
    itemSku  = Sale.itemMenuItemSku item
    itemName =
      maybe (T.pack $ show itemSku) TI.name $
        V.find (\m -> TI.sku m == itemSku) invVec
    pr =
      PullRequest
        { prId             = pullId
        , prTransactionId  = Sale.itemTransactionId item
        , prItemSku        = itemSku
        , prItemName       = itemName
        , prQuantityNeeded = quantityNeeded
        , prStatus         = PullPending
        , prCashierId      = Just (Sale.saleEmployeeId sale)
        , prRegisterId     = Just (Sale.saleRegisterId sale)
        , prLocationId     = Sale.saleLocationId sale
        , prCreatedAt      = now
        , prUpdatedAt      = now
        , prFulfilledAt    = Nothing
        }
  prResult <- StockDb.createPullRequest pr
  case prResult of
    Right () -> emit $ StockEvt $ PullRequestCreated {sePull = pr, seTimestamp = now}
    Left _   -> pure ()

createSaleSvc ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  ) =>
  Sale.SaleTransaction ->
  Eff es Sale.SaleTransaction
createSaleSvc sale = do
  result <- createSale sale
  now    <- currentTime
  emit $
    TransactionEvt $
      TransactionCreated
        { teTx        = saleToLegacyTransaction result
        , teTimestamp = now
        }
  pure result

-- | Adds a quantity of one sku to a sale and returns the line as stored.
--
-- The request carries the quantity to add. 'addSaleItem' works out the
-- line's whole quantity from the stored sale and prices it, so this
-- function never computes a quantity from the sale it loaded.
--
-- The state machine check here gives the caller a clear 409 for a sale
-- that is already closed. 'addSaleItem' checks the status again when it
-- writes, and it writes the move from Created to InProgress together with
-- the line, so a refused add changes nothing.
--
-- The events and the stock pull are built from what 'addSaleItem' reports
-- it replaced and stored.
addItem ::
  ( TransactionDb :> es
  , StockDb.StockDb :> es
  , EffInv.InventoryDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  SaleLineAdd ->
  Eff es Sale.Item
addItem change = do
  let txId   = lineAddSaleId change
      sku    = lineAddSku change
      addQty = lineAddQuantity change
  sale <- loadSale txId
  when (addQty <= 0) $
    failText err400 ("Quantity must be greater than zero, got " <> T.pack (show addQty))
  provisional <-
    case lineAddPrice change (lineAddNewItemId change) addQty of
      Right item   -> pure item
      Left message -> failText err400 message
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (AddItemCmd provisional)
  guardSaleTxEvent evt
  result <- addSaleItem change
  case result of
    Left refusal -> refuseWrite refusal
    Right added  -> do
      let addedItem = lineAddedItem added
      now <- currentTime
      forM_ (lineAddedReplaced added) $ \(oldId, oldQty) ->
        emit $
          TransactionEvt $
            TransactionItemRemoved
              { teTxId      = txId
              , teItemId    = oldId
              , teItemSku   = sku
              , teQty       = oldQty
              , teTimestamp = now
              }
      emit $
        TransactionEvt $
          TransactionItemAdded
            { teTxId      = txId
            , teItem      = saleItemToLegacy addedItem
            , teTimestamp = now
            }
      createStockPull sale addedItem addQty now
      pure addedItem

-- | Removes a line from a sale. The state machine check gives an early 409
-- for a sale that is closed. 'deleteSaleItem' checks the status again when
-- it writes, under the sale's row lock, so a line cannot be removed from a
-- sale that was completed in between. No event is emitted and no stock
-- pull is cancelled for a refused removal.
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
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (RemoveItemCmd itemId)
  guardSaleTxEvent evt
  let mItem = find (\i -> Sale.itemId i == itemId) (Sale.saleItems sale)
  outcome <- deleteSaleItem itemId
  case outcome of
    Left refusal -> refuseWrite refusal
    Right ()     -> do
      now <- currentTime
      case mItem of
        Just item -> do
          let itemSku = Sale.itemMenuItemSku item
              itemQty = saleQuantityCount (Sale.itemQuantity item)
          emit $
            TransactionEvt $
              TransactionItemRemoved
                { teTxId      = txId
                , teItemId    = itemId
                , teItemSku   = itemSku
                , teQty       = itemQty
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

-- | Records a payment. The state machine check gives an early 409 for a
-- sale that cannot take payments. 'addSalePayment' checks the status again
-- when it writes, so a payment cannot land on a sale that closed in between.
addPayment ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  Sale.Payment ->
  Eff es Sale.Payment
addPayment payment = do
  sale <- loadSale (Sale.paymentTransactionId payment)
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (AddPaymentCmd payment)
  guardSaleTxEvent evt
  outcome <- addSalePayment payment
  case outcome of
    Left refusal -> refuseWrite refusal
    Right result -> do
      now <- currentTime
      emit $
        TransactionEvt $
          TransactionPaymentAdded
            { teTxId      = Sale.paymentTransactionId payment
            , tePayment   = salePaymentToLegacy result
            , teTimestamp = now
            }
      pure result

-- | Removes a payment. 'deleteSalePayment' checks the sale's status when it
-- writes, so a payment cannot be removed from a sale that closed in between.
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
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (RemovePaymentCmd pymtId)
  guardSaleTxEvent evt
  outcome <- deleteSalePayment pymtId
  case outcome of
    Left refusal -> refuseWrite refusal
    Right ()     -> do
      now <- currentTime
      emit $
        TransactionEvt $
          TransactionPaymentRemoved
            { teTxId      = txId
            , tePaymentId = pymtId
            , teTimestamp = now
            }

-- | Completes a sale. The state machine check gives an early 409 for a sale
-- in the wrong status. Whether the sale has lines and is paid is decided by
-- 'finalizeSale' at the moment of the write, and nowhere else.
finalizeTx ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Eff es Sale.SaleTransaction
finalizeTx txId = do
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState FinalizeCmd
  guardSaleTxEvent evt
  outcome <- finalizeSale txId
  case outcome of
    Left refusal -> refuseWrite refusal
    Right result -> do
      now <- currentTime
      emit $
        TransactionEvt $
          TransactionFinalized
            { teTxId      = txId
            , teTx        = saleToLegacyTransaction result
            , teTimestamp = now
            }
      pure result

-- | Voids a sale. The state machine check gives an early 409 for a sale that
-- cannot be voided. 'voidSale' checks the status again when it writes, under
-- the sale's row lock, so a void cannot land on a sale that was voided or
-- refunded in between. No event is emitted and no stock pull is cancelled
-- for a refused void.
voidTx ::
  ( TransactionDb :> es
  , StockDb.StockDb :> es
  , EventEmitter :> es
  , Clock :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Text ->
  Eff es Sale.SaleTransaction
voidTx txId reason = do
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (VoidCmd reason)
  guardSaleTxEvent evt
  pulls   <- StockDb.getPullsByTransaction txId
  outcome <- voidSale txId reason
  case outcome of
    Left refusal -> refuseWrite refusal
    Right result -> do
      now <- currentTime
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

-- | Refunds a completed sale. The state machine check gives an early 409
-- for a sale that is not completed. 'writeRefund' checks again when it
-- writes, under the original sale's row lock, and also refuses a sale that
-- was already refunded, so one sale cannot be refunded twice. No event is
-- emitted for a refused refund.
refundTx ::
  ( TransactionDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  UUID ->
  Text ->
  Eff es Refund.RefundTransaction
refundTx txId reason = do
  sale          <- loadSale txId
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
      outcome <- writeRefund refundTyped
      case outcome of
        Left (SaleNotOpen _) ->
          failText err409 "The sale cannot be refunded: it is not completed or was already refunded"
        Left refusal -> refuseWrite refusal
        Right result -> do
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