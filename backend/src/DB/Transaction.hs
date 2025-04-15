{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# OPTIONS_GHC -Wno-unused-do-bind #-}
{-# OPTIONS_GHC -Wno-unused-matches #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module DB.Transaction where

import Control.Monad.IO.Class (liftIO)
import Data.Pool (Pool, withResource)  -- Add withResource to the import
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Data.UUID (UUID, toString)
import Data.UUID.V4 (nextRandom)
import Database.PostgreSQL.Simple
  ( Connection
  , Only(..)

  , execute
  , execute_

  , query
  , query_, FromRow

  )
import Database.PostgreSQL.Simple.FromRow ( FromRow(..), field )
import Database.PostgreSQL.Simple.SqlQQ (sql)
import System.IO (hPutStrLn, stderr)

import Types.Transaction
    ( DiscountRecord(discountAmount, discountType, discountReason,
                     discountApprovedBy),
      DiscountType(..),
      PaymentMethod(..),
      PaymentTransaction(paymentTransactionId, paymentMethod,
                         paymentReference, paymentApproved, paymentAuthorizationCode,
                         paymentId, paymentAmount, paymentTendered, paymentChange),
      TaxCategory(..),
      TaxRecord(taxAmount, taxCategory, taxRate, taxDescription),
      Transaction(..),
      TransactionItem(..),
      TransactionStatus(..),
      TransactionType(..) )
import API.Transaction (
    OpenRegisterRequest(..),
    Register(..),
    CloseRegisterRequest(..),
    CloseRegisterResult(CloseRegisterResult, closeRegisterResultRegister, closeRegisterResultVariance)
  )
import Data.Scientific (Scientific)
import Control.Monad (void)

type ConnectionPool = Pool Connection
type DBAction a = Connection -> IO a

withConnection :: ConnectionPool -> (Connection -> IO a) -> IO a
withConnection = withResource

data InventoryReservation = InventoryReservation
  { reservationItemSku :: UUID
  , reservationTransactionId :: UUID
  , reservationQuantity :: Int
  , reservationStatus :: Text
  } deriving (Show, Eq)

createTransactionTables :: ConnectionPool -> IO ()
createTransactionTables pool = withConnection pool $ \conn -> do
  hPutStrLn stderr "Creating transaction tables..."
  do
    results <- query_ conn "SELECT 1 FROM information_schema.tables WHERE table_name = 'transaction'" :: IO [Only Int]
    case results of
      [] -> do
        hPutStrLn stderr "Transaction tables not found, creating..."
        void $ execute_ conn
          [sql|
            CREATE TABLE IF NOT EXISTS transaction (
              id UUID PRIMARY KEY,
              status TEXT NOT NULL,
              created TIMESTAMP WITH TIME ZONE NOT NULL,
              completed TIMESTAMP WITH TIME ZONE,
              customer_id UUID,
              employee_id UUID NOT NULL,
              register_id UUID NOT NULL,
              location_id UUID NOT NULL,
              subtotal INTEGER NOT NULL,
              discount_total INTEGER NOT NULL,
              tax_total INTEGER NOT NULL,
              total INTEGER NOT NULL,
              transaction_type TEXT NOT NULL,
              is_voided BOOLEAN NOT NULL DEFAULT FALSE,
              void_reason TEXT,
              is_refunded BOOLEAN NOT NULL DEFAULT FALSE,
              refund_reason TEXT,
              reference_transaction_id UUID,
              notes TEXT
            )
          |]
        void $ execute_ conn
          [sql|
            CREATE TABLE IF NOT EXISTS inventory_reservation (
              id UUID PRIMARY KEY,
              item_sku UUID NOT NULL,
              transaction_id UUID NOT NULL,
              quantity INTEGER NOT NULL,
              status TEXT NOT NULL,
              created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
            )
          |]
      _ -> do
        hPutStrLn stderr "Transaction tables already exist"
        pure ()

-- Transaction Functions --
getAllTransactions :: ConnectionPool -> IO [Transaction]
getAllTransactions pool = withConnection pool $ \conn ->
  Database.PostgreSQL.Simple.query_ conn
    [sql|
      SELECT 
        t.id, 
        t.status, 
        t.created, 
        t.completed, 
        t.customer_id, 
        t.employee_id, 
        t.register_id, 
        t.location_id, 
        t.subtotal, 
        t.discount_total, 
        t.tax_total, 
        t.total, 
        t.transaction_type, 
        t.is_voided, 
        t.void_reason, 
        t.is_refunded, 
        t.refund_reason, 
        t.reference_transaction_id, 
        t.notes 
      FROM transaction t 
      ORDER BY t.created DESC
    |]

getTransactionById :: ConnectionPool -> UUID -> IO (Maybe Transaction)
getTransactionById pool transactionId = withConnection pool $ \conn -> do
  let query_str = [sql|
      SELECT 
        t.id, 
        t.status, 
        t.created, 
        t.completed, 
        t.customer_id, 
        t.employee_id, 
        t.register_id, 
        t.location_id, 
        t.subtotal, 
        t.discount_total, 
        t.tax_total, 
        t.total, 
        t.transaction_type, 
        t.is_voided, 
        t.void_reason, 
        t.is_refunded, 
        t.refund_reason, 
        t.reference_transaction_id, 
        t.notes 
      FROM transaction t 
      WHERE t.id = ?
    |]

  results <- Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only transactionId)

  case results of
    [transaction] -> do
      items <- getTransactionItemsByTransactionId conn transactionId
      payments <- getPaymentsByTransactionId conn transactionId
      pure $ Just $ transaction { transactionItems = items, transactionPayments = payments }
    _ -> pure Nothing

getTransactionItemsByTransactionId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [TransactionItem]
getTransactionItemsByTransactionId conn transactionId = do
  let query_str = [sql|
      SELECT 
        id, 
        transaction_id, 
        menu_item_sku, 
        quantity, 
        price_per_unit, 
        subtotal, 
        total 
      FROM transaction_item 
      WHERE transaction_id = ?
    |]

  items <- Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only transactionId)

  mapM (\item -> do
    discounts <- getDiscountsByTransactionItemId conn (transactionItemId item)
    taxes <- getTaxesByTransactionItemId conn (transactionItemId item)
    pure $ item { transactionItemDiscounts = discounts, transactionItemTaxes = taxes }
    ) items

