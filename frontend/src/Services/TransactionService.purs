module Services.TransactionService where

import Prelude

import API.Transaction as API
import Data.Array (foldl)
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete', toDiscrete)
import Data.Int (floor, toNumber)
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (nowDateTime)
import Services.AuthService (UserId)
import Types.Register (CartTotals)
import Types.Transaction (PaymentMethod, PaymentTransaction(..), TaxCategory(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (UUID, genUUID)

emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }

startTransaction
  :: UserId
  -> { employeeId :: UUID
     , registerId :: UUID
     , locationId :: UUID
     }
  -> Aff (Either String Transaction)
startTransaction userId params = do
  transactionId <- liftEffect genUUID
  timestamp <- liftEffect nowDateTime

  liftEffect $ Console.log $ "Starting transaction with params: "
    <> "\nemployeeId: "
    <> show params.employeeId
    <> "\nregisterId: "
    <> show params.registerId
    <> "\nlocationId: "
    <> show params.locationId

  let zeroMoney = fromDiscrete' (Discrete 0)

  let
    transaction = Transaction
      { transactionId: transactionId
      , transactionStatus: Created
      , transactionCreated: timestamp
      , transactionCompleted: Nothing
      , transactionCustomerId: Nothing
      , transactionEmployeeId: params.employeeId
      , transactionRegisterId: params.registerId
      , transactionLocationId: params.locationId
      , transactionItems: []
      , transactionPayments: []
      , transactionSubtotal: zeroMoney
      , transactionDiscountTotal: zeroMoney
      , transactionTaxTotal: zeroMoney
      , transactionTotal: zeroMoney
      , transactionType: Sale
      , transactionIsVoided: false
      , transactionVoidReason: Nothing
      , transactionIsRefunded: false
      , transactionRefundReason: Nothing
      , transactionReferenceTransactionId: Nothing
      , transactionNotes: Nothing
      }

  liftEffect $ Console.log "About to call API.createTransaction"
  result <- API.createTransaction userId transaction

  liftEffect $ case result of
    Right tx -> Console.log $ "Transaction created successfully with ID: " <>
      show (unwrap tx).transactionId
    Left err -> Console.error $ "Failed to create transaction: " <> err

  pure result

getTransaction :: UserId -> UUID -> Aff (Either String Transaction)
getTransaction userId transactionId = do
  liftEffect $ Console.log $ "Getting transaction: " <> show transactionId
  API.getTransaction userId transactionId

createTransactionItem
  :: UserId
  -> UUID
  -> UUID
  -> Int
  -> Int
  -> Aff (Either String TransactionItem)
createTransactionItem userId transactionId menuItemSku quantity pricePerUnit = do
  itemId <- liftEffect genUUID

  let salesTaxRate = 0.08
      subtotalCents = pricePerUnit * quantity
      taxCents = floor (toNumber subtotalCents * salesTaxRate)
      totalCents = subtotalCents + taxCents

      salesTax =
        { taxCategory: RegularSalesTax
        , taxRate: salesTaxRate
        , taxAmount: fromDiscrete' (Discrete taxCents)
        , taxDescription: "Sales Tax"
        }

      transactionItem = TransactionItem
        { transactionItemId: itemId
        , transactionItemTransactionId: transactionId
        , transactionItemMenuItemSku: menuItemSku
        , transactionItemQuantity: quantity
        , transactionItemPricePerUnit: fromDiscrete' (Discrete pricePerUnit)
        , transactionItemDiscounts: []
        , transactionItemTaxes: [salesTax]
        , transactionItemSubtotal: fromDiscrete' (Discrete subtotalCents)
        , transactionItemTotal: fromDiscrete' (Discrete totalCents)
        }

  API.addTransactionItem userId transactionItem

addTransactionItem :: UserId -> TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem userId item = do
  liftEffect $ Console.log $ "Adding transaction item: " <> show
    (unwrap item).transactionItemId
  API.addTransactionItem userId item

removeTransactionItem :: UserId -> UUID -> Aff (Either String Unit)
removeTransactionItem userId itemId = do
  liftEffect $ Console.log $ "Removing transaction item: " <> show itemId
  API.removeTransactionItem userId itemId

clearTransaction :: UserId -> UUID -> Aff (Either String Unit)
clearTransaction userId = API.clearTransaction userId

voidTransaction :: UserId -> UUID -> String -> Aff (Either String Transaction)
voidTransaction userId transactionId reason = do
  liftEffect $ Console.log $ "Voiding transaction: " <> show transactionId
  API.voidTransaction userId transactionId reason

addPayment
  :: UserId
  -> UUID
  -> PaymentMethod
  -> Int
  -> Int
  -> Maybe String
  -> Aff (Either String PaymentTransaction)
addPayment userId transactionId method amount tendered reference = do
  paymentId <- liftEffect genUUID

  liftEffect $ Console.log $ "Adding payment: "
    <> "\ntransactionId: "
    <> show transactionId
    <> "\nmethod: "
    <> show method
    <> "\namount: "
    <> show amount
    <> "\ntendered: "
    <> show tendered

  let
    change = max 0 (tendered - amount)

    payment = PaymentTransaction
      { paymentId: paymentId
      , paymentTransactionId: transactionId
      , paymentMethod: method
      , paymentAmount: fromDiscrete' (Discrete amount)
      , paymentTendered: fromDiscrete' (Discrete tendered)
      , paymentChange: fromDiscrete' (Discrete change)
      , paymentReference: reference
      , paymentApproved: true
      , paymentAuthorizationCode: Nothing
      }

  API.addPaymentTransaction userId payment

removePaymentTransaction :: UserId -> UUID -> Aff (Either String Unit)
removePaymentTransaction userId paymentId = do
  liftEffect $ Console.log $ "Removing payment transaction: " <> show paymentId
  API.removePaymentTransaction userId paymentId

finalizeTransaction :: UserId -> UUID -> Aff (Either String Transaction)
finalizeTransaction userId transactionId = do
  liftEffect $ Console.log $ "Finalizing transaction: " <> show transactionId
  API.finalizeTransaction userId transactionId

calculateCartTotals :: Array TransactionItem -> CartTotals
calculateCartTotals items =
  foldl addItemToTotals emptyCartTotals items
  where
  addItemToTotals :: CartTotals -> TransactionItem -> CartTotals
  addItemToTotals totals (TransactionItem item) =
    let
      itemSubtotal = toDiscrete item.transactionItemSubtotal
      itemTaxTotal = foldl (\acc tax -> acc + (toDiscrete tax.taxAmount))
        (Discrete 0)
        item.transactionItemTaxes
      itemTotal = toDiscrete item.transactionItemTotal
    in
      { subtotal: totals.subtotal + itemSubtotal
      , taxTotal: totals.taxTotal + itemTaxTotal
      , total: totals.total + itemTotal
      , discountTotal: totals.discountTotal
      }

calculateTotalPayments :: Array PaymentTransaction -> Discrete USD
calculateTotalPayments payments =
  foldl
    ( \acc (PaymentTransaction payment) ->
        acc + toDiscrete payment.paymentAmount
    )
    (Discrete 0)
    payments

paymentsCoversTotal :: Array PaymentTransaction -> Transaction -> Boolean
paymentsCoversTotal payments (Transaction tx) =
  calculateTotalPayments payments >= toDiscrete tx.transactionTotal

getRemainingBalance :: Array PaymentTransaction -> Transaction -> Discrete USD
getRemainingBalance payments (Transaction tx) =
  max (Discrete 0)
    (toDiscrete tx.transactionTotal - calculateTotalPayments payments)