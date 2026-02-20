module Types.Transaction where

import Prelude

import Data.DateTime (DateTime)
import Data.Finance.Currency (USD)
import Data.Finance.Money.Extended (DiscreteMoney)
import Data.Maybe (Maybe)
import Data.Newtype (class Newtype)
import Foreign (ForeignError(..), fail)
import Foreign.Index (readProp)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, writeImpl, readImpl)

----------------------------------------------------------------------
-- Transaction Status
----------------------------------------------------------------------

data TransactionStatus
  = Created
  | InProgress
  | Completed
  | Voided
  | Refunded

derive instance Eq TransactionStatus
derive instance Ord TransactionStatus

instance Show TransactionStatus where
  show Created = "Created"
  show InProgress = "InProgress"
  show Completed = "Completed"
  show Voided = "Voided"
  show Refunded = "Refunded"

instance WriteForeign TransactionStatus where
  writeImpl Created = writeImpl "CREATED"
  writeImpl InProgress = writeImpl "IN_PROGRESS"
  writeImpl Completed = writeImpl "COMPLETED"
  writeImpl Voided = writeImpl "VOIDED"
  writeImpl Refunded = writeImpl "REFUNDED"

instance ReadForeign TransactionStatus where
  readImpl f = do
    status <- readImpl f
    case status of
      "CREATED" -> pure Created
      "IN_PROGRESS" -> pure InProgress
      "COMPLETED" -> pure Completed
      "VOIDED" -> pure Voided
      "REFUNDED" -> pure Refunded
      _ -> fail (ForeignError $ "Invalid TransactionStatus: " <> status)

----------------------------------------------------------------------
-- Transaction Type
----------------------------------------------------------------------

data TransactionType
  = Sale
  | Return
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative

derive instance Eq TransactionType
derive instance Ord TransactionType

instance Show TransactionType where
  show Sale = "Sale"
  show Return = "Return"
  show Exchange = "Exchange"
  show InventoryAdjustment = "Inventory Adjustment"
  show ManagerComp = "Manager Comp"
  show Administrative = "Administrative"

instance WriteForeign TransactionType where
  writeImpl Sale = writeImpl "SALE"
  writeImpl Return = writeImpl "RETURN"
  writeImpl Exchange = writeImpl "EXCHANGE"
  writeImpl InventoryAdjustment = writeImpl "INVENTORY_ADJUSTMENT"
  writeImpl ManagerComp = writeImpl "MANAGER_COMP"
  writeImpl Administrative = writeImpl "ADMINISTRATIVE"

instance ReadForeign TransactionType where
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

----------------------------------------------------------------------
-- Payment Method
----------------------------------------------------------------------

data PaymentMethod
  = Cash
  | Debit
  | Credit
  | ACH
  | GiftCard
  | StoredValue
  | Mixed
  | Other String

derive instance Eq PaymentMethod
derive instance Ord PaymentMethod

instance Show PaymentMethod where
  show Cash = "Cash"
  show Debit = "Debit"
  show Credit = "Credit"
  show ACH = "ACH"
  show GiftCard = "Gift Card"
  show StoredValue = "Stored Value"
  show Mixed = "Mixed"
  show (Other s) = "Other: " <> s

instance WriteForeign PaymentMethod where
  writeImpl Cash = writeImpl "CASH"
  writeImpl Debit = writeImpl "DEBIT"
  writeImpl Credit = writeImpl "CREDIT"
  writeImpl ACH = writeImpl "ACH"
  writeImpl GiftCard = writeImpl "GIFT_CARD"
  writeImpl StoredValue = writeImpl "STORED_VALUE"
  writeImpl Mixed = writeImpl "MIXED"
  writeImpl (Other s) = writeImpl s

instance ReadForeign PaymentMethod where
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
      other -> pure (Other other)

----------------------------------------------------------------------
-- Discount Type
----------------------------------------------------------------------

