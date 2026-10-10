{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.TransactionDb (
  TransactionDb (..),

  TypedLoadError (..),
  getSaleById,
  getRefundById,
  getAllSales,
  getAllRefunds,
  getSalesByLocation,
  getRefundsByLocation,

  SaleLineAdd (..),
  SaleLineAdded (..),
  createSale,
  updateSaleStatus,
  voidSale,
  writeRefund,
  clearSale,
  finalizeSale,
  addSaleItem,
  deleteSaleItem,
  addSalePayment,
  deleteSalePayment,

  getTxIdByItemId,
  getTxIdByPaymentId,

  getInventoryAvailability,
  createReservation,
  releaseReservation,
  getAllActiveReservations,

  runTransactionDbIO,
  ReservationEntry (..),
  TxStore (..),
  emptyTxStore,
  runTransactionDbPure,
) where

import Control.Exception (try)
import Control.Monad (when)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Text as T
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import GHC.Generics (Generic)

import DB.Database (DBPool)
import DB.Transaction (InventoryException (..))
import qualified DB.Transaction as DBT
import qualified DB.Transaction.Refund as DBTRefund
import qualified DB.Transaction.Typed as DBTTyped
import qualified DB.Reservation as DBRes
import Domain.SaleRules (finalizeProblems)
import Domain.StockPolicy (RestockPolicy (..), StockPolicy (..))
import Effect.Clock
import Effect.GenUUID
import Types.Location (LocationId)
import Types.Transaction
import Types.Transaction.Conversion
  ( fromLegacyTransaction
  , saleItemFromLegacy
  , saleItemToLegacy
  , salePaymentFromLegacy
  , salePaymentToLegacy
  , saleToLegacyTransaction, refundToLegacyTransaction
  )
import qualified Types.Transaction.Refund as Refund
import qualified Types.Transaction.Sale as Sale

data TypedLoadError
  = TypedNotFound
  | TypedDecodeFailed Text
  | TypedWrongKind
  deriving stock (Show, Eq, Generic)

-- | A request to add a quantity of one sku to a sale.
--
-- It carries the quantity to add, never the line's whole quantity. The
-- interpreter reads the sale's current line for the sku, adds
-- 'lineAddQuantity' to it, and calls 'lineAddPrice' with the line id and
-- the whole quantity to get the line to store. The Postgres interpreter
-- does that under a row lock, so two adds of the same sku to the same sale
-- cannot overwrite each other.
--
-- 'lineAddNewItemId' is the id the line takes when the sku is new to the
-- sale. A line that already exists keeps its id.
data SaleLineAdd = SaleLineAdd
  { lineAddSaleId    :: UUID
  , lineAddSku       :: UUID
  , lineAddQuantity  :: Int
  , lineAddNewItemId :: UUID
  , lineAddPrice     :: UUID -> Int -> Either Text Sale.Item
  }

-- | The line as stored, and the id and quantity of each line it replaced.
data SaleLineAdded = SaleLineAdded
  { lineAddedItem     :: Sale.Item
  , lineAddedReplaced :: [(UUID, Int)]
  }

-- Every operation that writes to an open sale returns 'Either
-- InventoryException'. The interpreter checks the sale's status at the
-- moment of the write and refuses with 'SaleNotOpen' when the sale has
-- closed. 'DeleteSaleItem' is refused the same way unless the sale is in
-- progress. 'VoidSale' and 'ClearSale' are refused the same way when the sale
-- is in a status that cannot be voided or cleared, and 'WriteRefund' when
-- the original sale is not completed or was already refunded.
-- 'FinalizeSale' also decides, at the moment of the write, whether the sale
-- has lines and is paid.
--
-- 'VoidSale' and 'WriteRefund' of a completed sale put its quantities back
-- in stock or leave stock alone, according to the 'StockPolicy' the
-- interpreter was given. The operations themselves carry no policy.
data TransactionDb :: Effect where

  GetSaleById              :: UUID -> TransactionDb m (Either TypedLoadError Sale.SaleTransaction)
  GetRefundById            :: UUID -> TransactionDb m (Either TypedLoadError Refund.RefundTransaction)
  GetAllSales              :: TransactionDb m [Sale.SaleTransaction]
  GetAllRefunds            :: TransactionDb m [Refund.RefundTransaction]
  GetSalesByLocation       :: LocationId -> TransactionDb m [Sale.SaleTransaction]
  GetRefundsByLocation     :: LocationId -> TransactionDb m [Refund.RefundTransaction]

  CreateSale               :: Sale.SaleTransaction -> TransactionDb m Sale.SaleTransaction
  UpdateSaleStatus         :: UUID -> TransactionStatus -> TransactionDb m ()
  VoidSale                 :: UUID -> Text -> TransactionDb m (Either InventoryException Sale.SaleTransaction)
  WriteRefund              :: Refund.RefundTransaction -> TransactionDb m (Either InventoryException Refund.RefundTransaction)
  ClearSale                :: UUID -> TransactionDb m (Either InventoryException ())
  FinalizeSale             :: UUID -> TransactionDb m (Either InventoryException Sale.SaleTransaction)
  AddSaleItem              :: SaleLineAdd -> TransactionDb m (Either InventoryException SaleLineAdded)
  DeleteSaleItem           :: UUID -> TransactionDb m (Either InventoryException ())
  AddSalePayment           :: Sale.Payment -> TransactionDb m (Either InventoryException Sale.Payment)
  DeleteSalePayment        :: UUID -> TransactionDb m (Either InventoryException ())

  GetTxIdByItemId          :: UUID -> TransactionDb m (Maybe UUID)
  GetTxIdByPaymentId       :: UUID -> TransactionDb m (Maybe UUID)

  GetInventoryAvailability :: UUID -> TransactionDb m (Maybe (Int, Int))
  CreateReservation        :: UUID -> UUID -> UUID -> Int -> UTCTime -> TransactionDb m ()
  ReleaseReservation       :: UUID -> TransactionDb m Bool
  GetAllActiveReservations :: TransactionDb m [InventoryReservation]

type instance DispatchOf TransactionDb = Dynamic

getSaleById   :: (TransactionDb :> es) => UUID -> Eff es (Either TypedLoadError Sale.SaleTransaction)
getSaleById   = send . GetSaleById

getRefundById :: (TransactionDb :> es) => UUID -> Eff es (Either TypedLoadError Refund.RefundTransaction)
getRefundById = send . GetRefundById

getAllSales   :: (TransactionDb :> es) => Eff es [Sale.SaleTransaction]
getAllSales   = send GetAllSales

getAllRefunds :: (TransactionDb :> es) => Eff es [Refund.RefundTransaction]
getAllRefunds = send GetAllRefunds

getSalesByLocation   :: (TransactionDb :> es) => LocationId -> Eff es [Sale.SaleTransaction]
getSalesByLocation   = send . GetSalesByLocation

getRefundsByLocation :: (TransactionDb :> es) => LocationId -> Eff es [Refund.RefundTransaction]
getRefundsByLocation = send . GetRefundsByLocation

createSale :: (TransactionDb :> es) => Sale.SaleTransaction -> Eff es Sale.SaleTransaction
createSale = send . CreateSale

updateSaleStatus :: (TransactionDb :> es) => UUID -> TransactionStatus -> Eff es ()
updateSaleStatus txId s = send (UpdateSaleStatus txId s)

voidSale ::
  (TransactionDb :> es) =>
  UUID ->
  Text ->
  Eff es (Either InventoryException Sale.SaleTransaction)
voidSale txId reason = send (VoidSale txId reason)

writeRefund ::
  (TransactionDb :> es) =>
  Refund.RefundTransaction ->
  Eff es (Either InventoryException Refund.RefundTransaction)
writeRefund = send . WriteRefund

clearSale :: (TransactionDb :> es) => UUID -> Eff es (Either InventoryException ())
clearSale = send . ClearSale

finalizeSale ::
  (TransactionDb :> es) =>
  UUID ->
  Eff es (Either InventoryException Sale.SaleTransaction)
finalizeSale = send . FinalizeSale

addSaleItem ::
  (TransactionDb :> es) =>
  SaleLineAdd ->
  Eff es (Either InventoryException SaleLineAdded)
addSaleItem = send . AddSaleItem

deleteSaleItem ::
  (TransactionDb :> es) =>
  UUID ->
  Eff es (Either InventoryException ())
deleteSaleItem = send . DeleteSaleItem

addSalePayment ::
  (TransactionDb :> es) =>
  Sale.Payment ->
  Eff es (Either InventoryException Sale.Payment)
addSalePayment = send . AddSalePayment

deleteSalePayment ::
  (TransactionDb :> es) =>
  UUID ->
  Eff es (Either InventoryException ())
deleteSalePayment = send . DeleteSalePayment

getTxIdByItemId :: (TransactionDb :> es) => UUID -> Eff es (Maybe UUID)
getTxIdByItemId = send . GetTxIdByItemId

getTxIdByPaymentId :: (TransactionDb :> es) => UUID -> Eff es (Maybe UUID)
getTxIdByPaymentId = send . GetTxIdByPaymentId

getInventoryAvailability :: (TransactionDb :> es) => UUID -> Eff es (Maybe (Int, Int))
getInventoryAvailability = send . GetInventoryAvailability

createReservation ::
  (TransactionDb :> es) =>
  UUID -> UUID -> UUID -> Int -> UTCTime -> Eff es ()
createReservation a b c d e = send (CreateReservation a b c d e)

releaseReservation :: (TransactionDb :> es) => UUID -> Eff es Bool
releaseReservation = send . ReleaseReservation

getAllActiveReservations :: (TransactionDb :> es) => Eff es [InventoryReservation]
getAllActiveReservations = send GetAllActiveReservations

expectSaleTx :: Transaction -> Sale.SaleTransaction
expectSaleTx tx = case fromLegacyTransaction tx of
  Right (Left s)  -> s
  Right (Right _) ->
    error $
      "Effect.TransactionDb.expectSaleTx: expected sale, got refund (txId "
        <> show (transactionId tx) <> ")"
  Left e ->
    error $
      "Effect.TransactionDb.expectSaleTx: conversion failed for txId "
        <> show (transactionId tx) <> ": " <> T.unpack e

expectRefundTx :: Transaction -> Refund.RefundTransaction
expectRefundTx tx = case fromLegacyTransaction tx of
  Right (Right r) -> r
  Right (Left _)  ->
    error $
      "Effect.TransactionDb.expectRefundTx: expected refund, got sale (txId "
        <> show (transactionId tx) <> ")"
  Left e ->
    error $
      "Effect.TransactionDb.expectRefundTx: conversion failed for txId "
        <> show (transactionId tx) <> ": " <> T.unpack e

expectSaleItem :: TransactionItem -> Sale.Item
expectSaleItem ti = case saleItemFromLegacy ti of
  Right s -> s
  Left e ->
    error $
      "Effect.TransactionDb.expectSaleItem: conversion failed for itemId "
        <> show (transactionItemId ti) <> ": " <> T.unpack e

expectSalePayment :: PaymentTransaction -> Sale.Payment
expectSalePayment p = case salePaymentFromLegacy p of
  Right s -> s
  Left e ->
    error $
      "Effect.TransactionDb.expectSalePayment: conversion failed for paymentId "
        <> show (paymentId p) <> ": " <> T.unpack e

narrowToSale ::
  Maybe (Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)) ->
  Either TypedLoadError Sale.SaleTransaction
