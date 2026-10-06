{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module DB.Transaction where

import Control.Exception (Exception, throwIO)
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Data.Int (Int32)
import Data.List (sortOn)
import Data.Scientific (fromFloatDigits)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Data.Typeable (Typeable)
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import qualified Hasql.Decoders as Decoders
import qualified Hasql.Encoders as Encoders
import qualified Hasql.Session as Session
import qualified Hasql.Statement as Statement
import Rel8

import DB.Database (DBPool, ddl, runSession, runTransaction, runTransaction_)
import DB.Schema
import Domain.SaleRules (finalizeProblems)
import Types.Location (LocationId (..), locationIdToUUID)
import Types.Transaction

-- | Why a write to a sale was refused.
--
-- 'SaleNotOpen' carries the sale id and means the sale does not exist or is
-- not in a status that allows the write. 'LineRejected' carries the message
-- from the caller's pricing function. 'FinalizeRefused' carries every reason
-- the sale cannot be completed, as worded by "Domain.SaleRules".
data InventoryException
  = ItemNotFound UUID
  | InsufficientInventory UUID Int Int
  | SaleNotOpen UUID
  | LineRejected Text
  | FinalizeRefused [Text]
  deriving (Show, Typeable)

instance Exception InventoryException

-- | The result of a successful add: the line as stored, and the id and
-- quantity of each line it replaced.
data AddedLine = AddedLine
  { addedLineItem     :: TransactionItem
  , addedLineReplaced :: [(UUID, Int)]
  }

createTransactionTables :: DBPool -> IO ()
createTransactionTables pool = do
  runSession pool $ do
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS transaction (\
        \  id                        UUID PRIMARY KEY,\
        \  status                    TEXT NOT NULL,\
        \  created                   TIMESTAMP WITH TIME ZONE NOT NULL,\
        \  completed                 TIMESTAMP WITH TIME ZONE,\
        \  customer_id               UUID,\
        \  employee_id               UUID NOT NULL,\
        \  register_id               UUID NOT NULL,\
        \  location_id               UUID NOT NULL,\
        \  subtotal                  INTEGER NOT NULL,\
        \  discount_total            INTEGER NOT NULL,\
        \  tax_total                 INTEGER NOT NULL,\
        \  total                     INTEGER NOT NULL,\
        \  transaction_type          TEXT NOT NULL,\
        \  is_voided                 BOOLEAN NOT NULL DEFAULT FALSE,\
        \  void_reason               TEXT,\
        \  is_refunded               BOOLEAN NOT NULL DEFAULT FALSE,\
        \  refund_reason             TEXT,\
        \  reference_transaction_id  UUID,\
        \  notes                     TEXT\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS register (\
        \  id                      UUID PRIMARY KEY,\
        \  name                    TEXT NOT NULL,\
        \  location_id             UUID NOT NULL,\
        \  is_open                 BOOLEAN NOT NULL DEFAULT FALSE,\
        \  current_drawer_amount   INTEGER NOT NULL DEFAULT 0,\
        \  expected_drawer_amount  INTEGER NOT NULL DEFAULT 0,\
        \  opened_at               TIMESTAMP WITH TIME ZONE,\
        \  opened_by               UUID,\
        \  last_transaction_time   TIMESTAMP WITH TIME ZONE\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS inventory_reservation (\
        \  id              UUID PRIMARY KEY,\
        \  item_sku        UUID NOT NULL,\
        \  transaction_id  UUID NOT NULL,\
        \  quantity        INTEGER NOT NULL,\
        \  status          TEXT NOT NULL,\
        \  created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS transaction_item (\
        \  id              UUID PRIMARY KEY,\
        \  transaction_id  UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,\
        \  menu_item_sku   UUID NOT NULL,\
        \  quantity        INTEGER NOT NULL,\
        \  price_per_unit  INTEGER NOT NULL,\
        \  subtotal        INTEGER NOT NULL,\
        \  total           INTEGER NOT NULL\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS transaction_tax (\
        \  id                    UUID PRIMARY KEY,\
        \  transaction_item_id   UUID NOT NULL REFERENCES transaction_item(id) ON DELETE CASCADE,\
        \  category              TEXT NOT NULL,\
        \  rate                  NUMERIC NOT NULL,\
        \  amount                INTEGER NOT NULL,\
        \  description           TEXT NOT NULL\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS discount (\
        \  id                    UUID PRIMARY KEY,\
        \  transaction_item_id   UUID REFERENCES transaction_item(id) ON DELETE CASCADE,\
        \  transaction_id        UUID REFERENCES transaction(id) ON DELETE CASCADE,\
        \  type                  TEXT NOT NULL,\
        \  amount                INTEGER NOT NULL,\
        \  percent               NUMERIC,\
        \  reason                TEXT NOT NULL,\
        \  approved_by           UUID\
        \)"
    Session.statement () $
      ddl
        "CREATE TABLE IF NOT EXISTS payment_transaction (\
        \  id                 UUID PRIMARY KEY,\
        \  transaction_id     UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,\
        \  method             TEXT NOT NULL,\
        \  amount             INTEGER NOT NULL,\
        \  tendered           INTEGER NOT NULL,\
        \  change_amount      INTEGER NOT NULL,\
        \  reference          TEXT,\
        \  approved           BOOLEAN NOT NULL DEFAULT FALSE,\
        \  authorization_code TEXT\
        \)"

itemsForTx :: UUID -> Query (TransactionItemRow Expr)
itemsForTx txId = do
  ti <- each transactionItemSchema
  where_ $ tiTransactionId ti ==. lit txId
  pure ti

taxesForItem :: UUID -> Query (TaxRow Expr)
taxesForItem itemId = do
  t <- each taxSchema
  where_ $ taxRowTransactionItemId t ==. lit itemId
  pure t

discountsForItem :: UUID -> Query (DiscountRow Expr)
discountsForItem itemId = do
  d <- each discountSchema
  where_ $ discRowTransactionItemId d ==. lit (Just itemId)
  pure d

paymentsForTx :: UUID -> Query (PaymentRow Expr)
paymentsForTx txId = do
  p <- each paymentSchema
  where_ $ pymtTransactionId p ==. lit txId
  pure p

hydrateTx :: DBPool -> TransactionRow Result -> IO Transaction
hydrateTx pool txRow = do
  let txId    = DB.Schema.txId txRow
  itemRows   <- runSession pool $ Session.statement () $ run $ Rel8.select (itemsForTx txId)
  items      <- mapM (hydrateItem pool) itemRows
  pymtRows   <- runSession pool $ Session.statement () $ run $ Rel8.select (paymentsForTx txId)
  let payments = map paymentRowToDomain pymtRows
  pure $ txRowToDomain txRow items payments

hydrateItem :: DBPool -> TransactionItemRow Result -> IO TransactionItem
hydrateItem pool itemRow = do
  let itemId    = tiId itemRow
  taxRows      <- runSession pool $ Session.statement () $ run $ Rel8.select (taxesForItem itemId)
  discountRows <- runSession pool $ Session.statement () $ run $ Rel8.select (discountsForItem itemId)
  pure $
    itemRowToDomain
      itemRow
      (map taxRowToDomain taxRows)
      (map discountRowToDomain discountRows)

getAllTransactions :: DBPool -> IO [Transaction]
getAllTransactions pool = do
  txRows <- runSession pool $ Session.statement () $ run $ Rel8.select (each transactionSchema)
  mapM (hydrateTx pool) txRows

getTransactionById :: DBPool -> UUID -> IO (Maybe Transaction)
getTransactionById pool txId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    tx <- each transactionSchema
    where_ $ DB.Schema.txId tx ==. lit txId
    pure tx
  case rows of
    [row] -> Just <$> hydrateTx pool row
    _     -> pure Nothing

-- Row locks.
--
-- Rel8 has no locking clause, so these statements are plain Hasql. Every
-- write path below that touches stock takes the locks in the same order:
-- the sale row first, then menu item rows in ascending sku order. A single
-- order means two registers cannot deadlock each other.

lockTransactionRow :: Statement.Statement UUID (Maybe UUID)
lockTransactionRow =
  Statement.Statement
    "SELECT id FROM transaction WHERE id = $1 FOR UPDATE"
    (Encoders.param (Encoders.nonNullable Encoders.uuid))
    (Decoders.rowMaybe (Decoders.column (Decoders.nonNullable Decoders.uuid)))
    False

-- | Locks the sale row and returns its status text.
lockTransactionStatus :: Statement.Statement UUID (Maybe Text)
lockTransactionStatus =
  Statement.Statement
    "SELECT status FROM transaction WHERE id = $1 FOR UPDATE"
    (Encoders.param (Encoders.nonNullable Encoders.uuid))
    (Decoders.rowMaybe (Decoders.column (Decoders.nonNullable Decoders.text)))
    False

lockMenuItemQuantity :: Statement.Statement UUID (Maybe Int32)
lockMenuItemQuantity =
  Statement.Statement
    "SELECT quantity FROM menu_items WHERE sku = $1 FOR UPDATE"
    (Encoders.param (Encoders.nonNullable Encoders.uuid))
    (Decoders.rowMaybe (Decoders.column (Decoders.nonNullable Decoders.int4)))
    False

-- Session-level building blocks. They run on whatever connection the
-- enclosing session holds, so they can be combined inside 'runTransaction'.

reservedQuantityS :: UUID -> Session.Session Int
reservedQuantityS sku = do
  reservedSums <-
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn resQuantity) $ do
            r <- each reservationSchema
            where_ $
              resItemSku r ==. lit sku
                &&. resStatus r ==. lit "Reserved"
            pure r
  pure $ case reservedSums of
    (r : _) -> fromIntegral (r :: Int32)
    _       -> 0

insertItemS :: TransactionItem -> Session.Session ()
insertItemS item = do
  Session.statement () $
    run_ $
      Rel8.insert $
        Insert
          { into        = transactionItemSchema
          , rows        = values [tiDomainToRow item]
          , onConflict  = Abort
          , returning   = NoReturning
          }
  forM_ (transactionItemDiscounts item) $ \discount -> do
    discId <- liftIO nextRandom
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into        = discountSchema
            , rows        = values [discountDomainToRow discId (transactionItemId item) Nothing discount]
            , onConflict  = Abort
            , returning   = NoReturning
            }
  forM_ (transactionItemTaxes item) $ \tax -> do
    taxId <- liftIO nextRandom
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into        = taxSchema
            , rows        = values [taxDomainToRow taxId (transactionItemId item) tax]
            , onConflict  = Abort
            , returning   = NoReturning
            }

insertPaymentS :: PaymentTransaction -> Session.Session ()
insertPaymentS payment =
  Session.statement () $
    run_ $
      Rel8.insert $
        Insert
          { into        = paymentSchema
          , rows        = values [paymentDomainToRow payment]
          , onConflict  = Abort
          , returning   = NoReturning
          }

releaseReservedForTxS :: UUID -> Session.Session ()
releaseReservedForTxS txId =
  Session.statement () $
    run_ $
      Rel8.update $
        Update
          { target      = reservationSchema
          , from        = pure ()
          , set         = \() row -> row {resStatus = lit "Released"}
          , updateWhere = \() row ->
              resTransactionId row ==. lit txId
                &&. resStatus row ==. lit "Reserved"
          , returning   = NoReturning
          }

updateTotalsS :: UUID -> Session.Session ()
updateTotalsS txId = do
  subtotals <-
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn tiSubtotal) $ do
            ti <- each transactionItemSchema
            where_ $ tiTransactionId ti ==. lit txId
            pure ti
  let subtotal :: Int32 = case subtotals of (s : _) -> s; _ -> 0

  discountTotals <-
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn discRowAmount) $ do
            d  <- each discountSchema
            ti <- each transactionItemSchema
            where_ $
              discRowTransactionItemId d ==. nullify (tiId ti)
                &&. tiTransactionId ti ==. lit txId
            pure d
  let discountTotal :: Int32 = case discountTotals of (d : _) -> d; _ -> 0

  taxTotals <-
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn taxRowAmount) $ do
            t  <- each taxSchema
            ti <- each transactionItemSchema
            where_ $
              taxRowTransactionItemId t ==. tiId ti
                &&. tiTransactionId ti ==. lit txId
            pure t
  let taxTotal :: Int32 = case taxTotals of (t : _) -> t; _ -> 0

  let total = subtotal - discountTotal + taxTotal
  Session.statement () $
    run_ $
      Rel8.update $
        Update
          { target      = transactionSchema
          , from        = pure ()
          , set         = \() row ->
              row
                { txSubtotal      = lit subtotal
                , txDiscountTotal = lit discountTotal
                , txTaxTotal      = lit taxTotal
                , txTotal         = lit total
                }
          , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
          , returning   = NoReturning
          }

