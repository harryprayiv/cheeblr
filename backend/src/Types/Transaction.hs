{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Transaction where

import Data.UUID (UUID)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Scientific (Scientific)
import Data.Aeson (ToJSON(..), FromJSON(..))
import GHC.Generics
import Database.PostgreSQL.Simple.FromRow (FromRow(..), field)

data TransactionStatus
  = Created
  | InProgress
  | Completed
  | Voided
  | Refunded
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON TransactionStatus
instance FromJSON TransactionStatus

data InventoryReservation = InventoryReservation
  { reservationItemSku :: UUID
  , reservationTransactionId :: UUID
  , reservationQuantity :: Int
  , reservationStatus :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON InventoryReservation
instance FromJSON InventoryReservation

data TransactionType
  = Sale
  | Return
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON TransactionType
instance FromJSON TransactionType

data PaymentMethod
  = Cash
  | Debit
  | Credit
  | ACH
  | GiftCard
  | StoredValue
  | Mixed
  | Other Text
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON PaymentMethod
instance FromJSON PaymentMethod

data TaxCategory
  = RegularSalesTax
  | ExciseTax
  | CannabisTax
  | LocalTax
  | MedicalTax
  | NoTax
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON TaxCategory
instance FromJSON TaxCategory

data DiscountType
  = PercentOff Scientific
  | AmountOff Int
  | BuyOneGetOne
  | Custom Text Int
  deriving (Show, Eq, Ord, Generic)

instance ToJSON DiscountType
instance FromJSON DiscountType

data TaxRecord = TaxRecord
  { taxCategory :: TaxCategory
  , taxRate :: Scientific
  , taxAmount :: Int
  , taxDescription :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON TaxRecord
instance FromJSON TaxRecord

data DiscountRecord = DiscountRecord
  { discountType :: DiscountType
  , discountAmount :: Int
  , discountReason :: Text
  , discountApprovedBy :: Maybe UUID
  } deriving (Show, Eq, Generic)

instance ToJSON DiscountRecord
instance FromJSON DiscountRecord

data TransactionItem = TransactionItem
  { transactionItemId :: UUID
  , transactionItemTransactionId :: UUID
  , transactionItemMenuItemSku :: UUID
  , transactionItemQuantity :: Int
  , transactionItemPricePerUnit :: Int
  , transactionItemDiscounts :: [DiscountRecord]
  , transactionItemTaxes :: [TaxRecord]
  , transactionItemSubtotal :: Int
  , transactionItemTotal :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON TransactionItem
instance FromJSON TransactionItem

data PaymentTransaction = PaymentTransaction
  { paymentId :: UUID
  , paymentTransactionId :: UUID
  , paymentMethod :: PaymentMethod
  , paymentAmount :: Int
  , paymentTendered :: Int
  , paymentChange :: Int
  , paymentReference :: Maybe Text
  , paymentApproved :: Bool
  , paymentAuthorizationCode :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON PaymentTransaction
instance FromJSON PaymentTransaction

data Transaction = Transaction
  { transactionId :: UUID
  , transactionStatus :: TransactionStatus
  , transactionCreated :: UTCTime
  , transactionCompleted :: Maybe UTCTime
  , transactionCustomerId :: Maybe UUID
  , transactionEmployeeId :: UUID
  , transactionRegisterId :: UUID
  , transactionLocationId :: UUID
  , transactionItems :: [TransactionItem]
  , transactionPayments :: [PaymentTransaction]
  , transactionSubtotal :: Int
  , transactionDiscountTotal :: Int
  , transactionTaxTotal :: Int
  , transactionTotal :: Int
  , transactionType :: TransactionType
  , transactionIsVoided :: Bool
  , transactionVoidReason :: Maybe Text
  , transactionIsRefunded :: Bool
  , transactionRefundReason :: Maybe Text
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON Transaction
instance FromJSON Transaction

data LedgerEntryType
  = SaleEntry
  | Tax
  | Discount
  | Payment
  | Refund
  | Void
  | Adjustment
  | Fee
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON LedgerEntryType
instance FromJSON LedgerEntryType

data AccountType
  = Asset
  | Liability
  | Equity
  | Revenue
  | Expense
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON AccountType
instance FromJSON AccountType

data Account = Account
  { accountId :: UUID
  , accountCode :: Text
  , accountName :: Text
  , accountIsDebitNormal :: Bool
  , accountParentAccountId :: Maybe UUID
  , accountType :: AccountType
  } deriving (Show, Eq, Generic)

instance ToJSON Account
instance FromJSON Account

data LedgerEntry = LedgerEntry
  { ledgerEntryId :: UUID
  , ledgerEntryTransactionId :: UUID
  , ledgerEntryAccountId :: UUID
  , ledgerEntryAmount :: Int
  , ledgerEntryIsDebit :: Bool
  , ledgerEntryTimestamp :: UTCTime
  , ledgerEntryType :: LedgerEntryType
  , ledgerEntryDescription :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON LedgerEntry
instance FromJSON LedgerEntry

data VerificationType
  = AgeVerification
  | MedicalCardVerification
  | IDScan
  | VisualInspection
  | PatientRegistration
  | PurchaseLimitCheck
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON VerificationType
instance FromJSON VerificationType

data VerificationStatus
  = VerifiedStatus
  | FailedStatus
  | ExpiredStatus
  | NotRequiredStatus
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON VerificationStatus
instance FromJSON VerificationStatus

data CustomerVerification = CustomerVerification
  { customerVerificationId :: UUID
  , customerVerificationCustomerId :: UUID
  , customerVerificationType :: VerificationType
  , customerVerificationStatus :: VerificationStatus
  , customerVerificationVerifiedBy :: UUID
  , customerVerificationVerifiedAt :: UTCTime
  , customerVerificationExpiresAt :: Maybe UTCTime
  , customerVerificationNotes :: Maybe Text
  , customerVerificationDocumentId :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON CustomerVerification
instance FromJSON CustomerVerification

data ReportingStatus
  = NotRequired
  | Pending
  | Submitted
  | Acknowledged
  | Failed
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON ReportingStatus
instance FromJSON ReportingStatus

data ComplianceRecord = ComplianceRecord
  { complianceRecordId :: UUID
  , complianceRecordTransactionId :: UUID
  , complianceRecordVerifications :: [CustomerVerification]
  , complianceRecordIsCompliant :: Bool
  , complianceRecordRequiresStateReporting :: Bool
  , complianceRecordReportingStatus :: ReportingStatus
  , complianceRecordReportedAt :: Maybe UTCTime
  , complianceRecordReferenceId :: Maybe Text
  , complianceRecordNotes :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON ComplianceRecord
instance FromJSON ComplianceRecord

data InventoryStatus
  = Available
  | OnHold
  | Reserved
  | Sold
  | Damaged
  | Expired
  | InTransit
  | UnderReview
  | Recalled
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON InventoryStatus
instance FromJSON InventoryStatus

-- FromRow instances for database access

-- FromRow instance for Transaction
instance FromRow Transaction where
  fromRow =
    Transaction
      <$> field
      <*> (parseTransactionStatus <$> field)
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> pure []
      <*> pure []
      <*> field
      <*> field
      <*> field
      <*> field
      <*> (parseTransactionType <$> field)
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field

-- FromRow instance for TransactionItem
instance FromRow TransactionItem where
  fromRow =
    TransactionItem
      <$> field  -- transactionItemId
      <*> field  -- transactionItemTransactionId
      <*> field  -- transactionItemMenuItemSku
      <*> field  -- transactionItemQuantity
      <*> field  -- transactionItemPricePerUnit
      <*> pure [] -- transactionItemDiscounts (populated later)
      <*> pure [] -- transactionItemTaxes (populated later)
      <*> field  -- transactionItemSubtotal
      <*> field  -- transactionItemTotal

-- FromRow instance for DiscountRecord
instance FromRow DiscountRecord where
  fromRow =
    DiscountRecord
      <$> (parseDiscountType <$> field <*> field)  -- discountType (from type and percent)
      <*> field  -- discountAmount
      <*> field  -- discountReason
      <*> field  -- discountApprovedBy

-- Helper to parse the discount type from DB columns
parseDiscountType :: Text -> Maybe Int -> DiscountType
parseDiscountType typ (Just val)
  | typ == "PERCENT_OFF" = PercentOff (fromIntegral val / 100) 
  | typ == "AMOUNT_OFF" = AmountOff val  
  | typ == "BUY_ONE_GET_ONE" = BuyOneGetOne
  | otherwise = Custom typ val
parseDiscountType typ _
  | typ == "BUY_ONE_GET_ONE" = BuyOneGetOne
  | otherwise = AmountOff 0

-- FromRow instance for TaxRecord
instance FromRow TaxRecord where
  fromRow =
    TaxRecord
      <$> (read <$> field)  -- taxCategory
      <*> field  -- taxRate
      <*> field  -- taxAmount
      <*> field  -- taxDescription

-- FromRow instance for PaymentTransaction
instance FromRow PaymentTransaction where
  fromRow =
    PaymentTransaction
      <$> field  -- paymentId
      <*> field  -- paymentTransactionId
      <*> (read <$> field)  -- paymentMethod
      <*> field  -- paymentAmount
      <*> field  -- paymentTendered
      <*> field  -- paymentChange
      <*> field  -- paymentReference
      <*> field  -- paymentApproved
      <*> field  -- paymentAuthorizationCode

parseTransactionStatus :: String -> TransactionStatus
parseTransactionStatus "CREATED" = Created
parseTransactionStatus "IN_PROGRESS" = InProgress
parseTransactionStatus "COMPLETED" = Completed
parseTransactionStatus "VOIDED" = Voided
parseTransactionStatus "REFUNDED" = Refunded
parseTransactionStatus s = error $ "Invalid transaction status: " ++ s

parseTransactionType :: String -> TransactionType
parseTransactionType "SALE" = Sale
parseTransactionType "RETURN" = Return
parseTransactionType "EXCHANGE" = Exchange
parseTransactionType "INVENTORY_ADJUSTMENT" = InventoryAdjustment
parseTransactionType "MANAGER_COMP" = ManagerComp
parseTransactionType "ADMINISTRATIVE" = Administrative
parseTransactionType s = error $ "Invalid transaction type: " ++ s