narrowToSale Nothing                       = Left TypedNotFound
narrowToSale (Just (Left e))               = Left (TypedDecodeFailed e)
narrowToSale (Just (Right (Left s)))       = Right s
narrowToSale (Just (Right (Right _)))      = Left TypedWrongKind

narrowToRefund ::
  Maybe (Either Text (Either Sale.SaleTransaction Refund.RefundTransaction)) ->
  Either TypedLoadError Refund.RefundTransaction
narrowToRefund Nothing                      = Left TypedNotFound
narrowToRefund (Just (Left e))              = Left (TypedDecodeFailed e)
narrowToRefund (Just (Right (Left _)))      = Left TypedWrongKind
narrowToRefund (Just (Right (Right r)))     = Right r

-- | The Postgres interpreter. The 'StockPolicy' comes from configuration
-- and decides what a void and a refund of a completed sale do to stock.
runTransactionDbIO ::
  (IOE :> es) =>
  StockPolicy ->
  DBPool ->
  Eff (TransactionDb : es) a ->
  Eff es a
runTransactionDbIO stockPolicy pool = interpret $ \_ -> \case

  GetSaleById uuid -> liftIO $ do
    r <- DBTTyped.getTransactionByIdTyped pool uuid
    pure (narrowToSale r)

  GetRefundById uuid -> liftIO $ do
    r <- DBTTyped.getTransactionByIdTyped pool uuid
    pure (narrowToRefund r)

  GetAllSales -> liftIO $ do
    results <- DBTTyped.getAllTransactionsTyped pool

    pure [s | Right (Left s) <- results]

  GetAllRefunds -> liftIO $ do
    results <- DBTTyped.getAllTransactionsTyped pool
    pure [r | Right (Right r) <- results]

  GetSalesByLocation locId -> liftIO $ do
    results <- DBTTyped.getTransactionsByLocationTyped pool locId
    pure [s | Right (Left s) <- results]

  GetRefundsByLocation locId -> liftIO $ do
    results <- DBTTyped.getTransactionsByLocationTyped pool locId
    pure [r | Right (Right r) <- results]

  CreateSale sale -> liftIO $ do
    let legacyTx = saleToLegacyTransaction sale
    result <- DBT.createTransaction pool legacyTx
    pure (expectSaleTx result)

  UpdateSaleStatus txId status -> liftIO $
    DBT.updateTransactionStatus pool txId status

  VoidSale txId reason -> liftIO $ do
    res <- try @InventoryException $ DBT.voidTransaction pool (restockOnVoid stockPolicy) txId reason
    pure (fmap expectSaleTx res)

  WriteRefund refund -> liftIO $ do
    res <- try @InventoryException $ DBTRefund.writeTypedRefund pool (restockOnRefund stockPolicy) refund
    pure (fmap expectRefundTx res)

  ClearSale txId -> liftIO $
    try @InventoryException $ DBT.clearTransaction pool txId

  FinalizeSale txId -> liftIO $ do
    res <- try @InventoryException $ DBT.finalizeTransaction pool txId
    pure (fmap expectSaleTx res)

  AddSaleItem change -> liftIO $ do
    res <-
      try @InventoryException $
        DBT.addTransactionItem
          pool
          (lineAddSaleId change)
          (lineAddSku change)
          (lineAddQuantity change)
          (lineAddNewItemId change)
          (\lineId qty -> saleItemToLegacy <$> lineAddPrice change lineId qty)
    pure $ case res of
      Left e      -> Left e
      Right added ->
        Right
          SaleLineAdded
            { lineAddedItem     = expectSaleItem (DBT.addedLineItem added)
            , lineAddedReplaced = DBT.addedLineReplaced added
            }

  DeleteSaleItem itemId -> liftIO $
    try @InventoryException $ DBT.deleteTransactionItem pool itemId

  AddSalePayment payment -> liftIO $ do
    let legacyPayment = salePaymentToLegacy payment
    res <- try @InventoryException $ DBT.addPaymentTransaction pool legacyPayment
    pure (fmap expectSalePayment res)

  DeleteSalePayment pymtId -> liftIO $
    try @InventoryException $ DBT.deletePaymentTransaction pool pymtId

  GetTxIdByItemId u -> liftIO $ DBT.getTransactionIdByItemId pool u
  GetTxIdByPaymentId u -> liftIO $ DBT.getTransactionIdByPaymentId pool u
  GetInventoryAvailability u -> liftIO $ DBT.getInventoryAvailability pool u
  CreateReservation a b c d e -> liftIO $ DBRes.createInventoryReservation pool a b c d e
  ReleaseReservation u -> liftIO $ DBRes.releaseInventoryReservation pool u
  GetAllActiveReservations -> liftIO $ DBRes.getAllActiveReservations pool

