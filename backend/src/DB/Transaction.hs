{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module DB.Transaction where

import Control.Exception (Exception, throwIO)
import Control.Monad (forM_)
import Data.Functor.Contravariant (contramap)
import Data.Int (Int32)
import Data.Scientific (fromFloatDigits)
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Data.Typeable (Typeable)
import Data.UUID (UUID, toString)
import Data.UUID.V4 (nextRandom)
import qualified Hasql.Session as Session
import Rel8
import System.IO (hPutStrLn, stderr)

import API.Transaction (
  CloseRegisterRequest (..),
  CloseRegisterResult (..),
  OpenRegisterRequest (..),
  Register (..),
 )
import DB.Database (DBPool, ddl, runSession)
import DB.Schema
import Types.Location (LocationId (..), locationIdToUUID)
import Types.Transaction

data InventoryException
  = ItemNotFound UUID
  | InsufficientInventory UUID Int Int
  deriving (Show, Typeable)

instance Exception InventoryException

createTransactionTables :: DBPool -> IO ()
createTransactionTables pool = do
  hPutStrLn stderr "Creating transaction tables..."
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
  hPutStrLn stderr "Transaction tables setup completed."

-- Queries

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

sel :: Query (MenuItemRow Expr) -> Query (MenuItemRow Expr)
sel = id

hydrateTx :: DBPool -> TransactionRow Result -> IO Transaction
hydrateTx pool txRow = do
  let txId = DB.Schema.txId txRow
  itemRows <- runSession pool $ Session.statement () $ run $ Rel8.select (itemsForTx txId)
  items <- mapM (hydrateItem pool) itemRows
  pymtRows <- runSession pool $ Session.statement () $ run $ Rel8.select (paymentsForTx txId)
  let payments = map paymentRowToDomain pymtRows
  pure $ txRowToDomain txRow items payments

hydrateItem :: DBPool -> TransactionItemRow Result -> IO TransactionItem
hydrateItem pool itemRow = do
  let itemId = tiId itemRow
  taxRows <- runSession pool $ Session.statement () $ run $ Rel8.select (taxesForItem itemId)
  discountRows <- runSession pool $ Session.statement () $ run $ Rel8.select (discountsForItem itemId)
  pure $
    itemRowToDomain
      itemRow
      (map taxRowToDomain taxRows)
      (map discountRowToDomain discountRows)

getAllActiveReservations :: DBPool -> IO [InventoryReservation]
getAllActiveReservations pool = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    res <- each reservationSchema
    where_ $ resStatus res ==. lit "Reserved"
    pure res
  pure $ map rowToReservation rows
  where
    rowToReservation row =
      InventoryReservation
        { reservationItemSku = resItemSku row
        , reservationTransactionId = resTransactionId row
        , reservationQuantity = fromIntegral (resQuantity row)
        , reservationStatus = resStatus row
        }

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
    _ -> pure Nothing

createTransaction :: DBPool -> Transaction -> IO Transaction
createTransaction pool tx = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = transactionSchema
            , rows = values [txDomainToRow tx]
            , onConflict = Abort
            , returning = NoReturning
            }
  items <- mapM (insertTransactionItem pool) (transactionItems tx)
  payments <- mapM (insertPaymentTransaction pool) (transactionPayments tx)
  pure tx {transactionItems = items, transactionPayments = payments}

insertTransactionItem :: DBPool -> TransactionItem -> IO TransactionItem
insertTransactionItem pool item = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = transactionItemSchema
            , rows = values [tiDomainToRow item]
            , onConflict = Abort
            , returning = NoReturning
            }
  discounts <-
    mapM
      (insertDiscount pool (transactionItemId item) Nothing)
      (transactionItemDiscounts item)
  taxes <-
    mapM
      (insertTax pool (transactionItemId item))
      (transactionItemTaxes item)
  pure item {transactionItemDiscounts = discounts, transactionItemTaxes = taxes}

insertDiscount :: DBPool -> UUID -> Maybe UUID -> DiscountRecord -> IO DiscountRecord
insertDiscount pool itemId mTxId discount = do
  discId <- nextRandom
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = discountSchema
            , rows = values [discountDomainToRow discId itemId mTxId discount]
            , onConflict = Abort
            , returning = NoReturning
            }
  pure discount

