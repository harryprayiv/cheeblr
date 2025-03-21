module UI.Transaction.LiveCart where

import Prelude

import Data.Array (filter, find, null, sort, (:))
import Data.Array (nub) as Array
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete', toDiscrete)
import Data.Foldable (for_)
import Data.Int as Int
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
import Effect.Aff (launchAff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Transaction (TransactionItem(..), TaxCategory(..))
import Types.UUID (UUID)
import Utils.Money (formatMoney')
import Utils.UUIDGen (genUUID)
import Web.Event.Event as Event
import Web.HTML.HTMLInputElement as Input
import Web.PointerEvent.PointerEvent as PointerEvent

-- Format cents to dollars for display
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

liveCart :: (Array TransactionItem -> Effect Unit) -> Poll Inventory -> Nut
liveCart updateTransactionItems inventoryPoll = Deku.do
  -- State for filtering
  setSearchText /\ searchTextValue <- useState ""
  setActiveCategory /\ activeCategoryValue <- useState "All Items"
  
  -- State for selected items
  setSelectedItems /\ selectedItemsValue <- useState []
  
  -- UI state
  setStatusMessage /\ statusMessageValue <- useState ""

  -- Main component UI
  D.div
    [ DA.klass_ "inv-selector-inventory-main-container"
    , DL.load_ \_ -> liftEffect $ Console.log "LiveInventoryView component loading"
    ]
    [
      -- Inventory header with search
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
      
      -- Category tabs - render directly from the inventory Poll
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
      
      -- Main content: two-column layout for inventory and selected items
      D.div
        [ DA.klass_ "inv-selector-inventory-content-layout" ]
        [
          -- Left column: Inventory table
          D.div
            [ DA.klass_ "inv-selector-inventory-table-container" ]
            [ 
              -- Use the inventory poll directly for rendering and filtering
              inventoryPoll <#~> \(Inventory items) ->
                (Tuple <$> searchTextValue <*> activeCategoryValue) <#~> \(searchText /\ activeCategory) ->
                  let 
                    -- Filter by category
                    categoryFiltered = 
                      if activeCategory == "All Items" 
                      then items 
                      else filter (\(MenuItem i) -> show i.category == activeCategory) items
                      
                    -- Filter by search text
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
            
          -- Right column: Selected items
          D.div
            [ DA.klass_ "inv-selector-selected-items-container" ]
            [
              D.h4 [ DA.klass_ "inv-selector-selected-items-header" ] [ text_ "Selected Items" ],
              
              -- List of selected items
              selectedItemsValue <#~> \items ->
                if null items then
                  D.div [ DA.klass_ "inv-selector-empty-selection" ] [ text_ "No items selected" ]
                else
                  D.div
                    [ DA.klass_ "inv-selector-selected-items-list" ]
                    [
                      -- Table header
                      D.div
                        [ DA.klass_ "inv-selector-selected-item-header" ]
                        [
                          D.div [ DA.klass_ "inv-selector-col-item" ] [ text_ "Item" ],
                          D.div [ DA.klass_ "inv-selector-col-qty" ] [ text_ "Qty" ],
                          D.div [ DA.klass_ "inv-selector-col-price" ] [ text_ "Price" ],
                          D.div [ DA.klass_ "inv-selector-col-actions" ] [ text_ "" ]
                        ],
                        
                      -- Table body
                      D.div
                        [ DA.klass_ "inv-selector-selected-item-body" ]
                        (items <#> \(TransactionItem item) ->
                          D.div
                            [ DA.klass_ "inv-selector-selected-item-row" ]
                            [
                              -- Item name (lookup from inventory)
                              D.div 
                                [ DA.klass_ "inv-selector-col-item" ] 
                                [ 
                                  -- Use inventoryPoll directly for lookup
                                  inventoryPoll <#~> \(Inventory invItems) ->
                                    let
                                      itemInfo = find (\(MenuItem i) -> i.sku == item.menuItemSku) invItems
                                    in
                                      case itemInfo of
                                        Just (MenuItem i) -> text_ i.name
                                        Nothing -> text_ "Unknown Item"
                                ]
                              ,
                              
                              -- Quantity
                              D.div 
                                [ DA.klass_ "inv-selector-col-qty" ] 
                                [ text_ (show item.quantity) ],
                              
                              -- Price
                              D.div 
                                [ DA.klass_ "inv-selector-col-price" ] 
                                [ text_ (formatMoney' item.pricePerUnit) ],
                              
                              -- Remove button
                              D.div 
                                [ DA.klass_ "inv-selector-col-actions" ]
                                [ selectedItemsValue <#~> \currentItems ->
                                    D.button
                                      [ DA.klass_ "inv-selector-remove-btn"
                                      , DL.click_ \_ -> 
                                          removeSelectedItem item.id currentItems setSelectedItems
                                      ]
                                      [ text_ "✕" ]
                                ]
                            ]
                        )
                    ],
                    
              -- Button to update transaction
              D.div
                [ DA.klass_ "inv-selector-action-buttons" ]
                [
                  D.button
                    [ DA.klass_ "inv-selector-clear-btn"
                    , DL.click_ \_ -> do
                        setSelectedItems []
                        setStatusMessage "Selection cleared"
                    ]
                    [ text_ "Clear Selection" ],
                    
                  selectedItemsValue <#~> \items ->
                    D.button
                      [ DA.klass_ "inv-selector-update-btn"
                      , DL.click_ \_ -> do
                          updateTransactionItems items
                          setStatusMessage "Items added to transaction"
                      ]
                      [ text_ "Update Transaction" ]
                ]
            ]
        ],
            
      -- Status message
      statusMessageValue <#~> \msg ->
        if msg == "" then D.div_ []
        else D.div
          [ DA.klass_ "inv-selector-status-message" ]
          [ text_ msg ]
    ]

-- Helper to get item name from inventory
getItemName :: MenuItem -> String
getItemName (MenuItem item) = item.name

-- Helper to remove an item from selected items
removeSelectedItem :: UUID -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Effect Unit
removeSelectedItem itemId currentItems setItems = 
  setItems (filter (\(TransactionItem item) -> item.id /= itemId) currentItems)

renderInventoryTable :: Array MenuItem -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Nut
renderInventoryTable items selectedItems setSelectedItems = 
  D.div
    [ DA.klass_ "inv-selector-inventory-table" ]
    [
      -- Table header
      D.div
        [ DA.klass_ "inv-selector-inventory-table-header" ]
        [
          -- Make sure to keep the same class names here
          -- D.div [ DA.klass_ "inv-selector-col sku-col" ] [ text_ "SKU" ],
          D.div [ DA.klass_ "inv-selector-col name-col" ] [ text_ "Name" ],
          D.div [ DA.klass_ "inv-selector-col brand-col" ] [ text_ "Brand" ],
          D.div [ DA.klass_ "inv-selector-col category-col" ] [ text_ "Category" ],
          D.div [ DA.klass_ "inv-selector-col price-col" ] [ text_ "Price" ],
          D.div [ DA.klass_ "inv-selector-col stock-col" ] [ text_ "In Stock" ],
          D.div [ DA.klass_ "inv-selector-col actions-col" ] [ text_ "Actions" ]
        ],
      
      -- Table body with rows
      D.div
        [ DA.klass_ "inv-selector-inventory-table-body" ]
        (map (\item -> renderInventoryRow item selectedItems setSelectedItems) items)
    ]

renderInventoryRow :: MenuItem -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Nut
renderInventoryRow menuItem@(MenuItem record) selectedItems setSelectedItems =
  let
    formattedPrice = "$" <> formatCentsToDollars (unwrap record.price)
    stockClass = if record.quantity <= 5 then "low-stock" else ""
    
    -- Check if item is already in selected items
    isSelected = find 
      (\(TransactionItem item) -> item.menuItemSku == record.sku) 
      selectedItems
    
    -- Get current quantity if selected
    currentQty = case isSelected of
      Just (TransactionItem item) -> item.quantity
      Nothing -> 0.0
  in
    D.div
      [ DA.klass_ ("inventory-row " <> if record.quantity <= 0 then "out-of-stock" else "") ]
      [
        -- D.div [ DA.klass_ "inv-selector-col sku-col" ] [ text_ (show record.sku) ],
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
                  -- Show current quantity if selected
                  if currentQty > 0.0
                  then D.div
                    [ DA.klass_ "inv-selector-quantity-indicator" ]
                    [ text_ (show currentQty) ]
                  else D.span_ [],
                  
                  -- Add button
                  D.button
                    [ DA.klass_ "inv-selector-add-btn"
                    , DL.click_ \evt -> do
                        -- Prevent row selection
                        Event.stopPropagation (PointerEvent.toEvent evt)
                        -- Add to selection with default quantity 1.0
                        addSelectedItem menuItem 1.0 selectedItems setSelectedItems
                    ]
                    [ text_ "Add" ]
                ]
          ]
      ]

addSelectedItem :: MenuItem -> Number -> Array TransactionItem -> (Array TransactionItem -> Effect Unit) -> Effect Unit
addSelectedItem menuItem@(MenuItem item) qty selectedItems setSelectedItems = do
  void $ launchAff do
    -- Generate UUIDs for the transaction item
    itemId <- liftEffect genUUID
    transactionId <- liftEffect genUUID

    -- Calculate price, tax, etc.
    let
      -- item.price is already Discrete USD, convert to DiscreteMoney
      priceAsMoney = fromDiscrete' item.price
      
      -- Calculate subtotal (using raw Int values)
      qtyAsInt = Int.floor qty
      priceInCents = unwrap item.price
      subtotalInCents = priceInCents * qtyAsInt
      subtotalDiscrete = Discrete subtotalInCents
      subtotalAsMoney = fromDiscrete' subtotalDiscrete
      
      -- Apply default 10% tax
      taxRate = 0.1
      taxRateInt = Int.floor (taxRate * 100.0)
      taxAmountInCents = (subtotalInCents * taxRateInt) / 100
      taxDiscrete = Discrete taxAmountInCents
      taxAsMoney = fromDiscrete' taxDiscrete
      
      -- Calculate total
      totalInCents = subtotalInCents + taxAmountInCents
      totalDiscrete = Discrete totalInCents
      totalAsMoney = fromDiscrete' totalDiscrete
      
      -- Create new transaction item
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
      -- Check if item already exists in selection
      let existingItem = find 
            (\(TransactionItem i) -> i.menuItemSku == item.sku) 
            selectedItems
      
      case existingItem of
        -- If exists, update quantity
        Just (TransactionItem existing) ->
          let
            -- New quantity
            newQty = existing.quantity + qty
            newQtyInt = Int.floor newQty
            
            -- Get price from existing item
            existingPriceDiscrete = toDiscrete existing.pricePerUnit
            existingPriceInCents = unwrap existingPriceDiscrete
            
            -- Recalculate amounts
            newSubtotalInCents = existingPriceInCents * newQtyInt
            newTaxInCents = (newSubtotalInCents * taxRateInt) / 100
            newTotalInCents = newSubtotalInCents + newTaxInCents
            
            -- Create new Discrete USD values
            newSubtotalDiscrete = Discrete newSubtotalInCents
            newTaxDiscrete = Discrete newTaxInCents
            newTotalDiscrete = Discrete newTotalInCents
            
            -- Convert to DiscreteMoney USD
            newSubtotalAsMoney = fromDiscrete' newSubtotalDiscrete
            newTaxAsMoney = fromDiscrete' newTaxDiscrete
            newTotalAsMoney = fromDiscrete' newTotalDiscrete
            
            -- Create updated tax record
            newTaxRecord = 
              { category: RegularSalesTax
              , rate: taxRate
              , amount: newTaxAsMoney
              , description: "Sales Tax"
              }
            
            -- Create updated item
            updatedItem = TransactionItem $ existing
              { quantity = newQty
              , subtotal = newSubtotalAsMoney
              , total = newTotalAsMoney
              , taxes = [newTaxRecord]
              }
            
            -- Update items array
            updatedItems = map
              (\i@(TransactionItem currItem) ->
                if currItem.menuItemSku == item.sku
                then updatedItem
                else i)
              selectedItems
          in
            setSelectedItems updatedItems
            
        -- If new, add to array
        Nothing ->
          setSelectedItems (newItem : selectedItems)

-- CSS Styles
styles :: String
styles = """
.inventory-main-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: 1rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
}

.inv-selector-inventory-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.inv-selector-inventory-controls {
  display: flex;
  gap: 0.5rem;
}

.inv-selector-search-input {
  min-width: 250px;
  padding: 0.5rem;
  border: 1px solid #ddd;
  border-radius: 4px;
}

.inv-selector-inventory-tabs {
  display: flex;
  overflow-x: auto;
  gap: 0.25rem;
  margin-bottom: 1rem;
  border-bottom: 1px solid #ddd;
}

.inv-selector-category-tab {
  padding: 0.5rem 1rem;
  cursor: pointer;
  white-space: nowrap;
  border-radius: 4px 4px 0 0;
  transition: background-color 0.2s;
}

.inv-selector-category-tab:hover {
  background-color: #f0f0f0;
}

.inv-selector-category-tab.active {
  background-color: #f5f5f5;
  border: 1px solid #ddd;
  border-bottom-color: white;
  margin-bottom: -1px;
  font-weight: 600;
}

.inv-selector-inventory-content-layout {
  display: flex;
  gap: 1rem;
  flex: 1;
  overflow: hidden;
}

.inv-selector-inventory-table-container {
  flex: 6;
  display: flex;
  flex-direction: column;
  border: 1px solid #ddd;
  border-radius: 4px;
  overflow: hidden;
}

.inv-selector-selected-items-container {
  flex: 4;
  display: flex;
  flex-direction: column;
  border: 1px solid #ddd;
  border-radius: 4px;
  overflow: hidden;
}

.inv-selector-selected-items-header {
  padding: 0.75rem;
  margin: 0;
  background-color: #f5f5f5;
  border-bottom: 1px solid #ddd;
}

.inv-selector-selected-items-list {
  flex: 1;
  overflow-y: auto;
}

.inv-selector-selected-item-header {
  display: flex;
  padding: 0.5rem;
  background-color: #f9f9f9;
  font-weight: 600;
  border-bottom: 1px solid #ddd;
}

.inv-selector-selected-item-body {
  overflow-y: auto;
}

.inv-selector-selected-item-row {
  display: flex;
  padding: 0.5rem;
  border-bottom: 1px solid #eee;
  transition: background-color 0.2s;
}

.inv-selector-selected-item-row:hover {
  background-color: #f0f0f0;
}

.inv-selector-action-buttons {
  display: flex;
  padding: 0.75rem;
  gap: 0.5rem;
  border-top: 1px solid #ddd;
  background-color: #f5f5f5;
}

.inv-selector-clear-btn {
  background-color: #f1c40f;
  color: #333;
  border: none;
  padding: 0.5rem 1rem;
  border-radius: 4px;
  cursor: pointer;
  flex: 1;
}

.inv-selector-clear-btn:hover {
  background-color: #f39c12;
}

.inv-selector-update-btn {
  background-color: #2ecc71;
  color: white;
  border: none;
  padding: 0.5rem 1rem;
  border-radius: 4px;
  cursor: pointer;
  flex: 2;
}

.inv-selector-update-btn:hover {
  background-color: #27ae60;
}

.inv-selector-inventory-table {
  display: flex;
  flex-direction: column;
  flex: 1;
}

.inv-selector-inventory-table-header {
  display: flex;
  background-color: #f5f5f5;
  font-weight: bold;
  border-bottom: 2px solid #ddd;
  padding: 0.75rem 0.5rem;
}

.inv-selector-inventory-table-body {
  flex: 1;
  overflow-y: auto;
}

.inv-selector-inventory-row {
  display: flex;
  padding: 0.5rem;
  border-bottom: 1px solid #eee;
  transition: background-color 0.2s;
  cursor: pointer;
}

.inv-selector-inventory-row:hover {
  background-color: #f5f5f5;
}

.inv-selector-inventory-row.out-of-stock {
  opacity: 0.6;
  background-color: #f9f9f9;
}

.inv-selector-col {
  padding: 0.5rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.inv-selector-sku-col {
  width: 10%;
}

.inv-selector-name-col {
  width: 20%;
  font-weight: 500;
}

.inv-selector-brand-col {
  width: 10%;
}

.inv-selector-category-col {
  width: 20%;
}

.inv-selector-price-col {
  width: 10%;
  text-align: right;
}

.inv-selector-stock-col {
  width: 10%;
  text-align: center;
}

.inv-selector-low-stock {
  color: #e67e22;
  font-weight: bold;
}

.inv-selector-actions-col {
  width: 20%;
  text-align: center;
}

.inv-selector-quantity-controls {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 0.5rem;
}

.inv-selector-quantity-indicator {
  background-color: #3498db;
  color: white;
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 12px;
  font-size: 0.8rem;
  font-weight: bold;
}

.inv-selector-add-btn {
  background-color: #3498db;
  color: white;
  border: none;
  border-radius: 4px;
  padding: 0.25rem 0.5rem;
  cursor: pointer;
}

.inv-selector-add-btn:hover:not(.disabled) {
  background-color: #2980b9;
}

.inv-selector-add-btn.disabled {
  background-color: #95a5a6;
  cursor: not-allowed;
}

.inv-selector-empty-result {
  padding: 2rem;
  text-align: center;
  color: #95a5a6;
}

.inv-selector-empty-selection {
  padding: 2rem;
  text-align: center;
  color: #95a5a6;
}

.inv-selector-remove-btn {
  background-color: #e74c3c;
  color: white;
  border: none;
  border-radius: 50%;
  width: 20px;
  height: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.7rem;
  cursor: pointer;
}

.inv-selector-remove-btn:hover {
  background-color: #c0392b;
}

.inv-selector-col-item {
  flex: 3;
}

.inv-selector-col-qty {
  flex: 1;
  text-align: center;
}

.inv-selector-col-price {
  flex: 2;
  text-align: right;
}

.inv-selector-col-actions {
  flex: 1;
  display: flex;
  justify-content: center;
}

.inv-selector-status-message {
  position: fixed;
  bottom: 1rem;
  right: 1rem;
  padding: 0.75rem 1.5rem;
  background-color: #2ecc71;
  color: white;
  border-radius: 4px;
  box-shadow: 0 2px 5px rgba(0,0,0,0.2);
  animation: fadeOut 3s forwards;
  animation-delay: 2s;
  z-index: 100;
}

@keyframes fadeOut {
  from { opacity: 1; }
  to { opacity: 0; visibility: hidden; }
}
"""