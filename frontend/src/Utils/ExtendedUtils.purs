module Utils.ExtendedUtils where

import Prelude

import Data.Array (filter, find, foldl, (:))
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (DiscreteMoney, fromDiscrete', toDiscrete)
-- import Data.Int (toNumber)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Services.TransactionService as TransactionService
import Types.Inventory (MenuItem(..), Inventory(..))
import Types.Register (CartTotals)
import Types.Transaction (TaxCategory(..), TransactionItem(..))
import Types.UUID (UUID)
import Utils.Money (formatMoney')
import Utils.UUIDGen (genUUID)

emptyCartTotals :: CartTotals
emptyCartTotals =
  { subtotal: Discrete 0
  , taxTotal: Discrete 0
  , total: Discrete 0
  , discountTotal: Discrete 0
  }

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

formatPrice :: DiscreteMoney USD -> String
formatPrice = formatMoney'

formatDiscretePrice :: Discrete USD -> String
formatDiscretePrice = formatMoney' <<< fromDiscrete'

-- Calculate how many items are already in the cart (local reservation)
getCartQuantityForSku :: UUID -> Array TransactionItem -> Int
getCartQuantityForSku sku cartItems =
  case find (\(TransactionItem item) -> item.transactionItemMenuItemSku == sku) cartItems of
    Just (TransactionItem item) -> item.transactionItemQuantity
    Nothing -> 0

-- Check if an item is available considering both inventory and cart quantities
isItemAvailable :: MenuItem -> Int -> Array TransactionItem -> Boolean
isItemAvailable (MenuItem item) requestedQty cartItems =
  let
    currentInCart = getCartQuantityForSku item.sku cartItems
    totalRequestedQty = currentInCart + requestedQty
  in
    totalRequestedQty <= item.quantity

-- Get the remaining available quantity considering cart items
getAvailableQuantity :: MenuItem -> Array TransactionItem -> Int
getAvailableQuantity (MenuItem item) cartItems =
  let
    currentInCart = getCartQuantityForSku item.sku cartItems
  in
    item.quantity - currentInCart

-- Find items that are already in the transaction but might no longer be available
findUnavailableItems :: Array TransactionItem -> Inventory -> Array { id :: UUID, name :: String }
findUnavailableItems cartItems (Inventory inventory) =
  cartItems 
    # filter (\(TransactionItem item) -> 
        case find (\(MenuItem menuItem) -> menuItem.sku == item.transactionItemMenuItemSku) inventory of
          Just (MenuItem menuItem) -> 
            -- If item quantity in cart exceeds inventory
            menuItem.quantity < item.transactionItemQuantity
          Nothing -> 
            -- Item is in cart but no longer in inventory
            true
      )
    # map (\(TransactionItem item) -> 
        let 
          name = case find (\(MenuItem menuItem) -> menuItem.sku == item.transactionItemMenuItemSku) inventory of
            Just (MenuItem menuItem) -> menuItem.name
            Nothing -> "Unknown Item"
        in
          { id: item.transactionItemId, name }
      )