insertTax :: DBPool -> UUID -> TaxRecord -> IO TaxRecord
insertTax pool itemId tax = do
  taxId <- nextRandom
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = taxSchema
            , rows = values [taxDomainToRow taxId itemId tax]
            , onConflict = Abort
            , returning = NoReturning
            }
  pure tax

insertPaymentTransaction :: DBPool -> PaymentTransaction -> IO PaymentTransaction
insertPaymentTransaction pool payment = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = paymentSchema
            , rows = values [paymentDomainToRow payment]
            , onConflict = Abort
            , returning = NoReturning
            }
  pure payment

updateTransaction :: DBPool -> UUID -> Transaction -> IO Transaction
updateTransaction pool txId tx = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = transactionSchema
            , from = pure ()
            , set = \() _ -> txDomainToRow tx
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning = NoReturning
            }
  mTx <- getTransactionById pool txId
  case mTx of
    Just updated -> pure updated
    Nothing -> throwIO $ userError $ "Transaction not found after update: " <> show txId

voidTransaction :: DBPool -> UUID -> Text -> IO Transaction
voidTransaction pool txId reason = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = transactionSchema
            , from = pure ()
            , set = \() row ->
                row
                  { txStatus = lit "VOIDED"
                  , txIsVoided = lit True
                  , txVoidReason = lit (Just reason)
                  }
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning = NoReturning
            }
  mTx <- getTransactionById pool txId
  case mTx of
    Just tx -> pure tx
    Nothing -> throwIO $ userError $ "Transaction not found after void: " <> show txId

refundTransaction :: DBPool -> UUID -> Text -> IO Transaction
refundTransaction pool txId reason = do
  mOrig <- getTransactionById pool txId
  case mOrig of
    Nothing -> throwIO $ userError $ "Original transaction not found: " <> show txId
    Just orig -> do
      refundId <- nextRandom
      now <- getCurrentTime
      let refund =
            orig
              { transactionId = refundId
              , transactionStatus = Completed
              , transactionCreated = now
              , transactionCompleted = Just now
              , transactionSubtotal = negate (transactionSubtotal orig)
              , transactionDiscountTotal = negate (transactionDiscountTotal orig)
              , transactionTaxTotal = negate (transactionTaxTotal orig)
              , transactionTotal = negate (transactionTotal orig)
              , transactionType = Return
              , transactionIsVoided = False
              , transactionVoidReason = Nothing
              , transactionIsRefunded = False
              , transactionRefundReason = Nothing
              , transactionReferenceTransactionId = Just txId
              , transactionNotes =
                  Just $
                    "Refund for transaction " <> pack (toString txId) <> ": " <> reason
              , transactionItems = map negateTransactionItem (transactionItems orig)
              , transactionPayments = map negatePaymentTransaction (transactionPayments orig)
              }
      newRefund <- createTransaction pool refund
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.update $
              Update
                { target = transactionSchema
                , from = pure ()
                , set = \() row ->
                    row
                      { txIsRefunded = lit True
                      , txRefundReason = lit (Just reason)
                      }
                , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
                , returning = NoReturning
                }
      pure newRefund

clearTransaction :: DBPool -> UUID -> IO ()
clearTransaction pool txId = do
  hPutStrLn stderr $ "Cancelling transaction: " <> show txId
  runSession pool $ do
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = reservationSchema
            , from = pure ()
            , set = \() row -> row {resStatus = lit "Released"}
            , updateWhere = \() row ->
                resTransactionId row ==. lit txId
                  &&. resStatus row ==. lit "Reserved"
            , returning = NoReturning
            }
    Session.statement () $
      run_ $
        Rel8.delete $
          Delete
            { from = paymentSchema
            , using = pure ()
            , deleteWhere = \() row -> pymtTransactionId row ==. lit txId
            , returning = NoReturning
            }
    Session.statement () $
      run_ $
        Rel8.delete $
          Delete
            { from = transactionItemSchema
            , using = pure ()
            , deleteWhere = \() row -> tiTransactionId row ==. lit txId
            , returning = NoReturning
            }
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = transactionSchema
            , from = pure ()
            , set = \() row ->
                row
                  { txSubtotal = lit 0
                  , txDiscountTotal = lit 0
                  , txTaxTotal = lit 0
                  , txTotal = lit 0
                  , txStatus = lit "CREATED"
                  }
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning = NoReturning
            }
  hPutStrLn stderr "Transaction cancelled successfully."

