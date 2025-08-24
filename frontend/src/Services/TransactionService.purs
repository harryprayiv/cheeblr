module Services.TransactionService where

import Prelude

import API.Transaction as API
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete')
import Data.Int (floor, toNumber)
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Array (filter, length, sortBy)
import Effect.Aff (Aff)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Aff (launchAff_)
import Types.Register (Register, CartTotals)
import Effect.Class.Console as Console
import Effect.Now (nowDateTime)
import Types.Transaction (PaymentMethod, PaymentTransaction(..), TaxCategory(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (UUID)
import Utils.UUIDGen (genUUID)
import Data.Array (filter, find, foldl, (:))
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (DiscreteMoney, fromDiscrete', toDiscrete)
import Data.Int (toNumber)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
-- import Services.TransactionService as TransactionService
import Types.Inventory (MenuItem(..))
import Types.Register (CartTotals)
import Types.Transaction (TaxCategory(..), TransactionItem(..))
import Types.UUID (UUID)
import Utils.Money (formatMoney')
-- import Utils.CartUtils (emptyCartTotals, formatDiscretePrice)
import Utils.UUIDGen (genUUID)

emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }


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
    <> "\nemployeeId: "
    <> show params.employeeId
    <> "\nregisterId: "
    <> show params.registerId
    <> "\nlocationId: "
    <> show params.locationId

  let zeroMoney = fromDiscrete' (Discrete 0)

  -- Create transaction with the Transaction constructor to match Haskell backend
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
  result <- API.createTransaction transaction

  liftEffect $ case result of
    Right tx -> Console.log $ "Transaction created successfully with ID: " <>
      show (unwrap tx).transactionId
    Left err -> Console.error $ "Failed to create transaction: " <> err

  pure result

getTransaction :: UUID -> Aff (Either String Transaction)
getTransaction transactionId = do
  liftEffect $ Console.log $ "Getting transaction: " <> show transactionId
  API.getTransaction transactionId

-- createTransactionItem
--   :: UUID  -- transactionId
--   -> UUID  -- menuItemSku
--   -> Number  -- quantity
--   -> Int  -- pricePerUnit in cents
--   -> Aff (Either String TransactionItem)
-- createTransactionItem transactionId menuItemSku quantity pricePerUnit = do
--   itemId <- liftEffect genUUID
  
--   let quantityInt = floor quantity
--       salesTaxRate = 0.08
--       subtotalCents = pricePerUnit * quantityInt
--       taxCents = floor (toNumber subtotalCents * salesTaxRate)
--       totalCents = subtotalCents + taxCents
      
--       salesTax = 
--         { category: RegularSalesTax
--         , rate: salesTaxRate
--         , amount: fromDiscrete' (Discrete taxCents)
--         , description: "Sales Tax"
--         }
      
--       transactionItem = TransactionItem
--               { transactionItemId: itemId
--               , transactionItemTransactionId: transactionId
--               , transactionItemMenuItemSku: menuItemSku
--               , transactionItemQuantity: toNumber quantityInt
--               , transactionItemPricePerUnit: fromDiscrete' (Discrete pricePerUnit)
--               , transactionItemDiscounts: []
--               , transactionItemTaxes: [salesTax]
--               , transactionItemSubtotal: fromDiscrete' (Discrete subtotalCents)
--               , transactionItemTotal: fromDiscrete' (Discrete totalCents)
--               }
        
--   API.addTransactionItem transactionItem

createTransactionItem
  :: UUID
  -> UUID
  -> Int  -- Changed from Number
  -> Int
  -> Aff (Either String TransactionItem)
createTransactionItem transactionId menuItemSku quantity pricePerUnit = do
  itemId <- liftEffect genUUID

  let salesTaxRate = 0.08
      subtotalCents = pricePerUnit * quantity
      taxCents = floor (toNumber subtotalCents * salesTaxRate)
      totalCents = subtotalCents + taxCents

      salesTax =
        { category: RegularSalesTax
        , rate: salesTaxRate
        , amount: fromDiscrete' (Discrete taxCents)
        , description: "Sales Tax"
        }

      transactionItem = TransactionItem
              { transactionItemId: itemId
              , transactionItemTransactionId: transactionId
              , transactionItemMenuItemSku: menuItemSku
              , transactionItemQuantity: quantity  -- Now an Int
              , transactionItemPricePerUnit: fromDiscrete' (Discrete pricePerUnit)
              , transactionItemDiscounts: []
              , transactionItemTaxes: [salesTax]
              , transactionItemSubtotal: fromDiscrete' (Discrete subtotalCents)
              , transactionItemTotal: fromDiscrete' (Discrete totalCents)
              }

  API.addTransactionItem transactionItem

addTransactionItem :: TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem item = do
  liftEffect $ Console.log $ "Adding transaction item: " <> show
    (unwrap item).transactionItemId
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

removeItemFromCart
  :: UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Effect Unit
removeItemFromCart itemId currentItems setItems setTotals setCheckingInventory = do
  setCheckingInventory true
  
  void $ launchAff_ do
    result <- removeTransactionItem itemId
    
    liftEffect $ case result of
      Right _ -> do
        let newItems = filter 
              (\(TransactionItem item) -> item.transactionItemId /= itemId) 
              currentItems
        let newTotals = calculateCartTotals newItems
        setItems newItems
        setTotals newTotals
        setCheckingInventory false
      Left err -> do
        setCheckingInventory false
        Console.error $ "Failed to remove item: " <> err

calculateCartTotals :: Array TransactionItem -> CartTotals
calculateCartTotals items =
  foldl addItemToTotals emptyCartTotals items
  where
  addItemToTotals :: CartTotals -> TransactionItem -> CartTotals
  addItemToTotals totals (TransactionItem item) =
    let
      itemSubtotal = toDiscrete item.transactionItemSubtotal
      itemTaxTotal = foldl (\acc tax -> acc + (toDiscrete tax.amount))
        (Discrete 0)
        item.transactionItemTaxes
      itemTotal = toDiscrete item.transactionItemTotal
    in
      { subtotal: totals.subtotal + itemSubtotal
      , taxTotal: totals.taxTotal + itemTaxTotal
      , total: totals.total + itemTotal
      , discountTotal: totals.discountTotal
      }