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

data LedgerError
  = UnbalancedTransaction
  | InvalidAccountReference
  | InsufficientFunds
  | DuplicateEntry
  | InvalidAmount
  | TransactionClosed
  | AuthorizationFailed
  | SystemError String

derive instance eqLedgerError :: Eq LedgerError
derive instance ordLedgerError :: Ord LedgerError

instance showLedgerError :: Show LedgerError where
  show UnbalancedTransaction = "Transaction debits and credits do not balance"
  show InvalidAccountReference = "Referenced account does not exist"
  show InsufficientFunds = "Insufficient funds in account"
  show DuplicateEntry = "Duplicate ledger entry detected"
  show InvalidAmount = "Invalid amount for ledger entry"
  show TransactionClosed = "Cannot modify a closed transaction"
  show AuthorizationFailed = "User not authorized for this operation"
  show (SystemError msg) = "System error: " <> msg

type EntityId = UUID

data TransactionStatus
  = Created
  | InProgress
  | Completed
  | Voided
  | Refunded

derive instance eqTransactionStatus :: Eq TransactionStatus
derive instance ordTransactionStatus :: Ord TransactionStatus

instance showTransactionStatus :: Show TransactionStatus where
  show Created = "Created"
  show InProgress = "In Progress"
  show Completed = "Completed"
  show Voided = "Voided"
  show Refunded = "Refunded"

instance writeForeignTransactionStatus :: WriteForeign TransactionStatus where
  writeImpl Created = writeImpl "CREATED"
  writeImpl InProgress = writeImpl "IN_PROGRESS"
  writeImpl Completed = writeImpl "COMPLETED"
  writeImpl Voided = writeImpl "VOIDED"
  writeImpl Refunded = writeImpl "REFUNDED"

instance readForeignTransactionStatus :: ReadForeign TransactionStatus where
  readImpl f = do
    status <- readImpl f
    case status of
      "CREATED" -> pure Created
      "IN_PROGRESS" -> pure InProgress
      "COMPLETED" -> pure Completed
      "VOIDED" -> pure Voided
      "REFUNDED" -> pure Refunded
      _ -> fail (ForeignError $ "Invalid TransactionStatus: " <> status)

data PaymentMethod
  = Cash
  | Debit
  | Credit
  | ACH
  | GiftCard
  | StoredValue
  | Mixed
  | Other String

derive instance eqPaymentMethod :: Eq PaymentMethod
derive instance ordPaymentMethod :: Ord PaymentMethod

instance showPaymentMethod :: Show PaymentMethod where
  show Cash = "Cash"
  show Debit = "Debit"
  show Credit = "Credit"
  show ACH = "ACH"
  show GiftCard = "Gift Card"
  show StoredValue = "Stored Value"
  show Mixed = "Mixed Payment"
  show (Other s) = "Other: " <> s

instance writeForeignPaymentMethod :: WriteForeign PaymentMethod where
  writeImpl Cash = writeImpl "CASH"
  writeImpl Debit = writeImpl "DEBIT"
  writeImpl Credit = writeImpl "CREDIT"
  writeImpl ACH = writeImpl "ACH"
  writeImpl GiftCard = writeImpl "GIFT_CARD"
  writeImpl StoredValue = writeImpl "STORED_VALUE"
  writeImpl Mixed = writeImpl "MIXED"
  writeImpl (Other s) = writeImpl ("OTHER:" <> s)

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

data DiscountType
  = PercentOff Number
  | AmountOff (Discrete USD)
  | BuyOneGetOne
  | Custom String (Discrete USD)

derive instance eqDiscountType :: Eq DiscountType
derive instance ordDiscountType :: Ord DiscountType

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

data TaxCategory
  = RegularSalesTax
  | ExciseTax
  | CannabisTax
  | LocalTax
  | MedicalTax
  | NoTax

derive instance eqTaxCategory :: Eq TaxCategory
derive instance ordTaxCategory :: Ord TaxCategory