data DiscountType
  = PercentOff Number
  | AmountOff Number
  | BuyOneGetOne
  | Custom String Number

derive instance Eq DiscountType
derive instance Ord DiscountType

instance WriteForeign DiscountType where
  writeImpl (PercentOff pct) = writeImpl
    { "type": "PERCENT_OFF", percent: pct, amount: 0.0 }
  writeImpl (AmountOff amt) = writeImpl
    { "type": "AMOUNT_OFF", percent: 0.0, amount: amt }
  writeImpl BuyOneGetOne = writeImpl
    { "type": "BUY_ONE_GET_ONE", percent: 0.0, amount: 0.0 }
  writeImpl (Custom name amt) = writeImpl
    { "type": "CUSTOM", name, percent: 0.0, amount: amt }

instance ReadForeign DiscountType where
  readImpl f = do
    obj <- readImpl f
    discType <- readProp "type" obj >>= readImpl
    case discType of
      "PERCENT_OFF" -> PercentOff <$> (readProp "percent" obj >>= readImpl)
      "AMOUNT_OFF" -> AmountOff <$> (readProp "amount" obj >>= readImpl)
      "BUY_ONE_GET_ONE" -> pure BuyOneGetOne
      "CUSTOM" -> do
        name <- readProp "name" obj >>= readImpl
        amount <- readProp "amount" obj >>= readImpl
        pure $ Custom name amount
      _ -> fail (ForeignError $ "Invalid DiscountType: " <> discType)

----------------------------------------------------------------------
-- Tax Category
----------------------------------------------------------------------

data TaxCategory
  = RegularSalesTax
  | ExciseTax
  | CannabisTax
  | LocalTax
  | MedicalTax
  | NoTax

derive instance Eq TaxCategory
derive instance Ord TaxCategory

instance WriteForeign TaxCategory where
  writeImpl RegularSalesTax = writeImpl "REGULAR_SALES_TAX"
  writeImpl ExciseTax = writeImpl "EXCISE_TAX"
  writeImpl CannabisTax = writeImpl "CANNABIS_TAX"
  writeImpl LocalTax = writeImpl "LOCAL_TAX"
  writeImpl MedicalTax = writeImpl "MEDICAL_TAX"
  writeImpl NoTax = writeImpl "NO_TAX"

instance ReadForeign TaxCategory where
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

----------------------------------------------------------------------
-- Supporting Records
----------------------------------------------------------------------

type TaxRecord =
  { category :: TaxCategory
  , rate :: Number
  , amount :: DiscreteMoney USD
  , description :: String
  }

type DiscountRecord =
  { "type" :: DiscountType
  , amount :: DiscreteMoney USD
  , reason :: String
  , approvedBy :: Maybe UUID
  }

----------------------------------------------------------------------
-- Transaction Item
----------------------------------------------------------------------

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

derive instance Newtype TransactionItem _
derive instance Eq TransactionItem
derive instance Ord TransactionItem

instance WriteForeign TransactionItem where
  writeImpl (TransactionItem item) = writeImpl item

instance ReadForeign TransactionItem where
  readImpl f = TransactionItem <$> readImpl f

----------------------------------------------------------------------
-- Payment Transaction
----------------------------------------------------------------------

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

derive instance Newtype PaymentTransaction _
derive instance Eq PaymentTransaction
derive instance Ord PaymentTransaction

instance WriteForeign PaymentTransaction where
  writeImpl (PaymentTransaction payment) = writeImpl payment

instance ReadForeign PaymentTransaction where
  readImpl f = PaymentTransaction <$> readImpl f

----------------------------------------------------------------------
-- Transaction
----------------------------------------------------------------------

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

derive instance Newtype Transaction _
derive instance Eq Transaction
derive instance Ord Transaction

instance WriteForeign Transaction where
  writeImpl (Transaction tx) = writeImpl tx

instance ReadForeign Transaction where
  readImpl f = Transaction <$> readImpl f