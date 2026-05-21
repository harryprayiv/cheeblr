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
  , saleKind          :: SaleType
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
-- Wire format
-- ---------------------------------------------------------------------------
--
-- JSON field names match the Haskell record field names verbatim. This
-- replaces the previous 'stripFieldPrefix' convention (which produced
-- "id"/"menuItemSku"/etc.) — that convention collided with PureScript
-- reserved words ('type' as a record label) and offered no value
-- commensurate with the blast radius across consumers.
--
-- The 'saleType' field was renamed to 'saleKind' as part of this revert
-- so the wire field is "saleKind" rather than "saleType".
--
-- OpenAPI schema naming still needs disambiguation: 'Sale.Item' and
-- 'Refund.Item' (and the other line types) share Generic type names,
-- so every typed schema gets an explicit 'datatypeNameModifier' to
-- force a unique top-level name ("SaleItem", "RefundItem", etc).
-- Without this, the second-registered schema would silently overwrite
-- the first in the OpenAPI definitions map.

nameAs :: String -> SchemaOptions
nameAs n = defaultSchemaOptions { datatypeNameModifier = const n }

-- Item

instance ToJSON Item
instance FromJSON Item

instance ToSchema Item where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "SaleItem")

-- Discount

instance ToJSON Discount
instance FromJSON Discount

instance ToSchema Discount where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "SaleDiscount")

-- Tax

instance ToJSON Tax
instance FromJSON Tax

instance ToSchema Tax where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "SaleTax")

-- Payment

instance ToJSON Payment
instance FromJSON Payment

instance ToSchema Payment where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "SalePayment")

-- SaleType (nullary sum type; default options yield string-tag wire format)

instance ToJSON SaleType
instance FromJSON SaleType
instance ToSchema SaleType

-- SaleTransaction

instance ToJSON SaleTransaction
instance FromJSON SaleTransaction

instance ToSchema SaleTransaction where
  declareNamedSchema = genericDeclareNamedSchema (nameAs "SaleTransaction")