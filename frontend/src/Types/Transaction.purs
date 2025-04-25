module Types.Transaction where

import Prelude

import Data.DateTime (DateTime)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (DiscreteMoney)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.Number as Number
import Data.String (drop, take)
import Foreign (ForeignError(..), fail)
import Foreign.Index (readProp)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, writeImpl, readImpl)

-- || Base Types
data TransactionStatus
  = Created
  | InProgress
  | Completed
  | Voided
  | Refunded

data TransactionType
  = Sale
  | Return
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative

newtype Transaction = Transaction
  { transactionId :: UUID
  , transactionStatus :: TransactionStatus
  , transactionCreated :: DateTime
  , transactionCompleted :: Maybe DateTime
  , transactionCustomerId :: Maybe UUID
  , transactionEmployeeId :: UUID
  , transactionRegisterId :: UUID
  , transactionLocationId :: UUID
  , transactionItems :: Array TransactionItem
  , transactionPayments :: Array PaymentTransaction
  , transactionSubtotal :: DiscreteMoney USD
  , transactionDiscountTotal :: DiscreteMoney USD
  , transactionTaxTotal :: DiscreteMoney USD
  , transactionTotal :: DiscreteMoney USD
  , transactionType :: TransactionType
  , transactionIsVoided :: Boolean
  , transactionVoidReason :: Maybe String
  , transactionIsRefunded :: Boolean
  , transactionRefundReason :: Maybe String
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes :: Maybe String
  }

newtype TransactionItem = TransactionItem
  { id :: UUID
  , transactionId :: UUID
  , menuItemSku :: UUID
  , quantity :: Number
  , pricePerUnit :: DiscreteMoney USD
  , discounts :: Array DiscountRecord
  , taxes :: Array TaxRecord
  , subtotal :: DiscreteMoney USD
  , total :: DiscreteMoney USD
  }

newtype PaymentTransaction = PaymentTransaction
  { id :: UUID
  , transactionId :: UUID
  , method :: PaymentMethod
  , amount :: DiscreteMoney USD
  , tendered :: DiscreteMoney USD
  , change :: DiscreteMoney USD
  , reference :: Maybe String
  , approved :: Boolean
  , authorizationCode :: Maybe String
  }

data PaymentMethod
  = Cash
  | Debit
  | Credit
  | ACH
  | GiftCard
  | StoredValue
  | Mixed
  | Other String

data DiscountType
  = PercentOff Number
  | AmountOff (Discrete USD)
  | BuyOneGetOne
  | Custom String (Discrete USD)

data TaxCategory
  = RegularSalesTax
  | ExciseTax
  | CannabisTax
  | LocalTax
  | MedicalTax
  | NoTax

type TaxRecord =
  { category :: TaxCategory
  , rate :: Number
  , amount :: DiscreteMoney USD
  , description :: String
  }

type DiscountRecord =
  { type :: DiscountType
  , amount :: DiscreteMoney USD
  , reason :: String
  , approvedBy :: Maybe UUID
  }

data AccountType
  = Asset
  | Liability
  | Equity
  | Revenue
  | Expense

newtype Account = Account
  { id :: UUID
  , code :: String
  , name :: String
  , isDebitNormal :: Boolean
  , parentAccount :: Maybe UUID
  , accountType :: AccountType
  }

data LedgerError
  = UnbalancedTransaction
  | InvalidAccountReference
  | InsufficientFunds
  | DuplicateEntry
  | InvalidAmount
  | TransactionClosed
  | AuthorizationFailed
  | SystemError String

newtype LedgerEntry = LedgerEntry
  { id :: UUID
  , transactionId :: UUID
  , accountId :: UUID
  , amount :: DiscreteMoney USD
  , isDebit :: Boolean
  , timestamp :: DateTime
  , entryType :: LedgerEntryType
  , description :: String
  }

data LedgerEntryType
  = SaleEntry
  | Tax
  | Discount
  | Payment
  | Refund
  | Void
  | Adjustment
  | Fee

