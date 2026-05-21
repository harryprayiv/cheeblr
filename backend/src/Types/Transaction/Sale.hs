{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Transaction.Sale
  (
    Item (..)
  , Discount (..)
  , Tax (..)
  , Payment (..)

  , SaleTransaction (..)
  , SaleType (..)
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
import Types.Transaction (DiscountType, PaymentMethod, TaxCategory, TransactionStatus)
import Types.Transaction.Class (IsTransaction (..))

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

data Item = Item
  { itemId            :: UUID
  , itemTransactionId :: UUID
  , itemMenuItemSku   :: UUID
  , itemQuantity      :: SaleQuantity
  , itemPricePerUnit  :: SaleMoney
  , itemDiscounts     :: [Discount]
  , itemTaxes         :: [Tax]
  , itemSubtotal      :: SaleMoney
  , itemTotal         :: SaleMoney
  }
  deriving stock (Show, Eq, Generic)

data Discount = Discount
  { discountType       :: DiscountType
  , discountAmount     :: SaleMoney
  , discountReason     :: Text
  , discountApprovedBy :: Maybe UUID
  }
  deriving stock (Show, Eq, Generic)

data Tax = Tax
  { taxCategory    :: TaxCategory
  , taxRate        :: Scientific
  , taxAmount      :: SaleMoney
  , taxDescription :: Text
  }
  deriving stock (Show, Eq, Generic)

data Payment = Payment
  { paymentId                :: UUID
  , paymentTransactionId     :: UUID
  , paymentMethod            :: PaymentMethod
  , paymentAmount            :: SaleMoney
  , paymentTendered          :: SaleMoney
  , paymentChange            :: SaleMoney
  , paymentReference         :: Maybe Text
  , paymentApproved          :: Bool
  , paymentAuthorizationCode :: Maybe Text
  }
  deriving stock (Show, Eq, Generic)

data SaleType
  = StandardSale
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative
  deriving stock (Show, Eq, Ord, Generic, Read)

data SaleTransaction = SaleTransaction
  { saleId            :: UUID
  , saleStatus        :: TransactionStatus
  , saleCreated       :: UTCTime
  , saleCompleted     :: Maybe UTCTime
  , saleCustomerId    :: Maybe UUID
  , saleEmployeeId    :: UUID
  , saleRegisterId    :: UUID
  , saleLocationId    :: LocationId
  , saleItems         :: [Item]
  , salePayments      :: [Payment]
  , saleSubtotal      :: SaleMoney
  , saleDiscountTotal :: SaleMoney
  , saleTaxTotal      :: SaleMoney
  , saleTotal         :: SaleMoney
  , saleType          :: SaleType
  , saleIsVoided      :: Bool
  , saleVoidReason    :: Maybe Text
  , saleIsRefunded    :: Bool
  , saleRefundReason  :: Maybe Text
  , saleNotes         :: Maybe Text
  }
  deriving stock (Show, Eq, Generic)

instance IsTransaction SaleTransaction where
  txId         = saleId
  txCreatedAt  = saleCreated
  txEmployeeId = saleEmployeeId
  txRegisterId = saleRegisterId
  txLocationId = saleLocationId

-- ---------------------------------------------------------------------------
-- Wire format (Phase 2H-2)
-- ---------------------------------------------------------------------------
--
-- Aeson field naming: strip the type-specific prefix and lowercase the
-- first letter. 'saleId' becomes "id", 'itemMenuItemSku' becomes
-- "menuItemSku", 'discountApprovedBy' becomes "approvedBy", etc. Matches
-- the convention already used in 'Types.Public.AvailableItem'.
--
-- OpenAPI schema naming: because 'Sale.Item' / 'Refund.Item' (and the
-- other line types) share Generic type names, every typed schema gets
-- an explicit 'datatypeNameModifier' to force a unique top-level name
-- ("SaleItem", "RefundItem", etc). Without this, the second-registered
-- schema would silently overwrite the first in the OpenAPI definitions
-- map.
--
-- 'SaleType' uses default options. Its constructors are nullary so the
-- Aeson default (allNullaryToStringTag = True) yields plain string
-- values like "StandardSale" on the wire.

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

saleTransactionAesonOptions :: Aeson.Options
saleTransactionAesonOptions = Aeson.defaultOptions
  { Aeson.fieldLabelModifier = stripFieldPrefix "sale" }

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
    genericDeclareNamedSchema (namedSchema "SaleItem" itemAesonOptions)

-- Discount

instance ToJSON Discount where
  toJSON     = Aeson.genericToJSON discountAesonOptions
  toEncoding = Aeson.genericToEncoding discountAesonOptions

instance FromJSON Discount where
  parseJSON = Aeson.genericParseJSON discountAesonOptions

instance ToSchema Discount where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "SaleDiscount" discountAesonOptions)

-- Tax

instance ToJSON Tax where
  toJSON     = Aeson.genericToJSON taxAesonOptions
  toEncoding = Aeson.genericToEncoding taxAesonOptions

instance FromJSON Tax where
  parseJSON = Aeson.genericParseJSON taxAesonOptions

instance ToSchema Tax where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "SaleTax" taxAesonOptions)

-- Payment

instance ToJSON Payment where
  toJSON     = Aeson.genericToJSON paymentAesonOptions
  toEncoding = Aeson.genericToEncoding paymentAesonOptions

instance FromJSON Payment where
  parseJSON = Aeson.genericParseJSON paymentAesonOptions

instance ToSchema Payment where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "SalePayment" paymentAesonOptions)

-- SaleType (nullary sum type; default options)

instance ToJSON SaleType
instance FromJSON SaleType
instance ToSchema SaleType

-- SaleTransaction

instance ToJSON SaleTransaction where
  toJSON     = Aeson.genericToJSON saleTransactionAesonOptions
  toEncoding = Aeson.genericToEncoding saleTransactionAesonOptions

instance FromJSON SaleTransaction where
  parseJSON = Aeson.genericParseJSON saleTransactionAesonOptions

instance ToSchema SaleTransaction where
  declareNamedSchema =
    genericDeclareNamedSchema (namedSchema "SaleTransaction" saleTransactionAesonOptions)