getDiscountsByTransactionItemId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [DiscountRecord]
getDiscountsByTransactionItemId conn itemId = do
  let query_str = [sql|
      SELECT 
        d.type, 
        d.amount, 
        d.percent, 
        d.reason, 
        d.approved_by 
      FROM discount d 
      WHERE d.transaction_item_id = ?
    |]

  Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only itemId)


getTaxesByTransactionItemId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [TaxRecord]
getTaxesByTransactionItemId conn itemId = do
  let query_str = [sql|
      SELECT 
        t.category, 
        t.rate, 
        t.amount, 
        t.description 
      FROM transaction_tax t 
      WHERE t.transaction_item_id = ?
    |]

  Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only itemId)


getPaymentsByTransactionId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [PaymentTransaction]
getPaymentsByTransactionId conn transactionId = do
  let query_str = [sql|
      SELECT 
        id, 
        transaction_id, 
        method, 
        amount, 
        tendered, 
        change_amount, 
        reference, 
        approved, 
        authorization_code 
      FROM payment_transaction 
      WHERE transaction_id = ?
    |]

  Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only transactionId)


createTransaction :: ConnectionPool -> Transaction -> IO Transaction
createTransaction pool transaction = withConnection pool $ \conn -> do

  let insert_str = [sql|
      INSERT INTO transaction (
        id, 
        status, 
        created, 
        completed, 
        customer_id, 
        employee_id, 
        register_id, 
        location_id, 
        subtotal, 
        discount_total, 
        tax_total, 
        total, 
        transaction_type, 
        is_voided, 
        void_reason, 
        is_refunded, 
        refund_reason, 
        reference_transaction_id, 
        notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING
        id, 
        status, 
        created, 
        completed, 
        customer_id, 
        employee_id, 
        register_id, 
        location_id, 
        subtotal, 
        discount_total, 
        tax_total, 
        total, 
        transaction_type, 
        is_voided, 
        void_reason, 
        is_refunded, 
        refund_reason, 
        reference_transaction_id, 
        notes
    |]

  [newTransaction] <- Database.PostgreSQL.Simple.query conn insert_str (
    transactionId transaction,
    showStatus (transactionStatus transaction),
    transactionCreated transaction,
    transactionCompleted transaction,
    transactionCustomerId transaction,
    transactionEmployeeId transaction,
    transactionRegisterId transaction,
    transactionLocationId transaction,
    transactionSubtotal transaction,
    transactionDiscountTotal transaction,
    transactionTaxTotal transaction,
    transactionTotal transaction,
    showTransactionType (transactionType transaction),
    transactionIsVoided transaction,
    transactionVoidReason transaction,
    transactionIsRefunded transaction,
    transactionRefundReason transaction,
    transactionReferenceTransactionId transaction,
    transactionNotes transaction
   )

  newItems <- mapM (insertTransactionItem conn) (transactionItems transaction)
  newPayments <- mapM (insertPaymentTransaction conn) (transactionPayments transaction)
  pure $ newTransaction { transactionItems = newItems, transactionPayments = newPayments }


-- | Insert a transaction item
insertTransactionItem :: Database.PostgreSQL.Simple.Connection -> TransactionItem -> IO TransactionItem
insertTransactionItem conn item = do
  -- Insert transaction item
  [newItem] <- Database.PostgreSQL.Simple.query conn [sql|
    INSERT INTO transaction_item (
      id, 
      transaction_id, 
      menu_item_sku, 
      quantity, 
      price_per_unit, 
      subtotal, 
      total
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    RETURNING 
      id, 
      transaction_id, 
      menu_item_sku, 
      quantity, 
      price_per_unit, 
      subtotal, 
      total
  |] (
    transactionItemId item,
    transactionItemTransactionId item,
    transactionItemMenuItemSku item,
    transactionItemQuantity item,
    transactionItemPricePerUnit item,
    transactionItemSubtotal item,
    transactionItemTotal item
   )

  -- Insert discounts
  discounts <- mapM (insertDiscount conn (transactionItemId item) Nothing)
                   (transactionItemDiscounts item)

  -- Insert taxes
  taxes <- mapM (insertTax conn (transactionItemId item))
               (transactionItemTaxes item)

  -- Return complete item
  pure $ newItem { transactionItemDiscounts = discounts, transactionItemTaxes = taxes }

-- | Insert a discount
insertDiscount :: Database.PostgreSQL.Simple.Connection -> UUID -> Maybe UUID -> DiscountRecord -> IO DiscountRecord
insertDiscount conn itemId transactionId discount = do
  discountId <- liftIO nextRandom
  Database.PostgreSQL.Simple.execute conn [sql|
    INSERT INTO discount (
      id,
      transaction_item_id,
      transaction_id,
      type,
      amount,
      percent,
      reason,
      approved_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  |] (
    discountId,
    itemId,
    transactionId,
    showDiscountType (discountType discount),
    discountAmount discount,
    getDiscountPercent (discountType discount),
    discountReason discount,
    discountApprovedBy discount
    )
  pure discount

-- | Get percent from discount type
getDiscountPercent :: DiscountType -> Maybe Data.Scientific.Scientific
getDiscountPercent (PercentOff percent) = Just percent
getDiscountPercent _ = Nothing

-- | Insert a tax record
insertTax :: Database.PostgreSQL.Simple.Connection -> UUID -> TaxRecord -> IO TaxRecord
insertTax conn itemId tax = do
  taxId <- liftIO nextRandom
  Database.PostgreSQL.Simple.execute conn [sql|
    INSERT INTO transaction_tax (
      id,
      transaction_item_id,
      category,
      rate,
      amount,
      description
    ) VALUES (?, ?, ?, ?, ?, ?)
  |] (
    taxId,
    itemId,
    showTaxCategory (taxCategory tax),
    taxRate tax,
    taxAmount tax,
    taxDescription tax
    )
  pure tax

-- | Insert a payment transaction
insertPaymentTransaction :: Database.PostgreSQL.Simple.Connection -> PaymentTransaction -> IO PaymentTransaction
insertPaymentTransaction conn payment = do
  [newPayment] <- Database.PostgreSQL.Simple.query conn [sql|
    INSERT INTO payment_transaction (
      id,
      transaction_id,
      method,
      amount,
      tendered,
      change_amount,
      reference,
      approved,
      authorization_code
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    RETURNING
      id,
      transaction_id,
      method,
      amount,
      tendered,
      change_amount,
      reference,
      approved,
      authorization_code
  |] (
    paymentId payment,
    paymentTransactionId payment,
    showPaymentMethod (paymentMethod payment),
    paymentAmount payment,
    paymentTendered payment,
    paymentChange payment,
    paymentReference payment,
    paymentApproved payment,
    paymentAuthorizationCode payment
   )
  pure newPayment

-- | Update a transaction
updateTransaction :: ConnectionPool -> UUID -> Transaction -> IO Transaction
updateTransaction pool transactionId transaction = withConnection pool $ \conn -> do
  -- Update transaction
  Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = ?,
      completed = ?,
      customer_id = ?,
      employee_id = ?,
      register_id = ?,
      location_id = ?,
      subtotal = ?,
      discount_total = ?,
      tax_total = ?,
      total = ?,
      transaction_type = ?,
      is_voided = ?,
      void_reason = ?,
      is_refunded = ?,
      refund_reason = ?,
      reference_transaction_id = ?,
      notes = ?
    WHERE id = ?
  |] (
    showStatus (transactionStatus transaction),
    transactionCompleted transaction,
    transactionCustomerId transaction,
    transactionEmployeeId transaction,
    transactionRegisterId transaction,
    transactionLocationId transaction,
    transactionSubtotal transaction,
    transactionDiscountTotal transaction,
    transactionTaxTotal transaction,
    transactionTotal transaction,
    showTransactionType (transactionType transaction),
    transactionIsVoided transaction,
    transactionVoidReason transaction,
    transactionIsRefunded transaction,
    transactionRefundReason transaction,
    transactionReferenceTransactionId transaction,
    transactionNotes transaction,
    transactionId
   )

  -- Get the updated transaction
  maybeTransaction <- getTransactionById pool transactionId
  case maybeTransaction of
    Just updatedTransaction -> pure updatedTransaction
    Nothing -> error $ "Transaction not found after update: " ++ show transactionId

-- | Void a transaction
voidTransaction :: ConnectionPool -> UUID -> Text -> IO Transaction
voidTransaction pool transactionId reason = withConnection pool $ \conn -> do
  -- Update transaction to voided status
  Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = 'VOIDED',
      is_voided = TRUE,
      void_reason = ?
    WHERE id = ?
  |] (reason, transactionId)

  -- Get the updated transaction
  maybeTransaction <- getTransactionById pool transactionId
  case maybeTransaction of
    Just updatedTransaction -> pure updatedTransaction
    Nothing -> error $ "Transaction not found after void: " ++ show transactionId

-- | Refund a transaction
refundTransaction :: ConnectionPool -> UUID -> Text -> IO Transaction
refundTransaction pool transactionId reason = withConnection pool $ \conn -> do
  -- First, get the original transaction
  maybeOriginalTransaction <- getTransactionById pool transactionId
  case maybeOriginalTransaction of
    Nothing -> error $ "Original transaction not found for refund: " ++ show transactionId
    Just originalTransaction -> do
      -- Create a new transaction for the refund
      refundId <- liftIO nextRandom
      now <- liftIO getCurrentTime

      let refundTransaction = Transaction {
        transactionId = refundId,
        transactionStatus = Completed,
        transactionCreated = now,
        transactionCompleted = Just now,
        transactionCustomerId = transactionCustomerId originalTransaction,
        transactionEmployeeId = transactionEmployeeId originalTransaction,
        transactionRegisterId = transactionRegisterId originalTransaction,
        transactionLocationId = transactionLocationId originalTransaction,
        -- Negate amounts for refund
        transactionSubtotal = negate $ transactionSubtotal originalTransaction,
        transactionDiscountTotal = negate $ transactionDiscountTotal originalTransaction,
        transactionTaxTotal = negate $ transactionTaxTotal originalTransaction,
        transactionTotal = negate $ transactionTotal originalTransaction,
        transactionType = Return,
        transactionIsVoided = False,
        transactionVoidReason = Nothing,
        transactionIsRefunded = False,
        transactionRefundReason = Nothing,
        transactionReferenceTransactionId = Just transactionId,
        transactionNotes = Just $ "Refund for transaction " <> T.pack (toString transactionId) <> ": " <> reason,
        -- Create refund items and payment
        transactionItems = map negateTransactionItem $ transactionItems originalTransaction,
        transactionPayments = map negatePaymentTransaction $ transactionPayments originalTransaction
      }

      -- Insert the refund transaction
      newRefundTransaction <- createTransaction pool refundTransaction

      -- Mark the original transaction as refunded
      Database.PostgreSQL.Simple.execute conn [sql|
        UPDATE transaction SET
          is_refunded = TRUE,
          refund_reason = ?
        WHERE id = ?
      |] (reason, transactionId)

      -- Return the refund transaction
      pure newRefundTransaction

-- Fix for negateTransactionItem function
negateTransactionItem :: TransactionItem -> TransactionItem
negateTransactionItem item = TransactionItem {
  transactionItemId = transactionItemId item,
  transactionItemTransactionId = transactionItemTransactionId item,
  transactionItemMenuItemSku = transactionItemMenuItemSku item,
  transactionItemQuantity = transactionItemQuantity item,
  transactionItemPricePerUnit = transactionItemPricePerUnit item,
  transactionItemDiscounts = map negateDiscountRecord (transactionItemDiscounts item),
  transactionItemTaxes = map negateTaxRecord (transactionItemTaxes item),
  transactionItemSubtotal = negate (transactionItemSubtotal item),
  transactionItemTotal = negate (transactionItemTotal item)
}

-- | Negate a discount record for refunds
negateDiscountRecord :: DiscountRecord -> DiscountRecord
negateDiscountRecord discount = discount {
  discountAmount = negate $ discountAmount discount
}

-- | Negate a tax record for refunds
negateTaxRecord :: TaxRecord -> TaxRecord
negateTaxRecord tax = tax {
  taxAmount = negate $ taxAmount tax
}

-- | Negate a payment transaction for refunds
negatePaymentTransaction :: PaymentTransaction -> PaymentTransaction
negatePaymentTransaction payment = payment {
  paymentId = paymentId payment, -- Will be replaced when inserted
  paymentAmount = negate $ paymentAmount payment,
  paymentTendered = negate $ paymentTendered payment,
  paymentChange = negate $ paymentChange payment
}

-- | Finalize a transaction
finalizeTransaction :: ConnectionPool -> UUID -> IO Transaction
finalizeTransaction pool transactionId = withConnection pool $ \conn -> do
  -- Update transaction status to Completed
  now <- liftIO getCurrentTime
  Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = 'COMPLETED',
      completed = ?
    WHERE id = ?
  |] (now, transactionId)

  -- Get the updated transaction
  maybeTransaction <- getTransactionById pool transactionId
  case maybeTransaction of
    Just updatedTransaction -> pure updatedTransaction
    Nothing -> error $ "Transaction not found after finalization: " ++ show transactionId

insertInventoryReservation :: Connection -> InventoryReservation -> IO ()
insertInventoryReservation conn InventoryReservation{..} = do
  reservationId <- liftIO nextRandom
  void $ execute conn [sql|
    INSERT INTO inventory_reservation
    (id, item_sku, transaction_id, quantity, status)
    VALUES (?, ?, ?, ?, ?)
  |] (
    reservationId,
    reservationItemSku,
    reservationTransactionId,
    reservationQuantity,
    reservationStatus
    )

addTransactionItem :: ConnectionPool -> TransactionItem -> IO TransactionItem
addTransactionItem pool item = withConnection pool $ \conn -> do
  -- Check if there's enough inventory for this item
  let quantity = transactionItemQuantity item
      menuItemSku = transactionItemMenuItemSku item
  
  [Only availableQuantity] <- query conn 
    "SELECT quantity FROM menu_items WHERE sku = ?" 
    (Only menuItemSku)
  
  if availableQuantity < quantity
    then error $ "Not enough inventory. Only " ++ show availableQuantity ++ " available."
    else do
      -- Temporarily decrement inventory
      execute conn 
        "UPDATE menu_items SET quantity = quantity - ? WHERE sku = ?" 
        (quantity, menuItemSku)
      
      -- Add the transaction item
      newItem <- insertTransactionItem conn item
      
      -- Add inventory record
      let reservation = InventoryReservation
            { reservationItemSku = menuItemSku
            , reservationTransactionId = transactionItemTransactionId item
            , reservationQuantity = quantity
            , reservationStatus = "Reserved"
            }
      insertInventoryReservation conn reservation
      
      pure newItem

-- | Delete a transaction item
deleteTransactionItem :: ConnectionPool -> UUID -> IO ()
deleteTransactionItem pool itemId = withConnection pool $ \conn -> do
  -- Get transaction ID before deleting
  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT transaction_id FROM transaction_item WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only itemId)

  case results of
    [Database.PostgreSQL.Simple.Only transactionId] -> do
      -- Delete discounts for this item
      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM discount WHERE transaction_item_id = ?
      |] (Database.PostgreSQL.Simple.Only itemId)

      -- Delete taxes for this item
      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM transaction_tax WHERE transaction_item_id = ?
      |] (Database.PostgreSQL.Simple.Only itemId)

      -- Delete the item
      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM transaction_item WHERE id = ?
      |] (Database.PostgreSQL.Simple.Only itemId)

      -- Update transaction totals
      updateTransactionTotals conn transactionId

    _ -> pure () -- Item not found

