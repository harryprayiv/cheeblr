-- src/Types/Transaction/Sale.hs

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Types.Transaction.Sale
  ( -- * Line-item types
    Item (..)
  , Discount (..)
  , Tax (..)
  , Payment (..)
    -- * Aggregate
  , SaleTransaction (..)
  , SaleType (..)
  ) where

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
-- Line-item types (unchanged from 2C-1/2)
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

-- ---------------------------------------------------------------------------
-- Aggregate
-- ---------------------------------------------------------------------------

-- | Variants of sale-shaped transactions.
--
-- The legacy 'Types.Transaction.TransactionType' enum bundled 'Sale', 'Return',
-- 'Exchange', 'InventoryAdjustment', 'ManagerComp', and 'Administrative'
-- together. Of those, only 'Return' is a genuinely different event and now
-- lives in 'Types.Transaction.Refund'. The other five are all sale-shaped and
-- live here.
data SaleType
  = StandardSale
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative
  deriving stock (Show, Eq, Ord, Generic, Read)

-- | A sale transaction.
--
-- Distinct from 'Types.Transaction.Refund.RefundTransaction' on:
--
-- * Field set differs: no 'referenceTransactionId' (a sale never references
--   another transaction).
-- * Money fields are 'SaleMoney' (non-negative invariant).
-- * Goes through the full state machine in 'State.TransactionMachine':
--   Created -> InProgress -> Completed -> Voided / Refunded.
-- * Tracks whether it's been refunded ('saleIsRefunded'/'saleRefundReason')
--   and whether it's been voided ('saleIsVoided'/'saleVoidReason').
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