finalizeTransaction :: DBPool -> UUID -> IO Transaction
finalizeTransaction pool txId = do
  reservations <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    res <- each reservationSchema
    where_ $
      resTransactionId res ==. lit txId
        &&. resStatus res ==. lit "Reserved"
    pure res
  forM_ reservations $ \res -> do
    let
      sku = resItemSku res
      qty = resQuantity res
    runSession pool $ do
      Session.statement () $
        run_ $
          Rel8.update $
            Update
              { target = menuItemSchema
              , from = pure ()
              , set = \() row -> row {menuQuantity = menuQuantity row - lit qty}
              , updateWhere = \() row -> menuSku row ==. lit sku
              , returning = NoReturning
              }
      Session.statement () $
        run_ $
          Rel8.update $
            Update
              { target = reservationSchema
              , from = pure ()
              , set = \() row -> row {resStatus = lit "Completed"}
              , updateWhere = \() row ->
                  resTransactionId row ==. lit txId
                    &&. resItemSku row ==. lit sku
              , returning = NoReturning
              }
  now <- getCurrentTime
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = transactionSchema
            , from = pure ()
            , set = \() row ->
                row
                  { txStatus = lit "COMPLETED"
                  , txCompleted = lit (Just now)
                  }
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning = NoReturning
            }
  mTx <- getTransactionById pool txId
  case mTx of
    Just tx -> pure tx
    Nothing -> throwIO $ userError $ "Transaction not found after finalization: " <> show txId

addTransactionItem :: DBPool -> TransactionItem -> IO TransactionItem
addTransactionItem pool item = do
  let
    sku = transactionItemMenuItemSku item
    qty = transactionItemQuantity item

  -- Two separate queries; aggregate always returns exactly one row for Full fold.
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
    [] -> throwIO $ ItemNotFound sku
    (total : _) -> do
      let
        reserved = case reservedSums of (r : _) -> r; _ -> 0
        available = fromIntegral total - fromIntegral reserved :: Int
      if available < qty
        then throwIO $ InsufficientInventory sku qty available
        else do
          newItem <- insertTransactionItem pool item
          resId <- nextRandom
          now <- getCurrentTime
          runSession pool $
            Session.statement () $
              run_ $
                Rel8.insert $
                  Insert
                    { into = reservationSchema
                    , rows =
                        values
                          [ ReservationRow
                              { resId = lit resId
                              , resItemSku = lit sku
                              , resTransactionId = lit (transactionItemTransactionId item)
                              , resQuantity = lit (fromIntegral qty)
                              , resStatus = lit "Reserved"
                              , resCreatedAt = lit now
                              }
                          ]
                    , onConflict = Abort
                    , returning = NoReturning
                    }
          pure newItem

deleteTransactionItem :: DBPool -> UUID -> IO ()
deleteTransactionItem pool itemId = do
  itemRows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    ti <- each transactionItemSchema
    where_ $ tiId ti ==. lit itemId
    pure ti
  case itemRows of
    [item] ->
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.update $
              Update
                { target = reservationSchema
                , from = pure ()
                , set = \() row -> row {resStatus = lit "Released"}
                , updateWhere = \() row ->
                    resItemSku row ==. lit (tiMenuItemSku item)
                      &&. resTransactionId row ==. lit (tiTransactionId item)
                , returning = NoReturning
                }
    _ -> pure ()
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.delete $
          Delete
            { from = transactionItemSchema
            , using = pure ()
            , deleteWhere = \() row -> tiId row ==. lit itemId
            , returning = NoReturning
            }
  case itemRows of
    [item] -> updateTransactionTotals pool (tiTransactionId item)
    _ -> pure ()

addPaymentTransaction :: DBPool -> PaymentTransaction -> IO PaymentTransaction
addPaymentTransaction pool payment = do
  p <- insertPaymentTransaction pool payment
  updateTransactionPaymentStatus pool (paymentTransactionId payment)
  pure p

