module Services.SaleActions
  ( PaymentInput
  , addItem
  , removeItem
  , addPayment
  , removePayment
  , clear
  , finalize
  ) where

import API.Request (ApiError)
import API.SaleCommand as API
import Data.Either (Either)
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Types.Inventory (MenuItem(..))
import Types.Transaction (PaymentMethod)
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

type PaymentInput =
  { method :: PaymentMethod
  , amount :: Int
  , tendered :: Maybe Int
  , authCode :: Maybe String
  }

-- Only the SKU and quantity are sent. The backend prices the line.

addItem
  :: UUID
  -> MenuItem
  -> Int
  -> Aff (Either ApiError Sale.SaleTransaction)
addItem saleId (MenuItem item) quantity =
  API.addItem
    { addItemSaleId: saleId
    , addItemSku: item.sku
    , addItemQuantity: quantity
    }

removeItem :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
removeItem = API.removeItem

addPayment
  :: UUID
  -> PaymentInput
  -> Aff (Either ApiError Sale.SaleTransaction)
addPayment saleId input =
  API.addPayment
    { addPaymentSaleId: saleId
    , addPaymentMethod: input.method
    , addPaymentAmount: input.amount
    , addPaymentTendered: input.tendered
    , addPaymentReference: input.authCode
    }

removePayment :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
removePayment = API.removePayment

clear :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
clear = API.clear

finalize :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
finalize = API.finalize