-- || Derived Instances
derive instance eqLedgerError :: Eq LedgerError
derive instance ordLedgerError :: Ord LedgerError

derive instance newtypeAccount :: Newtype Account _
derive instance eqAccount :: Eq Account
derive instance ordAccount :: Ord Account

derive instance eqAccountType :: Eq AccountType
derive instance ordAccountType :: Ord AccountType

derive instance eqLedgerEntryType :: Eq LedgerEntryType
derive instance ordLedgerEntryType :: Ord LedgerEntryType

derive instance newtypeLedgerEntry :: Newtype LedgerEntry _
derive instance eqLedgerEntry :: Eq LedgerEntry
derive instance ordLedgerEntry :: Ord LedgerEntry

derive instance eqTransactionType :: Eq TransactionType
derive instance ordTransactionType :: Ord TransactionType

derive instance newtypeTransaction :: Newtype Transaction _
derive instance eqTransaction :: Eq Transaction
derive instance ordTransaction :: Ord Transaction

derive instance newtypePaymentTransaction :: Newtype PaymentTransaction _
derive instance eqPaymentTransaction :: Eq PaymentTransaction
derive instance ordPaymentTransaction :: Ord PaymentTransaction

derive instance newtypeTransactionItem :: Newtype TransactionItem _
derive instance eqTransactionItem :: Eq TransactionItem
derive instance ordTransactionItem :: Ord TransactionItem

derive instance eqTaxCategory :: Eq TaxCategory
derive instance ordTaxCategory :: Ord TaxCategory

derive instance eqDiscountType :: Eq DiscountType
derive instance ordDiscountType :: Ord DiscountType

derive instance eqPaymentMethod :: Eq PaymentMethod
derive instance ordPaymentMethod :: Ord PaymentMethod

derive instance eqTransactionStatus :: Eq TransactionStatus
derive instance ordTransactionStatus :: Ord TransactionStatus

-- || Show Instances
instance showTransactionStatus :: Show TransactionStatus where
  show Created = "CREATED"
  show InProgress = "IN_PROGRESS"
  show Completed = "COMPLETED"
  show Voided = "VOIDED"
  show Refunded = "REFUNDED"

instance showPaymentMethod :: Show PaymentMethod where
  show Cash = "Cash"
  show Debit = "Debit"
  show Credit = "Credit"
  show ACH = "ACH"
  show GiftCard = "Gift Card"
  show StoredValue = "Stored Value"
  show Mixed = "Mixed Payment"
  show (Other s) = "Other: " <> s

instance showTransactionType :: Show TransactionType where
  show Sale = "Sale"
  show Return = "Return"
  show Exchange = "Exchange"
  show InventoryAdjustment = "Inventory Adjustment"
  show ManagerComp = "Manager Comp"
  show Administrative = "Administrative"

instance showAccountType :: Show AccountType where
  show Asset = "Asset"
  show Liability = "Liability"
  show Equity = "Equity"
  show Revenue = "Revenue"
  show Expense = "Expense"

instance showLedgerEntryType :: Show LedgerEntryType where
  show SaleEntry = "Sale"
  show Tax = "Tax"
  show Discount = "Discount"
  show Payment = "Payment"
  show Refund = "Refund"
  show Void = "Void"
  show Adjustment = "Adjustment"
  show Fee = "Fee"

instance showLedgerError :: Show LedgerError where
  show UnbalancedTransaction = "Transaction debits and credits do not balance"
  show InvalidAccountReference = "Referenced account does not exist"
  show InsufficientFunds = "Insufficient funds in account"
  show DuplicateEntry = "Duplicate ledger entry detected"
  show InvalidAmount = "Invalid amount for ledger entry"
  show TransactionClosed = "Cannot modify a closed transaction"
  show AuthorizationFailed = "User not authorized for this operation"
  show (SystemError msg) = "System error: " <> msg