-- IO entry points.

createTransaction :: DBPool -> Transaction -> IO Transaction
createTransaction pool tx = do
  runTransaction_ pool $ do
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into        = transactionSchema
            , rows        = values [txDomainToRow tx]
            , onConflict  = Abort
            , returning   = NoReturning
            }
    mapM_ insertItemS (transactionItems tx)
    mapM_ insertPaymentS (transactionPayments tx)
  pure tx

insertTransactionItem :: DBPool -> TransactionItem -> IO TransactionItem
insertTransactionItem pool item = do
  runTransaction_ pool (insertItemS item)
  pure item

-- | Inserts a payment row with no check on the sale. Sale code must use
-- 'addPaymentTransaction', which checks the sale's status under its lock.
insertPaymentTransaction :: DBPool -> PaymentTransaction -> IO PaymentTransaction
insertPaymentTransaction pool payment = do
  runSession pool (insertPaymentS payment)
  pure payment

-- | Marks the sale voided and releases every reservation it still holds, in
-- one SQL transaction. Reservations of a completed sale are already
-- "Completed" and are left alone, so voiding a completed sale does not put
-- stock back.
voidTransaction :: DBPool -> UUID -> Text -> IO Transaction
voidTransaction pool txId reason = do
  runTransaction_ pool $ do
    _ <- Session.statement txId lockTransactionRow
    releaseReservedForTxS txId
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target      = transactionSchema
            , from        = pure ()
            , set         = \() row ->
                row
                  { txStatus     = lit "VOIDED"
                  , txIsVoided   = lit True
                  , txVoidReason = lit (Just reason)
                  }
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning   = NoReturning
            }
  mTx <- getTransactionById pool txId
  case mTx of
    Just tx -> pure tx
    Nothing -> throwIO $ userError $ "Transaction not found after void: " <> show txId

