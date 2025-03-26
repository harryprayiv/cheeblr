module UI.Transaction.LiveCart where

import Prelude

import Data.Array (filter, find, null, sort)
import Data.Array (nub) as Array
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete)
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.String (Pattern(..), contains)
import Data.String as String
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Transaction (TransactionItem(..))
import Types.UUID (UUID)
import UI.Transaction.LiveCart.PriceCalculator (addItemToTransaction, calculateCartTotals, emptyCartTotals, formatDiscretePrice, formatPrice, removeItemFromTransaction)
import Web.Event.Event as Event
import Web.HTML.HTMLInputElement as Input
import Web.PointerEvent.PointerEvent as PointerEvent

formatCentsToDollars :: Int -> String
formatCentsToDollars cents =
  let
    dollars = cents / 100
    centsRemaining = cents `mod` 100
    centsStr = if centsRemaining < 10
               then "0" <> show centsRemaining
               else show centsRemaining
  in
    show dollars <> "." <> centsStr

getItemName :: MenuItem -> String
getItemName (MenuItem item) = item.name

findItemNameBySku :: UUID -> Inventory -> String
findItemNameBySku sku (Inventory items) =
  case find (\(MenuItem item) -> item.sku == sku) items of
    Just (MenuItem item) -> item.name
    Nothing -> "Unknown Item"

-- Modified version of addItemToTransaction that updates cart state
addItemWithTotals :: 
  MenuItem -> 
  Number -> 
  Array TransactionItem -> 
  (Array TransactionItem -> Effect Unit) ->
  (CartTotals -> Effect Unit) ->
  Effect Unit
addItemWithTotals menuItem qty currentItems setItems setTotals = do
  addItemToTransaction menuItem qty currentItems \newItems -> do
    -- When we add an item, update totals too
    let newTotals = calculateCartTotals newItems
    setTotals newTotals
    setItems newItems
    liftEffect $ Console.log $ "Updated cart with new item and totals"

-- Modified version of removeItemFromTransaction that updates cart state
removeItemWithTotals :: 
  UUID -> 
  Array TransactionItem -> 
  (Array TransactionItem -> Effect Unit) ->
  (CartTotals -> Effect Unit) ->
  Effect Unit
removeItemWithTotals itemId currentItems setItems setTotals = do
  removeItemFromTransaction itemId currentItems \newItems -> do
    -- When we remove an item, update totals too
    let newTotals = calculateCartTotals newItems
    setTotals newTotals
    setItems newItems
    liftEffect $ Console.log $ "Updated cart after removal"

-- Reusing the CartTotals type from UI.Transaction.LiveCart.PriceCalculator
type CartTotals =
  { subtotal :: Discrete USD
  , taxTotal :: Discrete USD
  , total :: Discrete USD
  , discountTotal :: Discrete USD
  }

