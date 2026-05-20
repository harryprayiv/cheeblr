{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Types.Transaction.Refund
  ( -- * Line-item types
    Item (..)
  , Discount (..)
  , Tax (..)
  , Payment (..)
    -- * Aggregate
  , RefundTransaction (..)
  ) where

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
-- Line-item types (unchanged from 2C-1/2)
-- ---------------------------------------------------------------------------

data Item = Item
  { itemId            :: UUID
  , itemTransactionId :: UUID
  , itemMenuItemSku   :: UUID
  , itemQuantity      :: RefundQuantity
  , itemPricePerUnit  :: SaleMoney
  -- ^ Unit price stays non-negative; the line subtotal and total are
  -- 'RefundMoney'. The catalog still prices items in positive cents; the
  -- refund-ness shows up in line aggregates.
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

-- ---------------------------------------------------------------------------
-- Aggregate
-- ---------------------------------------------------------------------------

-- | A refund transaction.
--
-- Distinct from 'Types.Transaction.Sale.SaleTransaction' on:
--
-- * 'refundReferenceTransactionId' is REQUIRED. Every refund references an
--   original sale; a refund without one is meaningless.
-- * No status field. Refunds are created Completed and have no lifecycle.
-- * No type field. There is exactly one kind of refund.
-- * No void or refund-of-refund tracking. Refunds aren't voided or refunded
--   themselves; corrective sales handle the rare case where a refund was
--   issued in error.
-- * Money fields use 'RefundMoney' (non-positive invariant).
-- * 'refundReason' is REQUIRED. A refund without a stated reason fails
--   compliance review.
-- * 'refundCompleted' is non-optional. Refunds are created Completed; the
--   field is set at construction.
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