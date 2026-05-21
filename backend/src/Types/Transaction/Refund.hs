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

import qualified Data.Aeson as Aeson
import Data.Aeson (FromJSON (..), ToJSON (..))
import qualified Data.Char as Char
import qualified Data.List as List
import Data.OpenApi
  ( SchemaOptions (..)
  , ToSchema (..)
  , fromAesonOptions
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
-- Wire format (Phase 2H-2)
-- ---------------------------------------------------------------------------
--
-- Same conventions as 'Types.Transaction.Sale'. Field names strip the
-- type-specific prefix; schema names are forced to "RefundItem",
-- "RefundDiscount", etc to avoid collision with the Sale-side schemas
-- in the OpenAPI definitions map.

stripFieldPrefix :: String -> String -> String
stripFieldPrefix prefix s = case List.stripPrefix prefix s of
  Just (c : rest) -> Char.toLower c : rest
  Just []         -> s
  Nothing         -> s

itemAesonOptions :: Aeson.Options
itemAesonOptions = Aeson.defaultOptions
  { Aeson.fieldLabelModifier = stripFieldPrefix "item" }

discountAesonOptions :: Aeson.Options
discountAesonOptions = Aeson.defaultOptions
  { Aeson.fieldLabelModifier = stripFieldPrefix "discount" }

taxAesonOptions :: Aeson.Options
taxAesonOptions = Aeson.defaultOptions
  { Aeson.fieldLabelModifier = stripFieldPrefix "tax" }

paymentAesonOptions :: Aeson.Options
paymentAesonOptions = Aeson.defaultOptions
  { Aeson.fieldLabelModifier = stripFieldPrefix "payment" }

refundTransactionAesonOptions :: Aeson.Options
refundTransactionAesonOptions = Aeson.defaultOptions
  { Aeson.fieldLabelModifier = stripFieldPrefix "refund" }

namedSchema :: String -> Aeson.Options -> SchemaOptions
namedSchema schemaName opts =
  (fromAesonOptions opts) { datatypeNameModifier = const schemaName }

-- Item

instance ToJSON Item where
  toJSON     = Aeson.genericToJSON itemAesonOptions
  toEncoding = Aeson.genericToEncoding itemAesonOptions

instance FromJSON Item where
  parseJSON = Aeson.genericParseJSON itemAesonOptions

instance ToSchema Item where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "RefundItem" itemAesonOptions)

-- Discount

instance ToJSON Discount where
  toJSON     = Aeson.genericToJSON discountAesonOptions
  toEncoding = Aeson.genericToEncoding discountAesonOptions

instance FromJSON Discount where
  parseJSON = Aeson.genericParseJSON discountAesonOptions

instance ToSchema Discount where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "RefundDiscount" discountAesonOptions)

-- Tax

instance ToJSON Tax where
  toJSON     = Aeson.genericToJSON taxAesonOptions
  toEncoding = Aeson.genericToEncoding taxAesonOptions

instance FromJSON Tax where
  parseJSON = Aeson.genericParseJSON taxAesonOptions

instance ToSchema Tax where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "RefundTax" taxAesonOptions)

-- Payment

instance ToJSON Payment where
  toJSON     = Aeson.genericToJSON paymentAesonOptions
  toEncoding = Aeson.genericToEncoding paymentAesonOptions

instance FromJSON Payment where
  parseJSON = Aeson.genericParseJSON paymentAesonOptions

instance ToSchema Payment where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "RefundPayment" paymentAesonOptions)

-- RefundTransaction

instance ToJSON RefundTransaction where
  toJSON     = Aeson.genericToJSON refundTransactionAesonOptions
  toEncoding = Aeson.genericToEncoding refundTransactionAesonOptions

instance FromJSON RefundTransaction where
  parseJSON = Aeson.genericParseJSON refundTransactionAesonOptions

instance ToSchema RefundTransaction where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "RefundTransaction" refundTransactionAesonOptions)