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

  -- Reads (typed)
  TypedLoadError (..),
  getSaleById,
  getRefundById,
  getAllSales,
  getAllRefunds,
  getSalesByLocation,
  getRefundsByLocation,

  -- Writes (typed)
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

  -- By-id lookups
  getTxIdByItemId,
  getTxIdByPaymentId,

  -- Inventory / reservations
  getInventoryAvailability,
  createReservation,
  releaseReservation,
  getAllActiveReservations,

  -- Interpreters
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
import Data.Maybe (fromMaybe)
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
import Effect.Clock
import Effect.GenUUID
import Types.Location (LocationId)
import Types.Primitives.Quantity (saleQuantityCount)
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

data TransactionDb :: Effect where

  -- Reads
  GetSaleById              :: UUID -> TransactionDb m (Either TypedLoadError Sale.SaleTransaction)
  GetRefundById            :: UUID -> TransactionDb m (Either TypedLoadError Refund.RefundTransaction)
  GetAllSales              :: TransactionDb m [Sale.SaleTransaction]
  GetAllRefunds            :: TransactionDb m [Refund.RefundTransaction]
  GetSalesByLocation       :: LocationId -> TransactionDb m [Sale.SaleTransaction]
  GetRefundsByLocation     :: LocationId -> TransactionDb m [Refund.RefundTransaction]

  -- Writes
  CreateSale               :: Sale.SaleTransaction -> TransactionDb m Sale.SaleTransaction
  UpdateSaleStatus         :: UUID -> TransactionStatus -> TransactionDb m ()
  VoidSale                 :: UUID -> Text -> TransactionDb m Sale.SaleTransaction
  WriteRefund              :: Refund.RefundTransaction -> TransactionDb m Refund.RefundTransaction
  ClearSale                :: UUID -> TransactionDb m ()
  FinalizeSale             :: UUID -> TransactionDb m Sale.SaleTransaction
  AddSaleItem              :: Sale.Item -> TransactionDb m (Either InventoryException Sale.Item)
  DeleteSaleItem           :: UUID -> TransactionDb m ()
  AddSalePayment           :: Sale.Payment -> TransactionDb m Sale.Payment
  DeleteSalePayment        :: UUID -> TransactionDb m ()

  -- By-id lookups (kind-agnostic, used for resolving entity → parent tx)
  GetTxIdByItemId          :: UUID -> TransactionDb m (Maybe UUID)
  GetTxIdByPaymentId       :: UUID -> TransactionDb m (Maybe UUID)

  -- Inventory / reservations
  GetInventoryAvailability :: UUID -> TransactionDb m (Maybe (Int, Int))
  CreateReservation        :: UUID -> UUID -> UUID -> Int -> UTCTime -> TransactionDb m ()
  ReleaseReservation       :: UUID -> TransactionDb m Bool
  GetAllActiveReservations :: TransactionDb m [InventoryReservation]

type instance DispatchOf TransactionDb = Dynamic

-- send wrappers

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

voidSale :: (TransactionDb :> es) => UUID -> Text -> Eff es Sale.SaleTransaction
voidSale txId reason = send (VoidSale txId reason)

writeRefund :: (TransactionDb :> es) => Refund.RefundTransaction -> Eff es Refund.RefundTransaction
writeRefund = send . WriteRefund

clearSale :: (TransactionDb :> es) => UUID -> Eff es ()
clearSale = send . ClearSale

finalizeSale :: (TransactionDb :> es) => UUID -> Eff es Sale.SaleTransaction
finalizeSale = send . FinalizeSale

addSaleItem ::
  (TransactionDb :> es) =>
  Sale.Item ->
  Eff es (Either InventoryException Sale.Item)
addSaleItem = send . AddSaleItem

deleteSaleItem :: (TransactionDb :> es) => UUID -> Eff es ()
deleteSaleItem = send . DeleteSaleItem

addSalePayment :: (TransactionDb :> es) => Sale.Payment -> Eff es Sale.Payment
addSalePayment = send . AddSalePayment

deleteSalePayment :: (TransactionDb :> es) => UUID -> Eff es ()
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

-- ---------------------------------------------------------------------------
-- Internal: conversion at the SQL boundary
-- ---------------------------------------------------------------------------
--
-- The legacy DB functions take and return legacy 'Transaction' /
-- 'TransactionItem' / 'PaymentTransaction'. The interpreters convert
-- typed -> legacy on input and legacy -> typed on output.
--
-- For write operations, the output side cannot legitimately fail: we
-- just stored a sale, the returned row must convert back to a sale.
-- A failure here means DB corruption or a serialization bug, not a
-- user error. We panic with a descriptive message.
--
-- For read operations, failure modes are normal: the id might not
-- exist, the stored row might be the wrong kind, or the row might be
-- malformed. Those propagate as 'TypedLoadError'.

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

