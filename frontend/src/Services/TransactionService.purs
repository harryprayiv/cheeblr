module Services.TransactionService where

import Prelude

import API.Transaction as API
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete')
import Data.Int (floor, toNumber)
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (nowDateTime)
import Types.Transaction (PaymentMethod, PaymentTransaction(..), TaxCategory(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (UUID)
import Utils.UUIDGen (genUUID)

startTransaction
  :: { employeeId :: UUID
     , registerId :: UUID
     , locationId :: UUID
     }
  -> Aff (Either String Transaction)
startTransaction params = do
  transactionId <- liftEffect genUUID
  timestamp <- liftEffect nowDateTime

  liftEffect $ Console.log $ "Starting transaction with params: "
    <> "\nemployeeId: " <> show params.employeeId
    <> "\nregisterId: " <> show params.registerId
    <> "\nlocationId: " <> show params.locationId

  let
    -- Convert integers to DiscreteMoney USD using fromDiscrete'
    zeroMoney = fromDiscrete' (Discrete 0)
    
    transaction = Transaction
      { id: transactionId
      , status: Created
      , created: timestamp
      , completed: Nothing
      , customer: Nothing
      , employee: params.employeeId
      , register: params.registerId
      , location: params.locationId
      , items: []
      , payments: []
      , subtotal: zeroMoney       
      , discountTotal: zeroMoney  
      , taxTotal: zeroMoney       
      , total: zeroMoney
      , transactionType: Sale
      , isVoided: false
      , voidReason: Nothing
      , isRefunded: false
      , refundReason: Nothing
      , referenceTransactionId: Nothing
      , notes: Nothing
      }

  liftEffect $ Console.log "About to call API.createTransaction"
  result <- API.createTransaction transaction

  liftEffect $ case result of
    Right tx -> Console.log $ "Transaction created successfully with ID: " <> show (unwrap tx).id
    Left err -> Console.error $ "Failed to create transaction: " <> err

  pure result

getTransaction :: UUID -> Aff (Either String Transaction)
getTransaction transactionId = do
  liftEffect $ Console.log $ "Getting transaction: " <> show transactionId
  API.getTransaction transactionId

createTransactionItem
  :: UUID
  -> UUID
  -> Number
  -> Int
  -> Aff (Either String TransactionItem)
createTransactionItem transactionId menuItemSku quantity pricePerUnit = do
  itemId <- liftEffect genUUID

  liftEffect $ Console.log $ "Creating transaction item: "
    <> "\ntransactionId: " <> show transactionId
    <> "\nmenuItemSku: " <> show menuItemSku
    <> "\nquantity: " <> show quantity
    <> "\npricePerUnit: " <> show pricePerUnit

  let
    quantityAsInt = floor quantity
    salesTaxRate = 0.08
    
    -- Calculate subtotal
    subtotalInt = pricePerUnit * quantityAsInt
    subtotalMoney = fromDiscrete' (Discrete subtotalInt)
    
    -- Calculate tax
    taxAmountInt = floor (toNumber subtotalInt * salesTaxRate)
    taxMoney = fromDiscrete' (Discrete taxAmountInt)
    
    -- Calculate total
    totalInt = subtotalInt + taxAmountInt
    totalMoney = fromDiscrete' (Discrete totalInt)
    
    -- Create tax record
    salesTax =
      { category: RegularSalesTax
      , rate: salesTaxRate
      , amount: taxMoney
      , description: "Sales Tax"
      }
    
    -- Create transaction item
    transactionItem = TransactionItem
      { id: itemId
      , transactionId: transactionId
      , menuItemSku: menuItemSku
      , quantity: toNumber quantityAsInt
      , pricePerUnit: fromDiscrete' (Discrete pricePerUnit)
      , discounts: []
      , taxes: [ salesTax ]
      , subtotal: subtotalMoney
      , total: totalMoney
      }

  API.addTransactionItem transactionItem

addTransactionItem :: TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem item = do
  liftEffect $ Console.log $ "Adding transaction item: " <> show (unwrap item).id
  API.addTransactionItem item

removeTransactionItem :: UUID -> Aff (Either String Unit)
removeTransactionItem itemId = do
  liftEffect $ Console.log $ "Removing transaction item: " <> show itemId
  API.removeTransactionItem itemId

voidTransaction :: UUID -> String -> Aff (Either String Transaction)
voidTransaction transactionId reason = do
  liftEffect $ Console.log $ "Voiding transaction: " <> show transactionId
  API.voidTransaction transactionId reason

addPayment
  :: UUID
  -> PaymentMethod
  -> Int
  -> Int
  -> Maybe String
  -> Aff (Either String PaymentTransaction)
addPayment transactionId method amount tendered reference = do
  paymentId <- liftEffect genUUID

  liftEffect $ Console.log $ "Adding payment: "
    <> "\ntransactionId: " <> show transactionId
    <> "\nmethod: " <> show method
    <> "\namount: " <> show amount
    <> "\ntendered: " <> show tendered

  let
    change = max 0 (tendered - amount)
    
    payment = PaymentTransaction
      { id: paymentId
      , transactionId: transactionId
      , method: method
      , amount: fromDiscrete' (Discrete amount)
      , tendered: fromDiscrete' (Discrete tendered)
      , change: fromDiscrete' (Discrete change)
      , reference: reference
      , approved: true
      , authorizationCode: Nothing
      }

  API.addPaymentTransaction payment

removePaymentTransaction :: UUID -> Aff (Either String Unit)
removePaymentTransaction paymentId = do
  liftEffect $ Console.log $ "Removing payment transaction: " <> show paymentId
  API.removePaymentTransaction paymentId

finalizeTransaction :: UUID -> Aff (Either String Transaction)
finalizeTransaction transactionId = do
  liftEffect $ Console.log $ "Finalizing transaction: " <> show transactionId
  API.finalizeTransaction transactionId