data ReservationEntry = ReservationEntry
  { reSku    :: UUID
  , reTxId   :: UUID
  , reQty    :: Int
  , reStatus :: Text
  }
  deriving (Show, Eq)

-- | The in-memory store. 'tsStockPolicy' says what a void and a refund of a
-- completed sale do to 'tsInventory'. It takes the place of the
-- configuration the Postgres interpreter is given.
data TxStore = TxStore
  { tsTxs          :: Map UUID Transaction
  , tsItemToTx     :: Map UUID UUID
  , tsPaymentToTx  :: Map UUID UUID
  , tsReservations :: Map UUID ReservationEntry
  , tsInventory    :: Map UUID Int
  , tsStockPolicy  :: StockPolicy
  }
  deriving (Show, Eq)

-- | A store with nothing in it. Its stock policy is 'DoNotRestock' for both
-- void and refund. That value is a fixture for tests, not a default of the
-- running backend, which reads its policy from configuration. A test of
-- restocking sets 'tsStockPolicy' itself.
emptyTxStore :: TxStore
emptyTxStore =
  TxStore
    { tsTxs          = Map.empty
    , tsItemToTx     = Map.empty
    , tsPaymentToTx  = Map.empty
    , tsReservations = Map.empty
    , tsInventory    = Map.empty
    , tsStockPolicy  =
        StockPolicy
          { restockOnVoid   = DoNotRestock
          , restockOnRefund = DoNotRestock
          }
    }

