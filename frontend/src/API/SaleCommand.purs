module API.SaleCommand where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Transaction (PaymentMethod)
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

-- The register's sale commands. A request says what is wanted. The backend
-- looks up the price, applies tax, computes change, generates ids, and
-- answers every command with the whole sale as it now stands.
--
-- Field names match the Haskell records in Types.Transaction.Request.

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

startSale
  :: UserId -> StartSaleRequest -> Aff (Either String Sale.SaleTransaction)
startSale userId request =
  Request.authPostChecked userId "/pos/sale" request

addItem
  :: UserId -> AddItemRequest -> Aff (Either String Sale.SaleTransaction)
addItem userId request =
  Request.authPostChecked userId "/pos/sale/item" request

removeItem :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
removeItem userId itemId =
  Request.authDelete userId ("/pos/sale/item/" <> show itemId)

addPayment
  :: UserId -> AddPaymentRequest -> Aff (Either String Sale.SaleTransaction)
addPayment userId request =
  Request.authPostChecked userId "/pos/sale/payment" request

removePayment :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
removePayment userId paymentId =
  Request.authDelete userId ("/pos/sale/payment/" <> show paymentId)

clear :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
clear userId saleId =
  Request.authPostEmpty userId ("/pos/sale/clear/" <> show saleId)

finalize :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
finalize userId saleId =
  Request.authPostEmpty userId ("/pos/sale/finalize/" <> show saleId)