instance writeForeignTaxCategory :: WriteForeign TaxCategory where
  writeImpl RegularSalesTax = writeImpl "REGULAR_SALES_TAX"
  writeImpl ExciseTax = writeImpl "EXCISE_TAX"
  writeImpl CannabisTax = writeImpl "CANNABIS_TAX"
  writeImpl LocalTax = writeImpl "LOCAL_TAX"
  writeImpl MedicalTax = writeImpl "MEDICAL_TAX"
  writeImpl NoTax = writeImpl "NO_TAX"

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

derive instance newtypeTransactionItem :: Newtype TransactionItem _
derive instance eqTransactionItem :: Eq TransactionItem
derive instance ordTransactionItem :: Ord TransactionItem

instance writeForeignTransactionItem :: WriteForeign TransactionItem where
  writeImpl (TransactionItem item) = writeImpl item

instance readForeignTransactionItem :: ReadForeign TransactionItem where
  readImpl f = TransactionItem <$> readImpl f

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

derive instance newtypePaymentTransaction :: Newtype PaymentTransaction _
derive instance eqPaymentTransaction :: Eq PaymentTransaction
derive instance ordPaymentTransaction :: Ord PaymentTransaction

instance writeForeignPaymentTransaction :: WriteForeign PaymentTransaction where
  writeImpl (PaymentTransaction payment) = writeImpl payment

instance readForeignPaymentTransaction :: ReadForeign PaymentTransaction where
  readImpl f = PaymentTransaction <$> readImpl f

type CartTotals =
  { subtotal :: Discrete USD
  , taxTotal :: Discrete USD
  , total :: Discrete USD
  , discountTotal :: Discrete USD
  }

newtype Transaction = Transaction
  { id :: UUID
  , status :: TransactionStatus
  , created :: DateTime
  , completed :: Maybe DateTime
  , customer :: Maybe UUID
  , employee :: UUID
  , register :: UUID
  , location :: UUID
  , items :: Array TransactionItem
  , payments :: Array PaymentTransaction
  , subtotal :: DiscreteMoney USD
  , discountTotal :: DiscreteMoney USD
  , taxTotal :: DiscreteMoney USD
  , total :: DiscreteMoney USD
  , transactionType :: TransactionType
  , isVoided :: Boolean
  , voidReason :: Maybe String
  , isRefunded :: Boolean
  , refundReason :: Maybe String
  , referenceTransactionId :: Maybe UUID
  , notes :: Maybe String
  }

derive instance newtypeTransaction :: Newtype Transaction _
derive instance eqTransaction :: Eq Transaction
derive instance ordTransaction :: Ord Transaction

instance writeForeignTransaction :: WriteForeign Transaction where
  writeImpl (Transaction tx) = writeImpl
    { id: tx.id
    , status: tx.status
    , created: tx.created
    , completed: tx.completed
    , customer: tx.customer
    , employee: tx.employee
    , register: tx.register
    , location: tx.location
    , items: tx.items
    , payments: tx.payments
    , subtotal: tx.subtotal
    , discountTotal: tx.discountTotal
    , taxTotal: tx.taxTotal
    , total: tx.total
    , transactionType: tx.transactionType
    , isVoided: tx.isVoided
    , voidReason: tx.voidReason
    , isRefunded: tx.isRefunded
    , refundReason: tx.refundReason
    , referenceTransactionId: tx.referenceTransactionId
    , notes: tx.notes
    }

instance readForeignTransaction :: ReadForeign Transaction where
  readImpl f = Transaction <$> readImpl f

data TransactionType
  = Sale
  | Return
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative

derive instance eqTransactionType :: Eq TransactionType
derive instance ordTransactionType :: Ord TransactionType

instance showTransactionType :: Show TransactionType where
  show Sale = "Sale"
  show Return = "Return"
  show Exchange = "Exchange"
  show InventoryAdjustment = "Inventory Adjustment"
  show ManagerComp = "Manager Comp"
  show Administrative = "Administrative"