deletePaymentTransaction :: DBPool -> UUID -> IO ()
deletePaymentTransaction pool paymentId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    p <- each paymentSchema
    where_ $ pymtId p ==. lit paymentId
    pure p
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.delete $
          Delete
            { from = paymentSchema
            , using = pure ()
            , deleteWhere = \() row -> pymtId row ==. lit paymentId
            , returning = NoReturning
            }
  case rows of
    [p] -> updateTransactionPaymentStatus pool (pymtTransactionId p)
    _ -> pure ()

-- aggregate :: Aggregator i a -> Query i -> Query a
-- Returns exactly one row (identity value if query is empty).
updateTransactionTotals :: DBPool -> UUID -> IO ()
updateTransactionTotals pool txId = do
  subtotals <- runSession pool $
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn tiSubtotal) $ do
            ti <- each transactionItemSchema
            where_ $ tiTransactionId ti ==. lit txId
            pure ti
  let subtotal :: Int32 = case subtotals of (s : _) -> s; _ -> 0

  discountTotals <- runSession pool $
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn discRowAmount) $ do
            d <- each discountSchema
            ti <- each transactionItemSchema
            where_ $
              discRowTransactionItemId d ==. nullify (tiId ti)
                &&. tiTransactionId ti ==. lit txId
            pure d
  let discountTotal :: Int32 = case discountTotals of (d : _) -> d; _ -> 0

  taxTotals <- runSession pool $
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn taxRowAmount) $ do
            t <- each taxSchema
            ti <- each transactionItemSchema
            where_ $
              taxRowTransactionItemId t ==. tiId ti
                &&. tiTransactionId ti ==. lit txId
            pure t
  let taxTotal :: Int32 = case taxTotals of (t : _) -> t; _ -> 0

  let total = subtotal - discountTotal + taxTotal
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = transactionSchema
            , from = pure ()
            , set = \() row ->
                row
                  { txSubtotal = lit subtotal
                  , txDiscountTotal = lit discountTotal
                  , txTaxTotal = lit taxTotal
                  , txTotal = lit total
                  }
            , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
            , returning = NoReturning
            }

updateTransactionPaymentStatus :: DBPool -> UUID -> IO ()
updateTransactionPaymentStatus pool txId = do
  totals <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    tx <- each transactionSchema
    where_ $ DB.Schema.txId tx ==. lit txId
    pure (txTotal tx)
  pymtSums <- runSession pool $
    Session.statement () $
      run $
        Rel8.select $
          aggregate (sumOn pymtAmount) $ do
            p <- each paymentSchema
            where_ $ pymtTransactionId p ==. lit txId
            pure p
  case (totals, pymtSums) of
    (total : _, paid : _) -> do
      let status = if paid >= total then "COMPLETED" else "IN_PROGRESS" :: Text
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.update $
              Update
                { target = transactionSchema
                , from = pure ()
                , set = \() row -> row {txStatus = lit status}
                , updateWhere = \() row -> DB.Schema.txId row ==. lit txId
                , returning = NoReturning
                }
    _ -> pure ()

getTransactionIdByItemId :: DBPool -> UUID -> IO (Maybe UUID)
getTransactionIdByItemId pool itemId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    ti <- each transactionItemSchema
    where_ $ tiId ti ==. lit itemId
    pure (tiTransactionId ti)
  case rows of
    [txId] -> pure (Just txId)
    _ -> pure Nothing

getTransactionIdByPaymentId :: DBPool -> UUID -> IO (Maybe UUID)
getTransactionIdByPaymentId pool paymentId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    p <- each paymentSchema
    where_ $ pymtId p ==. lit paymentId
    pure (pymtTransactionId p)
  case rows of
    [txId] -> pure (Just txId)
    _ -> pure Nothing

getAllRegisters :: DBPool -> IO [Register]
getAllRegisters pool = do
  -- asc :: Order (Expr a) — a value; contramap projects into it
  rows <-
    runSession pool $
      Session.statement () $
        run $
          Rel8.select $
            orderBy (contramap regName asc) (each registerSchema)
  pure $ map regRowToDomain rows