updateTransactionStatus :: DBPool -> UUID -> TransactionStatus -> IO ()
updateTransactionStatus pool txId status =
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target      = transactionSchema
            , from        = pure ()
            , set         = \() row -> row {txStatus = lit (showStatus status)}
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning   = NoReturning
            }

clearTransaction :: DBPool -> UUID -> IO ()
clearTransaction pool txId =
  runTransaction_ pool $ do
    _ <- Session.statement txId lockTransactionRow
    releaseReservedForTxS txId
    Session.statement () $
      run_ $
        Rel8.delete $
          Delete
            { from        = paymentSchema
            , using       = pure ()
            , deleteWhere = \() row -> pymtTransactionId row ==. lit txId
            , returning   = NoReturning
            }
    Session.statement () $
      run_ $
        Rel8.delete $
          Delete
            { from        = transactionItemSchema
            , using       = pure ()
            , deleteWhere = \() row -> tiTransactionId row ==. lit txId
            , returning   = NoReturning
            }
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target      = transactionSchema
            , from        = pure ()
            , set         = \() row ->
                row
                  { txSubtotal      = lit 0
                  , txDiscountTotal = lit 0
                  , txTaxTotal      = lit 0
                  , txTotal         = lit 0
                  , txStatus        = lit "CREATED"
                  }
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning   = NoReturning
            }