activeReservedQty :: UUID -> Map UUID ReservationEntry -> Int
activeReservedQty sku rs =
  sum [reQty r | r <- Map.elems rs, reSku r == sku, reStatus r == "Reserved"]

-- The helpers below mirror "DB.Transaction" so the in-memory interpreter
-- behaves like Postgres: 'recomputeTotals' is 'updateTotalsS',
-- 'releaseReservedForTx' is 'releaseReservedForTxS',
-- 'releaseOneReservation' is the reservation match in
-- 'deleteTransactionItem', and 'startProgress' is the CREATED to
-- IN_PROGRESS update in 'addTransactionItem'.

recomputeTotals :: Transaction -> Transaction
recomputeTotals tx =
  let items         = transactionItems tx
      subtotal      = sum (map transactionItemSubtotal items)
      discountTotal = sum [discountAmount d | i <- items, d <- transactionItemDiscounts i]
      taxTotal      = sum [taxAmount t | i <- items, t <- transactionItemTaxes i]
   in tx
        { transactionSubtotal      = subtotal
        , transactionDiscountTotal = discountTotal
        , transactionTaxTotal      = taxTotal
        , transactionTotal         = subtotal - discountTotal + taxTotal
        }

startProgress :: Transaction -> Transaction
startProgress tx =
  if transactionStatus tx == Created
    then tx {transactionStatus = InProgress}
    else tx

