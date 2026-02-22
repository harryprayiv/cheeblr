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
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
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
  :: Ref AuthContext
  -> { employeeId :: UUID
     , registerId :: UUID
     , locationId :: UUID
     }
  -> Aff (Either String Transaction)
startTransaction authRef params = do
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
  result <- API.createTransaction authRef transaction

  liftEffect $ case result of
    Right tx -> Console.log $ "Transaction created successfully with ID: " <>
      show (unwrap tx).transactionId
    Left err -> Console.error $ "Failed to create transaction: " <> err

  pure result

getTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
getTransaction authRef transactionId = do
  liftEffect $ Console.log $ "Getting transaction: " <> show transactionId
  API.getTransaction authRef transactionId

createTransactionItem
  :: Ref AuthContext
  -> UUID
  -> UUID
  -> Int
  -> Int
  -> Aff (Either String TransactionItem)
createTransactionItem authRef transactionId menuItemSku quantity pricePerUnit = do
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

  API.addTransactionItem authRef transactionItem

addTransactionItem :: Ref AuthContext -> TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem authRef item = do
  liftEffect $ Console.log $ "Adding transaction item: " <> show
    (unwrap item).transactionItemId
  API.addTransactionItem authRef item

removeTransactionItem :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removeTransactionItem authRef itemId = do
  liftEffect $ Console.log $ "Removing transaction item: " <> show itemId
  API.removeTransactionItem authRef itemId

clearTransaction :: Ref AuthContext -> UUID -> Aff (Either String Unit)
clearTransaction authRef = API.clearTransaction authRef

voidTransaction :: Ref AuthContext -> UUID -> String -> Aff (Either String Transaction)
voidTransaction authRef transactionId reason = do
  liftEffect $ Console.log $ "Voiding transaction: " <> show transactionId
  API.voidTransaction authRef transactionId reason

addPayment
  :: Ref AuthContext
  -> UUID
  -> PaymentMethod
  -> Int
  -> Int
  -> Maybe String
  -> Aff (Either String PaymentTransaction)
addPayment authRef transactionId method amount tendered reference = do
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

  API.addPaymentTransaction authRef payment

removePaymentTransaction :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removePaymentTransaction authRef paymentId = do
  liftEffect $ Console.log $ "Removing payment transaction: " <> show paymentId
  API.removePaymentTransaction authRef paymentId

finalizeTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
finalizeTransaction authRef transactionId = do
  liftEffect $ Console.log $ "Finalizing transaction: " <> show transactionId
  API.finalizeTransaction authRef transactionId

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