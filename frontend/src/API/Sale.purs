module API.Sale where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Transaction.Refund as Refund
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

getAllSales :: UserId -> Aff (Either String (Array Sale.SaleTransaction))
getAllSales userId = Request.authGet userId "/sale"

getSale :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
getSale userId saleId =
  Request.authGet userId ("/sale/" <> show saleId)

voidSale
  :: UserId
  -> UUID
  -> String
  -> Aff (Either String Sale.SaleTransaction)
voidSale userId saleId reason =
  Request.authPost userId ("/sale/void/" <> show saleId) reason

refundSale
  :: UserId
  -> UUID
  -> String
  -> Aff (Either String Refund.RefundTransaction)
refundSale userId saleId reason =
  Request.authPost userId ("/sale/refund/" <> show saleId) reason