-- | Completes a sale, in one SQL transaction.
--
-- The sale row is locked first. Under that lock this function reads the
-- status, the number of lines, the stored total and the sum of payments,
-- and decides whether the sale may be completed. Payment writes take the
-- same lock, so a payment cannot be added or removed between the decision
-- and the write.
--
-- The sale must be IN_PROGRESS, or the result is 'SaleNotOpen'. It must
-- have at least one line and payments covering its total, or the result is
-- 'FinalizeRefused' with every reason listed. A second finalize of the same
-- sale waits at the lock and is then refused, so stock is reduced once.
--
-- When the sale may be completed, stock is reduced for every reservation it
-- holds, those reservations are marked completed, and the sale is marked
-- completed. Throws 'InventoryException' after rolling back.
finalizeTransaction :: DBPool -> UUID -> IO Transaction
finalizeTransaction pool txId = do
  now <- getCurrentTime
  outcome <- runTransaction pool $ do
    mStatus <- Session.statement txId lockTransactionStatus
    if mStatus /= Just "IN_PROGRESS"
      then pure (Left (SaleNotOpen txId))
      else do
        lineIds <- Session.statement () $ run $ Rel8.select $ do
          ti <- each transactionItemSchema
          where_ $ tiTransactionId ti ==. lit txId
          pure (tiId ti)
        totals <- Session.statement () $ run $ Rel8.select $ do
          t <- each transactionSchema
          where_ $ DB.Schema.txId t ==. lit txId
          pure (txTotal t)
        paidSums <-
          Session.statement () $
            run $
              Rel8.select $
                aggregate (sumOn pymtAmount) $ do
                  p <- each paymentSchema
                  where_ $ pymtTransactionId p ==. lit txId
                  pure p
        let itemCount = length (lineIds :: [UUID])
            total     = case totals of
              (t : _) -> fromIntegral (t :: Int32) :: Int
              _       -> 0
            paid      = case paidSums of
              (p : _) -> fromIntegral (p :: Int32) :: Int
              _       -> 0
        case finalizeProblems itemCount total paid of
          problems@(_ : _) -> pure (Left (FinalizeRefused problems))
          []               -> do
            reservations <- Session.statement () $ run $ Rel8.select $ do
              res <- each reservationSchema
              where_ $
                resTransactionId res ==. lit txId
                  &&. resStatus res ==. lit "Reserved"
              pure res
            forM_ (sortOn resItemSku reservations) $ \res -> do
              Session.statement () $
                run_ $
                  Rel8.update $
                    Update
                      { target      = menuItemSchema
                      , from        = pure ()
                      , set         = \() row -> row {menuQuantity = menuQuantity row - lit (resQuantity res)}
                      , updateWhere = \() row -> menuSku row ==. lit (resItemSku res)
                      , returning   = NoReturning
                      }
              Session.statement () $
                run_ $
                  Rel8.update $
                    Update
                      { target      = reservationSchema
                      , from        = pure ()
                      , set         = \() row -> row {resStatus = lit "Completed"}
                      , updateWhere = \() row -> resId row ==. lit (resId res)
                      , returning   = NoReturning
                      }
            Session.statement () $
              run_ $
                Rel8.update $
                  Update
                    { target      = transactionSchema
                    , from        = pure ()
                    , set         = \() row ->
                        row
                          { txStatus    = lit "COMPLETED"
                          , txCompleted = lit (Just now)
                          }
                    , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
                    , returning   = NoReturning
                    }
            pure (Right ())
  case outcome of
    Left e   -> throwIO e
    Right () -> do
      mTx <- getTransactionById pool txId
      case mTx of
        Just tx -> pure tx
        Nothing -> throwIO $ userError $ "Transaction not found after finalization: " <> show txId

-- | Adds a quantity of one sku to a sale, in one SQL transaction.
--
-- The caller passes the quantity to add and a pricing function. It does not
-- pass the line's whole quantity. Under the sale row lock this function
-- reads the sale's current line for the sku, adds the increment to that
-- line's quantity, and calls the pricing function with the line id and the
-- whole quantity. Two adds of the same sku to the same sale therefore run
-- one after the other, and the second one sees the first one's line.
--
-- A sale holds at most one line per sku. An existing line is deleted and
-- its reservation released, then the new line and one reservation for the
-- whole quantity are inserted and the sale totals are updated. The line
-- keeps the existing line's id, or takes @newItemId@ when the sku is new to
-- the sale.
--
-- The sale's status is read under the same lock. The add is refused with
-- 'SaleNotOpen' unless the sale is CREATED or IN_PROGRESS, and a CREATED
-- sale moves to IN_PROGRESS in this transaction. A refused add leaves the
-- sale exactly as it was, status included.
--
-- The menu item row is locked before the stock check, so a second register
-- adding the same sku waits for this commit and then counts this
-- reservation. The check counts stock this sale already holds for the sku
-- as available to it. Throws 'InventoryException' after rolling back.
addTransactionItem ::
  DBPool ->
  UUID ->
  UUID ->
  Int ->
  UUID ->
  (UUID -> Int -> Either Text TransactionItem) ->
  IO AddedLine
