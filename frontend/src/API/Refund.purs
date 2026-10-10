module API.Refund where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Types.Transaction.Refund as Refund
import Types.UUID (UUID)

getAllRefunds :: Aff (Either ApiError (Array Refund.RefundTransaction))
getAllRefunds = Request.get "/refund"

getRefund :: UUID -> Aff (Either ApiError Refund.RefundTransaction)
getRefund refundId = Request.get ("/refund/" <> show refundId)