liveCart :: (Array TransactionItem -> Effect Unit) -> Poll Inventory -> Nut
liveCart updateTransactionItems inventoryPoll = Deku.do
  setSearchText /\ searchTextValue <- useState ""
  setActiveCategory /\ activeCategoryValue <- useState "All Items"

  setSelectedItems /\ selectedItemsValue <- useState []
  setTotals /\ totalsValue <- useState emptyCartTotals

  setStatusMessage /\ statusMessageValue <- useState ""

  D.div
    [ DA.klass_ "inv-selector-inventory-main-container"
    , DL.load_ \_ -> do
        liftEffect $ Console.log "LiveCart component loading"
        setTotals emptyCartTotals
    ]
    [
      D.div
        [ DA.klass_ "inv-selector-inventory-header" ]
        [
          D.h3_ [ text_ "Select Items" ],
          D.div
            [ DA.klass_ "inv-selector-inventory-controls" ]
            [
              D.input
                [ DA.klass_ "inv-selector-search-input"
                , DA.placeholder_ "Search inventory..."
                , DA.value_ ""
                , DL.input_ \evt -> do
                  for_ (Event.target evt >>= Input.fromEventTarget) \el -> do
                    value <- Input.value el
                    setSearchText value
                ]
                []
            ]
        ],

      inventoryPoll <#~> \(Inventory items) ->
        let categories = ["All Items"] <> (sort $ Array.nub $ map (\(MenuItem i) -> show i.category) items)
        in
          D.div
            [ DA.klass_ "inv-selector-inventory-tabs" ]
            [ D.div_ (categories <#> \cat ->
                D.div
                  [ DA.klass $ activeCategoryValue <#> \active ->
                      "category-tab" <> if active == cat then " active" else ""
                  , DL.click_ \_ -> setActiveCategory cat
                  ]
                  [ text_ cat ]
              )
            ],

      D.div
        [ DA.klass_ "inv-selector-inventory-content-layout" ]
        [
          D.div
            [ DA.klass_ "inv-selector-inventory-table-container" ]
            [
              inventoryPoll <#~> \(Inventory items) ->
                (Tuple <$> searchTextValue <*> activeCategoryValue) <#~> \(Tuple searchText activeCategory) ->
                  let
                    -- Get filtered items for display only
                    -- This does NOT affect what's in the cart
                    categoryFiltered =
                      if activeCategory == "All Items"
                      then items
                      else filter (\(MenuItem i) -> show i.category == activeCategory) items

                    searchFiltered =
                      if searchText == ""
                      then categoryFiltered
                      else filter
                            (\(MenuItem item) ->
                              contains (Pattern (String.toLower searchText))
                                      (String.toLower item.name))
                            categoryFiltered
                  in
                    if null searchFiltered then
                      D.div [ DA.klass_ "inv-selector-empty-result" ] [ text_ "No items found" ]
                    else
                      -- The key part: we need the latest selectedItems value
                      selectedItemsValue <#~> \currentItems ->
                        renderInventoryTable 
                          searchFiltered 
                          currentItems 
                          \newItems -> do
                            -- Update both items and totals when the cart changes
                            let newTotals = calculateCartTotals newItems
                            setTotals newTotals
                            setSelectedItems newItems
            ],

          D.div
            [ DA.klass_ "inv-selector-selected-items-container" ]
            [
              D.h4 [ DA.klass_ "inv-selector-selected-items-header" ] [ text_ "Selected Items" ],

              -- Use the cart items with inventory for proper display
              (Tuple <$> selectedItemsValue <*> inventoryPoll) <#~> \(Tuple items inventory) ->
                if null items then
                  D.div [ DA.klass_ "inv-selector-empty-selection" ] [ text_ "No items selected" ]
                else
                  D.div
                    [ DA.klass_ "inv-selector-selected-items-list" ]
                    [
                      D.div
                        [ DA.klass_ "inv-selector-selected-item-header" ]
                        [
                          D.div [ DA.klass_ "inv-selector-col-item" ] [ text_ "Item" ],
                          D.div [ DA.klass_ "inv-selector-col-qty" ] [ text_ "Qty" ],
                          D.div [ DA.klass_ "inv-selector-col-price" ] [ text_ "Price" ],
                          D.div [ DA.klass_ "inv-selector-col-total" ] [ text_ "Total" ],
                          D.div [ DA.klass_ "inv-selector-col-actions" ] [ text_ "" ]
                        ],

                      D.div
                        [ DA.klass_ "inv-selector-selected-item-body" ]
                        (items <#> \(TransactionItem itemData) ->
                          let
                            -- Look up item name from full inventory, not filtered view
                            itemName = findItemNameBySku itemData.menuItemSku inventory
                          in
                            D.div
                              [ DA.klass_ "inv-selector-selected-item-row" ]
                              [
                                D.div
                                  [ DA.klass_ "inv-selector-col-item" ]
                                  [ text_ itemName ],

                                D.div
                                  [ DA.klass_ "inv-selector-col-qty" ]
                                  [ text_ (show itemData.quantity) ],

                                D.div
                                  [ DA.klass_ "inv-selector-col-price" ]
                                  [ text_ (formatPrice itemData.pricePerUnit) ],

                                D.div
                                  [ DA.klass_ "inv-selector-col-total" ]
                                  [ text_ (formatPrice itemData.total) ],

                                D.div
                                  [ DA.klass_ "inv-selector-col-actions" ]
                                  [
                                    D.button
                                      [ DA.klass_ "inv-selector-remove-btn"
                                      , DL.click_ \_ -> do
                                          -- Use the helper function to remove item and update totals
                                          removeItemWithTotals itemData.id items setSelectedItems setTotals
                                      ]
                                      [ text_ "✕" ]
                                  ]
                              ]
                        )
                    ],

              D.div
                [ DA.klass_ "price-calculation-panel" ]
                [
                  D.div
                    [ DA.klass_ "price-summary" ]
                    [
                      D.div
                        [ DA.klass_ "price-summary-row" ]
                        [
                          D.div
                            [ DA.klass_ "price-summary-label" ]
                            [ text_ "Subtotal:" ],
                          D.div
                            [ DA.klass_ "price-summary-value" ]
                            [ totalsValue <#~> \totals ->
                                let totalsStr = formatDiscretePrice totals.subtotal
                                in text_ totalsStr
                            ]
                        ],

                      D.div
                        [ DA.klass_ "price-summary-row" ]
                        [
                          D.div
                            [ DA.klass_ "price-summary-label" ]
                            [ text_ "Tax:" ],
                          D.div
                            [ DA.klass_ "price-summary-value" ]
                            [ totalsValue <#~> \totals ->
                                let totalsStr = formatDiscretePrice totals.taxTotal
                                in text_ totalsStr
                            ]
                        ],

                      D.div
                        [ DA.klass_ "price-summary-row total-row" ]
                        [
                          D.div
                            [ DA.klass_ "price-summary-label" ]
                            [ text_ "Total:" ],
                          D.div
                            [ DA.klass_ "price-summary-value" ]
                            [ totalsValue <#~> \totals ->
                                let totalsStr = formatDiscretePrice totals.total
                                in text_ totalsStr
                            ]
                        ]
                    ],

                  D.div
                    [ DA.klass_ "inv-selector-action-buttons" ]
                    [
                      D.button
                        [ DA.klass_ "inv-selector-clear-btn"
                        , DL.click_ \_ -> do
                            setSelectedItems []
                            setTotals emptyCartTotals
                            setStatusMessage "Selection cleared"
                            liftEffect $ Console.log "Selection cleared"
                        ]
                        [ text_ "Clear Selection" ],

                      selectedItemsValue <#~> \items ->
                        D.button
                          [ DA.klass_ "inv-selector-update-btn"
                          , DA.klass $ pure $ if null items then "disabled" else ""
                          , DA.disabled_ $ if null items then "disabled" else ""
                          , DL.click_ \_ -> do
                              updateTransactionItems items
                              setStatusMessage "Items added to transaction"
                              liftEffect $ Console.log "Items added to transaction"
                          ]
                          [ text_ "Update Transaction" ]
                    ]
                ]
            ]
        ],

      statusMessageValue <#~> \msg ->
        if msg == "" then D.div_ []
        else D.div
          [ DA.klass_ "inv-selector-status-message" ]
          [ text_ msg ]
    ]

