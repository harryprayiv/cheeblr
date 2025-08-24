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
import Effect.Class.Console as Console
import Services.TransactionService (getTransaction)
import Types.Inventory (MenuItem(..))
import Types.Transaction (PaymentTransaction(..), TaxCategory(..), Transaction(..), TransactionItem(..))
import Types.UUID (UUID)
import Data.Int as Int 
import Utils.UUIDGen (genUUID)

menuItemToTransactionItem
  :: MenuItem
  -> Number
  -> UUID
  -> Aff TransactionItem
menuItemToTransactionItem (MenuItem item) quantity transactionId = do
  itemId <- liftEffect genUUID

  let
    priceInCents = unwrap item.price

    salesTaxRate = 0.08
    salesTaxAmount = floor
      (toNumber (priceInCents * floor quantity) * salesTaxRate)

    salesTax =
      { category: RegularSalesTax
      , rate: salesTaxRate
      , amount: fromDiscrete' (Discrete salesTaxAmount)
      , description: "Sales Tax"
      }

    subtotalInCents = priceInCents * floor quantity

    totalInCents = subtotalInCents + salesTaxAmount

  pure $ TransactionItem
    { transactionItemId: itemId
    , transactionItemTransactionId: transactionId
    , transactionItemMenuItemSku: item.sku
    , transactionItemQuantity: Int.floor quantity
    , transactionItemPricePerUnit: fromDiscrete' (Discrete priceInCents)
    , transactionItemDiscounts: []
    , transactionItemTaxes: [ salesTax ]
    , transactionItemSubtotal: fromDiscrete' (Discrete subtotalInCents)
    , transactionItemTotal: fromDiscrete' (Discrete totalInCents)
    }

calculateTotalPayments :: Array PaymentTransaction -> Discrete USD
calculateTotalPayments payments =
  foldl
    ( \acc (PaymentTransaction payment) ->
        acc + toDiscrete payment.amount
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

getTransactionItems :: Transaction -> Array TransactionItem
getTransactionItems (Transaction tx) = tx.transactionItems

updateTransactionData
  :: Transaction
  -> (Transaction -> Effect Unit)
  -> Aff Unit
updateTransactionData (Transaction tx) setTransaction = do
  liftEffect $ Console.log $ "Updating transaction data for ID: " <> show
    tx.transactionId
  result <- getTransaction tx.transactionId
  liftEffect $ case result of
    Right updatedTx -> do
      Console.log "Successfully fetched updated transaction data"
      setTransaction updatedTx
    Left err -> do
      Console.error $ "Failed to update transaction data: " <> err
      pure unit