addItemToTransaction
  :: MenuItem
  -> Int
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> Effect Unit
addItemToTransaction menuItem@(MenuItem item) qty currentItems updateItems = do
  launchAff_ do
    itemId <- liftEffect genUUID
    transactionId <- liftEffect genUUID

    let
      priceAsMoney = fromDiscrete' item.price

      priceInCents = unwrap item.price
      subtotalInCents = priceInCents * qty
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
        { transactionItemId: itemId
        , transactionItemTransactionId: transactionId
        , transactionItemMenuItemSku: item.sku
        , transactionItemQuantity: qty
        , transactionItemPricePerUnit: priceAsMoney
        , transactionItemDiscounts: []
        , transactionItemTaxes:
            [ { category: RegularSalesTax
              , rate: taxRate
              , amount: taxAsMoney
              , description: "Sales Tax"
              }
            ]
        , transactionItemSubtotal: subtotalAsMoney
        , transactionItemTotal: totalAsMoney
        }

    liftEffect do
      let
        existingItem = find
          (\(TransactionItem i) -> i.transactionItemMenuItemSku == item.sku)
          currentItems

      case existingItem of
        Just (TransactionItem existing) ->
          let
            newQty = existing.transactionItemQuantity + qty

            existingPriceDiscrete = toDiscrete existing.transactionItemPricePerUnit
            existingPriceInCents = unwrap existingPriceDiscrete

            newSubtotalInCents = existingPriceInCents * newQty
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
              { transactionItemQuantity = newQty
              , transactionItemSubtotal = newSubtotalAsMoney
              , transactionItemTotal = newTotalAsMoney
              , transactionItemTaxes = [ newTaxRecord ]
              }

            updatedItems = map
              ( \i@(TransactionItem currItem) ->
                  if currItem.transactionItemMenuItemSku == item.sku then updatedItem
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
    (filter (\(TransactionItem item) -> item.transactionItemId /= itemId) currentItems)

findExistingItem :: MenuItem -> Array TransactionItem -> Maybe TransactionItem
findExistingItem (MenuItem menuItem) items =
  find (\(TransactionItem txItem) -> txItem.transactionItemMenuItemSku == menuItem.sku) items

addItemToCart
  :: MenuItem
  -> Int
  -> Array TransactionItem
  -> UUID
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (String -> Effect Unit)
  -> (Boolean -> Effect Unit)
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

  if qty <= 0 then
    setStatusMessage "Quantity must be greater than 0"
  else do
    let
      currentQtyInCart =
        case
          find (\(TransactionItem item) -> item.transactionItemMenuItemSku == record.sku)
            currentItems
          of
          Just (TransactionItem item) -> item.transactionItemQuantity
          Nothing -> 0

      totalRequestedQty = currentQtyInCart + qty

    if totalRequestedQty > record.quantity then
      setStatusMessage $ "Cannot add " <> show qty <> " more items. Only "
        <> show (record.quantity - currentQtyInCart)
        <> " more available."
    else do
      -- Set processing state but don't block UI updates
      setIsProcessing true
      setStatusMessage $ "Reserving " <> show qty <> " of " <> record.name <> "..."
      
      void $ launchAff_ do
        result <- TransactionService.createTransactionItem
          transactionId
          record.sku
          qty
          (unwrap record.price)

        liftEffect $ case result of
          Right addedItem -> do
            let newItems = addedItem : currentItems
            let newTotals = calculateCartTotals newItems

            setTotals newTotals
            setItems newItems
            setStatusMessage $ "Added " <> show qty <> " of " <> record.name <> " to cart"
            Console.log $ "Added and reserved item: " <> record.name <> ", Quantity: " <> show qty

          Left err -> do
            let errorMsg = if err == "Product not available" 
                           then "This item has just been reserved by another customer. Please refresh inventory."
                           else "Error: " <> err
            setStatusMessage errorMsg
            Console.error $ "Failed to reserve item: " <> err

        -- Always reset the processing state
        liftEffect $ setIsProcessing false

removeItemFromCart
  :: UUID
  -> Array TransactionItem
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Effect Unit
removeItemFromCart itemId currentItems setItems setTotals setIsProcessing = do
  setIsProcessing true
  
  -- Find item info for better messaging
  let itemInfo = case find (\(TransactionItem item) -> item.transactionItemId == itemId) currentItems of
                   Just (TransactionItem item) -> ", SKU: " <> show item.transactionItemMenuItemSku
                   Nothing -> ""
                   
  Console.log $ "Removing item ID: " <> show itemId <> itemInfo

  void $ launchAff_ do
    result <- TransactionService.removeTransactionItem itemId

    liftEffect $ case result of
      Right _ -> do
        let
          newItems = filter (\(TransactionItem item) -> item.transactionItemId /= itemId) currentItems
        let newTotals = calculateCartTotals newItems

        setTotals newTotals
        setItems newItems
        Console.log $ "Successfully removed item and released reservation: " <> show itemId

      Left err -> do
        Console.error $ "Error removing item: " <> err

    liftEffect $ setIsProcessing false