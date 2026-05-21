module API.Refund where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Transaction.Refund as Refund
import Types.UUID (UUID)

getAllRefunds
  :: UserId -> Aff (Either String (Array Refund.RefundTransaction))
getAllRefunds userId = Request.authGet userId "/refund"

getRefund
  :: UserId -> UUID -> Aff (Either String Refund.RefundTransaction)
getRefund userId refundId =
  Request.authGet userId ("/refund/" <> show refundId)