-- | Add a payment to a transaction
addPaymentTransaction :: ConnectionPool -> PaymentTransaction -> IO PaymentTransaction
addPaymentTransaction pool payment = withConnection pool $ \conn -> do
  -- Insert the payment
  newPayment <- insertPaymentTransaction conn payment

  -- Update transaction
  updateTransactionPaymentStatus conn (paymentTransactionId payment)

  -- Return the new payment
  pure newPayment

-- | Delete a payment
deletePaymentTransaction :: ConnectionPool -> UUID -> IO ()
deletePaymentTransaction pool paymentId = withConnection pool $ \conn -> do
  -- Get transaction ID before deleting
  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT transaction_id FROM payment_transaction WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only paymentId)

  case results of
    [Database.PostgreSQL.Simple.Only transactionId] -> do
      -- Delete the payment
      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM payment_transaction WHERE id = ?
      |] (Database.PostgreSQL.Simple.Only paymentId)

      -- Update transaction status
      updateTransactionPaymentStatus conn transactionId

    _ -> pure () -- Payment not found

-- | Update transaction totals
updateTransactionTotals :: Database.PostgreSQL.Simple.Connection -> UUID -> IO ()
updateTransactionTotals conn transactionId = do
  [Database.PostgreSQL.Simple.Only subtotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(subtotal), 0) FROM transaction_item WHERE transaction_id = ?
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  [Database.PostgreSQL.Simple.Only discountTotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(amount), 0) FROM discount
    WHERE transaction_id = ? OR transaction_item_id IN (
      SELECT id FROM transaction_item WHERE transaction_id = ?
    )
  |] (transactionId, transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  [Database.PostgreSQL.Simple.Only taxTotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(amount), 0) FROM transaction_tax
    WHERE transaction_item_id IN (
      SELECT id FROM transaction_item WHERE transaction_id = ?
    )
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  let total = subtotal - discountTotal + taxTotal

  void $ Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      subtotal = ?,
      discount_total = ?,
      tax_total = ?,
      total = ?
    WHERE id = ?
  |] (subtotal, discountTotal, taxTotal, total, transactionId)

