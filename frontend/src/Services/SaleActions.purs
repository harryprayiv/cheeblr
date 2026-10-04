module Services.SaleActions
  ( PaymentInput
  , addItem
  , removeItem
  , addPayment
  , removePayment
  , clear
  , finalize
  , startNext
  ) where

import API.SaleCommand as API
import Data.Either (Either)
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Inventory (MenuItem(..))
import Types.Transaction (PaymentMethod)
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

-- Every action the transaction screen can take on a sale. Each one sends a
-- command to the backend and returns the sale the backend answers with, so
-- the screen never edits its own copy and never computes money.

-- What the payment form produces. Amounts are in cents.
type PaymentInput =
  { method :: PaymentMethod
  , amount :: Int
  , tendered :: Maybe Int
  , authCode :: Maybe String
  }

-- Only the SKU and quantity are sent. The backend prices the line.
addItem
  :: UserId
  -> UUID
  -> MenuItem
  -> Int
  -> Aff (Either String Sale.SaleTransaction)
addItem userId saleId (MenuItem item) quantity =
  API.addItem userId
    { addItemSaleId: saleId
    , addItemSku: item.sku
    , addItemQuantity: quantity
    }

removeItem
  :: UserId -> UUID -> UUID -> Aff (Either String Sale.SaleTransaction)
removeItem userId _saleId itemId =
  API.removeItem userId itemId

addPayment
  :: UserId
  -> UUID
  -> PaymentInput
  -> Aff (Either String Sale.SaleTransaction)
addPayment userId saleId input =
  API.addPayment userId
    { addPaymentSaleId: saleId
    , addPaymentMethod: input.method
    , addPaymentAmount: input.amount
    , addPaymentTendered: input.tendered
    , addPaymentReference: input.authCode
    }

removePayment
  :: UserId -> UUID -> UUID -> Aff (Either String Sale.SaleTransaction)
removePayment userId _saleId paymentId =
  API.removePayment userId paymentId

clear :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
clear = API.clear

finalize :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
finalize = API.finalize

-- Opens a new sale for the same employee, register and location as the one
-- just finished.
startNext
  :: UserId
  -> Sale.SaleTransaction
  -> Aff (Either String Sale.SaleTransaction)
startNext userId previous =
  API.startSale userId
    { startSaleEmployeeId: previous.saleEmployeeId
    , startSaleRegisterId: previous.saleRegisterId
    , startSaleLocationId: previous.saleLocationId
    }