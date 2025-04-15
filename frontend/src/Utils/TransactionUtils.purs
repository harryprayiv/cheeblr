module Utils.TransactionUtils where

import Prelude

import Data.Array (foldl)
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete', toDiscrete)
import Data.Int (floor, toNumber)
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Services.TransactionService (getTransaction)
import Types.Inventory (MenuItem(..))
import Types.Transaction (PaymentTransaction(..), TaxCategory(..), Transaction(..), TransactionItem(..))
import Types.UUID (UUID)
import Utils.UUIDGen (genUUID)

-- Convert menu item to transaction item
menuItemToTransactionItem
  :: MenuItem
  -> Number
  -> UUID
  -> Aff TransactionItem
menuItemToTransactionItem (MenuItem item) quantity transactionId = do
  itemId <- liftEffect genUUID

  let
    -- Get price in cents
    priceInCents = unwrap item.price

    -- Calculate tax (8% sales tax)
    salesTaxRate = 0.08
    salesTaxAmount = floor
      (toNumber (priceInCents * floor quantity) * salesTaxRate)

    -- Create sales tax record
    salesTax =
      { category: RegularSalesTax
      , rate: salesTaxRate
      , amount: fromDiscrete' (Discrete salesTaxAmount)
      , description: "Sales Tax"
      }

    -- Calculate subtotal
    subtotalInCents = priceInCents * floor quantity

    -- Calculate total (with tax)
    totalInCents = subtotalInCents + salesTaxAmount

  -- Create and return the transaction item
  pure $ TransactionItem
    { id: itemId
    , transactionId: transactionId
    , menuItemSku: item.sku
    , quantity: quantity
    , pricePerUnit: fromDiscrete' (Discrete priceInCents)
    , discounts: []
    , taxes: [ salesTax ]
    , subtotal: fromDiscrete' (Discrete subtotalInCents)
    , total: fromDiscrete' (Discrete totalInCents)
    }

-- Calculate total amount of all payments
calculateTotalPayments :: Array PaymentTransaction -> Discrete USD
calculateTotalPayments payments =
  foldl
    ( \acc (PaymentTransaction payment) ->
        acc + toDiscrete payment.amount
    )
    (Discrete 0)
    payments

-- Check if payments cover the transaction total
paymentsCoversTotal :: Array PaymentTransaction -> Transaction -> Boolean
paymentsCoversTotal payments (Transaction tx) =
  calculateTotalPayments payments >= toDiscrete tx.total

-- Calculate remaining balance after payments
getRemainingBalance :: Array PaymentTransaction -> Transaction -> Discrete USD
getRemainingBalance payments (Transaction tx) =
  max (Discrete 0) (toDiscrete tx.total - calculateTotalPayments payments)

-- Get items from a transaction
getTransactionItems :: Transaction -> Array TransactionItem
getTransactionItems (Transaction tx) = tx.items

-- Update transaction data from backend
updateTransactionData
  :: Transaction
  -> (Transaction -> Effect Unit)
  -> Aff Unit
updateTransactionData (Transaction tx) setTransaction = do
  -- Fetch the latest transaction data from the backend
  result <- getTransaction tx.id
  liftEffect $ case result of
    Right updatedTx -> setTransaction updatedTx
    Left _ -> pure unit