instance writeForeignTransactionType :: WriteForeign TransactionType where
  writeImpl Sale = writeImpl "SALE"
  writeImpl Return = writeImpl "RETURN"
  writeImpl Exchange = writeImpl "EXCHANGE"
  writeImpl InventoryAdjustment = writeImpl "INVENTORY_ADJUSTMENT"
  writeImpl ManagerComp = writeImpl "MANAGER_COMP"
  writeImpl Administrative = writeImpl "ADMINISTRATIVE"

instance readForeignTransactionType :: ReadForeign TransactionType where
  readImpl f = do
    txType <- readImpl f
    case txType of
      "SALE" -> pure Sale
      "RETURN" -> pure Return
      "EXCHANGE" -> pure Exchange
      "INVENTORY_ADJUSTMENT" -> pure InventoryAdjustment
      "MANAGER_COMP" -> pure ManagerComp
      "ADMINISTRATIVE" -> pure Administrative
      _ -> fail (ForeignError $ "Invalid TransactionType: " <> txType)

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

derive instance newtypeLedgerEntry :: Newtype LedgerEntry _
derive instance eqLedgerEntry :: Eq LedgerEntry
derive instance ordLedgerEntry :: Ord LedgerEntry

instance writeForeignLedgerEntry :: WriteForeign LedgerEntry where
  writeImpl (LedgerEntry entry) = writeImpl entry

instance readForeignLedgerEntry :: ReadForeign LedgerEntry where
  readImpl f = LedgerEntry <$> readImpl f

data LedgerEntryType
  = SaleEntry
  | Tax
  | Discount
  | Payment
  | Refund
  | Void
  | Adjustment
  | Fee

derive instance eqLedgerEntryType :: Eq LedgerEntryType
derive instance ordLedgerEntryType :: Ord LedgerEntryType

instance showLedgerEntryType :: Show LedgerEntryType where
  show SaleEntry = "Sale"
  show Tax = "Tax"
  show Discount = "Discount"
  show Payment = "Payment"
  show Refund = "Refund"
  show Void = "Void"
  show Adjustment = "Adjustment"
  show Fee = "Fee"

instance writeForeignLedgerEntryType :: WriteForeign LedgerEntryType where
  writeImpl SaleEntry = writeImpl "SALE"
  writeImpl Tax = writeImpl "TAX"
  writeImpl Discount = writeImpl "DISCOUNT"
  writeImpl Payment = writeImpl "PAYMENT"
  writeImpl Refund = writeImpl "REFUND"
  writeImpl Void = writeImpl "VOID"
  writeImpl Adjustment = writeImpl "ADJUSTMENT"
  writeImpl Fee = writeImpl "FEE"

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

data AccountType
  = Asset
  | Liability
  | Equity
  | Revenue
  | Expense

derive instance eqAccountType :: Eq AccountType
derive instance ordAccountType :: Ord AccountType

instance showAccountType :: Show AccountType where
  show Asset = "Asset"
  show Liability = "Liability"
  show Equity = "Equity"
  show Revenue = "Revenue"
  show Expense = "Expense"

instance writeForeignAccountType :: WriteForeign AccountType where
  writeImpl Asset = writeImpl "ASSET"
  writeImpl Liability = writeImpl "LIABILITY"
  writeImpl Equity = writeImpl "EQUITY"
  writeImpl Revenue = writeImpl "REVENUE"
  writeImpl Expense = writeImpl "EXPENSE"

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

newtype Account = Account
  { id :: UUID
  , code :: String
  , name :: String
  , isDebitNormal :: Boolean
  , parentAccount :: Maybe UUID
  , accountType :: AccountType
  }

derive instance newtypeAccount :: Newtype Account _
derive instance eqAccount :: Eq Account
derive instance ordAccount :: Ord Account

instance writeForeignAccount :: WriteForeign Account where
  writeImpl (Account account) = writeImpl account

instance readForeignAccount :: ReadForeign Account where
  readImpl f = Account <$> readImpl f

instance showTransaction :: Show Transaction where
  show (Transaction t) =
    "Transaction { id: " <> show t.id
      <> ", total: "
      <> show t.total
      <> ", status: "
      <> show t.status
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