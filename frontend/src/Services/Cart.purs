module Services.Cart where

import Prelude

import Data.Array (filter, find)
import Data.Maybe (Maybe(..))
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Primitives.Quantity (saleQuantityCount)
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)

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