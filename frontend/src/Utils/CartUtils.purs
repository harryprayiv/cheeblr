module Utils.CartUtils where

import Prelude

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
import Services.TransactionService as TransactionService
import Types.Inventory (MenuItem(..))
import Types.Transaction (TaxCategory(..), TransactionItem(..), CartTotals)
import Types.UUID (UUID)
import Utils.Money (formatMoney')
import Utils.UUIDGen (genUUID)

-- Base cart totals structure
emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }

-- Calculate cart totals from transaction items
calculateCartTotals :: Array TransactionItem -> CartTotals
calculateCartTotals items =
  foldl addItemToTotals emptyCartTotals items
  where
  addItemToTotals :: CartTotals -> TransactionItem -> CartTotals
  addItemToTotals totals (TransactionItem item) =
    let
      itemSubtotal = toDiscrete item.subtotal
      itemTaxTotal = foldl (\acc tax -> acc + (toDiscrete tax.amount))
        (Discrete 0)
        item.taxes
      itemTotal = toDiscrete item.total
    in
      { subtotal: totals.subtotal + itemSubtotal
      , taxTotal: totals.taxTotal + itemTaxTotal
      , total: totals.total + itemTotal
      , discountTotal: totals.discountTotal
      }

-- Format price helpers
formatPrice :: DiscreteMoney USD -> String
formatPrice = formatMoney'

formatDiscretePrice :: Discrete USD -> String
formatDiscretePrice = formatMoney' <<< fromDiscrete'

addItemToTransaction
  :: MenuItem
  -> Number
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> Effect Unit
addItemToTransaction menuItem@(MenuItem item) qty currentItems updateItems = do
  launchAff_ do
    itemId <- liftEffect genUUID
    transactionId <- liftEffect genUUID

    let
      priceAsMoney = fromDiscrete' item.price

      qtyAsInt = Int.floor qty
      priceInCents = unwrap item.price
      subtotalInCents = priceInCents * qtyAsInt
      subtotalDiscrete = Discrete subtotalInCents
      subtotalAsMoney = fromDiscrete' subtotalDiscrete

      taxRate = 0.15
      taxRateInt = Int.floor (taxRate * 100.0)
      taxAmountInCents = (subtotalInCents * taxRateInt) / 100
      taxDiscrete = Discrete taxAmountInCents
      taxAsMoney = fromDiscrete' taxDiscrete

      totalInCents = subtotalInCents + taxAmountInCents
      totalDiscrete = Discrete totalInCents
      totalAsMoney = fromDiscrete' totalDiscrete

      newItem = TransactionItem
        { id: itemId
        , transactionId: transactionId
        , menuItemSku: item.sku
        , quantity: qty
        , pricePerUnit: priceAsMoney
        , discounts: []
        , taxes:
            [ { category: RegularSalesTax
              , rate: taxRate
              , amount: taxAsMoney
              , description: "Sales Tax"
              }
            ]
        , subtotal: subtotalAsMoney
        , total: totalAsMoney
        }

    liftEffect do
      let
        existingItem = find
          (\(TransactionItem i) -> i.menuItemSku == item.sku)
          currentItems

      case existingItem of
        Just (TransactionItem existing) ->
          let
            newQty = existing.quantity + qty
            newQtyInt = Int.floor newQty

            existingPriceDiscrete = toDiscrete existing.pricePerUnit
            existingPriceInCents = unwrap existingPriceDiscrete

            newSubtotalInCents = existingPriceInCents * newQtyInt
            newTaxInCents = (newSubtotalInCents * taxRateInt) / 100
            newTotalInCents = newSubtotalInCents + newTaxInCents

            newSubtotalDiscrete = Discrete newSubtotalInCents
            newTaxDiscrete = Discrete newTaxInCents
            newTotalDiscrete = Discrete newTotalInCents

            newSubtotalAsMoney = fromDiscrete' newSubtotalDiscrete
            newTaxAsMoney = fromDiscrete' newTaxDiscrete
            newTotalAsMoney = fromDiscrete' newTotalDiscrete

            newTaxRecord =
              { category: RegularSalesTax
              , rate: taxRate
              , amount: newTaxAsMoney
              , description: "Sales Tax"
              }

            updatedItem = TransactionItem $ existing
              { quantity = newQty
              , subtotal = newSubtotalAsMoney
              , total = newTotalAsMoney
              , taxes = [ newTaxRecord ]
              }

            updatedItems = map
              ( \i@(TransactionItem currItem) ->
                  if currItem.menuItemSku == item.sku then updatedItem
                  else i
              )
              currentItems
          in
            updateItems updatedItems

        Nothing ->
          updateItems (newItem : currentItems)

