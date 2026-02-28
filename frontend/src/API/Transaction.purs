module API.Transaction where

import Prelude

import API.Request as Request
import Data.Either (Either(..))
import Data.Maybe (Maybe, maybe)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Register (CloseRegisterRequest, CloseRegisterResult, OpenRegisterRequest, Register)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)
import Types.UUID (UUID)
import Yoga.JSON (readJSON_)

getRegister :: UserId -> UUID -> Aff (Either String Register)
getRegister userId registerId =
  Request.authGet userId ("/register/" <> show registerId)

createRegister :: UserId -> Register -> Aff (Either String Register)
createRegister userId register =
  Request.authPost userId "/register" register

openRegister :: UserId -> OpenRegisterRequest -> UUID -> Aff (Either String Register)
openRegister userId request registerId =
  Request.authPost userId ("/register/open/" <> show registerId) request

closeRegister :: UserId -> CloseRegisterRequest -> UUID -> Aff (Either String CloseRegisterResult)
closeRegister userId request registerId =
  Request.authPost userId ("/register/close/" <> show registerId) request

createTransaction :: UserId -> Transaction -> Aff (Either String Transaction)
createTransaction userId transaction =
  Request.authPostChecked userId "/transaction" transaction

getTransaction :: UserId -> UUID -> Aff (Either String Transaction)
getTransaction userId transactionId =
  Request.authGet userId ("/transaction/" <> show transactionId)

finalizeTransaction :: UserId -> UUID -> Aff (Either String Transaction)
finalizeTransaction userId transactionId =
  Request.authPostEmpty userId ("/transaction/finalize/" <> show transactionId)

voidTransaction :: UserId -> UUID -> String -> Aff (Either String Transaction)
voidTransaction userId transactionId reason =
  Request.authPost userId ("/transaction/void/" <> show transactionId) reason

addTransactionItem :: UserId -> TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem userId item = do
  result <- Request.authPostChecked userId "/transaction/item" item

  pure $ case result of
    Left err -> Left (parseErrorResponse err)
    Right parsed -> Right parsed

removeTransactionItem :: UserId -> UUID -> Aff (Either String Unit)
removeTransactionItem userId itemId =
  Request.authDeleteUnit userId ("/transaction/item/" <> show itemId)

clearTransaction :: UserId -> UUID -> Aff (Either String Unit)
clearTransaction userId transactionId =
  Request.authPostUnit userId ("/transaction/clear/" <> show transactionId)

addPaymentTransaction :: UserId -> PaymentTransaction -> Aff (Either String PaymentTransaction)
addPaymentTransaction userId payment =
  Request.authPost userId "/transaction/payment" payment

removePaymentTransaction :: UserId -> UUID -> Aff (Either String Unit)
removePaymentTransaction userId paymentId =
  Request.authDeleteUnit userId ("/transaction/payment/" <> show paymentId)

type ErrorResponse = { error :: String }

parseErrorResponse :: String -> String
parseErrorResponse str =
  maybe str _.error (readJSON_ str :: Maybe ErrorResponse)