instance showTransaction :: Show Transaction where
  show (Transaction t) =
    "Transaction { id: " <> show t.transactionId
      <> ", total: "
      <> show t.transactionTotal
      <> ", status: "
      <> show t.transactionStatus
      <> " }"

instance showTransactionItem :: Show TransactionItem where
  show (TransactionItem ti) =
    "TransactionItem { sku: " <> show ti.menuItemSku
      <> ", quantity: "
      <> show ti.quantity
      <> ", total: "
      <> show ti.total
      <> " }"

instance showPaymentTransaction :: Show PaymentTransaction where
  show (PaymentTransaction pt) =
    "Payment { method: " <> show pt.method
      <> ", amount: "
      <> show pt.amount
      <> " }"

instance showLedgerEntry :: Show LedgerEntry where
  show (LedgerEntry le) =
    "LedgerEntry { entryType: " <> show le.entryType
      <> ", amount: "
      <> show le.amount
      <> ", isDebit: "
      <> show le.isDebit
      <> " }"

instance showAccount :: Show Account where
  show (Account a) =
    "Account { name: " <> a.name
      <> ", type: "
      <> show a.accountType
      <> " }"

-- || WriteForeign Instances
instance writeForeignTransactionStatus :: WriteForeign TransactionStatus where
  writeImpl Created = writeImpl "Created"
  writeImpl InProgress = writeImpl "InProgress"
  writeImpl Completed = writeImpl "Completed"
  writeImpl Voided = writeImpl "Voided"
  writeImpl Refunded = writeImpl "Refunded"

instance writeForeignPaymentMethod :: WriteForeign PaymentMethod where
  writeImpl Cash = writeImpl "Cash"
  writeImpl Debit = writeImpl "Debit"
  writeImpl Credit = writeImpl "Credit"
  writeImpl ACH = writeImpl "ACH"
  writeImpl GiftCard = writeImpl "GiftCard"
  writeImpl StoredValue = writeImpl "StoredValue"
  writeImpl Mixed = writeImpl "Mixed"
  writeImpl (Other s) = writeImpl ("Other:" <> s)

instance writeForeignDiscountType :: WriteForeign DiscountType where
  writeImpl (PercentOff pct) = writeImpl
    { type: "PERCENT_OFF", percent: pct, amount: 0.0 }
  writeImpl (AmountOff amount) = writeImpl
    { type: "AMOUNT_OFF"
    , percent: 0.0
    , amount: show ((Int.toNumber (unwrap amount)) / 100.0)
    }
  writeImpl BuyOneGetOne = writeImpl
    { type: "BUY_ONE_GET_ONE", percent: 0.0, amount: 0.0 }
  writeImpl (Custom name amount) = writeImpl
    { type: "CUSTOM"
    , name
    , percent: 0.0
    , amount: show ((Int.toNumber (unwrap amount)) / 100.0)
    }

instance writeForeignTaxCategory :: WriteForeign TaxCategory where
  writeImpl RegularSalesTax = writeImpl "RegularSalesTax"
  writeImpl ExciseTax = writeImpl "ExciseTax"
  writeImpl CannabisTax = writeImpl "CannabisTax"
  writeImpl LocalTax = writeImpl "LocalTax"
  writeImpl MedicalTax = writeImpl "MedicalTax"
  writeImpl NoTax = writeImpl "NoTax"

instance writeForeignTransactionItem :: WriteForeign TransactionItem where
  writeImpl (TransactionItem item) = writeImpl item

instance writeForeignPaymentTransaction :: WriteForeign PaymentTransaction where
  writeImpl (PaymentTransaction payment) = writeImpl payment