removeItemFromTransaction
  :: UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> Effect Unit
removeItemFromTransaction itemId currentItems updateItems = do
  updateItems
    (filter (\(TransactionItem item) -> item.id /= itemId) currentItems)

findExistingItem :: MenuItem -> Array TransactionItem -> Maybe TransactionItem
findExistingItem (MenuItem menuItem) items =
  find (\(TransactionItem txItem) -> txItem.menuItemSku == menuItem.sku) items

addItemToCart
  :: MenuItem
  -> Number
  -> Array TransactionItem
  -> UUID -- Transaction ID
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (String -> Effect Unit) -- For status messages
  -> (Boolean -> Effect Unit) -- For loading state
  -> Effect Unit
addItemToCart
  menuItem@(MenuItem record)
  qty
  currentItems
  transactionId
  setItems
  setTotals
  setStatusMessage
  setIsProcessing = do

  if qty <= 0.0 then
    setStatusMessage "Quantity must be greater than 0"
  else do
    -- Check current cart quantity first
    let
      currentQtyInCart =
        case
          find (\(TransactionItem item) -> item.menuItemSku == record.sku)
            currentItems
          of
          Just (TransactionItem item) -> item.quantity
          Nothing -> 0.0

      totalRequestedQty = currentQtyInCart + qty

    if totalRequestedQty > toNumber record.quantity then
      setStatusMessage $ "Cannot add " <> show qty <> " more items. Only "
        <> show (record.quantity - Int.floor currentQtyInCart)
        <> " more available."
    else do
      -- Set loading state
      setIsProcessing true

      -- Make a backend call to reserve the item
      void $ launchAff_ do
        result <- TransactionService.createTransactionItem
          transactionId
          record.sku
          qty
          (unwrap record.price)

        liftEffect $ case result of
          Right addedItem -> do
            -- Item successfully reserved, update the cart
            let newItems = addedItem : currentItems

            -- Recalculate totals
            let newTotals = calculateCartTotals newItems

            -- Update state
            setTotals newTotals
            setItems newItems
            setStatusMessage "Item added to transaction and reserved"
            Console.log $ "Added and reserved item: " <> record.name

          Left err -> do
            -- Handle error (likely inventory unavailable)
            setStatusMessage $ "Error: " <> err
            Console.error $ "Failed to reserve item: " <> err

        -- End loading state
        liftEffect $ setIsProcessing false

removeItemFromCart
  :: UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (Boolean -> Effect Unit) -- For loading state
  -> Effect Unit
removeItemFromCart itemId currentItems setItems setTotals setIsProcessing = do
  -- Set loading state
  setIsProcessing true

  -- Make a backend call to release the reservation
  void $ launchAff_ do
    -- Call backend to remove the transaction item
    result <- TransactionService.removeTransactionItem itemId

    liftEffect $ case result of
      Right _ -> do
        -- Item reservation released, update the cart
        let
          newItems = filter (\(TransactionItem item) -> item.id /= itemId)
            currentItems

        -- Recalculate totals  
        let newTotals = calculateCartTotals newItems

        -- Update state
        setTotals newTotals
        setItems newItems
        Console.log $ "Removed item and released reservation with ID: " <> show
          itemId

      Left err -> do
        Console.error $ "Error removing item: " <> err

    -- End loading state  
    liftEffect $ setIsProcessing false