updateTransactionPaymentStatus :: Database.PostgreSQL.Simple.Connection -> UUID -> IO ()
updateTransactionPaymentStatus conn transactionId = do
  [Database.PostgreSQL.Simple.Only total] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT total FROM transaction WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  [Database.PostgreSQL.Simple.Only paymentTotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(amount), 0) FROM payment_transaction
    WHERE transaction_id = ?
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  let status = if paymentTotal >= total then "COMPLETED" else "IN_PROGRESS" :: Text

  void $ Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = ?
    WHERE id = ?
  |] (status, transactionId)

-- Helper functions to convert enum types to database strings
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
showPaymentMethod (Other text) = "OTHER"

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

-- Register functions --

getAllRegisters :: ConnectionPool -> IO [Register]
getAllRegisters pool = withConnection pool $ \conn ->
  Database.PostgreSQL.Simple.query_ conn [sql|
    SELECT
      id,
      name,
      location_id,
      is_open,
      current_drawer_amount,
      expected_drawer_amount,
      opened_at,
      opened_by,
      last_transaction_time
    FROM register
    ORDER BY name
  |]

instance FromRow Register where
  fromRow =
    Register
      <$> field  -- registerId
      <*> field  -- registerName  
      <*> field  -- registerLocationId
      <*> field  -- registerIsOpen
      <*> field  -- registerCurrentDrawerAmount
      <*> field  -- registerExpectedDrawerAmount
      <*> field  -- registerOpenedAt
      <*> field  -- registerOpenedBy
      <*> field  -- registerLastTransactionTime

