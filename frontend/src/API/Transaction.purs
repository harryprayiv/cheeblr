module API.Transaction where

import Prelude

import API.Request as Request
import Data.Either (Either(..))
import Data.Maybe (Maybe, maybe)
import Effect.Aff (Aff)
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import Types.Register (CloseRegisterRequest, CloseRegisterResult, OpenRegisterRequest, Register)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)
import Types.UUID (UUID)
import Yoga.JSON (readJSON_)

-- Register operations
getRegister :: Ref AuthContext -> UUID -> Aff (Either String Register)
getRegister authRef registerId =
  Request.authGet authRef ("/register/" <> show registerId)

createRegister :: Ref AuthContext -> Register -> Aff (Either String Register)
createRegister authRef register =
  Request.authPost authRef "/register" register

openRegister :: Ref AuthContext -> OpenRegisterRequest -> UUID -> Aff (Either String Register)
openRegister authRef request registerId =
  Request.authPost authRef ("/register/open/" <> show registerId) request

closeRegister :: Ref AuthContext -> CloseRegisterRequest -> UUID -> Aff (Either String CloseRegisterResult)
closeRegister authRef request registerId =
  Request.authPost authRef ("/register/close/" <> show registerId) request

-- Transaction lifecycle
createTransaction :: Ref AuthContext -> Transaction -> Aff (Either String Transaction)
createTransaction authRef transaction =
  Request.authPostChecked authRef "/transaction" transaction

getTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
getTransaction authRef transactionId =
  Request.authGet authRef ("/transaction/" <> show transactionId)

finalizeTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
finalizeTransaction authRef transactionId =
  Request.authPostEmpty authRef ("/transaction/finalize/" <> show transactionId)

voidTransaction :: Ref AuthContext -> UUID -> String -> Aff (Either String Transaction)
voidTransaction authRef transactionId reason =
  Request.authPost authRef ("/transaction/void/" <> show transactionId) reason

-- Transaction items
addTransactionItem :: Ref AuthContext -> TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem authRef item = do
  result <- Request.authPostChecked authRef "/transaction/item" item
  -- Parse server error JSON if available for cleaner error messages
  pure $ case result of
    Left err -> Left (parseErrorResponse err)
    Right parsed -> Right parsed

removeTransactionItem :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removeTransactionItem authRef itemId =
  Request.authDeleteUnit authRef ("/transaction/item/" <> show itemId)

clearTransaction :: Ref AuthContext -> UUID -> Aff (Either String Unit)
clearTransaction authRef transactionId =
  Request.authPostUnit authRef ("/transaction/clear/" <> show transactionId)

-- Payments
addPaymentTransaction :: Ref AuthContext -> PaymentTransaction -> Aff (Either String PaymentTransaction)
addPaymentTransaction authRef payment =
  Request.authPost authRef "/transaction/payment" payment

removePaymentTransaction :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removePaymentTransaction authRef paymentId =
  Request.authDeleteUnit authRef ("/transaction/payment/" <> show paymentId)

-- Error parsing helper
type ErrorResponse = { error :: String }

-- | Attempts to extract the "error" field from a JSON error response string.
-- | If the string contains JSON like {"error": "some message"}, returns "some message".
-- | Otherwise returns the original string unchanged.
parseErrorResponse :: String -> String
parseErrorResponse str =
  maybe str _.error (readJSON_ str :: Maybe ErrorResponse)