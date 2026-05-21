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
  , SomeSaleTxState
  , fromSaleTransaction
  , runTxCommand
  , someTxStatus
  )
import State.StockPullMachine (PullVertex (..))
-- import Types.Primitives.Money (saleMoneyCents)
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
-- import Types.Transaction

-- | Load only the typed Sale view of a transaction.
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

persistStatusChange ::
  (TransactionDb :> es) =>
  Sale.SaleTransaction ->
  SomeSaleTxState ->
  Eff es ()
persistStatusChange sale nextState = do
  let nextStatus = someTxStatus nextState
  when (Sale.saleStatus sale /= nextStatus) $
    updateSaleStatus (Sale.saleId sale) nextStatus

-- | Best-effort creation of a stock pull for an item just added to a
-- sale.
createStockPull ::
  ( StockDb.StockDb :> es
  , EffInv.InventoryDb :> es
  , EventEmitter :> es
  , GenUUID :> es
  ) =>
  Sale.SaleTransaction ->
  Sale.Item ->
  UTCTime ->
  Eff es ()
createStockPull sale item now = do
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
        , prQuantityNeeded = saleQuantityCount (Sale.itemQuantity item)
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

addItem ::
  ( TransactionDb :> es
  , StockDb.StockDb :> es
  , EffInv.InventoryDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  Sale.Item ->
  Eff es Sale.Item
addItem item = do
  sale <- loadSale (Sale.itemTransactionId item)
  let someState        = fromSaleTransaction sale
      (evt, nextState) = runTxCommand someState (AddItemCmd item)
  guardSaleTxEvent evt
  persistStatusChange sale nextState
  result <- addSaleItem item
  case result of
    Right addedItem -> do
      now <- currentTime
      emit $
        TransactionEvt $
          TransactionItemAdded
            { teTxId      = Sale.itemTransactionId item
            , teItem      = saleItemToLegacy addedItem
            , teTimestamp = now
            }
      createStockPull sale addedItem now
      pure addedItem
    Left (ItemNotFound sku) ->
      throwError
        err404
          { errBody =
              LBS.fromStrict . TE.encodeUtf8 $
                "Item not found: " <> T.pack (show sku)
          }
    Left (InsufficientInventory sku requested available) ->
      throwError
        err400
          { errBody =
              LBS.fromStrict . TE.encodeUtf8 $
                "Insufficient inventory for "
                  <> T.pack (show sku)
                  <> ": "
                  <> T.pack (show available)
                  <> " available, "
                  <> T.pack (show requested)
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
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (RemoveItemCmd itemId)
  guardSaleTxEvent evt
  let mItem = find (\i -> Sale.itemId i == itemId) (Sale.saleItems sale)
  deleteSaleItem itemId
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
  result <- addSalePayment payment
  now    <- currentTime
  emit $
    TransactionEvt $
      TransactionPaymentAdded
        { teTxId      = Sale.paymentTransactionId payment
        , tePayment   = salePaymentToLegacy result
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
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (RemovePaymentCmd pymtId)
  guardSaleTxEvent evt
  deleteSalePayment pymtId
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
  Eff es Sale.SaleTransaction
finalizeTx txId = do
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState FinalizeCmd
  guardSaleTxEvent evt
  result <- finalizeSale txId
  now    <- currentTime
  emit $
    TransactionEvt $
      TransactionFinalized
        { teTxId      = txId
        , teTx        = saleToLegacyTransaction result
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
  Eff es Sale.SaleTransaction
voidTx txId reason = do
  sale <- loadSale txId
  let someState = fromSaleTransaction sale
      (evt, _)  = runTxCommand someState (VoidCmd reason)
  guardSaleTxEvent evt
  pulls  <- StockDb.getPullsByTransaction txId
  result <- voidSale txId reason
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