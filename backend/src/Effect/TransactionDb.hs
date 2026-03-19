{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.TransactionDb
  ( TransactionDb (..)
  , getAllTransactions
  , getTransactionById
  , createTransaction
  , updateTransaction
  , voidTransaction
  , refundTransaction
  , clearTransaction
  , finalizeTransaction
  , addTransactionItem
  , deleteTransactionItem
  , addPaymentTransaction
  , deletePaymentTransaction
  , getTxIdByItemId
  , getTxIdByPaymentId
  , getInventoryAvailability
  , createReservation
  , releaseReservation
  , runTransactionDbIO
  , ReservationEntry (..)
  , TxStore (..)
  , emptyTxStore
  , runTransactionDbPure
  ) where

import Control.Exception (try)
import Data.List (find)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local

import DB.Database (DBPool)
import DB.Transaction (InventoryException (..))
import qualified DB.Transaction as DBT
import Effect.Clock
import Effect.GenUUID
import Types.Transaction

data TransactionDb :: Effect where
  GetAllTransactions       :: TransactionDb m [Transaction]
  GetTransactionById       :: UUID -> TransactionDb m (Maybe Transaction)
  CreateTransaction        :: Transaction -> TransactionDb m Transaction
  UpdateTransaction        :: UUID -> Transaction -> TransactionDb m Transaction
  VoidTransaction          :: UUID -> Text -> TransactionDb m Transaction
  RefundTransaction        :: UUID -> Text -> TransactionDb m Transaction
  ClearTransaction         :: UUID -> TransactionDb m ()
  FinalizeTransaction      :: UUID -> TransactionDb m Transaction
  AddTransactionItem       :: TransactionItem -> TransactionDb m (Either InventoryException TransactionItem)
  DeleteTransactionItem    :: UUID -> TransactionDb m ()
  AddPayment               :: PaymentTransaction -> TransactionDb m PaymentTransaction
  DeletePayment            :: UUID -> TransactionDb m ()
  GetTxIdByItemId          :: UUID -> TransactionDb m (Maybe UUID)
  GetTxIdByPaymentId       :: UUID -> TransactionDb m (Maybe UUID)
  GetInventoryAvailability :: UUID -> TransactionDb m (Maybe (Int, Int))
  CreateReservation        :: UUID -> UUID -> UUID -> Int -> UTCTime -> TransactionDb m ()
  ReleaseReservation       :: UUID -> TransactionDb m Bool

type instance DispatchOf TransactionDb = Dynamic

getAllTransactions :: TransactionDb :> es => Eff es [Transaction]
getAllTransactions = send GetAllTransactions

getTransactionById :: TransactionDb :> es => UUID -> Eff es (Maybe Transaction)
getTransactionById = send . GetTransactionById

createTransaction :: TransactionDb :> es => Transaction -> Eff es Transaction
createTransaction = send . CreateTransaction

updateTransaction :: TransactionDb :> es => UUID -> Transaction -> Eff es Transaction
updateTransaction txId tx = send (UpdateTransaction txId tx)

voidTransaction :: TransactionDb :> es => UUID -> Text -> Eff es Transaction
voidTransaction txId reason = send (VoidTransaction txId reason)

refundTransaction :: TransactionDb :> es => UUID -> Text -> Eff es Transaction
refundTransaction txId reason = send (RefundTransaction txId reason)

clearTransaction :: TransactionDb :> es => UUID -> Eff es ()
clearTransaction = send . ClearTransaction

finalizeTransaction :: TransactionDb :> es => UUID -> Eff es Transaction
finalizeTransaction = send . FinalizeTransaction

addTransactionItem :: TransactionDb :> es => TransactionItem -> Eff es (Either InventoryException TransactionItem)
addTransactionItem = send . AddTransactionItem

deleteTransactionItem :: TransactionDb :> es => UUID -> Eff es ()
deleteTransactionItem = send . DeleteTransactionItem

addPaymentTransaction :: TransactionDb :> es => PaymentTransaction -> Eff es PaymentTransaction
addPaymentTransaction = send . AddPayment

deletePaymentTransaction :: TransactionDb :> es => UUID -> Eff es ()
deletePaymentTransaction = send . DeletePayment

getTxIdByItemId :: TransactionDb :> es => UUID -> Eff es (Maybe UUID)
getTxIdByItemId = send . GetTxIdByItemId

getTxIdByPaymentId :: TransactionDb :> es => UUID -> Eff es (Maybe UUID)
getTxIdByPaymentId = send . GetTxIdByPaymentId

getInventoryAvailability :: TransactionDb :> es => UUID -> Eff es (Maybe (Int, Int))
getInventoryAvailability = send . GetInventoryAvailability

createReservation :: TransactionDb :> es => UUID -> UUID -> UUID -> Int -> UTCTime -> Eff es ()
createReservation resId itemSku txId qty now =
  send (CreateReservation resId itemSku txId qty now)

releaseReservation :: TransactionDb :> es => UUID -> Eff es Bool
releaseReservation = send . ReleaseReservation

-- IO interpreter

runTransactionDbIO :: IOE :> es => DBPool -> Eff (TransactionDb : es) a -> Eff es a
runTransactionDbIO pool = interpret $ \_ -> \case
  GetAllTransactions          -> liftIO $ DBT.getAllTransactions pool
  GetTransactionById u        -> liftIO $ DBT.getTransactionById pool u
  CreateTransaction tx        -> liftIO $ DBT.createTransaction pool tx
  UpdateTransaction u tx      -> liftIO $ DBT.updateTransaction pool u tx
  VoidTransaction u r         -> liftIO $ DBT.voidTransaction pool u r
  RefundTransaction u r       -> liftIO $ DBT.refundTransaction pool u r
  ClearTransaction u          -> liftIO $ DBT.clearTransaction pool u
  FinalizeTransaction u       -> liftIO $ DBT.finalizeTransaction pool u
  AddTransactionItem ti       -> liftIO $ try @InventoryException $ DBT.addTransactionItem pool ti
  DeleteTransactionItem u     -> liftIO $ DBT.deleteTransactionItem pool u
  AddPayment p                -> liftIO $ DBT.addPaymentTransaction pool p
  DeletePayment u             -> liftIO $ DBT.deletePaymentTransaction pool u
  GetTxIdByItemId u           -> liftIO $ DBT.getTransactionIdByItemId pool u
  GetTxIdByPaymentId u        -> liftIO $ DBT.getTransactionIdByPaymentId pool u
  GetInventoryAvailability u  -> liftIO $ DBT.getInventoryAvailability pool u
  CreateReservation a b c d e -> liftIO $ DBT.createInventoryReservation pool a b c d e
  ReleaseReservation u        -> liftIO $ DBT.releaseInventoryReservation pool u

-- Pure in-memory interpreter

data ReservationEntry = ReservationEntry
  { reSku    :: UUID
  , reTxId   :: UUID
  , reQty    :: Int
  , reStatus :: Text
  } deriving (Show, Eq)

data TxStore = TxStore
  { tsTxs          :: Map UUID Transaction
  , tsItemToTx     :: Map UUID UUID
  , tsPaymentToTx  :: Map UUID UUID
  , tsReservations :: Map UUID ReservationEntry
  , tsInventory    :: Map UUID Int
  } deriving (Show, Eq)

emptyTxStore :: TxStore
emptyTxStore = TxStore Map.empty Map.empty Map.empty Map.empty Map.empty

activeReservedQty :: UUID -> Map UUID ReservationEntry -> Int
activeReservedQty sku rs =
  sum [ reQty r | r <- Map.elems rs, reSku r == sku, reStatus r == "Reserved" ]

runTransactionDbPure
  :: (GenUUID :> es, Clock :> es)
  => TxStore
  -> Eff (TransactionDb : es) a
  -> Eff es (a, TxStore)
runTransactionDbPure initial = reinterpret (runState initial) $ \_ -> \case
  GetAllTransactions ->
    gets @TxStore (Map.elems . tsTxs)

  GetTransactionById txId ->
    gets @TxStore (Map.lookup txId . tsTxs)

  CreateTransaction tx -> do
    modify @TxStore $ \st -> st
      { tsTxs = Map.insert (transactionId tx) tx (tsTxs st)
      , tsItemToTx =
          foldl (\m i -> Map.insert (transactionItemId i) (transactionId tx) m)
                (tsItemToTx st) (transactionItems tx)
      , tsPaymentToTx =
          foldl (\m p -> Map.insert (paymentId p) (transactionId tx) m)
                (tsPaymentToTx st) (transactionPayments tx)
      }
    pure tx

  UpdateTransaction txId tx -> do
    modify @TxStore $ \st -> st { tsTxs = Map.insert txId tx (tsTxs st) }
    pure tx

  VoidTransaction txId reason -> do
    st <- get @TxStore
    case Map.lookup txId (tsTxs st) of
      Nothing -> error $ "VoidTransaction: not found: " <> show txId
      Just tx -> do
        let voided = tx
              { transactionStatus     = Voided
              , transactionIsVoided   = True
              , transactionVoidReason = Just reason
              }
        put @TxStore st { tsTxs = Map.insert txId voided (tsTxs st) }
        pure voided

  RefundTransaction txId reason -> do
    st <- get @TxStore
    case Map.lookup txId (tsTxs st) of
      Nothing -> error $ "RefundTransaction: not found: " <> show txId
      Just orig -> do
        refundId <- nextUUID
        now      <- currentTime
        let refund = orig
              { transactionId                     = refundId
              , transactionStatus                 = Completed
              , transactionCreated                = now
              , transactionCompleted              = Just now
              , transactionSubtotal               = negate (transactionSubtotal orig)
              , transactionDiscountTotal          = negate (transactionDiscountTotal orig)
              , transactionTaxTotal               = negate (transactionTaxTotal orig)
              , transactionTotal                  = negate (transactionTotal orig)
              , transactionType                   = Return
              , transactionIsVoided               = False
              , transactionVoidReason             = Nothing
              , transactionIsRefunded             = False
              , transactionRefundReason           = Nothing
              , transactionReferenceTransactionId = Just txId
              , transactionNotes                  = Just $ "Refund: " <> T.pack (show txId)
              , transactionItems                  = []
              , transactionPayments               = []
              }
            origUpdated = orig
              { transactionIsRefunded   = True
              , transactionRefundReason = Just reason
              }
        put @TxStore st
          { tsTxs = Map.insert refundId refund
                  . Map.insert txId origUpdated
                  $ tsTxs st
          }
        pure refund

  ClearTransaction txId ->
    modify @TxStore $ \st -> st
      { tsTxs = Map.adjust (\tx -> tx
          { transactionStatus        = Created
          , transactionSubtotal      = 0
          , transactionDiscountTotal = 0
          , transactionTaxTotal      = 0
          , transactionTotal         = 0
          , transactionItems         = []
          , transactionPayments      = []
          }) txId (tsTxs st)
      , tsReservations = Map.map (\r ->
          if reTxId r == txId && reStatus r == "Reserved"
            then r { reStatus = "Released" }
            else r
          ) (tsReservations st)
      }

  FinalizeTransaction txId -> do
    st <- get @TxStore
    now <- currentTime
    case Map.lookup txId (tsTxs st) of
      Nothing -> error $ "FinalizeTransaction: not found: " <> show txId
      Just tx -> do
        let active = [ (k, r) | (k, r) <- Map.toList (tsReservations st)
                               , reTxId r == txId, reStatus r == "Reserved" ]
        let newReservations = foldl
              (\m (k, r) -> Map.insert k r { reStatus = "Completed" } m)
              (tsReservations st) active
        let newInventory = foldl
              (\m (_, r) -> Map.adjust (subtract (reQty r)) (reSku r) m)
              (tsInventory st) active
        let finalized = tx { transactionStatus = Completed, transactionCompleted = Just now }
        put @TxStore st
          { tsTxs          = Map.insert txId finalized (tsTxs st)
          , tsReservations = newReservations
          , tsInventory    = newInventory
          }
        pure finalized

  AddTransactionItem ti -> do
    st <- get @TxStore
    let sku = transactionItemMenuItemSku ti
        qty = transactionItemQuantity ti
    if not (Map.member sku (tsInventory st))
      then pure $ Left (ItemNotFound sku)
      else do
        let total     = fromMaybe 0 (Map.lookup sku (tsInventory st))
            reserved  = activeReservedQty sku (tsReservations st)
            available = total - reserved
        if available < qty
          then pure $ Left (InsufficientInventory sku qty available)
          else do
            resId <- nextUUID
            let txId  = transactionItemTransactionId ti
                newRes = ReservationEntry sku txId qty "Reserved"
            modify @TxStore $ \s -> s
              { tsItemToTx     = Map.insert (transactionItemId ti) txId (tsItemToTx s)
              , tsReservations = Map.insert resId newRes (tsReservations s)
              , tsTxs          = Map.adjust
                  (\tx -> tx { transactionItems = ti : transactionItems tx }) txId (tsTxs s)
              }
            pure $ Right ti

  DeleteTransactionItem itemId -> do
    st <- get @TxStore
    case Map.lookup itemId (tsItemToTx st) of
      Nothing   -> pure ()
      Just txId -> do
        let mItem = Map.lookup txId (tsTxs st) >>= \tx ->
              find (\i -> transactionItemId i == itemId) (transactionItems tx)
        case mItem of
          Nothing   -> pure ()
          Just item -> do
            let sku = transactionItemMenuItemSku item
            modify @TxStore $ \s -> s
              { tsItemToTx     = Map.delete itemId (tsItemToTx s)
              , tsReservations = Map.map (\r ->
                  if reSku r == sku && reTxId r == txId && reStatus r == "Reserved"
                    then r { reStatus = "Released" }
                    else r
                  ) (tsReservations s)
              , tsTxs = Map.adjust
                  (\tx -> tx { transactionItems =
                      filter (\i -> transactionItemId i /= itemId) (transactionItems tx) })
                  txId (tsTxs s)
              }

  AddPayment p -> do
    let txId = paymentTransactionId p
    modify @TxStore $ \st -> st
      { tsPaymentToTx = Map.insert (paymentId p) txId (tsPaymentToTx st)
      , tsTxs         = Map.adjust
          (\tx -> tx { transactionPayments = p : transactionPayments tx }) txId (tsTxs st)
      }
    pure p

  DeletePayment pymtId -> do
    st <- get @TxStore
    case Map.lookup pymtId (tsPaymentToTx st) of
      Nothing   -> pure ()
      Just txId ->
        modify @TxStore $ \s -> s
          { tsPaymentToTx = Map.delete pymtId (tsPaymentToTx s)
          , tsTxs         = Map.adjust
              (\tx -> tx { transactionPayments =
                  filter (\p -> paymentId p /= pymtId) (transactionPayments tx) })
              txId (tsTxs s)
          }

  GetTxIdByItemId itemId ->
    gets @TxStore (Map.lookup itemId . tsItemToTx)

  GetTxIdByPaymentId pymtId ->
    gets @TxStore (Map.lookup pymtId . tsPaymentToTx)

  GetInventoryAvailability sku -> do
    st <- get @TxStore
    case Map.lookup sku (tsInventory st) of
      Nothing    -> pure Nothing
      Just total -> pure $ Just (total, activeReservedQty sku (tsReservations st))

  CreateReservation resId itemSku txId qty _now ->
    modify @TxStore $ \st -> st
      { tsReservations = Map.insert resId (ReservationEntry itemSku txId qty "Reserved")
                                          (tsReservations st) }

  ReleaseReservation resId -> do
    st <- get @TxStore
    case Map.lookup resId (tsReservations st) of
      Nothing -> pure False
      Just r  ->
        if reStatus r == "Reserved"
          then do
            put @TxStore st
              { tsReservations = Map.insert resId r { reStatus = "Released" } (tsReservations st) }
            pure True
          else pure False