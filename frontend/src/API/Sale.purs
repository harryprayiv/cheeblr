module API.Sale where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Types.Transaction.Refund as Refund
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

-- Every sale, of every status. Refund rows are not included.
getAllSales :: Aff (Either ApiError (Array Sale.SaleTransaction))
getAllSales = Request.get "/sale"

getSale :: UUID -> Aff (Either ApiError Sale.SaleTransaction)
getSale saleId = Request.get ("/sale/" <> show saleId)

-- Needs capCanVoidTransaction (403). There is no ownership check. Answers
-- 409 for a sale that is already voided or was refunded.
voidSale :: UUID -> String -> Aff (Either ApiError Sale.SaleTransaction)
voidSale saleId reason =
  Request.post ("/sale/void/" <> show saleId) reason

-- Needs capCanRefundTransaction (403). There is no ownership check. Only a
-- completed sale can be refunded, and only once (409 otherwise). The answer
-- is the refund row. The sale itself becomes REFUNDED.
refundSale :: UUID -> String -> Aff (Either ApiError Refund.RefundTransaction)
refundSale saleId reason =
  Request.post ("/sale/refund/" <> show saleId) reason