renderInventoryTable :: Array MenuItem -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Nut
renderInventoryTable items selectedItems setItems =
  D.div
    [ DA.klass_ "inv-selector-inventory-table" ]
    [
      D.div
        [ DA.klass_ "inv-selector-inventory-table-header" ]
        [
          D.div [ DA.klass_ "inv-selector-col name-col" ] [ text_ "Name" ],
          D.div [ DA.klass_ "inv-selector-col brand-col" ] [ text_ "Brand" ],
          D.div [ DA.klass_ "inv-selector-col category-col" ] [ text_ "Category" ],
          D.div [ DA.klass_ "inv-selector-col price-col" ] [ text_ "Price" ],
          D.div [ DA.klass_ "inv-selector-col stock-col" ] [ text_ "In Stock" ],
          D.div [ DA.klass_ "inv-selector-col actions-col" ] [ text_ "Actions" ]
        ],

      D.div
        [ DA.klass_ "inv-selector-inventory-table-body" ]
        (map (\item -> renderInventoryRow item selectedItems setItems) items)
    ]

renderInventoryRow :: MenuItem -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Nut
renderInventoryRow menuItem@(MenuItem record) selectedItems setItems =
  let
    formattedPrice = "$" <> formatCentsToDollars (unwrap record.price)
    stockClass = if record.quantity <= 5 then "low-stock" else ""

    existingItem = find
      (\(TransactionItem item) -> item.menuItemSku == record.sku)
      selectedItems
    
    currentQty = case existingItem of
      Just (TransactionItem item) -> item.quantity
      Nothing -> 0.0
  in
    D.div
      [ DA.klass_ ("inventory-row " <> if record.quantity <= 0 then "out-of-stock" else "") ]
      [
        D.div [ DA.klass_ "inv-selector-col name-col" ] [ text_ record.name ],
        D.div [ DA.klass_ "inv-selector-col brand-col" ] [ text_ record.brand ],
        D.div [ DA.klass_ "inv-selector-col category-col" ] [ text_ (show record.category <> " - " <> record.subcategory) ],
        D.div [ DA.klass_ "inv-selector-col price-col" ] [ text_ formattedPrice ],
        D.div [ DA.klass_ ("inv-selector-col stock-col " <> stockClass) ] [ text_ (show record.quantity) ],
        D.div
          [ DA.klass_ "inv-selector-col actions-col" ]
          [
            if record.quantity <= 0
            then
              D.button
                [ DA.klass_ "inv-selector-add-btn disabled"
                , DA.disabled_ "true"
                ]
                [ text_ "Out of Stock" ]
            else
              D.div
                [ DA.klass_ "inv-selector-quantity-controls" ]
                [
                  if currentQty > 0.0
                  then D.div
                    [ DA.klass_ "inv-selector-quantity-indicator" ]
                    [ text_ (show currentQty) ]
                  else D.span_ [],

                  D.button
                    [ DA.klass_ "inv-selector-add-btn"
                    , DL.click_ \evt -> do
                        Event.stopPropagation (PointerEvent.toEvent evt)
                        -- Add item using the FULL current state, not just what's visible
                        addItemToTransaction menuItem 1.0 selectedItems \newItems -> do
                          setItems newItems
                          liftEffect $ Console.log $ "Added item: " <> getItemName menuItem
                    ]
                    [ text_ "Add" ]
                ]
          ]
      ]

styles :: String
styles = """
/* LiveCart Styles for Price Totals */

.price-calculation-panel {
  border-top: 1px solid #ddd;
  padding: 1rem;
  background: #f9f9f9;
  border-radius: 0 0 4px 4px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.price-summary {
  margin-bottom: 1rem;
}

.price-summary-row {
  display: flex;
  justify-content: space-between;
  padding: 0.5rem 0;
  border-bottom: 1px solid #eee;
}

.price-summary-row:last-child {
  border-bottom: none;
}

.price-summary-row.total-row {
  font-weight: bold;
  font-size: 1.2em;
  margin-top: 0.5rem;
  padding-top: 0.5rem;
  border-top: 2px solid #ddd;
}

.price-summary-label {
  color: #555;
}

.price-summary-value {
  font-weight: 600;
}

.inv-selector-col-total {
  flex: 1;
  text-align: right;
  font-weight: 600;
}
"""