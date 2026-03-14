{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module Types.Transaction where

import Data.Aeson
import Data.List (isPrefixOf)
import Data.OpenApi (ToSchema)
import Data.Scientific (Scientific)
import qualified Data.Text as T
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Database.PostgreSQL.Simple.FromRow (FromRow (..), field)
import GHC.Generics (Generic)

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
  { reservationItemSku       :: UUID
  , reservationTransactionId :: UUID
  , reservationQuantity      :: Int
  , reservationStatus        :: Text
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

instance ToJSON DiscountType where
  toJSON (PercentOff pct) = object
    [ "discountType" .= ("PERCENT_OFF" :: Text)
    , "percent"      .= pct
    ]
  toJSON (AmountOff amt) = object
    [ "discountType" .= ("AMOUNT_OFF" :: Text)
    , "amount"       .= amt
    ]
  toJSON BuyOneGetOne = object
    [ "discountType" .= ("BUY_ONE_GET_ONE" :: Text)
    ]
  toJSON (Custom name amt) = object
    [ "discountType" .= ("CUSTOM" :: Text)
    , "name"         .= name
    , "amount"       .= amt
    ]

instance FromJSON DiscountType where
  parseJSON = withObject "DiscountType" $ \v -> do
    typ <- v .: "discountType"
    case (typ :: Text) of
      "PERCENT_OFF"     -> PercentOff <$> v .: "percent"
      "AMOUNT_OFF"      -> AmountOff  <$> v .: "amount"
      "BUY_ONE_GET_ONE" -> pure BuyOneGetOne
      "CUSTOM"          -> Custom <$> v .: "name" <*> v .: "amount"
      other             -> fail $ "Unknown DiscountType: " ++ T.unpack other

data TaxRecord = TaxRecord
  { taxCategory    :: TaxCategory
  , taxRate        :: Scientific
  , taxAmount      :: Int
  , taxDescription :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON TaxRecord
instance FromJSON TaxRecord

data DiscountRecord = DiscountRecord
  { discountType       :: DiscountType
  , discountAmount     :: Int
  , discountReason     :: Text
  , discountApprovedBy :: Maybe UUID
  } deriving (Show, Eq, Generic)

instance ToJSON DiscountRecord
instance FromJSON DiscountRecord

data TransactionItem = TransactionItem
  { transactionItemId            :: UUID
  , transactionItemTransactionId :: UUID
  , transactionItemMenuItemSku   :: UUID
  , transactionItemQuantity      :: Int
  , transactionItemPricePerUnit  :: Int
  , transactionItemDiscounts     :: [DiscountRecord]
  , transactionItemTaxes         :: [TaxRecord]
  , transactionItemSubtotal      :: Int
  , transactionItemTotal         :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON TransactionItem
instance FromJSON TransactionItem

data PaymentTransaction = PaymentTransaction
  { paymentId                :: UUID
  , paymentTransactionId     :: UUID
  , paymentMethod            :: PaymentMethod
  , paymentAmount            :: Int
  , paymentTendered          :: Int
  , paymentChange            :: Int
  , paymentReference         :: Maybe Text
  , paymentApproved          :: Bool
  , paymentAuthorizationCode :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON PaymentMethod where
  toJSON Cash          = String "Cash"
  toJSON Debit         = String "Debit"
  toJSON Credit        = String "Credit"
  toJSON ACH           = String "ACH"
  toJSON GiftCard      = String "GiftCard"
  toJSON StoredValue   = String "StoredValue"
  toJSON Mixed         = String "Mixed"
  toJSON (Other t)     = String ("Other:" <> t)

instance ToJSON PaymentTransaction

instance FromJSON PaymentMethod where
  parseJSON = withText "PaymentMethod" $ \case
    "Cash"         -> pure Cash
    "CASH"         -> pure Cash
    "Debit"        -> pure Debit
    "DEBIT"        -> pure Debit
    "Credit"       -> pure Credit
    "CREDIT"       -> pure Credit
    "ACH"          -> pure ACH
    "GiftCard"     -> pure GiftCard
    "GIFT_CARD"    -> pure GiftCard
    "StoredValue"  -> pure StoredValue
    "STORED_VALUE" -> pure StoredValue
    "Mixed"        -> pure Mixed
    "MIXED"        -> pure Mixed
    other
      | "Other:" `T.isPrefixOf` other -> pure $ Other (T.drop 6 other)
      | "OTHER:" `T.isPrefixOf` other -> pure $ Other (T.drop 6 other)
      | otherwise                      -> pure $ Other other

instance FromJSON PaymentTransaction where
  parseJSON = withObject "PaymentTransaction" $ \v -> PaymentTransaction
    <$> v .:  "paymentId"
    <*> v .:  "paymentTransactionId"
    <*> v .:  "paymentMethod"
    <*> v .:  "paymentAmount"
    <*> v .:  "paymentTendered"
    <*> v .:  "paymentChange"
    <*> v .:? "paymentReference"
    <*> v .:  "paymentApproved"
    <*> v .:? "paymentAuthorizationCode"

data Transaction = Transaction
  { transactionId                    :: UUID
  , transactionStatus                :: TransactionStatus
  , transactionCreated               :: UTCTime
  , transactionCompleted             :: Maybe UTCTime
  , transactionCustomerId            :: Maybe UUID
  , transactionEmployeeId            :: UUID
  , transactionRegisterId            :: UUID
  , transactionLocationId            :: UUID
  , transactionItems                 :: [TransactionItem]
  , transactionPayments              :: [PaymentTransaction]
  , transactionSubtotal              :: Int
  , transactionDiscountTotal         :: Int
  , transactionTaxTotal              :: Int
  , transactionTotal                 :: Int
  , transactionType                  :: TransactionType
  , transactionIsVoided              :: Bool
  , transactionVoidReason            :: Maybe Text
  , transactionIsRefunded            :: Bool
  , transactionRefundReason          :: Maybe Text
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes                 :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON Transaction

instance FromJSON Transaction where
  parseJSON = withObject "Transaction" $ \v -> Transaction
    <$> v .:  "transactionId"
    <*> v .:  "transactionStatus"
    <*> v .:  "transactionCreated"
    <*> v .:? "transactionCompleted"
    <*> v .:? "transactionCustomerId"
    <*> v .:  "transactionEmployeeId"
    <*> v .:  "transactionRegisterId"
    <*> v .:  "transactionLocationId"
    <*> v .:  "transactionItems"
    <*> v .:  "transactionPayments"
    <*> v .:  "transactionSubtotal"
    <*> v .:  "transactionDiscountTotal"
    <*> v .:  "transactionTaxTotal"
    <*> v .:  "transactionTotal"
    <*> v .:  "transactionType"
    <*> v .:  "transactionIsVoided"
    <*> v .:? "transactionVoidReason"
    <*> v .:  "transactionIsRefunded"
    <*> v .:? "transactionRefundReason"
    <*> v .:? "transactionReferenceTransactionId"
    <*> v .:? "transactionNotes"

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
  { accountId             :: UUID
  , accountCode           :: Text
  , accountName           :: Text
  , accountIsDebitNormal  :: Bool
  , accountParentAccountId :: Maybe UUID
  , accountType           :: AccountType
  } deriving (Show, Eq, Generic)

instance ToJSON Account
instance FromJSON Account

data LedgerEntry = LedgerEntry
  { ledgerEntryId            :: UUID
  , ledgerEntryTransactionId :: UUID
  , ledgerEntryAccountId     :: UUID
  , ledgerEntryAmount        :: Int
  , ledgerEntryIsDebit       :: Bool
  , ledgerEntryTimestamp     :: UTCTime
  , ledgerEntryType          :: LedgerEntryType
  , ledgerEntryDescription   :: Text
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
  { customerVerificationId         :: UUID
  , customerVerificationCustomerId :: UUID
  , customerVerificationType       :: VerificationType
  , customerVerificationStatus     :: VerificationStatus
  , customerVerificationVerifiedBy :: UUID
  , customerVerificationVerifiedAt :: UTCTime
  , customerVerificationExpiresAt  :: Maybe UTCTime
  , customerVerificationNotes      :: Maybe Text
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
  { complianceRecordId                    :: UUID
  , complianceRecordTransactionId         :: UUID
  , complianceRecordVerifications         :: [CustomerVerification]
  , complianceRecordIsCompliant           :: Bool
  , complianceRecordRequiresStateReporting :: Bool
  , complianceRecordReportingStatus       :: ReportingStatus
  , complianceRecordReportedAt            :: Maybe UTCTime
  , complianceRecordReferenceId           :: Maybe Text
  , complianceRecordNotes                 :: Maybe Text
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

-- | FromRow instances for database access

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

instance FromRow TransactionItem where
  fromRow =
    TransactionItem
      <$> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> pure []
      <*> pure []
      <*> field
      <*> field

instance FromRow DiscountRecord where
  fromRow =
    DiscountRecord
      <$> (parseDiscountType <$> field <*> field)
      <*> field
      <*> field
      <*> field

parseDiscountType :: Text -> Maybe Int -> DiscountType
parseDiscountType typ (Just val)
  | typ == "PERCENT_OFF"    = PercentOff (fromIntegral val / 100)
  | typ == "AMOUNT_OFF"     = AmountOff val
  | typ == "BUY_ONE_GET_ONE" = BuyOneGetOne
  | otherwise               = Custom typ val
parseDiscountType typ _
  | typ == "BUY_ONE_GET_ONE" = BuyOneGetOne
  | otherwise               = AmountOff 0

instance FromRow TaxRecord where
  fromRow =
    (TaxRecord . parseTaxCategory <$> field)
      <*> field
      <*> field
      <*> field

instance FromRow PaymentTransaction where
  fromRow =
    PaymentTransaction
      <$> field
      <*> field
      <*> (parsePaymentMethod <$> field)
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field

parseTransactionStatus :: String -> TransactionStatus
parseTransactionStatus "CREATED"     = Created
parseTransactionStatus "IN_PROGRESS" = InProgress
parseTransactionStatus "COMPLETED"   = Completed
parseTransactionStatus "VOIDED"      = Voided
parseTransactionStatus "REFUNDED"    = Refunded
parseTransactionStatus s             = error $ "Invalid transaction status: " ++ s

parseTransactionType :: String -> TransactionType
parseTransactionType "SALE"                 = Sale
parseTransactionType "RETURN"               = Return
parseTransactionType "EXCHANGE"             = Exchange
parseTransactionType "INVENTORY_ADJUSTMENT" = InventoryAdjustment
parseTransactionType "MANAGER_COMP"         = ManagerComp
parseTransactionType "ADMINISTRATIVE"       = Administrative
parseTransactionType s                      = error $ "Invalid transaction type: " ++ s

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
  | "OTHER:" `isPrefixOf` s = Other (T.pack $ drop 6 s)
  | "Other:" `isPrefixOf` s = Other (T.pack $ drop 6 s)
  | otherwise               = Other (T.pack s)

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
parseTaxCategory s                   = error $ "Unknown TaxCategory: " ++ s

-- | OpenAPI3 instances
deriving instance ToSchema TransactionStatus
deriving instance ToSchema TransactionType
deriving instance ToSchema PaymentMethod
deriving instance ToSchema TaxCategory
deriving instance ToSchema DiscountType
deriving instance ToSchema TaxRecord
deriving instance ToSchema DiscountRecord
deriving instance ToSchema TransactionItem
deriving instance ToSchema PaymentTransaction
deriving instance ToSchema Transaction
deriving instance ToSchema InventoryReservation
deriving instance ToSchema LedgerEntryType
deriving instance ToSchema AccountType
deriving instance ToSchema Account
deriving instance ToSchema LedgerEntry
deriving instance ToSchema VerificationType
deriving instance ToSchema VerificationStatus
deriving instance ToSchema CustomerVerification
deriving instance ToSchema ReportingStatus
deriving instance ToSchema ComplianceRecord
deriving instance ToSchema InventoryStatus