getRegisterById :: DBPool -> UUID -> IO (Maybe Register)
getRegisterById pool regId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    r <- each registerSchema
    where_ $ DB.Schema.regId r ==. lit regId
    pure r
  case rows of
    [row] -> pure $ Just $ regRowToDomain row
    _ -> pure Nothing

createRegister :: DBPool -> Register -> IO Register
createRegister pool reg = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = registerSchema
            , rows = values [regDomainToRow reg]
            , onConflict = Abort
            , returning = NoReturning
            }
  mReg <- getRegisterById pool (registerId reg)
  case mReg of
    Just r -> pure r
    Nothing -> throwIO $ userError "INSERT RETURNING produced no rows"

updateRegister :: DBPool -> UUID -> Register -> IO Register
updateRegister pool regId reg = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = registerSchema
            , from = pure ()
            , set = \() _ -> regDomainToRow reg
            , updateWhere = \() row -> DB.Schema.regId row ==. lit regId
            , returning = NoReturning
            }
  mReg <- getRegisterById pool regId
  case mReg of
    Just r -> pure r
    Nothing -> throwIO $ userError $ "Register not found after update: " <> show regId

openRegister :: DBPool -> UUID -> OpenRegisterRequest -> IO Register
openRegister pool regId req = do
  now <- getCurrentTime
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target = registerSchema
            , from = pure ()
            , set = \() row ->
                row
                  { regIsOpen = lit True
                  , regCurrentDrawerAmount = lit $ fromIntegral (openRegisterStartingCash req)
                  , regExpectedDrawerAmount = lit $ fromIntegral (openRegisterStartingCash req)
                  , regOpenedAt = lit (Just now)
                  , regOpenedBy = lit (Just (openRegisterEmployeeId req))
                  }
            , updateWhere = \() row -> DB.Schema.regId row ==. lit regId
            , returning = NoReturning
            }
  mReg <- getRegisterById pool regId
  case mReg of
    Just r -> pure r
    Nothing -> throwIO $ userError $ "Register not found after opening: " <> show regId

closeRegister :: DBPool -> UUID -> CloseRegisterRequest -> IO CloseRegisterResult
closeRegister pool regId req = do
  mReg <- getRegisterById pool regId
  case mReg of
    Nothing -> throwIO $ userError $ "Register not found: " <> show regId
    Just reg -> do
      now <- getCurrentTime
      let variance = registerExpectedDrawerAmount reg - closeRegisterCountedCash req
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.update $
              Update
                { target = registerSchema
                , from = pure ()
                , set = \() row ->
                    row
                      { regIsOpen = lit False
                      , regCurrentDrawerAmount = lit $ fromIntegral (closeRegisterCountedCash req)
                      , regLastTransactionTime = lit (Just now)
                      }
                , updateWhere = \() row -> DB.Schema.regId row ==. lit regId
                , returning = NoReturning
                }
      mUpdated <- getRegisterById pool regId
      case mUpdated of
        Nothing -> throwIO $ userError $ "Register not found after closing: " <> show regId
        Just updated ->
          pure
            CloseRegisterResult
              { closeRegisterResultRegister = updated
              , closeRegisterResultVariance = variance
              }

-- Domain <-> row conversions

txDomainToRow :: Transaction -> TransactionRow Expr
txDomainToRow tx =
  TransactionRow
    { txId = lit (transactionId tx)
    , txStatus = lit $ showStatus (transactionStatus tx)
    , txCreated = lit (transactionCreated tx)
    , txCompleted = lit (transactionCompleted tx)
    , txCustomerId = lit (transactionCustomerId tx)
    , txEmployeeId = lit (transactionEmployeeId tx)
    , txRegisterId = lit (transactionRegisterId tx)
    , txLocationId = lit (locationIdToUUID (transactionLocationId tx))
    , txSubtotal = lit $ fromIntegral (transactionSubtotal tx)
    , txDiscountTotal = lit $ fromIntegral (transactionDiscountTotal tx)
    , txTaxTotal = lit $ fromIntegral (transactionTaxTotal tx)
    , txTotal = lit $ fromIntegral (transactionTotal tx)
    , txTransactionType = lit $ showTransactionType (transactionType tx)
    , txIsVoided = lit (transactionIsVoided tx)
    , txVoidReason = lit (transactionVoidReason tx)
    , txIsRefunded = lit (transactionIsRefunded tx)
    , txRefundReason = lit (transactionRefundReason tx)
    , txReferenceTransactionId = lit (transactionReferenceTransactionId tx)
    , txNotes = lit (transactionNotes tx)
    }

