{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module Types.Transaction where

import Data.Aeson
import Data.OpenApi (ToParamSchema, ToSchema)
import Data.Scientific (Scientific)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Types.Location (LocationId)
import Web.HttpApiData (FromHttpApiData (..), parseBoundedTextData)

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
  }
  deriving (Show, Eq, Generic)

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
  toJSON (PercentOff pct) =
    object
      [ "discountType" .= ("PERCENT_OFF" :: Text)
      , "percent" .= pct
      ]
  toJSON (AmountOff amt) =
    object
      [ "discountType" .= ("AMOUNT_OFF" :: Text)
      , "amount" .= amt
      ]
  toJSON BuyOneGetOne =
    object ["discountType" .= ("BUY_ONE_GET_ONE" :: Text)]
  toJSON (Custom name amt) =
    object
      [ "discountType" .= ("CUSTOM" :: Text)
      , "name" .= name
      , "amount" .= amt
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
  }
  deriving (Show, Eq, Generic)

instance ToJSON TaxRecord
instance FromJSON TaxRecord

data DiscountRecord = DiscountRecord
  { discountType       :: DiscountType
  , discountAmount     :: Int
  , discountReason     :: Text
  , discountApprovedBy :: Maybe UUID
  }
  deriving (Show, Eq, Generic)

instance ToJSON DiscountRecord
instance FromJSON DiscountRecord

data TransactionItem = TransactionItem
  { transactionItemId              :: UUID
  , transactionItemTransactionId   :: UUID
  , transactionItemMenuItemSku     :: UUID
  , transactionItemQuantity        :: Int
  , transactionItemPricePerUnit    :: Int
  , transactionItemDiscounts       :: [DiscountRecord]
  , transactionItemTaxes           :: [TaxRecord]
  , transactionItemSubtotal        :: Int
  , transactionItemTotal           :: Int
  }
  deriving (Show, Eq, Generic)

instance ToJSON TransactionItem
instance FromJSON TransactionItem

data PaymentTransaction = PaymentTransaction
  { paymentId               :: UUID
  , paymentTransactionId    :: UUID
  , paymentMethod           :: PaymentMethod
  , paymentAmount           :: Int
  , paymentTendered         :: Int
  , paymentChange           :: Int
  , paymentReference        :: Maybe Text
  , paymentApproved         :: Bool
  , paymentAuthorizationCode :: Maybe Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON PaymentMethod where
  toJSON Cash        = String "Cash"
  toJSON Debit       = String "Debit"
  toJSON Credit      = String "Credit"
  toJSON ACH         = String "ACH"
  toJSON GiftCard    = String "GiftCard"
  toJSON StoredValue = String "StoredValue"
  toJSON Mixed       = String "Mixed"
  toJSON (Other t)   = String ("Other:" <> t)

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
  parseJSON = withObject "PaymentTransaction" $ \v ->
    PaymentTransaction
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
  { transactionId                     :: UUID
  , transactionStatus                 :: TransactionStatus
  , transactionCreated                :: UTCTime
  , transactionCompleted              :: Maybe UTCTime
  , transactionCustomerId             :: Maybe UUID
  , transactionEmployeeId             :: UUID
  , transactionRegisterId             :: UUID
  , transactionLocationId             :: LocationId
  , transactionItems                  :: [TransactionItem]
  , transactionPayments               :: [PaymentTransaction]
  , transactionSubtotal               :: Int
  , transactionDiscountTotal          :: Int
  , transactionTaxTotal               :: Int
  , transactionTotal                  :: Int
  , transactionType                   :: TransactionType
  , transactionIsVoided               :: Bool
  , transactionVoidReason             :: Maybe Text
  , transactionIsRefunded             :: Bool
  , transactionRefundReason           :: Maybe Text
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes                  :: Maybe Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON Transaction

instance FromJSON Transaction where
  parseJSON = withObject "Transaction" $ \v ->
    Transaction
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
  }
  deriving (Show, Eq, Generic)

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
  }
  deriving (Show, Eq, Generic)

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
  { customerVerificationId           :: UUID
  , customerVerificationCustomerId   :: UUID
  , customerVerificationType         :: VerificationType
  , customerVerificationStatus       :: VerificationStatus
  , customerVerificationVerifiedBy   :: UUID
  , customerVerificationVerifiedAt   :: UTCTime
  , customerVerificationExpiresAt    :: Maybe UTCTime
  , customerVerificationNotes        :: Maybe Text
  , customerVerificationDocumentId   :: Maybe Text
  }
  deriving (Show, Eq, Generic)

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
  }
  deriving (Show, Eq, Generic)

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

instance FromHttpApiData TransactionStatus where
  parseUrlPiece = parseBoundedTextData

deriving instance Bounded TransactionStatus
deriving instance Enum TransactionStatus

-- OpenAPI schema instances
deriving instance ToSchema TransactionStatus
deriving instance ToParamSchema TransactionStatus
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