releaseReservedForTx :: UUID -> Map UUID ReservationEntry -> Map UUID ReservationEntry
releaseReservedForTx txId =
  Map.map
    ( \r ->
        if reTxId r == txId && reStatus r == "Reserved"
          then r {reStatus = "Released"}
          else r
    )

releaseOneReservation :: UUID -> UUID -> Int -> Map UUID ReservationEntry -> Map UUID ReservationEntry
releaseOneReservation txId sku qty rs =
  case [ k
       | (k, r) <- Map.toList rs
       , reTxId r == txId
       , reSku r == sku
       , reQty r == qty
       , reStatus r == "Reserved"
       ] of
    (k : _) -> Map.adjust (\r -> r {reStatus = "Released"}) k rs
    []      -> rs

-- | Mirrors 'DBT.restockSaleS': adds the quantity of every line of a sale
-- back to its item's stock. An item that is not in the inventory map is
-- left out, as a missing row is in Postgres.
restockLines :: Transaction -> Map UUID Int -> Map UUID Int
restockLines tx inventory =
  foldl
    ( \m i ->
        Map.adjust (+ transactionItemQuantity i) (transactionItemMenuItemSku i) m
    )
    inventory
    (transactionItems tx)

-- | The reasons a stored sale cannot be completed, by the same rule
-- 'DB.Transaction.finalizeTransaction' applies under its lock.
finalizeProblemsFor :: Transaction -> [Text]
finalizeProblemsFor tx =
  finalizeProblems
    (length (transactionItems tx))
    (transactionTotal tx)
    (sum (map paymentAmount (transactionPayments tx)))

runTransactionDbPure ::
  (GenUUID :> es, Clock :> es) =>
  TxStore ->
  Eff (TransactionDb : es) a ->
  Eff es (a, TxStore)
