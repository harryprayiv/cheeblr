-- FILE: ./frontend/src/Types/Transaction/Sale.purs
module Types.Transaction.Sale
  ( SaleType(..)
  , Item
  , Discount
  , Tax
  , Payment
  , SaleTransaction
  ) where

import Prelude

import Data.DateTime (DateTime)
import Data.Maybe (Maybe)
import Foreign (ForeignError(..), fail)
import Types.Primitives.Money (SaleMoney)
import Types.Primitives.Quantity (SaleQuantity)
import Types.Transaction
  ( DiscountType
  , PaymentMethod
  , TaxCategory
  , TransactionStatus
  )
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

-- | Mirrors backend 'Sale.SaleType'. Nullary sum; wire form is the
-- | constructor name as a bare string.
data SaleType
  = StandardSale
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative

derive instance eqSaleType :: Eq SaleType
derive instance ordSaleType :: Ord SaleType

instance showSaleType :: Show SaleType where
  show StandardSale = "StandardSale"
  show Exchange = "Exchange"
  show InventoryAdjustment = "InventoryAdjustment"
  show ManagerComp = "ManagerComp"
  show Administrative = "Administrative"

instance writeForeignSaleType :: WriteForeign SaleType where
  writeImpl = writeImpl <<< show

instance readForeignSaleType :: ReadForeign SaleType where
  readImpl f = do
    s <- readImpl f
    case s of
      "StandardSale" -> pure StandardSale
      "Exchange" -> pure Exchange
      "InventoryAdjustment" -> pure InventoryAdjustment
      "ManagerComp" -> pure ManagerComp
      "Administrative" -> pure Administrative
      other -> fail (ForeignError $ "Invalid SaleType: " <> other)

-- Field names below match the backend Haskell record fields verbatim.
-- That's now the project-wide convention; do not strip prefixes.

type Item =
  { itemId            :: UUID
  , itemTransactionId :: UUID
  , itemMenuItemSku   :: UUID
  , itemQuantity      :: SaleQuantity
  , itemPricePerUnit  :: SaleMoney
  , itemDiscounts     :: Array Discount
  , itemTaxes         :: Array Tax
  , itemSubtotal      :: SaleMoney
  , itemTotal         :: SaleMoney
  }

type Discount =
  { discountType       :: DiscountType
  , discountAmount     :: SaleMoney
  , discountReason     :: String
  , discountApprovedBy :: Maybe UUID
  }

type Tax =
  { taxCategory    :: TaxCategory
  , taxRate        :: Number
  , taxAmount      :: SaleMoney
  , taxDescription :: String
  }

type Payment =
  { paymentId                :: UUID
  , paymentTransactionId     :: UUID
  , paymentMethod            :: PaymentMethod
  , paymentAmount            :: SaleMoney
  , paymentTendered          :: SaleMoney
  , paymentChange            :: SaleMoney
  , paymentReference         :: Maybe String
  , paymentApproved          :: Boolean
  , paymentAuthorizationCode :: Maybe String
  }

type SaleTransaction =
  { saleId            :: UUID
  , saleStatus        :: TransactionStatus
  , saleCreated       :: DateTime
  , saleCompleted     :: Maybe DateTime
  , saleCustomerId    :: Maybe UUID
  , saleEmployeeId    :: UUID
  , saleRegisterId    :: UUID
  , saleLocationId    :: UUID
  , saleItems         :: Array Item
  , salePayments      :: Array Payment
  , saleSubtotal      :: SaleMoney
  , saleDiscountTotal :: SaleMoney
  , saleTaxTotal      :: SaleMoney
  , saleTotal         :: SaleMoney
  , saleKind          :: SaleType
  , saleIsVoided      :: Boolean
  , saleVoidReason    :: Maybe String
  , saleIsRefunded    :: Boolean
  , saleRefundReason  :: Maybe String
  , saleNotes         :: Maybe String
  }