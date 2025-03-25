module UI.Transaction.LiveCart where

import Prelude

import Data.Array (filter, find, null, sort)
import Data.Array (nub) as Array
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

-- Helper function to find an item name by sku
findItemNameBySku :: UUID -> Inventory -> String
findItemNameBySku sku (Inventory items) = 
  case find (\(MenuItem item) -> item.sku == sku) items of
    Just (MenuItem item) -> item.name
    Nothing -> "Unknown Item"

removeSelectedItem :: UUID -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Effect Unit
removeSelectedItem itemId currentItems setItems =
  setItems (filter (\(TransactionItem item) -> item.id /= itemId) currentItems)

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
                      selectedItemsValue <#~> \selectedItems ->
                        renderInventoryTable searchFiltered selectedItems setSelectedItems
            ],

          D.div
            [ DA.klass_ "inv-selector-selected-items-container" ]
            [
              D.h4 [ DA.klass_ "inv-selector-selected-items-header" ] [ text_ "Selected Items" ],

              (Tuple <$> selectedItemsValue <*> inventoryPoll) <#~> \(Tuple items inventory) -> 
                D.div_ [
                  { effect: do
                      -- Calculate totals and set them explicitly
                      let newTotals = calculateCartTotals items
                      liftEffect $ Console.log $ "Updating cart totals: " <> formatDiscretePrice newTotals.total
                      setTotals newTotals
                    , value: 
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
                                -- Get item name directly from inventory
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
                                              removeItemFromTransaction itemData.id items setSelectedItems
                                              liftEffect $ Console.log "Item removed from cart"
                                          ]
                                          [ text_ "✕" ]
                                      ]
                                  ]
                            )
                        ]
                  }.value
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
renderInventoryTable items selectedItems setSelectedItems =
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
        (map (\item -> renderInventoryRow item selectedItems setSelectedItems) items)
    ]

renderInventoryRow :: MenuItem -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Nut
renderInventoryRow menuItem@(MenuItem record) selectedItems setSelectedItems =
  let
    formattedPrice = "$" <> formatCentsToDollars (unwrap record.price)
    stockClass = if record.quantity <= 5 then "low-stock" else ""

    isSelected = find
      (\(TransactionItem item) -> item.menuItemSku == record.sku)
      selectedItems

    currentQty = case isSelected of
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
                        addItemToTransaction menuItem 1.0 selectedItems setSelectedItems
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