-- ---------------------------------------------------------------------------
-- IO interpreter
-- ---------------------------------------------------------------------------

runTransactionDbIO :: (IOE :> es) => DBPool -> Eff (TransactionDb : es) a -> Eff es a
runTransactionDbIO pool = interpret $ \_ -> \case

  GetSaleById uuid -> liftIO $ do
    r <- DBTTyped.getTransactionByIdTyped pool uuid
    pure (narrowToSale r)

  GetRefundById uuid -> liftIO $ do
    r <- DBTTyped.getTransactionByIdTyped pool uuid
    pure (narrowToRefund r)

  GetAllSales -> liftIO $ do
    results <- DBTTyped.getAllTransactionsTyped pool
    -- Decode failures are silently dropped. See critical notes.
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
    result <- DBT.voidTransaction pool txId reason
    pure (expectSaleTx result)

  WriteRefund refund -> liftIO $ do
    result <- DBTRefund.writeTypedRefund pool refund
    pure (expectRefundTx result)

  ClearSale txId -> liftIO $
    DBT.clearTransaction pool txId

  FinalizeSale txId -> liftIO $ do
    result <- DBT.finalizeTransaction pool txId
    pure (expectSaleTx result)

  AddSaleItem item -> liftIO $ do
    let legacyItem = saleItemToLegacy item
    res <- try @InventoryException $ DBT.addTransactionItem pool legacyItem
    pure $ case res of
      Left e            -> Left e
      Right addedLegacy -> Right (expectSaleItem addedLegacy)

  DeleteSaleItem itemId -> liftIO $
    DBT.deleteTransactionItem pool itemId

  AddSalePayment payment -> liftIO $ do
    let legacyPayment = salePaymentToLegacy payment
    result <- DBT.addPaymentTransaction pool legacyPayment
    pure (expectSalePayment result)

  DeleteSalePayment pymtId -> liftIO $
    DBT.deletePaymentTransaction pool pymtId

  GetTxIdByItemId u -> liftIO $ DBT.getTransactionIdByItemId pool u
  GetTxIdByPaymentId u -> liftIO $ DBT.getTransactionIdByPaymentId pool u
  GetInventoryAvailability u -> liftIO $ DBT.getInventoryAvailability pool u
  CreateReservation a b c d e -> liftIO $ DBRes.createInventoryReservation pool a b c d e
  ReleaseReservation u -> liftIO $ DBRes.releaseInventoryReservation pool u
  GetAllActiveReservations -> liftIO $ DBRes.getAllActiveReservations pool

-- ---------------------------------------------------------------------------
-- Pure interpreter
-- ---------------------------------------------------------------------------

data ReservationEntry = ReservationEntry
  { reSku    :: UUID
  , reTxId   :: UUID
  , reQty    :: Int
  , reStatus :: Text
  }
  deriving (Show, Eq)

-- | The store still holds legacy 'Transaction' rows. Typed effect ops
-- convert at each touch. Pure-interpreter consumers (tests) never see
-- the legacy representation directly.
data TxStore = TxStore
  { tsTxs          :: Map UUID Transaction
  , tsItemToTx     :: Map UUID UUID
  , tsPaymentToTx  :: Map UUID UUID
  , tsReservations :: Map UUID ReservationEntry
  , tsInventory    :: Map UUID Int
  }
  deriving (Show, Eq)

emptyTxStore :: TxStore
emptyTxStore = TxStore Map.empty Map.empty Map.empty Map.empty Map.empty