addTransactionItem pool txId sku addQty newItemId priceLineAt = do
  newResId <- nextRandom
  now      <- getCurrentTime
  outcome <- runTransaction pool $ do
    mStatus <- Session.statement txId lockTransactionStatus
    if mStatus /= Just "CREATED" && mStatus /= Just "IN_PROGRESS"
      then pure (Left (SaleNotOpen txId))
      else do
        mTotal <- Session.statement sku lockMenuItemQuantity
        case mTotal of
          Nothing    -> pure (Left (ItemNotFound sku))
          Just total -> do
            existing <- Session.statement () $ run $ Rel8.select $ do
              ti <- each transactionItemSchema
              where_ $
                tiTransactionId ti ==. lit txId
                  &&. tiMenuItemSku ti ==. lit sku
              pure (tiId ti, tiQuantity ti)
            let replaced    = [(lineId, fromIntegral qty) | (lineId, qty :: Int32) <- existing]
                previousQty = Prelude.sum (map snd replaced) :: Int
                wantedQty   = previousQty + addQty
                lineId      = case replaced of
                  ((existingId, _) : _) -> existingId
                  []                    -> newItemId
            case priceLineAt lineId wantedQty of
              Left message -> pure (Left (LineRejected message))
              Right item   -> do
                reserved <- reservedQuantityS sku
                ownQuantities <- Session.statement () $ run $ Rel8.select $ do
                  r <- each reservationSchema
                  where_ $
                    resTransactionId r ==. lit txId
                      &&. resItemSku r ==. lit sku
                      &&. resStatus r ==. lit "Reserved"
                  pure (resQuantity r)
                let ownReserved = Prelude.sum (map fromIntegral (ownQuantities :: [Int32])) :: Int
                    available   = fromIntegral total - (reserved - ownReserved) :: Int
                if available < wantedQty
                  then pure (Left (InsufficientInventory sku wantedQty available))
                  else do
                    Session.statement () $
                      run_ $
                        Rel8.update $
                          Update
                            { target      = reservationSchema
                            , from        = pure ()
                            , set         = \() row -> row {resStatus = lit "Released"}
                            , updateWhere = \() row ->
                                resTransactionId row ==. lit txId
                                  &&. resItemSku row ==. lit sku
                                  &&. resStatus row ==. lit "Reserved"
                            , returning   = NoReturning
                            }
                    Session.statement () $
                      run_ $
                        Rel8.delete $
                          Delete
                            { from        = transactionItemSchema
                            , using       = pure ()
                            , deleteWhere = \() row ->
                                tiTransactionId row ==. lit txId
                                  &&. tiMenuItemSku row ==. lit sku
                            , returning   = NoReturning
                            }
                    insertItemS item
                    Session.statement () $
                      run_ $
                        Rel8.insert $
                          Insert
                            { into = reservationSchema
                            , rows =
                                values
                                  [ ReservationRow
                                      { resId            = lit newResId
                                      , resItemSku       = lit sku
                                      , resTransactionId = lit txId
                                      , resQuantity      = lit (fromIntegral wantedQty)
                                      , resStatus        = lit "Reserved"
                                      , resCreatedAt     = lit now
                                      }
                                  ]
                            , onConflict = Abort
                            , returning  = NoReturning
                            }
                    Session.statement () $
                      run_ $
                        Rel8.update $
                          Update
                            { target      = transactionSchema
                            , from        = pure ()
                            , set         = \() row -> row {txStatus = lit "IN_PROGRESS"}
                            , updateWhere = \() row ->
                                DB.Schema.txId row ==. lit txId
                                  &&. txStatus row ==. lit "CREATED"
                            , returning   = NoReturning
                            }
                    updateTotalsS txId
                    pure (Right (AddedLine item replaced))
  case outcome of
    Left e      -> throwIO e
    Right added -> pure added

-- | Releases the one reservation that belongs to this line, deletes the line
-- and updates the sale totals, in one SQL transaction.
--
-- A reservation row does not record which line created it. The match is on
-- sale, sku, "Reserved" status and quantity, and exactly one matching row is
-- released. 'addTransactionItem' keeps a sale to one line per sku, so the
-- match is normally unique.
deleteTransactionItem :: DBPool -> UUID -> IO ()
deleteTransactionItem pool itemId =
  runTransaction_ pool $ do
    itemRows <- Session.statement () $ run $ Rel8.select $ do
      ti <- each transactionItemSchema
      where_ $ tiId ti ==. lit itemId
      pure ti
    case itemRows of
      [item] -> do
        let ownerTxId = tiTransactionId item
        _ <- Session.statement ownerTxId lockTransactionRow
        candidates <- Session.statement () $ run $ Rel8.select $ do
          r <- each reservationSchema
          where_ $
            resTransactionId r ==. lit ownerTxId
              &&. resItemSku r ==. lit (tiMenuItemSku item)
              &&. resStatus r ==. lit "Reserved"
              &&. resQuantity r ==. lit (tiQuantity item)
          pure (resId r)
        case candidates of
          (reservationId : _) ->
            Session.statement () $
              run_ $
                Rel8.update $
                  Update
                    { target      = reservationSchema
                    , from        = pure ()
                    , set         = \() row -> row {resStatus = lit "Released"}
                    , updateWhere = \() row -> resId row ==. lit reservationId
                    , returning   = NoReturning
                    }
          [] -> pure ()
        Session.statement () $
          run_ $
            Rel8.delete $
              Delete
                { from        = transactionItemSchema
                , using       = pure ()
                , deleteWhere = \() row -> tiId row ==. lit itemId
                , returning   = NoReturning
                }
        updateTotalsS ownerTxId
      _ -> pure ()

-- | Records a payment on a sale, in one SQL transaction. The sale row is
-- locked and the payment is refused with 'SaleNotOpen' unless the sale is
-- IN_PROGRESS at that moment. Throws 'InventoryException' after rolling
-- back.
addPaymentTransaction :: DBPool -> PaymentTransaction -> IO PaymentTransaction
addPaymentTransaction pool payment = do
  let ownerTxId = paymentTransactionId payment
  outcome <- runTransaction pool $ do
    mStatus <- Session.statement ownerTxId lockTransactionStatus
    if mStatus /= Just "IN_PROGRESS"
      then pure (Left (SaleNotOpen ownerTxId))
      else do
        insertPaymentS payment
        pure (Right ())
  case outcome of
    Left e   -> throwIO e
    Right () -> pure payment

