{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Transaction.Refund
  (
    Item (..)
  , Discount (..)
  , Tax (..)
  , Payment (..)

  , RefundTransaction (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi
  ( SchemaOptions
  , ToSchema (..)
  , datatypeNameModifier
  , defaultSchemaOptions
  , genericDeclareNamedSchema
  )
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

import Types.Location (LocationId)
import Types.Primitives.Money
import Types.Primitives.Quantity
import Types.Transaction (DiscountType, PaymentMethod, TaxCategory)
import Types.Transaction.Class (IsTransaction (..))

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

data Item = Item
  { itemId            :: UUID
  , itemTransactionId :: UUID
  , itemMenuItemSku   :: UUID
  , itemQuantity      :: RefundQuantity
  , itemPricePerUnit  :: SaleMoney
  -- ^ Catalog price stays non-negative; the refund-ness shows up in
  -- 'itemSubtotal' and 'itemTotal', which are 'RefundMoney'.
  , itemDiscounts     :: [Discount]
  , itemTaxes         :: [Tax]
  , itemSubtotal      :: RefundMoney
  , itemTotal         :: RefundMoney
  }
  deriving stock (Show, Eq, Generic)

data Discount = Discount
  { discountType       :: DiscountType
  , discountAmount     :: RefundMoney
  , discountReason     :: Text
  , discountApprovedBy :: Maybe UUID
  }
  deriving stock (Show, Eq, Generic)

data Tax = Tax
  { taxCategory    :: TaxCategory
  , taxRate        :: Scientific
  , taxAmount      :: RefundMoney
  , taxDescription :: Text
  }
  deriving stock (Show, Eq, Generic)

data Payment = Payment
  { paymentId                :: UUID
  , paymentTransactionId     :: UUID
  , paymentMethod            :: PaymentMethod
  , paymentAmount            :: RefundMoney
  , paymentTendered          :: RefundMoney
  , paymentChange            :: RefundMoney
  , paymentReference         :: Maybe Text
  , paymentApproved          :: Bool
  , paymentAuthorizationCode :: Maybe Text
  }
  deriving stock (Show, Eq, Generic)

data RefundTransaction = RefundTransaction
  { refundId                     :: UUID
  , refundCreated                :: UTCTime
  , refundCompleted              :: UTCTime
  , refundCustomerId             :: Maybe UUID
  , refundEmployeeId             :: UUID
  , refundRegisterId             :: UUID
  , refundLocationId             :: LocationId
  , refundItems                  :: [Item]
  , refundPayments               :: [Payment]
  , refundSubtotal               :: RefundMoney
  , refundDiscountTotal          :: RefundMoney
  , refundTaxTotal               :: RefundMoney
  , refundTotal                  :: RefundMoney
  , refundReferenceTransactionId :: UUID
  , refundReason                 :: Text
  , refundNotes                  :: Maybe Text
  }
  deriving stock (Show, Eq, Generic)

instance IsTransaction RefundTransaction where
  txId         = refundId
  txCreatedAt  = refundCreated
  txEmployeeId = refundEmployeeId
  txRegisterId = refundRegisterId
  txLocationId = refundLocationId

-- ---------------------------------------------------------------------------
-- Wire format
-- ---------------------------------------------------------------------------
--
-- Same conventions as 'Types.Transaction.Sale': JSON field names match
-- the Haskell record field names verbatim; schema names are forced to
-- "RefundItem", "RefundDiscount", etc to avoid collision with the
-- Sale-side schemas in the OpenAPI definitions map.

nameAs :: String -> SchemaOptions
nameAs n = defaultSchemaOptions { datatypeNameModifier = const n }

-- Item

instance ToJSON Item
instance FromJSON Item

instance ToSchema Item where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "RefundItem")

-- Discount

instance ToJSON Discount
instance FromJSON Discount

instance ToSchema Discount where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "RefundDiscount")

-- Tax

instance ToJSON Tax
instance FromJSON Tax

instance ToSchema Tax where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "RefundTax")

-- Payment

instance ToJSON Payment
instance FromJSON Payment

instance ToSchema Payment where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "RefundPayment")

-- RefundTransaction

instance ToJSON RefundTransaction
instance FromJSON RefundTransaction

instance ToSchema RefundTransaction where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "RefundTransaction")