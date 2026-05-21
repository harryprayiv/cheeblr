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

createSale
  :: UserId
  -> Sale.SaleTransaction
  -> Aff (Either String Sale.SaleTransaction)
createSale userId sale =
  Request.authPostChecked userId "/sale" sale

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

addSaleItem :: UserId -> Sale.Item -> Aff (Either String Sale.Item)
addSaleItem userId item =
  Request.authPostChecked userId "/sale/item" item

removeSaleItem :: UserId -> UUID -> Aff (Either String Unit)
removeSaleItem userId itemId =
  Request.authDeleteUnit userId ("/sale/item/" <> show itemId)

addSalePayment :: UserId -> Sale.Payment -> Aff (Either String Sale.Payment)
addSalePayment userId payment =
  Request.authPostChecked userId "/sale/payment" payment

removeSalePayment :: UserId -> UUID -> Aff (Either String Unit)
removeSalePayment userId paymentId =
  Request.authDeleteUnit userId ("/sale/payment/" <> show paymentId)

finalizeSale
  :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
finalizeSale userId saleId =
  Request.authPostEmpty userId ("/sale/finalize/" <> show saleId)

clearSale :: UserId -> UUID -> Aff (Either String Unit)
clearSale userId saleId =
  Request.authPostUnit userId ("/sale/clear/" <> show saleId)