runTransactionDbPure initial = reinterpret (runState initial) $ \_ -> \case

  GetSaleById txId ->
    gets @TxStore $ \st ->
      narrowToSale (fmap fromLegacyTransaction (Map.lookup txId (tsTxs st)))

  GetRefundById txId ->
    gets @TxStore $ \st ->
      narrowToRefund (fmap fromLegacyTransaction (Map.lookup txId (tsTxs st)))

  GetAllSales ->
    gets @TxStore $ \st ->
      [s | tx <- Map.elems (tsTxs st), Right (Left s) <- [fromLegacyTransaction tx]]

  GetAllRefunds ->
    gets @TxStore $ \st ->
      [r | tx <- Map.elems (tsTxs st), Right (Right r) <- [fromLegacyTransaction tx]]

  GetSalesByLocation locId ->
    gets @TxStore $ \st ->
      [ s
      | tx <- Map.elems (tsTxs st)
      , transactionLocationId tx == locId
      , Right (Left s) <- [fromLegacyTransaction tx]
      ]

  GetRefundsByLocation locId ->
    gets @TxStore $ \st ->
      [ r
      | tx <- Map.elems (tsTxs st)
      , transactionLocationId tx == locId
      , Right (Right r) <- [fromLegacyTransaction tx]
      ]

  CreateSale sale -> do
    let legacyTx = saleToLegacyTransaction sale
    modify @TxStore $ \st ->
      st
        { tsTxs = Map.insert (Sale.saleId sale) legacyTx (tsTxs st)
        , tsItemToTx =
            foldl
              (\m i -> Map.insert (Sale.itemId i) (Sale.saleId sale) m)
              (tsItemToTx st)
              (Sale.saleItems sale)
        , tsPaymentToTx =
            foldl
              (\m p -> Map.insert (Sale.paymentId p) (Sale.saleId sale) m)
              (tsPaymentToTx st)
              (Sale.salePayments sale)
        }
    pure sale

  UpdateSaleStatus txId nextStatus ->
    modify @TxStore $ \st ->
      st
        { tsTxs =
            Map.adjust
              (\tx -> tx {transactionStatus = nextStatus})
              txId
              (tsTxs st)
        }

  -- Mirrors 'DBT.voidTransaction': a sale that is missing, voided or
  -- refunded is refused and nothing changes. Voiding a Completed sale puts
  -- its quantities back in stock when the store's policy says so.
  VoidSale txId reason -> do
    st <- get @TxStore
    case Map.lookup txId (tsTxs st) of
      Just tx
        | transactionStatus tx `elem` [Created, InProgress, Completed] -> do
            let voided =
                  tx
                    { transactionStatus     = Voided
                    , transactionIsVoided   = True
                    , transactionVoidReason = Just reason
                    }
                restocks =
                  transactionStatus tx == Completed
                    && restockOnVoid (tsStockPolicy st) == ReturnToStock
            put @TxStore
              st
                { tsTxs          = Map.insert txId voided (tsTxs st)
                , tsReservations = releaseReservedForTx txId (tsReservations st)
                , tsInventory    =
                    if restocks
                      then restockLines tx (tsInventory st)
                      else tsInventory st
                }
            pure $ Right (expectSaleTx voided)
      _ -> pure $ Left (SaleNotOpen txId)

  -- Mirrors 'DBTRefund.writeTypedRefund': the original sale must be
  -- Completed and not already refunded, or the refund is refused and
  -- nothing changes. An allowed refund sets the original sale's status to
  -- Refunded, so it can be neither voided nor refunded again. It puts the
  -- original sale's quantities back in stock when the store's policy says
  -- so.
  WriteRefund refund -> do
    let refundTxId    = Refund.refundId refund
        origTxId      = Refund.refundReferenceTransactionId refund
        reason        = Refund.refundReason refund
        refundItemIds = map Refund.itemId (Refund.refundItems refund)
        refundPymtIds = map Refund.paymentId (Refund.refundPayments refund)
        refundLegacy  = refundToLegacyTransaction refund
    st <- get @TxStore
    case Map.lookup origTxId (tsTxs st) of
      Just orig
        | transactionStatus orig == Completed && not (transactionIsRefunded orig) -> do
            let origItemCount   = length (transactionItems orig)
                origPymtCount   = length (transactionPayments orig)
                refundItemCount = length refundItemIds
                refundPymtCount = length refundPymtIds
            when (refundItemCount /= origItemCount) $
              error $
                "WriteRefund (pure): refund has " <> show refundItemCount
                  <> " items but original sale has " <> show origItemCount
            when (refundPymtCount /= origPymtCount) $
              error $
                "WriteRefund (pure): refund has " <> show refundPymtCount
                  <> " payments but original sale has " <> show origPymtCount
            when (any (`Map.member` tsItemToTx st) refundItemIds) $
              error "WriteRefund (pure): refund item id collides with existing"
            when (any (`Map.member` tsPaymentToTx st) refundPymtIds) $
              error "WriteRefund (pure): refund payment id collides with existing"
            let origUpdated =
                  orig
                    { transactionStatus       = Refunded
                    , transactionIsRefunded   = True
                    , transactionRefundReason = Just reason
                    }
            put @TxStore
              st
                { tsTxs =
                    Map.insert refundTxId refundLegacy
                      . Map.insert origTxId origUpdated
                      $ tsTxs st
                , tsItemToTx =
                    foldl
                      (\m iid -> Map.insert iid refundTxId m)
                      (tsItemToTx st)
                      refundItemIds
                , tsPaymentToTx =
                    foldl
                      (\m pid -> Map.insert pid refundTxId m)
                      (tsPaymentToTx st)
                      refundPymtIds
                , tsInventory =
                    if restockOnRefund (tsStockPolicy st) == ReturnToStock
                      then restockLines orig (tsInventory st)
                      else tsInventory st
                }
            pure (Right refund)
      _ -> pure $ Left (SaleNotOpen origTxId)

  -- Mirrors 'DBT.clearTransaction': only a sale that is Created or
  -- InProgress is cleared. Any other sale is refused and nothing changes.
  ClearSale txId -> do
    st <- get @TxStore
    case Map.lookup txId (tsTxs st) of
      Just tx
        | transactionStatus tx `elem` [Created, InProgress] -> do
            let cleared =
                  tx
                    { transactionStatus        = Created
                    , transactionSubtotal      = 0
                    , transactionDiscountTotal = 0
                    , transactionTaxTotal      = 0
                    , transactionTotal         = 0
                    , transactionItems         = []
                    , transactionPayments      = []
                    }
            put @TxStore
              st
                { tsTxs          = Map.insert txId cleared (tsTxs st)
                , tsReservations = releaseReservedForTx txId (tsReservations st)
                }
            pure (Right ())
      _ -> pure $ Left (SaleNotOpen txId)

  FinalizeSale txId -> do
    st  <- get @TxStore
    now <- currentTime
    case Map.lookup txId (tsTxs st) of
      Just tx
        | transactionStatus tx == InProgress ->
            case finalizeProblemsFor tx of
              problems@(_ : _) -> pure $ Left (FinalizeRefused problems)
              []               -> do
                let active =
                      [ (k, r)
                      | (k, r) <- Map.toList (tsReservations st)
                      , reTxId r == txId
                      , reStatus r == "Reserved"
                      ]
                    newReservations =
                      foldl
                        (\m (k, r) -> Map.insert k r {reStatus = "Completed"} m)
                        (tsReservations st)
                        active
                    newInventory =
                      foldl
                        (\m (_, r) -> Map.adjust (subtract (reQty r)) (reSku r) m)
                        (tsInventory st)
                        active
                    finalized =
                      tx {transactionStatus = Completed, transactionCompleted = Just now}
                put @TxStore
                  st
                    { tsTxs          = Map.insert txId finalized (tsTxs st)
                    , tsReservations = newReservations
                    , tsInventory    = newInventory
                    }
                pure $ Right (expectSaleTx finalized)
      _ -> pure $ Left (SaleNotOpen txId)

  AddSaleItem change -> do
    let sku    = lineAddSku change
        addQty = lineAddQuantity change
        txId   = lineAddSaleId change
    st <- get @TxStore
    case Map.lookup txId (tsTxs st) of
      Just tx
        | transactionStatus tx `elem` [Created, InProgress] ->
            case Map.lookup sku (tsInventory st) of
              Nothing    -> pure $ Left (ItemNotFound sku)
              Just total -> do
                let existing    =
                      [i | i <- transactionItems tx, transactionItemMenuItemSku i == sku]
                    replaced    =
                      [(transactionItemId i, transactionItemQuantity i) | i <- existing]
                    previousQty = sum (map snd replaced)
                    wantedQty   = previousQty + addQty
                    lineId      = case replaced of
                      ((existingId, _) : _) -> existingId
                      []                    -> lineAddNewItemId change
                case lineAddPrice change lineId wantedQty of
                  Left message -> pure $ Left (LineRejected message)
                  Right item   -> do
                    let reserved    = activeReservedQty sku (tsReservations st)
                        ownReserved =
                          sum
                            [ reQty r
                            | r <- Map.elems (tsReservations st)
                            , reSku r == sku
                            , reTxId r == txId
                            , reStatus r == "Reserved"
                            ]
                        available   = total - (reserved - ownReserved)
                    if available < wantedQty
                      then pure $ Left (InsufficientInventory sku wantedQty available)
                      else do
                        resId <- nextUUID
                        let newRes     = ReservationEntry sku txId wantedQty "Reserved"
                            legacyItem = saleItemToLegacy item
                            releaseOwn r =
                              if reSku r == sku && reTxId r == txId && reStatus r == "Reserved"
                                then r {reStatus = "Released"}
                                else r
                        modify @TxStore $ \s ->
                          s
                            { tsItemToTx     =
                                Map.insert lineId txId $
                                  foldr Map.delete (tsItemToTx s) (map fst replaced)
                            , tsReservations =
                                Map.insert resId newRes (Map.map releaseOwn (tsReservations s))
                            , tsTxs          =
                                Map.adjust
                                  ( \t ->
                                      recomputeTotals
                                        (startProgress t)
                                          { transactionItems =
                                              legacyItem
                                                : filter
                                                    (\i -> transactionItemMenuItemSku i /= sku)
                                                    (transactionItems t)
                                          }
                                  )
                                  txId
                                  (tsTxs s)
                            }
                        pure $
                          Right
                            SaleLineAdded
                              { lineAddedItem     = item
                              , lineAddedReplaced = replaced
                              }
      _ -> pure $ Left (SaleNotOpen txId)

  -- Mirrors 'DBT.deleteTransactionItem': a line is removed only from a
  -- sale that is InProgress. Any other sale is refused and nothing
  -- changes. An item id that belongs to no sale is not an error.
  DeleteSaleItem itemId -> do
    st <- get @TxStore
    case Map.lookup itemId (tsItemToTx st) of
      Nothing   -> pure (Right ())
      Just txId ->
        case Map.lookup txId (tsTxs st) of
          Just tx
            | transactionStatus tx == InProgress -> do
                let mLegacyItem =
                      lookup itemId
                        [ (transactionItemId i, i) | i <- transactionItems tx ]
                case mLegacyItem of
                  Nothing   -> pure (Right ())
                  Just item -> do
                    let sku = transactionItemMenuItemSku item
                        qty = transactionItemQuantity item
                    put @TxStore
                      st
                        { tsItemToTx     = Map.delete itemId (tsItemToTx st)
                        , tsReservations = releaseOneReservation txId sku qty (tsReservations st)
                        , tsTxs          =
                            Map.insert
                              txId
                              ( recomputeTotals
                                  tx
                                    { transactionItems =
                                        filter (\i -> transactionItemId i /= itemId) (transactionItems tx)
                                    }
                              )
                              (tsTxs st)
                        }
                    pure (Right ())
          _ -> pure $ Left (SaleNotOpen txId)

  AddSalePayment payment -> do
    let legacyPayment = salePaymentToLegacy payment
        txId          = Sale.paymentTransactionId payment
    st <- get @TxStore
    case Map.lookup txId (tsTxs st) of
      Just tx
        | transactionStatus tx == InProgress -> do
            put @TxStore
              st
                { tsPaymentToTx =
                    Map.insert (Sale.paymentId payment) txId (tsPaymentToTx st)
                , tsTxs         =
                    Map.insert
                      txId
                      tx {transactionPayments = legacyPayment : transactionPayments tx}
                      (tsTxs st)
                }
            pure $ Right payment
      _ -> pure $ Left (SaleNotOpen txId)

  DeleteSalePayment pymtId -> do
    st <- get @TxStore
    case Map.lookup pymtId (tsPaymentToTx st) of
      Nothing   -> pure $ Right ()
      Just txId ->
        case Map.lookup txId (tsTxs st) of
          Just tx
            | transactionStatus tx == InProgress -> do
                put @TxStore
                  st
                    { tsPaymentToTx = Map.delete pymtId (tsPaymentToTx st)
                    , tsTxs         =
                        Map.insert
                          txId
                          tx
                            { transactionPayments =
                                filter (\p -> paymentId p /= pymtId) (transactionPayments tx)
                            }
                          (tsTxs st)
                    }
                pure $ Right ()
          _ -> pure $ Left (SaleNotOpen txId)

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
    modify @TxStore $ \st ->
      st
        { tsReservations =
            Map.insert
              resId
              (ReservationEntry itemSku txId qty "Reserved")
              (tsReservations st)
        }

  ReleaseReservation resId -> do
    st <- get @TxStore
    case Map.lookup resId (tsReservations st) of
      Nothing -> pure False
      Just r  ->
        if reStatus r == "Reserved"
          then do
            put @TxStore
              st
                { tsReservations =
                    Map.insert resId r {reStatus = "Released"} (tsReservations st)
                }
            pure True
          else pure False

  GetAllActiveReservations ->
    gets @TxStore $ \st ->
      [ InventoryReservation
          { reservationItemSku       = reSku r
          , reservationTransactionId = reTxId r
          , reservationQuantity      = reQty r
          , reservationStatus        = reStatus r
          }
      | r <- Map.elems (tsReservations st)
      , reStatus r == "Reserved"
      ]