activeReservedQty :: UUID -> Map UUID ReservationEntry -> Int
activeReservedQty sku rs =
  sum [reQty r | r <- Map.elems rs, reSku r == sku, reStatus r == "Reserved"]

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

  VoidSale txId reason -> do
    st <- get @TxStore
    case Map.lookup txId (tsTxs st) of
      Nothing -> error $ "VoidSale: not found: " <> show txId
      Just tx -> do
        let voided =
              tx
                { transactionStatus     = Voided
                , transactionIsVoided   = True
                , transactionVoidReason = Just reason
                }
        put @TxStore st {tsTxs = Map.insert txId voided (tsTxs st)}
        pure (expectSaleTx voided)

  WriteRefund refund -> do
    let refundTxId    = Refund.refundId refund
        origTxId      = Refund.refundReferenceTransactionId refund
        reason        = Refund.refundReason refund
        refundItemIds = map Refund.itemId (Refund.refundItems refund)
        refundPymtIds = map Refund.paymentId (Refund.refundPayments refund)
        refundLegacy  = refundToLegacyTransaction refund
    -- We need refundToLegacyTransaction here. Until it's imported, fall
    -- back to the conversion the test fixture actually needs:
    --   import Types.Transaction.Conversion (refundToLegacyTransaction)
    -- and replace the placeholder line with:
    --   refundLegacy = refundToLegacyTransaction refund
    st <- get @TxStore
    case Map.lookup origTxId (tsTxs st) of
      Nothing   -> error $ "WriteRefund: original sale not found: " <> show origTxId
      Just orig -> do
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
                { transactionIsRefunded   = True
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
            }
        pure refund

  ClearSale txId ->
    modify @TxStore $ \st ->
      st
        { tsTxs =
            Map.adjust
              ( \tx ->
                  tx
                    { transactionStatus        = Created
                    , transactionSubtotal      = 0
                    , transactionDiscountTotal = 0
                    , transactionTaxTotal      = 0
                    , transactionTotal         = 0
                    , transactionItems         = []
                    , transactionPayments      = []
                    }
              )
              txId
              (tsTxs st)
        , tsReservations =
            Map.map
              ( \r ->
                  if reTxId r == txId && reStatus r == "Reserved"
                    then r {reStatus = "Released"}
                    else r
              )
              (tsReservations st)
        }

  FinalizeSale txId -> do
    st  <- get @TxStore
    now <- currentTime
    case Map.lookup txId (tsTxs st) of
      Nothing -> error $ "FinalizeSale: not found: " <> show txId
      Just tx -> do
        let active =
              [ (k, r)
              | (k, r) <- Map.toList (tsReservations st)
              , reTxId r == txId
              , reStatus r == "Reserved"
              ]
        let newReservations =
              foldl
                (\m (k, r) -> Map.insert k r {reStatus = "Completed"} m)
                (tsReservations st)
                active
        let newInventory =
              foldl
                (\m (_, r) -> Map.adjust (subtract (reQty r)) (reSku r) m)
                (tsInventory st)
                active
        let finalized = tx {transactionStatus = Completed, transactionCompleted = Just now}
        put @TxStore
          st
            { tsTxs          = Map.insert txId finalized (tsTxs st)
            , tsReservations = newReservations
            , tsInventory    = newInventory
            }
        pure (expectSaleTx finalized)

  AddSaleItem item -> do
    let legacyItem = saleItemToLegacy item
        sku = Sale.itemMenuItemSku item
        qty = saleQuantityCount (Sale.itemQuantity item)
    st <- get @TxStore
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
            let txId   = Sale.itemTransactionId item
                newRes = ReservationEntry sku txId qty "Reserved"
            modify @TxStore $ \s ->
              s
                { tsItemToTx     = Map.insert (Sale.itemId item) txId (tsItemToTx s)
                , tsReservations = Map.insert resId newRes (tsReservations s)
                , tsTxs          =
                    Map.adjust
                      (\tx -> tx {transactionItems = legacyItem : transactionItems tx})
                      txId
                      (tsTxs s)
                }
            pure $ Right item

  DeleteSaleItem itemId -> do
    st <- get @TxStore
    case Map.lookup itemId (tsItemToTx st) of
      Nothing   -> pure ()
      Just txId -> do
        let mLegacyItem =
              Map.lookup txId (tsTxs st) >>= \tx ->
                lookup itemId
                  [ (transactionItemId i, i) | i <- transactionItems tx ]
        case mLegacyItem of
          Nothing   -> pure ()
          Just item -> do
            let sku = transactionItemMenuItemSku item
            modify @TxStore $ \s ->
              s
                { tsItemToTx     = Map.delete itemId (tsItemToTx s)
                , tsReservations =
                    Map.map
                      ( \r ->
                          if reSku r == sku && reTxId r == txId && reStatus r == "Reserved"
                            then r {reStatus = "Released"}
                            else r
                      )
                      (tsReservations s)
                , tsTxs          =
                    Map.adjust
                      ( \tx ->
                          tx
                            { transactionItems =
                                filter (\i -> transactionItemId i /= itemId) (transactionItems tx)
                            }
                      )
                      txId
                      (tsTxs s)
                }

  AddSalePayment payment -> do
    let legacyPayment = salePaymentToLegacy payment
        txId          = Sale.paymentTransactionId payment
    modify @TxStore $ \st ->
      st
        { tsPaymentToTx =
            Map.insert (Sale.paymentId payment) txId (tsPaymentToTx st)
        , tsTxs         =
            Map.adjust
              (\tx -> tx {transactionPayments = legacyPayment : transactionPayments tx})
              txId
              (tsTxs st)
        }
    pure payment

  DeleteSalePayment pymtId -> do
    st <- get @TxStore
    case Map.lookup pymtId (tsPaymentToTx st) of
      Nothing   -> pure ()
      Just txId ->
        modify @TxStore $ \s ->
          s
            { tsPaymentToTx = Map.delete pymtId (tsPaymentToTx s)
            , tsTxs         =
                Map.adjust
                  ( \tx ->
                      tx
                        { transactionPayments =
                            filter (\p -> paymentId p /= pymtId) (transactionPayments tx)
                        }
                  )
                  txId
                  (tsTxs s)
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