txRowToDomain :: TransactionRow Result -> [TransactionItem] -> [PaymentTransaction] -> Transaction
txRowToDomain row items payments =
  Transaction
    { transactionId = DB.Schema.txId row
    , transactionStatus = parseTransactionStatus (T.unpack (txStatus row))
    , transactionCreated = txCreated row
    , transactionCompleted = txCompleted row
    , transactionCustomerId = txCustomerId row
    , transactionEmployeeId = txEmployeeId row
    , transactionRegisterId = txRegisterId row
    , transactionLocationId = LocationId (txLocationId row)
    , transactionItems = items
    , transactionPayments = payments
    , transactionSubtotal = fromIntegral (txSubtotal row)
    , transactionDiscountTotal = fromIntegral (txDiscountTotal row)
    , transactionTaxTotal = fromIntegral (txTaxTotal row)
    , transactionTotal = fromIntegral (txTotal row)
    , transactionType = parseTransactionType (T.unpack (txTransactionType row))
    , transactionIsVoided = txIsVoided row
    , transactionVoidReason = txVoidReason row
    , transactionIsRefunded = txIsRefunded row
    , transactionRefundReason = txRefundReason row
    , transactionReferenceTransactionId = txReferenceTransactionId row
    , transactionNotes = txNotes row
    }

tiDomainToRow :: TransactionItem -> TransactionItemRow Expr
tiDomainToRow ti =
  TransactionItemRow
    { tiId = lit (transactionItemId ti)
    , tiTransactionId = lit (transactionItemTransactionId ti)
    , tiMenuItemSku = lit (transactionItemMenuItemSku ti)
    , tiQuantity = lit $ fromIntegral (transactionItemQuantity ti)
    , tiPricePerUnit = lit $ fromIntegral (transactionItemPricePerUnit ti)
    , tiSubtotal = lit $ fromIntegral (transactionItemSubtotal ti)
    , tiTotal = lit $ fromIntegral (transactionItemTotal ti)
    }

itemRowToDomain :: TransactionItemRow Result -> [TaxRecord] -> [DiscountRecord] -> TransactionItem
itemRowToDomain row taxes discounts =
  TransactionItem
    { transactionItemId = tiId row
    , transactionItemTransactionId = tiTransactionId row
    , transactionItemMenuItemSku = tiMenuItemSku row
    , transactionItemQuantity = fromIntegral (tiQuantity row)
    , transactionItemPricePerUnit = fromIntegral (tiPricePerUnit row)
    , transactionItemDiscounts = discounts
    , transactionItemTaxes = taxes
    , transactionItemSubtotal = fromIntegral (tiSubtotal row)
    , transactionItemTotal = fromIntegral (tiTotal row)
    }

taxDomainToRow :: UUID -> UUID -> TaxRecord -> TaxRow Expr
taxDomainToRow taxId itemId tax =
  TaxRow
    { taxRowId = lit taxId
    , taxRowTransactionItemId = lit itemId
    , taxRowCategory = lit $ showTaxCategory (taxCategory tax)
    , taxRowRate = lit $ realToFrac (taxRate tax)
    , taxRowAmount = lit $ fromIntegral (taxAmount tax)
    , taxRowDescription = lit (taxDescription tax)
    }

taxRowToDomain :: TaxRow Result -> TaxRecord
taxRowToDomain row =
  TaxRecord
    { taxCategory = parseTaxCategory (T.unpack (taxRowCategory row))
    , taxRate = fromFloatDigits (taxRowRate row)
    , taxAmount = fromIntegral (taxRowAmount row)
    , taxDescription = taxRowDescription row
    }

