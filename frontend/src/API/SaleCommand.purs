module API.SaleCommand where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Data.Either (Either)
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Types.Transaction (PaymentMethod)
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

-- The backend records the session user as the sale's opener and ignores
-- startSaleEmployeeId. The field is still required in the request body.

type StartSaleRequest =
  { startSaleEmployeeId :: UUID
  , startSaleRegisterId :: UUID
  , startSaleLocationId :: UUID
  }

type AddItemRequest =
  { addItemSaleId :: UUID
  , addItemSku :: UUID
  , addItemQuantity :: Int
  }

-- Amounts are cents. With no tendered amount the payment is exact.

type AddPaymentRequest =
  { addPaymentSaleId :: UUID
  , addPaymentMethod :: PaymentMethod
  , addPaymentAmount :: Int
  , addPaymentTendered :: Maybe Int
  , addPaymentReference :: Maybe String
  }

-- Refusals the sale writes below can return:
--   400  insufficient inventory, or a line the pricing rules reject
--   403  the sale belongs to another employee
--   404  the sale, item, line or payment is not found
--   409  the sale is no longer open, or finalize was refused

startSale :: StartSaleRequest -> Aff (Either ApiError Sale.SaleTransaction)
startSale req = Request.post "/pos/sale" req

addItem :: AddItemRequest -> Aff (Either ApiError Sale.SaleTransaction)
addItem req = Request.post "/pos/sale/item" req

removeItem :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
removeItem itemId = Request.delete ("/pos/sale/item/" <> show itemId)

addPayment :: AddPaymentRequest -> Aff (Either ApiError Sale.SaleTransaction)
addPayment req = Request.post "/pos/sale/payment" req

removePayment :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
removePayment paymentId =
  Request.delete ("/pos/sale/payment/" <> show paymentId)

clear :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
clear saleId = Request.postEmpty ("/pos/sale/clear/" <> show saleId)

finalize :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
finalize saleId = Request.postEmpty ("/pos/sale/finalize/" <> show saleId)
