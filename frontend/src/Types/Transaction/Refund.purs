-- FILE: ./frontend/src/Types/Transaction/Refund.purs
module Types.Transaction.Refund
  ( Item
  , Discount
  , Tax
  , Payment
  , RefundTransaction
  ) where

import Prelude

import Data.DateTime (DateTime)
import Data.Maybe (Maybe)
import Types.Primitives.Money (RefundMoney, SaleMoney)
import Types.Primitives.Quantity (RefundQuantity)
import Types.Transaction (DiscountType, PaymentMethod, TaxCategory)
import Types.UUID (UUID)

-- Refunds have no status field and no lifecycle: they're created
-- Completed and always reference an original sale.

type Item =
  { itemId            :: UUID
  , itemTransactionId :: UUID
  , itemMenuItemSku   :: UUID
  , itemQuantity      :: RefundQuantity
  , itemPricePerUnit  :: SaleMoney
  -- ^ Catalog price stays non-negative; refund-ness lives in subtotal/total.
  , itemDiscounts     :: Array Discount
  , itemTaxes         :: Array Tax
  , itemSubtotal      :: RefundMoney
  , itemTotal         :: RefundMoney
  }

type Discount =
  { discountType       :: DiscountType
  , discountAmount     :: RefundMoney
  , discountReason     :: String
  , discountApprovedBy :: Maybe UUID
  }

type Tax =
  { taxCategory    :: TaxCategory
  , taxRate        :: Number
  , taxAmount      :: RefundMoney
  , taxDescription :: String
  }

type Payment =
  { paymentId                :: UUID
  , paymentTransactionId     :: UUID
  , paymentMethod            :: PaymentMethod
  , paymentAmount            :: RefundMoney
  , paymentTendered          :: RefundMoney
  , paymentChange            :: RefundMoney
  , paymentReference         :: Maybe String
  , paymentApproved          :: Boolean
  , paymentAuthorizationCode :: Maybe String
  }

type RefundTransaction =
  { refundId                     :: UUID
  , refundCreated                :: DateTime
  , refundCompleted              :: DateTime
  , refundCustomerId             :: Maybe UUID
  , refundEmployeeId             :: UUID
  , refundRegisterId             :: UUID
  , refundLocationId             :: UUID
  , refundItems                  :: Array Item
  , refundPayments               :: Array Payment
  , refundSubtotal               :: RefundMoney
  , refundDiscountTotal          :: RefundMoney
  , refundTaxTotal               :: RefundMoney
  , refundTotal                  :: RefundMoney
  , refundReferenceTransactionId :: UUID
  , refundReason                 :: String
  , refundNotes                  :: Maybe String
  }