instance writeForeignTransaction :: WriteForeign Transaction where
  writeImpl (Transaction tx) = writeImpl
    { transactionId: tx.transactionId
    , transactionStatus: tx.transactionStatus
    , transactionCreated: tx.transactionCreated
    , transactionCompleted: tx.transactionCompleted
    , transactionCustomerId: tx.transactionCustomerId
    , transactionEmployeeId: tx.transactionEmployeeId
    , transactionRegisterId: tx.transactionRegisterId
    , transactionLocationId: tx.transactionLocationId
    , transactionItems: tx.transactionItems
    , transactionPayments: tx.transactionPayments
    , transactionSubtotal: tx.transactionSubtotal
    , transactionDiscountTotal: tx.transactionDiscountTotal
    , transactionTaxTotal: tx.transactionTaxTotal
    , transactionTotal: tx.transactionTotal
    , transactionType: tx.transactionType
    , transactionIsVoided: tx.transactionIsVoided
    , transactionVoidReason: tx.transactionVoidReason
    , transactionIsRefunded: tx.transactionIsRefunded
    , transactionRefundReason: tx.transactionRefundReason
    , transactionReferenceTransactionId: tx.transactionReferenceTransactionId
    , transactionNotes: tx.transactionNotes
    }

instance writeForeignTransactionType :: WriteForeign TransactionType where
  writeImpl Sale = writeImpl "Sale"
  writeImpl Return = writeImpl "Return"
  writeImpl Exchange = writeImpl "Exchange"
  writeImpl InventoryAdjustment = writeImpl "InventoryAdjustment"
  writeImpl ManagerComp = writeImpl "ManagerComp"
  writeImpl Administrative = writeImpl "Administrative"

instance writeForeignLedgerEntry :: WriteForeign LedgerEntry where
  writeImpl (LedgerEntry entry) = writeImpl entry

instance writeForeignLedgerEntryType :: WriteForeign LedgerEntryType where
  writeImpl SaleEntry = writeImpl "SaleEntry"
  writeImpl Tax = writeImpl "Tax"
  writeImpl Discount = writeImpl "Discount"
  writeImpl Payment = writeImpl "Payment"
  writeImpl Refund = writeImpl "Refund"
  writeImpl Void = writeImpl "Void"
  writeImpl Adjustment = writeImpl "Adjustment"
  writeImpl Fee = writeImpl "Fee"

instance writeForeignAccountType :: WriteForeign AccountType where
  writeImpl Asset = writeImpl "Asset"
  writeImpl Liability = writeImpl "Liability"
  writeImpl Equity = writeImpl "Equity"
  writeImpl Revenue = writeImpl "Revenue"
  writeImpl Expense = writeImpl "Expense"

instance writeForeignAccount :: WriteForeign Account where
  writeImpl (Account account) = writeImpl account

-- || ReadForeign Instances
instance readForeignTransactionStatus :: ReadForeign TransactionStatus where
  readImpl f = do
    status <- readImpl f
    case status of
      "Created" -> pure Created
      "InProgress" -> pure InProgress
      "Completed" -> pure Completed
      "Voided" -> pure Voided
      "Refunded" -> pure Refunded
      -- backward compatibility with uppercase format
      "CREATED" -> pure Created
      "IN_PROGRESS" -> pure InProgress
      "COMPLETED" -> pure Completed
      "VOIDED" -> pure Voided
      "REFUNDED" -> pure Refunded
      _ -> fail (ForeignError $ "Invalid TransactionStatus: " <> status)

instance readForeignPaymentMethod :: ReadForeign PaymentMethod where
  readImpl f = do
    method <- readImpl f
    case method of
      "CASH" -> pure Cash
      "DEBIT" -> pure Debit
      "CREDIT" -> pure Credit
      "ACH" -> pure ACH
      "GIFT_CARD" -> pure GiftCard
      "STORED_VALUE" -> pure StoredValue
      "MIXED" -> pure Mixed
      other ->
        if take 6 other == "OTHER:" then pure $ Other (drop 6 other)
        else pure $ Other other