-- | Get register by ID
getRegisterById :: ConnectionPool -> UUID -> IO (Maybe Register)
getRegisterById pool registerId = withConnection pool $ \conn -> do
  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT 
      id, 
      name, 
      location_id, 
      is_open, 
      current_drawer_amount, 
      expected_drawer_amount,
      opened_at, 
      opened_by, 
      last_transaction_time
    FROM register
    WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only registerId)

  case results of
    [register] -> pure $ Just register
    _ -> pure Nothing

-- | Create a register
createRegister :: ConnectionPool -> Register -> IO Register
createRegister pool register = withConnection pool $ \conn ->
  head <$> Database.PostgreSQL.Simple.query conn [sql|
    INSERT INTO register (
      id, 
      name, 
      location_id, 
      is_open, 
      current_drawer_amount, 
      expected_drawer_amount,
      opened_at, 
      opened_by, 
      last_transaction_time
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    RETURNING 
      id, 
      name, 
      location_id, 
      is_open, 
      current_drawer_amount, 
      expected_drawer_amount,
      opened_at, 
      opened_by, 
      last_transaction_time
  |] (
    registerId register,
    registerName register,
    registerLocationId register,
    registerIsOpen register,
    registerCurrentDrawerAmount register,
    registerExpectedDrawerAmount register,
    registerOpenedAt register,
    registerOpenedBy register,
    registerLastTransactionTime register
  )

updateRegister :: ConnectionPool -> UUID -> Register -> IO Register
updateRegister pool registerId register = withConnection pool $ \conn -> do
  let update_str = [sql|
    UPDATE register SET
      name = ?,
      location_id = ?,
      is_open = ?,
      current_drawer_amount = ?,
      expected_drawer_amount = ?,
      opened_at = ?,
      opened_by = ?,
      last_transaction_time = ?
    WHERE id = ?
  |]

  Database.PostgreSQL.Simple.execute conn update_str (
    registerName register,
    registerLocationId register,
    registerIsOpen register,
    registerCurrentDrawerAmount register,
    registerExpectedDrawerAmount register,
    registerOpenedAt register,
    registerOpenedBy register,
    registerLastTransactionTime register,
    registerId
   )

  maybeRegister <- getRegisterById pool registerId
  case maybeRegister of
    Just updatedRegister -> pure updatedRegister
    Nothing -> error $ "Register not found after update: " ++ show registerId


openRegister :: ConnectionPool -> UUID -> OpenRegisterRequest -> IO Register
openRegister pool registerId request = withConnection pool $ \conn -> do
  now <- liftIO getCurrentTime

  let update_str = [sql|
    UPDATE register SET
      is_open = TRUE,
      current_drawer_amount = ?,
      expected_drawer_amount = ?,
      opened_at = ?,
      opened_by = ?
    WHERE id = ?
  |]

  Database.PostgreSQL.Simple.execute conn update_str (
    openRegisterStartingCash request,
    openRegisterStartingCash request,
    now,
    openRegisterEmployeeId request,
    registerId
    )

  maybeRegister <- getRegisterById pool registerId
  case maybeRegister of
    Just updatedRegister -> pure updatedRegister
    Nothing -> error $ "Register not found after opening: " ++ show registerId


-- | Close a register
closeRegister :: ConnectionPool -> UUID -> CloseRegisterRequest -> IO CloseRegisterResult
closeRegister pool registerId request = withConnection pool $ \conn -> do
  now <- liftIO getCurrentTime

  maybeRegister <- getRegisterById pool registerId
  case maybeRegister of
    Nothing -> error $ "Register not found: " ++ show registerId
    Just register -> do

      let variance = registerExpectedDrawerAmount register - closeRegisterCountedCash request

      let update_str = [sql|
        UPDATE register SET
          is_open = FALSE,
          current_drawer_amount = ?,
          last_transaction_time = ?
        WHERE id = ?
      |]

      Database.PostgreSQL.Simple.execute conn update_str (
        closeRegisterCountedCash request,
        now,
        registerId
        )

      maybeUpdatedRegister <- getRegisterById pool registerId
      case maybeUpdatedRegister of
        Nothing -> error $ "Register not found after closing: " ++ show registerId
        Just updatedRegister ->
          pure $ CloseRegisterResult {
            closeRegisterResultRegister = updatedRegister,
            closeRegisterResultVariance = variance
          }