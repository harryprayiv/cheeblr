module Cheeblr.API.Transaction where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.AuthRequest as AR
import Data.Either (Either)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Ref (Ref)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)
import Types.UUID (UUID)
import Yoga.JSON (readJSON_)

----------------------------------------------------------------------
-- Transaction CRUD
----------------------------------------------------------------------

createTransaction :: Ref AuthContext -> Transaction -> Aff (Either String Transaction)
createTransaction ref txn =
  AR.authPostChecked ref "/transaction" txn

getTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
getTransaction ref txnId =
  AR.authGet ref ("/transaction/" <> show txnId)

finalizeTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
finalizeTransaction ref txnId =
  AR.authPostEmpty ref ("/transaction/finalize/" <> show txnId)

voidTransaction :: Ref AuthContext -> UUID -> String -> Aff (Either String Transaction)
voidTransaction ref txnId reason =
  AR.authPost ref ("/transaction/void/" <> show txnId) reason

----------------------------------------------------------------------
-- Transaction Items
----------------------------------------------------------------------

addItem :: Ref AuthContext -> TransactionItem -> Aff (Either String TransactionItem)
addItem ref item =
  AR.authPostChecked ref "/transaction/item" item

removeItem :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removeItem ref itemId =
  AR.authDeleteUnit ref ("/transaction/item/" <> show itemId)

clearItems :: Ref AuthContext -> UUID -> Aff (Either String Unit)
clearItems ref txnId =
  AR.authPostUnit ref ("/transaction/clear/" <> show txnId)

----------------------------------------------------------------------
-- Payments
----------------------------------------------------------------------

addPayment :: Ref AuthContext -> PaymentTransaction -> Aff (Either String PaymentTransaction)
addPayment ref payment =
  AR.authPost ref "/transaction/payment" payment

removePayment :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removePayment ref paymentId =
  AR.authDeleteUnit ref ("/transaction/payment/" <> show paymentId)

----------------------------------------------------------------------
-- Error parsing
----------------------------------------------------------------------

type ErrorResponse = { error :: String }

parseErrorResponse :: String -> String
parseErrorResponse str =
  case (readJSON_ str :: Maybe ErrorResponse) of
    Just resp -> resp.error
    Nothing -> str