module Services.TransactionService where

import Prelude

import API.Transaction as API
import Data.Either (Either)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete')
import Data.Int (floor, toNumber)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Now (nowDateTime)
import Types.Transaction (PaymentMethod, PaymentTransaction(..), TaxCategory(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (UUID)
import Utils.UUIDGen (genUUID)

-- Initialize and start a new transaction
startTransaction
  :: { employeeId :: UUID
     , registerId :: UUID
     , locationId :: UUID
     }
  -> Aff (Either String Transaction)
startTransaction params = do
  -- Generate a new UUID for the transaction
  transactionId <- liftEffect genUUID
  -- Get the current timestamp
  timestamp <- liftEffect nowDateTime

  -- Create the initial transaction object
  let
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
      , subtotal: fromDiscrete' (Discrete 0)
      , discountTotal: fromDiscrete' (Discrete 0)
      , taxTotal: fromDiscrete' (Discrete 0)
      , total: fromDiscrete' (Discrete 0)
      , transactionType: Sale
      , isVoided: false
      , voidReason: Nothing
      , isRefunded: false
      , refundReason: Nothing
      , referenceTransactionId: Nothing
      , notes: Nothing
      }

  -- Send the transaction to the backend
  API.createTransaction transaction

createTransactionItem
  :: UUID -- Transaction ID
  -> UUID -- Menu Item SKU
  -> Number -- Quantity
  -> Int -- Price per unit in cents
  -> Aff (Either String TransactionItem)
createTransactionItem transactionId menuItemSku quantity pricePerUnit = do
  -- Generate a new item ID
  itemId <- liftEffect genUUID

  -- Prepare the transaction item
  let
    -- Calculate price values
    ppu = fromDiscrete' (Discrete pricePerUnit)

    -- Convert quantity to appropriate number
    quantityAsNumber = quantity
    subtotalValue = Discrete (pricePerUnit * (floor quantityAsNumber))
    subtotal = fromDiscrete' subtotalValue

    -- Calculate tax (this might vary based on your business rules)
    taxRate = 0.08
    taxAmount = fromDiscrete'
      ( Discrete
          (floor (toNumber (pricePerUnit * (floor quantityAsNumber)) * taxRate))
      )

    -- Calculate total with tax
    total = fromDiscrete'
      ( Discrete
          ( (floor quantityAsNumber) * pricePerUnit +
              ( floor
                  (toNumber (pricePerUnit * (floor quantityAsNumber)) * taxRate)
              )
          )
      )

    -- Prepare sales tax record
    salesTax =
      { category: RegularSalesTax
      , rate: 0.08
      , amount: taxAmount
      , description: "Sales Tax"
      }

    -- Create the transaction item
    transactionItem = TransactionItem
      { id: itemId
      , transactionId: transactionId
      , menuItemSku: menuItemSku
      , quantity: quantity
      , pricePerUnit: ppu
      , discounts: []
      , taxes: [ salesTax ]
      , subtotal: subtotal
      , total: total
      }

  -- Send to backend to reserve inventory
  API.addTransactionItem transactionItem

-- Add transaction item to an existing transaction
addTransactionItem :: TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem = API.addTransactionItem

-- Remove a transaction item
removeTransactionItem :: UUID -> Aff (Either String Unit)
removeTransactionItem = API.removeTransactionItem

-- Void a transaction
voidTransaction :: UUID -> String -> Aff (Either String Transaction)
voidTransaction transactionId reason = do
  API.voidTransaction transactionId reason

-- Add a payment to a transaction
addPayment
  :: UUID
  -> PaymentMethod
  -> Int
  -> Int
  -> Maybe String
  -> Aff (Either String PaymentTransaction)
addPayment transactionId method amount tendered reference = do
  -- Generate a payment ID
  paymentId <- liftEffect genUUID

  -- Create payment transaction object
  let
    payment = PaymentTransaction
      { id: paymentId
      , transactionId: transactionId
      , method: method
      , amount: fromDiscrete' (Discrete amount)
      , tendered: fromDiscrete' (Discrete tendered)
      , change: fromDiscrete' (Discrete (max 0 (tendered - amount)))
      , reference: reference
      , approved: true
      , authorizationCode: Nothing
      }

  -- Send payment to the backend
  API.addPaymentTransaction payment

-- Remove a payment transaction
removePaymentTransaction :: UUID -> Aff (Either String Unit)
removePaymentTransaction = API.removePaymentTransaction

-- Finalize a transaction
finalizeTransaction :: UUID -> Aff (Either String Transaction)
finalizeTransaction = API.finalizeTransaction

-- Get a transaction by ID
getTransaction :: UUID -> Aff (Either String Transaction)
getTransaction = API.getTransaction