-- | Removes a payment, in one SQL transaction. The payment's sale row is
-- locked and the removal is refused with 'SaleNotOpen' unless the sale is
-- IN_PROGRESS at that moment. A payment id that does not exist is not an
-- error here. Throws 'InventoryException' after rolling back.
deletePaymentTransaction :: DBPool -> UUID -> IO ()
deletePaymentTransaction pool paymentId = do
  outcome <- runTransaction pool $ do
    owners <- Session.statement () $ run $ Rel8.select $ do
      p <- each paymentSchema
      where_ $ pymtId p ==. lit paymentId
      pure (pymtTransactionId p)
    case owners of
      [ownerTxId] -> do
        mStatus <- Session.statement ownerTxId lockTransactionStatus
        if mStatus /= Just "IN_PROGRESS"
          then pure (Left (SaleNotOpen ownerTxId))
          else do
            Session.statement () $
              run_ $
                Rel8.delete $
                  Delete
                    { from        = paymentSchema
                    , using       = pure ()
                    , deleteWhere = \() row -> pymtId row ==. lit paymentId
                    , returning   = NoReturning
                    }
            pure (Right ())
      _ -> pure (Right ())
  case outcome of
    Left e   -> throwIO e
    Right () -> pure ()

updateTransactionTotals :: DBPool -> UUID -> IO ()
updateTransactionTotals pool txId = runTransaction_ pool (updateTotalsS txId)

getTransactionIdByItemId :: DBPool -> UUID -> IO (Maybe UUID)
getTransactionIdByItemId pool itemId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    ti <- each transactionItemSchema
    where_ $ tiId ti ==. lit itemId
    pure (tiTransactionId ti)
  case rows of
    [txId] -> pure (Just txId)
    _      -> pure Nothing

getTransactionIdByPaymentId :: DBPool -> UUID -> IO (Maybe UUID)
getTransactionIdByPaymentId pool paymentId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    p <- each paymentSchema
    where_ $ pymtId p ==. lit paymentId
    pure (pymtTransactionId p)
  case rows of
    [txId] -> pure (Just txId)
    _      -> pure Nothing

getInventoryAvailability :: DBPool -> UUID -> IO (Maybe (Int, Int))
getInventoryAvailability pool sku = do
  totals <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    mi <- each menuItemSchema
    where_ $ menuSku mi ==. lit sku
    pure (menuQuantity mi)
  reservedSums <- runSession pool $
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn resQuantity) $ do
            r <- each reservationSchema
            where_ $
              resItemSku r ==. lit sku
                &&. resStatus r ==. lit "Reserved"
            pure r
  case totals of
    []          -> pure Nothing
    (total : _) ->
      let reserved = case reservedSums of (r : _) -> r; _ -> 0
       in pure $ Just (fromIntegral total, fromIntegral reserved)

txDomainToRow :: Transaction -> TransactionRow Expr
txDomainToRow tx =
  TransactionRow
    { txId                     = lit (transactionId tx)
    , txStatus                 = lit $ showStatus (transactionStatus tx)
    , txCreated                = lit (transactionCreated tx)
    , txCompleted              = lit (transactionCompleted tx)
    , txCustomerId             = lit (transactionCustomerId tx)
    , txEmployeeId             = lit (transactionEmployeeId tx)
    , txRegisterId             = lit (transactionRegisterId tx)
    , txLocationId             = lit (locationIdToUUID (transactionLocationId tx))
    , txSubtotal               = lit $ fromIntegral (transactionSubtotal tx)
    , txDiscountTotal          = lit $ fromIntegral (transactionDiscountTotal tx)
    , txTaxTotal               = lit $ fromIntegral (transactionTaxTotal tx)
    , txTotal                  = lit $ fromIntegral (transactionTotal tx)
    , txTransactionType        = lit $ showTransactionType (transactionType tx)
    , txIsVoided               = lit (transactionIsVoided tx)
    , txVoidReason             = lit (transactionVoidReason tx)
    , txIsRefunded             = lit (transactionIsRefunded tx)
    , txRefundReason           = lit (transactionRefundReason tx)
    , txReferenceTransactionId = lit (transactionReferenceTransactionId tx)
    , txNotes                  = lit (transactionNotes tx)
    }

txRowToDomain :: TransactionRow Result -> [TransactionItem] -> [PaymentTransaction] -> Transaction
txRowToDomain row items payments =
  Transaction
    { transactionId                     = DB.Schema.txId row
    , transactionStatus                 = parseTransactionStatus (T.unpack (txStatus row))
    , transactionCreated                = txCreated row
    , transactionCompleted              = txCompleted row
    , transactionCustomerId             = txCustomerId row
    , transactionEmployeeId             = txEmployeeId row
    , transactionRegisterId             = txRegisterId row
    , transactionLocationId             = LocationId (txLocationId row)
    , transactionItems                  = items
    , transactionPayments               = payments
    , transactionSubtotal               = fromIntegral (txSubtotal row)
    , transactionDiscountTotal          = fromIntegral (txDiscountTotal row)
    , transactionTaxTotal               = fromIntegral (txTaxTotal row)
    , transactionTotal                  = fromIntegral (txTotal row)
    , transactionType                   = parseTransactionType (T.unpack (txTransactionType row))
    , transactionIsVoided               = txIsVoided row
    , transactionVoidReason             = txVoidReason row
    , transactionIsRefunded             = txIsRefunded row
    , transactionRefundReason           = txRefundReason row
    , transactionReferenceTransactionId = txReferenceTransactionId row
    , transactionNotes                  = txNotes row
    }

