module Services.Cart where

import Prelude

import Data.Array (filter, find, (:))
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Services.AuthService (UserId)
import Services.TransactionService
  ( calculateCartTotals
  , createSaleItem
  , removeSaleItem
  )
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Primitives.Money
  ( saleMoneyCents
  , unsafeMkSaleMoney
  )
import Types.Primitives.Quantity
  ( saleQuantityCount
  , unsafeMkSaleQuantity
  )
import Types.Register (CartTotals)
import Types.Transaction (TaxCategory(..))
import Types.Transaction.Sale as Sale
import Types.UUID (UUID, genUUID)

getCartQuantityForSku :: UUID -> Array Sale.Item -> Int
getCartQuantityForSku sku cartItems =
  case find (\item -> item.itemMenuItemSku == sku) cartItems of
    Just item -> saleQuantityCount item.itemQuantity
    Nothing -> 0

isItemAvailable :: MenuItem -> Int -> Array Sale.Item -> Boolean
isItemAvailable (MenuItem item) requestedQty cartItems =
  let
    currentInCart = getCartQuantityForSku item.sku cartItems
    totalRequestedQty = currentInCart + requestedQty
  in
    totalRequestedQty <= item.quantity

getAvailableQuantity :: MenuItem -> Array Sale.Item -> Int
getAvailableQuantity (MenuItem item) cartItems =
  let
    currentInCart = getCartQuantityForSku item.sku cartItems
  in
    item.quantity - currentInCart

findUnavailableItems
  :: Array Sale.Item
  -> Inventory
  -> Array { id :: UUID, name :: String }
findUnavailableItems cartItems (Inventory inventory) =
  cartItems
    # filter
        ( \item ->
            case
              find (\(MenuItem m) -> m.sku == item.itemMenuItemSku) inventory
              of
              Just (MenuItem m) ->
                m.quantity < saleQuantityCount item.itemQuantity
              Nothing -> true
        )
    # map
        ( \item ->
            let
              name = case
                find
                  (\(MenuItem m) -> m.sku == item.itemMenuItemSku)
                  inventory
                of
                Just (MenuItem m) -> m.name
                Nothing -> "Unknown Item"
            in
              { id: item.itemId, name }
        )

findExistingItem :: MenuItem -> Array Sale.Item -> Maybe Sale.Item
findExistingItem (MenuItem menuItem) items =
  find (\item -> item.itemMenuItemSku == menuItem.sku) items

removeItemFromTransaction
  :: UUID
  -> Array Sale.Item
  -> (Array Sale.Item -> Effect Unit)
  -> Effect Unit
removeItemFromTransaction itemId currentItems updateItems =
  updateItems (filter (\item -> item.itemId /= itemId) currentItems)

-- | Local optimistic cart manipulation (no server round-trip). Kept available
-- | for offline-style UX. Server-side reservation is authoritative once
-- | 'addItemToCart' fires.
addItemToTransaction
  :: MenuItem
  -> Int
  -> Array Sale.Item
  -> (Array Sale.Item -> Effect Unit)
  -> Effect Unit
addItemToTransaction (MenuItem item) qty currentItems updateItems =
  launchAff_ do
    itemId <- liftEffect genUUID
    transactionId <- liftEffect genUUID

    let
      priceInCents = unwrap item.price
      subtotalInCents = priceInCents * qty
      taxRate = 0.15
      taxRateInt = Int.floor (taxRate * 100.0)
      taxAmountInCents = (subtotalInCents * taxRateInt) / 100
      totalInCents = subtotalInCents + taxAmountInCents

      newTax :: Sale.Tax
      newTax =
        { taxCategory: RegularSalesTax
        , taxRate: taxRate
        , taxAmount: unsafeMkSaleMoney taxAmountInCents
        , taxDescription: "Sales Tax"
        }

      newItem :: Sale.Item
      newItem =
        { itemId: itemId
        , itemTransactionId: transactionId
        , itemMenuItemSku: item.sku
        , itemQuantity: unsafeMkSaleQuantity qty
        , itemPricePerUnit: unsafeMkSaleMoney priceInCents
        , itemDiscounts: []
        , itemTaxes: [ newTax ]
        , itemSubtotal: unsafeMkSaleMoney subtotalInCents
        , itemTotal: unsafeMkSaleMoney totalInCents
        }

    liftEffect do
      let existing = find (\i -> i.itemMenuItemSku == item.sku) currentItems
      case existing of
        Just ex ->
          let
            newQty = saleQuantityCount ex.itemQuantity + qty
            existingPriceInCents = saleMoneyCents ex.itemPricePerUnit
            newSubtotalInCents = existingPriceInCents * newQty
            newTaxInCents = (newSubtotalInCents * taxRateInt) / 100
            newTotalInCents = newSubtotalInCents + newTaxInCents

            mergedTax :: Sale.Tax
            mergedTax =
              { taxCategory: RegularSalesTax
              , taxRate: taxRate
              , taxAmount: unsafeMkSaleMoney newTaxInCents
              , taxDescription: "Sales Tax"
              }

            updated :: Sale.Item
            updated = ex
              { itemQuantity = unsafeMkSaleQuantity newQty
              , itemSubtotal = unsafeMkSaleMoney newSubtotalInCents
              , itemTotal = unsafeMkSaleMoney newTotalInCents
              , itemTaxes = [ mergedTax ]
              }

            updatedItems =
              map
                ( \i ->
                    if i.itemMenuItemSku == item.sku then updated else i
                )
                currentItems
          in
            updateItems updatedItems

        Nothing ->
          updateItems (newItem : currentItems)