instance readForeignDiscountType :: ReadForeign DiscountType where
  readImpl f = do
    obj <- readImpl f
    discType <- readProp "type" obj >>= readImpl
    case discType of
      "PERCENT_OFF" -> PercentOff <$> (readProp "percent" obj >>= readImpl)
      "AMOUNT_OFF" -> do
        amountStr <- readProp "amount" obj >>= readImpl
        case Number.fromString amountStr of
          Just n -> pure $ AmountOff (Discrete (Int.floor (n * 100.0)))
          Nothing -> fail (ForeignError $ "Invalid amount: " <> amountStr)
      "BUY_ONE_GET_ONE" -> pure BuyOneGetOne
      "CUSTOM" -> do
        name <- readProp "name" obj >>= readImpl
        amountStr <- readProp "amount" obj >>= readImpl
        case Number.fromString amountStr of
          Just n -> pure $ Custom name (Discrete (Int.floor (n * 100.0)))
          Nothing -> fail (ForeignError $ "Invalid amount: " <> amountStr)
      _ -> fail (ForeignError $ "Invalid DiscountType: " <> discType)

instance readForeignTaxCategory :: ReadForeign TaxCategory where
  readImpl f = do
    category <- readImpl f
    case category of
      "REGULAR_SALES_TAX" -> pure RegularSalesTax
      "EXCISE_TAX" -> pure ExciseTax
      "CANNABIS_TAX" -> pure CannabisTax
      "LOCAL_TAX" -> pure LocalTax
      "MEDICAL_TAX" -> pure MedicalTax
      "NO_TAX" -> pure NoTax
      _ -> fail (ForeignError $ "Invalid TaxCategory: " <> category)

instance readForeignTransactionItem :: ReadForeign TransactionItem where
  readImpl f = TransactionItem <$> readImpl f

instance readForeignPaymentTransaction :: ReadForeign PaymentTransaction where
  readImpl f = PaymentTransaction <$> readImpl f

instance readForeignTransaction :: ReadForeign Transaction where
  readImpl f = Transaction <$> readImpl f

instance readForeignTransactionType :: ReadForeign TransactionType where
  readImpl f = do
    txType <- readImpl f
    case txType of
      "Sale" -> pure Sale
      "Return" -> pure Return
      "Exchange" -> pure Exchange
      "InventoryAdjustment" -> pure InventoryAdjustment
      "ManagerComp" -> pure ManagerComp
      "Administrative" -> pure Administrative
      -- For backward compatibility
      "SALE" -> pure Sale
      "RETURN" -> pure Return
      "EXCHANGE" -> pure Exchange
      "INVENTORY_ADJUSTMENT" -> pure InventoryAdjustment
      "MANAGER_COMP" -> pure ManagerComp
      "ADMINISTRATIVE" -> pure Administrative
      _ -> fail (ForeignError $ "Invalid TransactionType: " <> txType)

instance readForeignLedgerEntry :: ReadForeign LedgerEntry where
  readImpl f = LedgerEntry <$> readImpl f

instance readForeignLedgerEntryType :: ReadForeign LedgerEntryType where
  readImpl f = do
    entryType <- readImpl f
    case entryType of
      "SALE" -> pure SaleEntry
      "TAX" -> pure Tax
      "DISCOUNT" -> pure Discount
      "PAYMENT" -> pure Payment
      "REFUND" -> pure Refund
      "VOID" -> pure Void
      "ADJUSTMENT" -> pure Adjustment
      "FEE" -> pure Fee
      _ -> fail (ForeignError $ "Invalid LedgerEntryType: " <> entryType)

instance readForeignAccountType :: ReadForeign AccountType where
  readImpl f = do
    acctType <- readImpl f
    case acctType of
      "ASSET" -> pure Asset
      "LIABILITY" -> pure Liability
      "EQUITY" -> pure Equity
      "REVENUE" -> pure Revenue
      "EXPENSE" -> pure Expense
      _ -> fail (ForeignError $ "Invalid AccountType: " <> acctType)

instance readForeignAccount :: ReadForeign Account where
  readImpl f = Account <$> readImpl f