tiDomainToRow :: TransactionItem -> TransactionItemRow Expr
tiDomainToRow ti =
  TransactionItemRow
    { tiId            = lit (transactionItemId ti)
    , tiTransactionId = lit (transactionItemTransactionId ti)
    , tiMenuItemSku   = lit (transactionItemMenuItemSku ti)
    , tiQuantity      = lit $ fromIntegral (transactionItemQuantity ti)
    , tiPricePerUnit  = lit $ fromIntegral (transactionItemPricePerUnit ti)
    , tiSubtotal      = lit $ fromIntegral (transactionItemSubtotal ti)
    , tiTotal         = lit $ fromIntegral (transactionItemTotal ti)
    }

itemRowToDomain :: TransactionItemRow Result -> [TaxRecord] -> [DiscountRecord] -> TransactionItem
itemRowToDomain row taxes discounts =
  TransactionItem
    { transactionItemId              = tiId row
    , transactionItemTransactionId   = tiTransactionId row
    , transactionItemMenuItemSku     = tiMenuItemSku row
    , transactionItemQuantity        = fromIntegral (tiQuantity row)
    , transactionItemPricePerUnit    = fromIntegral (tiPricePerUnit row)
    , transactionItemDiscounts       = discounts
    , transactionItemTaxes           = taxes
    , transactionItemSubtotal        = fromIntegral (tiSubtotal row)
    , transactionItemTotal           = fromIntegral (tiTotal row)
    }

taxDomainToRow :: UUID -> UUID -> TaxRecord -> TaxRow Expr
taxDomainToRow taxId itemId tax =
  TaxRow
    { taxRowId                = lit taxId
    , taxRowTransactionItemId = lit itemId
    , taxRowCategory          = lit $ showTaxCategory (taxCategory tax)
    , taxRowRate              = lit $ realToFrac (taxRate tax)
    , taxRowAmount            = lit $ fromIntegral (taxAmount tax)
    , taxRowDescription       = lit (taxDescription tax)
    }

taxRowToDomain :: TaxRow Result -> TaxRecord
taxRowToDomain row =
  TaxRecord
    { taxCategory    = parseTaxCategory (T.unpack (taxRowCategory row))
    , taxRate        = fromFloatDigits (taxRowRate row)
    , taxAmount      = fromIntegral (taxRowAmount row)
    , taxDescription = taxRowDescription row
    }

discountDomainToRow :: UUID -> UUID -> Maybe UUID -> DiscountRecord -> DiscountRow Expr
discountDomainToRow discId itemId mTxId discount =
  DiscountRow
    { discRowId                = lit discId
    , discRowTransactionItemId = lit (Just itemId)
    , discRowTransactionId     = lit mTxId
    , discRowType              = lit $ showDiscountType (discountType discount)
    , discRowAmount            = lit $ fromIntegral (discountAmount discount)
    , discRowPercent           = lit $ getDiscountPercent (discountType discount)
    , discRowReason            = lit (discountReason discount)
    , discRowApprovedBy        = lit (discountApprovedBy discount)
    }

getDiscountPercent :: DiscountType -> Maybe Double
getDiscountPercent (PercentOff pct) = Just (realToFrac pct)
getDiscountPercent _                = Nothing

discountRowToDomain :: DiscountRow Result -> DiscountRecord
discountRowToDomain row =
  DiscountRecord
    { discountType       = parseDiscountType
                             (discRowType row)
                             (discRowPercent row)
                             (fromIntegral (discRowAmount row))
    , discountAmount     = fromIntegral (discRowAmount row)
    , discountReason     = discRowReason row
    , discountApprovedBy = discRowApprovedBy row
    }

paymentDomainToRow :: PaymentTransaction -> PaymentRow Expr
paymentDomainToRow p =
  PaymentRow
    { pymtId                = lit (paymentId p)
    , pymtTransactionId     = lit (paymentTransactionId p)
    , pymtMethod            = lit $ showPaymentMethod (paymentMethod p)
    , pymtAmount            = lit $ fromIntegral (paymentAmount p)
    , pymtTendered          = lit $ fromIntegral (paymentTendered p)
    , pymtChange            = lit $ fromIntegral (paymentChange p)
    , pymtReference         = lit (paymentReference p)
    , pymtApproved          = lit (paymentApproved p)
    , pymtAuthorizationCode = lit (paymentAuthorizationCode p)
    }

paymentRowToDomain :: PaymentRow Result -> PaymentTransaction
paymentRowToDomain row =
  PaymentTransaction
    { paymentId               = pymtId row
    , paymentTransactionId    = pymtTransactionId row
    , paymentMethod           = parsePaymentMethod (T.unpack (pymtMethod row))
    , paymentAmount           = fromIntegral (pymtAmount row)
    , paymentTendered         = fromIntegral (pymtTendered row)
    , paymentChange           = fromIntegral (pymtChange row)
    , paymentReference        = pymtReference row
    , paymentApproved         = pymtApproved row
    , paymentAuthorizationCode = pymtAuthorizationCode row
    }

negateTransactionItem :: TransactionItem -> TransactionItem
negateTransactionItem ti =
  ti
    { transactionItemDiscounts = map negateDiscountRecord (transactionItemDiscounts ti)
    , transactionItemTaxes     = map negateTaxRecord (transactionItemTaxes ti)
    , transactionItemSubtotal  = negate (transactionItemSubtotal ti)
    , transactionItemTotal     = negate (transactionItemTotal ti)
    }

negateDiscountRecord :: DiscountRecord -> DiscountRecord
negateDiscountRecord d = d {discountAmount = negate (discountAmount d)}