addItemToCart
  :: UserId
  -> MenuItem
  -> Int
  -> Array Sale.Item
  -> UUID -- saleId
  -> (Array Sale.Item -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (String -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Effect Unit
addItemToCart
  userId
  (MenuItem record)
  qty
  currentItems
  saleId
  setItems
  setTotals
  setStatusMessage
  setCheckingInventory =
  if qty <= 0 then
    setStatusMessage "Quantity must be greater than 0"
  else do
    setCheckingInventory true
    setStatusMessage "Checking inventory..."

    let
      existing = find (\i -> i.itemMenuItemSku == record.sku) currentItems
      currentQtyInCart = case existing of
        Just i -> saleQuantityCount i.itemQuantity
        Nothing -> 0
      totalRequestedQty = currentQtyInCart + qty

    void $ launchAff_ do
      result <- createSaleItem userId saleId record.sku qty (unwrap record.price)

      liftEffect case result of
        Right newItem -> do
          let
            updatedItems = case existing of
              Just ex ->
                let
                  priceInCents = saleMoneyCents ex.itemPricePerUnit
                  newSubtotal = priceInCents * totalRequestedQty
                  taxRate = case ex.itemTaxes of
                    [ t ] -> t.taxRate
                    _ -> case newItem.itemTaxes of
                      [ t ] -> t.taxRate
                      _ -> 0.08
                  taxAmount = Int.floor (Int.toNumber newSubtotal * taxRate)
                  newTotal = newSubtotal + taxAmount

                  mergedTax :: Sale.Tax
                  mergedTax =
                    { taxCategory: RegularSalesTax
                    , taxRate: taxRate
                    , taxAmount: unsafeMkSaleMoney taxAmount
                    , taxDescription: "Sales Tax"
                    }

                  merged :: Sale.Item
                  merged = ex
                    { itemQuantity = unsafeMkSaleQuantity totalRequestedQty
                    , itemSubtotal = unsafeMkSaleMoney newSubtotal
                    , itemTaxes = [ mergedTax ]
                    , itemTotal = unsafeMkSaleMoney newTotal
                    }
                in
                  map
                    ( \i ->
                        if i.itemMenuItemSku == record.sku then merged else i
                    )
                    currentItems
              Nothing ->
                newItem : currentItems

            newTotals = calculateCartTotals updatedItems

          setItems updatedItems
          setTotals newTotals
          setCheckingInventory false
          setStatusMessage $ "Added " <> record.name <> " to cart"

        Left err -> do
          setCheckingInventory false
          setStatusMessage $ "Failed to add item: " <> err

removeItemFromCart
  :: UserId
  -> UUID
  -> Array Sale.Item
  -> (Array Sale.Item -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Effect Unit
removeItemFromCart userId itemId currentItems setItems setTotals setIsProcessing = do
  setIsProcessing true

  let
    itemInfo = case find (\i -> i.itemId == itemId) currentItems of
      Just i -> ", SKU: " <> show i.itemMenuItemSku
      Nothing -> ""

  Console.log $ "Removing item ID: " <> show itemId <> itemInfo

  void $ launchAff_ do
    result <- removeSaleItem userId itemId

    liftEffect case result of
      Right _ -> do
        let
          newItems = filter (\i -> i.itemId /= itemId) currentItems
          newTotals = calculateCartTotals newItems
        setTotals newTotals
        setItems newItems
        Console.log $ "Successfully removed item: " <> show itemId

      Left err ->
        Console.error $ "Error removing item: " <> err

    liftEffect $ setIsProcessing false