discountDomainToRow :: UUID -> UUID -> Maybe UUID -> DiscountRecord -> DiscountRow Expr
discountDomainToRow discId itemId mTxId discount =
  DiscountRow
    { discRowId = lit discId
    , discRowTransactionItemId = lit (Just itemId)
    , discRowTransactionId = lit mTxId
    , discRowType = lit $ showDiscountType (discountType discount)
    , discRowAmount = lit $ fromIntegral (discountAmount discount)
    , discRowPercent = lit $ getDiscountPercent (discountType discount)
    , discRowReason = lit (discountReason discount)
    , discRowApprovedBy = lit (discountApprovedBy discount)
    }

getDiscountPercent :: DiscountType -> Maybe Double
getDiscountPercent (PercentOff pct) = Just (realToFrac pct)
getDiscountPercent _ = Nothing

discountRowToDomain :: DiscountRow Result -> DiscountRecord
discountRowToDomain row =
  DiscountRecord
    { discountType = parseDiscountType (discRowType row) (fmap round (discRowPercent row))
    , discountAmount = fromIntegral (discRowAmount row)
    , discountReason = discRowReason row
    , discountApprovedBy = discRowApprovedBy row
    }

paymentDomainToRow :: PaymentTransaction -> PaymentRow Expr
paymentDomainToRow p =
  PaymentRow
    { pymtId = lit (paymentId p)
    , pymtTransactionId = lit (paymentTransactionId p)
    , pymtMethod = lit $ showPaymentMethod (paymentMethod p)
    , pymtAmount = lit $ fromIntegral (paymentAmount p)
    , pymtTendered = lit $ fromIntegral (paymentTendered p)
    , pymtChange = lit $ fromIntegral (paymentChange p)
    , pymtReference = lit (paymentReference p)
    , pymtApproved = lit (paymentApproved p)
    , pymtAuthorizationCode = lit (paymentAuthorizationCode p)
    }

paymentRowToDomain :: PaymentRow Result -> PaymentTransaction
paymentRowToDomain row =
  PaymentTransaction
    { paymentId = pymtId row
    , paymentTransactionId = pymtTransactionId row
    , paymentMethod = parsePaymentMethod (T.unpack (pymtMethod row))
    , paymentAmount = fromIntegral (pymtAmount row)
    , paymentTendered = fromIntegral (pymtTendered row)
    , paymentChange = fromIntegral (pymtChange row)
    , paymentReference = pymtReference row
    , paymentApproved = pymtApproved row
    , paymentAuthorizationCode = pymtAuthorizationCode row
    }

regDomainToRow :: Register -> RegisterRow Expr
regDomainToRow r =
  RegisterRow
    { regId = lit (registerId r)
    , regName = lit (registerName r)
    , regLocationId = lit (locationIdToUUID (registerLocationId r))
    , regIsOpen = lit (registerIsOpen r)
    , regCurrentDrawerAmount = lit $ fromIntegral (registerCurrentDrawerAmount r)
    , regExpectedDrawerAmount = lit $ fromIntegral (registerExpectedDrawerAmount r)
    , regOpenedAt = lit (registerOpenedAt r)
    , regOpenedBy = lit (registerOpenedBy r)
    , regLastTransactionTime = lit (registerLastTransactionTime r)
    }

regRowToDomain :: RegisterRow Result -> Register
regRowToDomain row =
  Register
    { registerId = DB.Schema.regId row
    , registerName = regName row
    , registerLocationId = LocationId (regLocationId row)
    , registerIsOpen = regIsOpen row
    , registerCurrentDrawerAmount = fromIntegral (regCurrentDrawerAmount row)
    , registerExpectedDrawerAmount = fromIntegral (regExpectedDrawerAmount row)
    , registerOpenedAt = regOpenedAt row
    , registerOpenedBy = regOpenedBy row
    , registerLastTransactionTime = regLastTransactionTime row
    }

negateTransactionItem :: TransactionItem -> TransactionItem
negateTransactionItem ti =
  ti
    { transactionItemDiscounts = map negateDiscountRecord (transactionItemDiscounts ti)
    , transactionItemTaxes = map negateTaxRecord (transactionItemTaxes ti)
    , transactionItemSubtotal = negate (transactionItemSubtotal ti)
    , transactionItemTotal = negate (transactionItemTotal ti)
    }

negateDiscountRecord :: DiscountRecord -> DiscountRecord
negateDiscountRecord d = d {discountAmount = negate (discountAmount d)}