negateTaxRecord :: TaxRecord -> TaxRecord
negateTaxRecord t = t {taxAmount = negate (taxAmount t)}

negatePaymentTransaction :: PaymentTransaction -> PaymentTransaction
negatePaymentTransaction p =
  p
    { paymentAmount   = negate (paymentAmount p)
    , paymentTendered = negate (paymentTendered p)
    , paymentChange   = negate (paymentChange p)
    }

showStatus :: TransactionStatus -> Text
showStatus Created    = "CREATED"
showStatus InProgress = "IN_PROGRESS"
showStatus Completed  = "COMPLETED"
showStatus Voided     = "VOIDED"
showStatus Refunded   = "REFUNDED"

showTransactionType :: TransactionType -> Text
showTransactionType Sale                = "SALE"
showTransactionType Return              = "RETURN"
showTransactionType Exchange            = "EXCHANGE"
showTransactionType InventoryAdjustment = "INVENTORY_ADJUSTMENT"
showTransactionType ManagerComp         = "MANAGER_COMP"
showTransactionType Administrative      = "ADMINISTRATIVE"

showPaymentMethod :: PaymentMethod -> Text
showPaymentMethod Cash        = "CASH"
showPaymentMethod Debit       = "DEBIT"
showPaymentMethod Credit      = "CREDIT"
showPaymentMethod ACH         = "ACH"
showPaymentMethod GiftCard    = "GIFT_CARD"
showPaymentMethod StoredValue = "STORED_VALUE"
showPaymentMethod Mixed       = "MIXED"
showPaymentMethod (Other t)   = "OTHER:" <> t

showTaxCategory :: TaxCategory -> Text
showTaxCategory RegularSalesTax = "REGULAR_SALES_TAX"
showTaxCategory ExciseTax       = "EXCISE_TAX"
showTaxCategory CannabisTax     = "CANNABIS_TAX"
showTaxCategory LocalTax        = "LOCAL_TAX"
showTaxCategory MedicalTax      = "MEDICAL_TAX"
showTaxCategory NoTax           = "NO_TAX"

showDiscountType :: DiscountType -> Text
showDiscountType (PercentOff _) = "PERCENT_OFF"
showDiscountType (AmountOff _)  = "AMOUNT_OFF"
showDiscountType BuyOneGetOne   = "BUY_ONE_GET_ONE"
showDiscountType (Custom _ _)   = "CUSTOM"

parseDiscountType :: Text -> Maybe Double -> Int -> DiscountType
parseDiscountType "PERCENT_OFF"     mPct _   = PercentOff (maybe 0 realToFrac mPct)
parseDiscountType "AMOUNT_OFF"      _    amt = AmountOff amt
parseDiscountType "BUY_ONE_GET_ONE" _    _   = BuyOneGetOne
parseDiscountType typ               _    amt = Custom typ amt

parseTransactionStatus :: String -> TransactionStatus
parseTransactionStatus "CREATED"     = Created
parseTransactionStatus "IN_PROGRESS" = InProgress
parseTransactionStatus "COMPLETED"   = Completed
parseTransactionStatus "VOIDED"      = Voided
parseTransactionStatus "REFUNDED"    = Refunded
parseTransactionStatus _             = Created

parseTransactionType :: String -> TransactionType
parseTransactionType "SALE"                 = Sale
parseTransactionType "RETURN"               = Return
parseTransactionType "EXCHANGE"             = Exchange
parseTransactionType "INVENTORY_ADJUSTMENT" = InventoryAdjustment
parseTransactionType "MANAGER_COMP"         = ManagerComp
parseTransactionType "ADMINISTRATIVE"       = Administrative
parseTransactionType _                      = Sale

parsePaymentMethod :: String -> PaymentMethod
parsePaymentMethod "CASH"         = Cash
parsePaymentMethod "Cash"         = Cash
parsePaymentMethod "DEBIT"        = Debit
parsePaymentMethod "Debit"        = Debit
parsePaymentMethod "CREDIT"       = Credit
parsePaymentMethod "Credit"       = Credit
parsePaymentMethod "ACH"          = ACH
parsePaymentMethod "GIFT_CARD"    = GiftCard
parsePaymentMethod "GiftCard"     = GiftCard
parsePaymentMethod "STORED_VALUE" = StoredValue
parsePaymentMethod "StoredValue"  = StoredValue
parsePaymentMethod "MIXED"        = Mixed
parsePaymentMethod "Mixed"        = Mixed
parsePaymentMethod s
  | take 6 s == "OTHER:" = Other (T.pack $ drop 6 s)
  | take 6 s == "Other:" = Other (T.pack $ drop 6 s)
  | otherwise            = Other (T.pack s)

parseTaxCategory :: String -> TaxCategory
parseTaxCategory "REGULAR_SALES_TAX" = RegularSalesTax
parseTaxCategory "RegularSalesTax"   = RegularSalesTax
parseTaxCategory "EXCISE_TAX"        = ExciseTax
parseTaxCategory "ExciseTax"         = ExciseTax
parseTaxCategory "CANNABIS_TAX"      = CannabisTax
parseTaxCategory "CannabisTax"       = CannabisTax
parseTaxCategory "LOCAL_TAX"         = LocalTax
parseTaxCategory "LocalTax"          = LocalTax
parseTaxCategory "MEDICAL_TAX"       = MedicalTax
parseTaxCategory "MedicalTax"        = MedicalTax
parseTaxCategory "NO_TAX"            = NoTax
parseTaxCategory "NoTax"             = NoTax
parseTaxCategory _                   = NoTax