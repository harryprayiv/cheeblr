module Services.TransactionService where

import Prelude

import API.Sale as API
import API.SaleCommand as Command
import Data.Array (foldl)
import Data.Either (Either)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Services.AuthService (UserId)
import Types.Primitives.Money (saleMoneyCents)
import Types.Register (CartTotals)
import Types.Transaction.Refund as Refund
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }

-- Opens a new, empty sale. The backend generates the id and timestamp.
startSale
  :: UserId
  -> { employeeId :: UUID
     , registerId :: UUID
     , locationId :: UUID
     }
  -> Aff (Either String Sale.SaleTransaction)
startSale userId params =
  Command.startSale userId
    { startSaleEmployeeId: params.employeeId
    , startSaleRegisterId: params.registerId
    , startSaleLocationId: params.locationId
    }

getSale :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
getSale = API.getSale

voidSale
  :: UserId -> UUID -> String -> Aff (Either String Sale.SaleTransaction)
voidSale userId saleId reason = do
  liftEffect $ Console.log $ "Voiding sale: " <> show saleId
  API.voidSale userId saleId reason

refundSale
  :: UserId
  -> UUID
  -> String
  -> Aff (Either String Refund.RefundTransaction)
refundSale userId saleId reason = do
  liftEffect $ Console.log $ "Refunding sale: " <> show saleId
  API.refundSale userId saleId reason

calculateCartTotals :: Array Sale.Item -> CartTotals
calculateCartTotals = foldl addItemToTotals emptyCartTotals
  where
  addItemToTotals :: CartTotals -> Sale.Item -> CartTotals
  addItemToTotals totals item =
    let
      itemSubtotal = Discrete (saleMoneyCents item.itemSubtotal)
      itemTaxTotal = Discrete
        (foldl (\acc t -> acc + saleMoneyCents t.taxAmount) 0 item.itemTaxes)
      itemTotal = Discrete (saleMoneyCents item.itemTotal)
    in
      { subtotal: totals.subtotal + itemSubtotal
      , taxTotal: totals.taxTotal + itemTaxTotal
      , total: totals.total + itemTotal
      , discountTotal: totals.discountTotal
      }

calculateTotalPayments :: Array Sale.Payment -> Discrete USD
calculateTotalPayments =
  foldl
    (\acc p -> acc + Discrete (saleMoneyCents p.paymentAmount))
    (Discrete 0)

-- | Does the payment total meet or exceed the cart total? Caller passes the
-- | authoritative total — usually 'CartTotals.total' for live cart UI, or
-- | 'saleMoneyDiscrete sale.saleTotal' when checking against a server value.
paymentsCoversTotal :: Array Sale.Payment -> Discrete USD -> Boolean
paymentsCoversTotal payments total =
  calculateTotalPayments payments >= total

-- | Cash still owed; clamped at zero so overpayment doesn't show negative.
getRemainingBalance :: Array Sale.Payment -> Discrete USD -> Discrete USD
getRemainingBalance payments total =
  max (Discrete 0) (total - calculateTotalPayments payments)