negateTaxRecord :: TaxRecord -> TaxRecord
negateTaxRecord t = t {taxAmount = negate (taxAmount t)}

negatePaymentTransaction :: PaymentTransaction -> PaymentTransaction
negatePaymentTransaction p =
  p
    { paymentAmount = negate (paymentAmount p)
    , paymentTendered = negate (paymentTendered p)
    , paymentChange = negate (paymentChange p)
    }

showStatus :: TransactionStatus -> Text
showStatus Created = "CREATED"
showStatus InProgress = "IN_PROGRESS"
showStatus Completed = "COMPLETED"
showStatus Voided = "VOIDED"
showStatus Refunded = "REFUNDED"

showTransactionType :: TransactionType -> Text
showTransactionType Sale = "SALE"
showTransactionType Return = "RETURN"
showTransactionType Exchange = "EXCHANGE"
showTransactionType InventoryAdjustment = "INVENTORY_ADJUSTMENT"
showTransactionType ManagerComp = "MANAGER_COMP"
showTransactionType Administrative = "ADMINISTRATIVE"

showPaymentMethod :: PaymentMethod -> Text
showPaymentMethod Cash = "CASH"
showPaymentMethod Debit = "DEBIT"
showPaymentMethod Credit = "CREDIT"
showPaymentMethod ACH = "ACH"
showPaymentMethod GiftCard = "GIFT_CARD"
showPaymentMethod StoredValue = "STORED_VALUE"
showPaymentMethod Mixed = "MIXED"
showPaymentMethod (Other t) = "OTHER:" <> t

showTaxCategory :: TaxCategory -> Text
showTaxCategory RegularSalesTax = "REGULAR_SALES_TAX"
showTaxCategory ExciseTax = "EXCISE_TAX"
showTaxCategory CannabisTax = "CANNABIS_TAX"
showTaxCategory LocalTax = "LOCAL_TAX"
showTaxCategory MedicalTax = "MEDICAL_TAX"
showTaxCategory NoTax = "NO_TAX"

showDiscountType :: DiscountType -> Text
showDiscountType (PercentOff _) = "PERCENT_OFF"
showDiscountType (AmountOff _) = "AMOUNT_OFF"
showDiscountType BuyOneGetOne = "BUY_ONE_GET_ONE"
showDiscountType (Custom _ _) = "CUSTOM"

parseDiscountType :: Text -> Maybe Int -> DiscountType
parseDiscountType "PERCENT_OFF" (Just v) = PercentOff (fromIntegral v / 100)
parseDiscountType "AMOUNT_OFF" (Just v) = AmountOff v
parseDiscountType "BUY_ONE_GET_ONE" _ = BuyOneGetOne
parseDiscountType typ (Just v) = Custom typ v
parseDiscountType _ _ = AmountOff 0

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
    [] -> pure Nothing
    (total : _) ->
      let reserved = case reservedSums of (r : _) -> r; _ -> 0
       in pure $ Just (fromIntegral total, fromIntegral reserved)

createInventoryReservation :: DBPool -> UUID -> UUID -> UUID -> Int -> UTCTime -> IO ()
createInventoryReservation pool reservationId itemSku txId qty now =
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into = reservationSchema
            , rows =
                values
                  [ ReservationRow
                      { resId = lit reservationId
                      , resItemSku = lit itemSku
                      , resTransactionId = lit txId
                      , resQuantity = lit (fromIntegral qty)
                      , resStatus = lit "Reserved"
                      , resCreatedAt = lit now
                      }
                  ]
            , onConflict = Abort
            , returning = NoReturning
            }

releaseInventoryReservation :: DBPool -> UUID -> IO Bool
releaseInventoryReservation pool reservationId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    r <- each reservationSchema
    where_ $
      DB.Schema.resId r ==. lit reservationId
        &&. resStatus r ==. lit "Reserved"
    pure r
  case rows of
    [] -> pure False
    _ -> do
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.update $
              Update
                { target = reservationSchema
                , from = pure ()
                , set = \() row -> row {resStatus = lit "Released"}
                , updateWhere = \() row -> DB.Schema.resId row ==. lit reservationId
                , returning = NoReturning
                }
      pure True
