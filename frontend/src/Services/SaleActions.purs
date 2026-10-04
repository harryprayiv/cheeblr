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

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe, fromMaybe)
import Data.Newtype (unwrap)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Services.TransactionService as TransactionService
import Types.Inventory (MenuItem(..))
import Types.Transaction (PaymentMethod)
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

-- Every action the transaction screen can take on a sale. Each one returns
-- the sale as the backend holds it after the action, so the screen never
-- edits its own copy.

-- What the payment form produces. Amounts are in cents.
type PaymentInput =
  { method :: PaymentMethod
  , amount :: Int
  , tendered :: Maybe Int
  , authCode :: Maybe String
  }

-- Runs a change, then fetches the sale. A failed change is returned as is
-- and the fetch is skipped.
thenRefetch
  :: forall a
   . UserId
  -> UUID
  -> Aff (Either String a)
  -> Aff (Either String Sale.SaleTransaction)
thenRefetch userId saleId change = do
  result <- change
  case result of
    Left err -> pure (Left err)
    Right _ -> TransactionService.getSale userId saleId

addItem
  :: UserId
  -> UUID
  -> MenuItem
  -> Int
  -> Aff (Either String Sale.SaleTransaction)
addItem userId saleId (MenuItem item) quantity =
  thenRefetch userId saleId $
    TransactionService.createSaleItem userId saleId item.sku quantity
      (unwrap item.price)

removeItem
  :: UserId -> UUID -> UUID -> Aff (Either String Sale.SaleTransaction)
removeItem userId saleId itemId =
  thenRefetch userId saleId $
    TransactionService.removeSaleItem userId itemId

-- With no tendered amount the payment is treated as exact.
addPayment
  :: UserId
  -> UUID
  -> PaymentInput
  -> Aff (Either String Sale.SaleTransaction)
addPayment userId saleId input =
  thenRefetch userId saleId $
    TransactionService.addPayment userId saleId input.method input.amount
      (fromMaybe input.amount input.tendered)
      input.authCode

removePayment
  :: UserId -> UUID -> UUID -> Aff (Either String Sale.SaleTransaction)
removePayment userId saleId paymentId =
  thenRefetch userId saleId $
    TransactionService.removeSalePayment userId paymentId

clear :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
clear userId saleId =
  thenRefetch userId saleId $
    TransactionService.clearSale userId saleId

-- The finalize endpoint already returns the completed sale.
finalize :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
finalize = TransactionService.finalizeSale

-- Opens a new sale for the same employee, register and location as the one
-- just finished. Those ids were set by Main when the page opened and every
-- sale carries them.
startNext
  :: UserId
  -> Sale.SaleTransaction
  -> Aff (Either String Sale.SaleTransaction)
startNext userId previous =
  TransactionService.startSale userId
    { employeeId: previous.saleEmployeeId
    , registerId: previous.saleRegisterId
    , locationId: previous.saleLocationId
    }