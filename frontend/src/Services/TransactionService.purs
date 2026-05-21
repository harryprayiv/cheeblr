module Services.TransactionService where

import Prelude

import API.Sale as API
import Data.Array (foldl)
import Data.Either (Either)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Int (floor, toNumber)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (nowDateTime)
import Services.AuthService (UserId)
import Types.Primitives.Money
  ( saleMoneyCents
  , unsafeMkSaleMoney
  , zeroSale
  )
import Types.Primitives.Quantity (unsafeMkSaleQuantity)
import Types.Register (CartTotals)
import Types.Transaction
  ( PaymentMethod
  , TaxCategory(..)
  , TransactionStatus(..)
  )
import Types.Transaction.Refund as Refund
import Types.Transaction.Sale as Sale
import Types.UUID (UUID, genUUID)

emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }

-- Optimistic local rate for cart UI; backend recomputes on finalize.
defaultSalesTaxRate :: Number
defaultSalesTaxRate = 0.08

startSale
  :: UserId
  -> { employeeId :: UUID
     , registerId :: UUID
     , locationId :: UUID
     }
  -> Aff (Either String Sale.SaleTransaction)
startSale userId params = do
  saleId <- liftEffect genUUID
  timestamp <- liftEffect nowDateTime
  liftEffect $ Console.log $ "Starting sale: " <> show saleId

  let
    sale :: Sale.SaleTransaction
    sale =
      { saleId: saleId
      , saleStatus: Created
      , saleCreated: timestamp
      , saleCompleted: Nothing
      , saleCustomerId: Nothing
      , saleEmployeeId: params.employeeId
      , saleRegisterId: params.registerId
      , saleLocationId: params.locationId
      , saleItems: []
      , salePayments: []
      , saleSubtotal: zeroSale
      , saleDiscountTotal: zeroSale
      , saleTaxTotal: zeroSale
      , saleTotal: zeroSale
      , saleKind: Sale.StandardSale
      , saleIsVoided: false
      , saleVoidReason: Nothing
      , saleIsRefunded: false
      , saleRefundReason: Nothing
      , saleNotes: Nothing
      }

  API.createSale userId sale

getSale :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
getSale = API.getSale

createSaleItem
  :: UserId
  -> UUID
  -> UUID
  -> Int
  -> Int
  -> Aff (Either String Sale.Item)
createSaleItem userId saleId menuItemSku quantity pricePerUnit = do
  itemId <- liftEffect genUUID

  let
    subtotalCents = pricePerUnit * quantity
    taxCents = floor (toNumber subtotalCents * defaultSalesTaxRate)
    totalCents = subtotalCents + taxCents

    salesTax :: Sale.Tax
    salesTax =
      { taxCategory: RegularSalesTax
      , taxRate: defaultSalesTaxRate
      , taxAmount: unsafeMkSaleMoney taxCents
      , taxDescription: "Sales Tax"
      }

    item :: Sale.Item
    item =
      { itemId: itemId
      , itemTransactionId: saleId
      , itemMenuItemSku: menuItemSku
      , itemQuantity: unsafeMkSaleQuantity quantity
      , itemPricePerUnit: unsafeMkSaleMoney pricePerUnit
      , itemDiscounts: []
      , itemTaxes: [ salesTax ]
      , itemSubtotal: unsafeMkSaleMoney subtotalCents
      , itemTotal: unsafeMkSaleMoney totalCents
      }

  API.addSaleItem userId item

addSaleItem :: UserId -> Sale.Item -> Aff (Either String Sale.Item)
addSaleItem userId item = do
  liftEffect $ Console.log $ "Adding sale item: " <> show item.itemId
  API.addSaleItem userId item

removeSaleItem :: UserId -> UUID -> Aff (Either String Unit)
removeSaleItem userId itemId = do
  liftEffect $ Console.log $ "Removing sale item: " <> show itemId
  API.removeSaleItem userId itemId

clearSale :: UserId -> UUID -> Aff (Either String Unit)
clearSale = API.clearSale

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

addPayment
  :: UserId
  -> UUID
  -> PaymentMethod
  -> Int
  -> Int
  -> Maybe String
  -> Aff (Either String Sale.Payment)
addPayment userId saleId method amount tendered reference = do
  paymentId <- liftEffect genUUID
  let
    change = max 0 (tendered - amount)
    payment :: Sale.Payment
    payment =
      { paymentId: paymentId
      , paymentTransactionId: saleId
      , paymentMethod: method
      , paymentAmount: unsafeMkSaleMoney amount
      , paymentTendered: unsafeMkSaleMoney tendered
      , paymentChange: unsafeMkSaleMoney change
      , paymentReference: reference
      , paymentApproved: true
      , paymentAuthorizationCode: Nothing
      }
  API.addSalePayment userId payment

removeSalePayment :: UserId -> UUID -> Aff (Either String Unit)
removeSalePayment userId paymentId = do
  liftEffect $ Console.log $ "Removing sale payment: " <> show paymentId
  API.removeSalePayment userId paymentId

finalizeSale
  :: UserId -> UUID -> Aff (Either String Sale.SaleTransaction)
finalizeSale userId saleId = do
  liftEffect $ Console.log $ "Finalizing sale: " <> show saleId
  API.finalizeSale userId saleId

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