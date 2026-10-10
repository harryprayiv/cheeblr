{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

-- | Reads and writes of sales. The tables and constraints are in
-- "DB.Transaction.Tables" and the row conversions are in
-- "DB.Transaction.Rows". Both are re-exported here, so importers of this
-- module see the same names as before the split.
module DB.Transaction (
  module DB.Transaction,
  module DB.Transaction.Rows,
  module DB.Transaction.Tables,
) where

import Control.Exception (Exception, throwIO)
import Control.Monad (forM_, when)
import Control.Monad.IO.Class (liftIO)
import Data.Int (Int32)
import Data.List (sortOn)
import Data.Text (Text)
import Data.Time (getCurrentTime)
import Data.Typeable (Typeable)
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import qualified Hasql.Decoders as Decoders
import qualified Hasql.Encoders as Encoders
import qualified Hasql.Session as Session
import qualified Hasql.Statement as Statement
import Rel8

import DB.Database (DBPool, runSession, runTransaction, runTransaction_)
import DB.Schema
import DB.Transaction.Rows
import DB.Transaction.Tables
import Domain.SaleRules (finalizeProblems)
import Domain.StockPolicy (RestockPolicy (..))
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

-- | Adds the quantity of every line of a sale back to its item's stock.
--
-- The caller holds the sale's row lock and has decided, from the status
-- read under that lock, that the sale was COMPLETED. That is the only
-- status in which the sale's quantities have been taken out of stock.
--
-- The item rows are updated in ascending sku order, which is the lock
-- order every other stock write uses. A sale holds at most one line per
-- sku, so each item is updated once. A line whose item no longer exists
-- updates nothing.
restockSaleS :: UUID -> Session.Session ()
restockSaleS saleId = do
  soldLines <- Session.statement () $ run $ Rel8.select $ do
    ti <- each transactionItemSchema
    where_ $ tiTransactionId ti ==. lit saleId
    pure (tiMenuItemSku ti, tiQuantity ti)
  forM_ (sortOn fst (soldLines :: [(UUID, Int32)])) $ \(sku, qty) ->
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target      = menuItemSchema
            , from        = pure ()
            , set         = \() row -> row {menuQuantity = menuQuantity row + lit qty}
            , updateWhere = \() row -> menuSku row ==. lit sku
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

-- | Voids a sale, in one SQL transaction.
--
-- The sale row is locked and its status is read under the lock. A sale
-- that is CREATED, IN_PROGRESS or COMPLETED is marked voided and every
-- reservation it still holds is released. A sale in any other status, or a
-- sale that does not exist, is refused with 'SaleNotOpen' and nothing
-- changes. Throws 'InventoryException' after rolling back.
--
-- Stock: a sale that was CREATED or IN_PROGRESS never left stock, so
-- releasing its reservations is all there is to do. A COMPLETED sale has
-- had its quantities taken out of stock. Whether voiding it puts them back
-- is the caller's @restock@ argument, which comes from configuration:
-- 'ReturnToStock' adds every line's quantity back in this same SQL
-- transaction, 'DoNotRestock' leaves stock alone. A voided sale cannot be
-- voided or refunded again, so stock is put back at most once.
voidTransaction :: DBPool -> RestockPolicy -> UUID -> Text -> IO Transaction
voidTransaction pool restock txId reason = do
  outcome <- runTransaction pool $ do
    mStatus <- Session.statement txId lockTransactionStatus
    if mStatus /= Just "CREATED" && mStatus /= Just "IN_PROGRESS" && mStatus /= Just "COMPLETED"
      then pure (Left (SaleNotOpen txId))
      else do
        releaseReservedForTxS txId
        when (mStatus == Just "COMPLETED" && restock == ReturnToStock) $
          restockSaleS txId
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
        pure (Right ())
  case outcome of
    Left e   -> throwIO e
    Right () -> do
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

-- | Empties an open sale, in one SQL transaction.
--
-- The sale row is locked and its status is read under the lock. A sale
-- that is CREATED or IN_PROGRESS has its reservations released, its lines
-- and payments deleted, its totals set to zero and its status set back to
-- CREATED. A sale in any other status, or a sale that does not exist, is
-- refused with 'SaleNotOpen' and nothing changes. Finalize takes the same
-- lock, so a clear cannot empty a sale that was completed in between.
-- Throws 'InventoryException' after rolling back.
clearTransaction :: DBPool -> UUID -> IO ()
clearTransaction pool txId = do
  outcome <- runTransaction pool $ do
    mStatus <- Session.statement txId lockTransactionStatus
    if mStatus /= Just "CREATED" && mStatus /= Just "IN_PROGRESS"
      then pure (Left (SaleNotOpen txId))
      else do
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
        pure (Right ())
  case outcome of
    Left e   -> throwIO e
    Right () -> pure ()

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

-- | Removes a line from a sale, in one SQL transaction: releases the one
-- reservation that belongs to the line, deletes the line and updates the
-- sale totals.
--
-- The line's sale is found first, without a lock. Then the sale row is
-- locked, its status is read under the lock, and the line is read again.
-- The removal is refused with 'SaleNotOpen' unless the sale is IN_PROGRESS
-- at that moment. Finalize takes the same lock, so a line cannot be removed
-- from a sale that was completed in between. A line id that does not
-- exist, or a line that was removed while this call waited for the lock,
-- is not an error here. Throws 'InventoryException' after rolling back.
--
-- A reservation row does not record which line created it. The match is on
-- sale, sku, "Reserved" status and quantity, and exactly one matching row is
-- released. 'addTransactionItem' keeps a sale to one line per sku, and a
-- unique index keeps a sale to one live reservation per sku, so the match
-- is unique.
deleteTransactionItem :: DBPool -> UUID -> IO ()
deleteTransactionItem pool itemId = do
  outcome <- runTransaction pool $ do
    owners <- Session.statement () $ run $ Rel8.select $ do
      ti <- each transactionItemSchema
      where_ $ tiId ti ==. lit itemId
      pure (tiTransactionId ti)
    case owners of
      [ownerTxId] -> do
        mStatus <- Session.statement ownerTxId lockTransactionStatus
        if mStatus /= Just "IN_PROGRESS"
          then pure (Left (SaleNotOpen ownerTxId))
          else do
            itemRows <- Session.statement () $ run $ Rel8.select $ do
              ti <- each transactionItemSchema
              where_ $ tiId ti ==. lit itemId
              pure ti
            case itemRows of
              [item] -> do
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
                pure (Right ())
              _ -> pure (Right ())
      _ -> pure (Right ())
  case outcome of
    Left e   -> throwIO e
    Right () -> pure ()

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