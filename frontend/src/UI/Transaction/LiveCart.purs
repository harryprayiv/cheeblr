module UI.Transaction.LiveCart where

import Prelude

import Data.Array (filter, find, null, sort)
import Data.Array (nub) as Array
import Data.Foldable (for_)
import Data.Int (floor, toNumber)
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Number (fromString)
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
import Deku.Hooks (useHot, useState, (<#~>))
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Register (CartTotals)
import Types.Transaction (TransactionItem(..))
import Types.UUID (UUID)
import Utils.CartUtils (addItemToTransaction, calculateCartTotals, emptyCartTotals, formatDiscretePrice, formatPrice, removeItemFromTransaction)
import Utils.Formatting (findItemNameBySku, formatCentsToDollars)
import Web.Event.Event as Event
import Web.HTML.HTMLInputElement as Input
import Web.PointerEvent.PointerEvent as PointerEvent

-- The main LiveCart component
liveCart :: (Array TransactionItem -> Effect Unit) -> Poll Inventory -> Nut
liveCart updateTransactionItems inventoryPoll = Deku.do
  -- UI state for filtering
  setSearchText /\ searchTextValue <- useState ""
  setActiveCategory /\ activeCategoryValue <- useState "All Items"
  setQuantity /\ quantityValue <- useState 1.0
  setStatusMessage /\ statusMessageValue <- useState ""

  -- Cart state - keep isolated from the filtering mechanism
  setCartItems /\ cartItemsValue <- useHot []
  setCartTotals /\ cartTotalsValue <- useHot emptyCartTotals

  D.div
    [ DA.klass_ "inv-selector-inventory-main-container"
    , DL.load_ \_ -> do
        liftEffect $ Console.log "LiveCart component loading"
    ]
    [ D.div
        [ DA.klass_ "inv-selector-inventory-header" ]
        [ D.h3_ [ text_ "Select Items" ]
        , D.div
            [ DA.klass_ "inv-selector-inventory-controls" ]
            []
        ]
    ,
      -- Category navigation
      inventoryPoll <#~> \(Inventory items) ->
        let
          categories = [ "All Items" ] <>
            (sort $ Array.nub $ map (\(MenuItem i) -> show i.category) items)
        in
          D.div
            [ DA.klass_ "inv-selector-inventory-tabs" ]
            ( categories <#> \cat ->
                D.div
                  [ DA.klass $ activeCategoryValue <#> \active ->
                      "category-tab" <> if active == cat then " active" else ""
                  , DL.click_ \_ -> setActiveCategory cat
                  ]
                  [ text_ cat ]
            )
    , D.div
        [ DA.klass_ "inv-selector-inventory-content-layout" ]
        [
          -- Left side: Inventory table with filters
          D.div
            [ DA.klass_ "inv-selector-inventory-table-container" ]
            [
              -- Search and quantity controls
              D.div
                [ DA.klass_ "inv-selector-inventory-actions" ]
                [ D.div
                    [ DA.klass_ "inv-selector-search-control" ]
                    [ D.input
                        [ DA.klass_ "inv-selector-search-input"
                        , DA.placeholder_ "Search inventory..."
                        , DA.value_ ""
                        , DL.input_ \evt -> do
                            for_ (Event.target evt >>= Input.fromEventTarget)
                              \el -> do
                                value <- Input.value el
                                setSearchText value
                        ]
                        []
                    ]
                , D.div
                    [ DA.klass_ "inv-selector-right-controls" ]
                    [ D.div
                        [ DA.klass_ "inv-selector-quantity-control" ]
                        [ D.div
                            [ DA.klass_ "qty-label" ]
                            [ text_ "Quantity:" ]
                        , D.input
                            [ DA.klass_ "qty-input"
                            , DA.xtype_ "number"
                            , DA.min_ "1"
                            , DA.step_ "1"
                            , DA.value_ "1"
                            , DL.input_ \evt -> do
                                for_
                                  (Event.target evt >>= Input.fromEventTarget)
                                  \el -> do
                                    val <- Input.value el
                                    case fromString val of
                                      Just num ->
                                        if num > 0.0 then setQuantity num
                                        else pure unit
                                      Nothing -> pure unit
                            ]
                            []
                        ]
                    ]
                ]
            ,
              -- Filtered inventory table
              D.div_
                [
                  -- First transform: get the inventory and apply both filters
                  inventoryPoll <#~> \(Inventory allItems) ->
                    searchTextValue <#~> \searchText ->
                      activeCategoryValue <#~> \activeCategory ->
                        let
                          -- Apply category filter
                          categoryFiltered =
                            if activeCategory == "All Items" then allItems
                            else filter
                              ( \(MenuItem i) -> show i.category ==
                                  activeCategory
                              )
                              allItems

                          -- Apply search filter
                          filteredItems =
                            if searchText == "" then categoryFiltered
                            else filter
                              ( \(MenuItem item) ->
                                  contains (Pattern (String.toLower searchText))
                                    (String.toLower item.name)
                              )
                              categoryFiltered
                        in
                          if null filteredItems then
                            D.div [ DA.klass_ "inv-selector-empty-result" ]
                              [ text_ "No items found" ]
                          else
                            D.div
                              [ DA.klass_ "inv-selector-inventory-table" ]
                              [ D.div
                                  [ DA.klass_
                                      "inv-selector-inventory-table-header"
                                  ]
                                  [ D.div
                                      [ DA.klass_ "inv-selector-col name-col" ]
                                      [ text_ "Name" ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col brand-col" ]
                                      [ text_ "Brand" ]
                                  , D.div
                                      [ DA.klass_
                                          "inv-selector-col category-col"
                                      ]
                                      [ text_ "Category" ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col price-col" ]
                                      [ text_ "Price" ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col stock-col" ]
                                      [ text_ "In Stock" ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col actions-col"
                                      ]
                                      [ text_ "Actions" ]
                                  ]
                              , D.div
                                  [ DA.klass_
                                      "inv-selector-inventory-table-body"
                                  ]
                                  ( filteredItems <#>
                                      \menuItem@(MenuItem record) ->
                                        -- For each item in the filtered results, 
                                        -- we need to check if it's in the cart
                                        cartItemsValue <#~> \cartItems ->
                                          quantityValue <#~> \qtyVal ->
                                            let
                                              formattedPrice = "$" <>
                                                formatCentsToDollars
                                                  (unwrap record.price)
                                              stockClass =
                                                if record.quantity <= 5 then
                                                  "low-stock"
                                                else ""

                                              -- Find if this item is already in the cart
                                              existingItem = find
                                                ( \(TransactionItem item) ->
                                                    item.transactionItemMenuItemSku ==
                                                      record.sku
                                                )
                                                cartItems

                                              currentQty = case existingItem of
                                                Just (TransactionItem item) ->
                                                  item.transactionItemQuantity
                                                Nothing -> 0.0
                                            in
                                              D.div
                                                [ DA.klass_
                                                    ( "inventory-row " <>
                                                        if record.quantity <= 0 then
                                                          "out-of-stock"
                                                        else ""
                                                    )
                                                ]
                                                [ D.div
                                                    [ DA.klass_
                                                        "inv-selector-col name-col"
                                                    ]
                                                    [ text_ record.name ]
                                                , D.div
                                                    [ DA.klass_
                                                        "inv-selector-col brand-col"
                                                    ]
                                                    [ text_ record.brand ]
                                                , D.div
                                                    [ DA.klass_
                                                        "inv-selector-col category-col"
                                                    ]
                                                    [ text_
                                                        ( show record.category
                                                            <> " - "
                                                            <>
                                                              record.subcategory
                                                        )
                                                    ]
                                                , D.div
                                                    [ DA.klass_
                                                        "inv-selector-col price-col"
                                                    ]
                                                    [ text_ formattedPrice ]
                                                , D.div
                                                    [ DA.klass_
                                                        ( "inv-selector-col stock-col "
                                                            <> stockClass
                                                        )
                                                    ]
                                                    [ text_
                                                        (show record.quantity)
                                                    ]
                                                , D.div
                                                    [ DA.klass_
                                                        "inv-selector-col actions-col"
                                                    ]
                                                    [ if record.quantity <= 0 then
                                                        D.button
                                                          [ DA.klass_
                                                              "inv-selector-add-btn disabled"
                                                          , DA.disabled_ "true"
                                                          ]
                                                          [ text_ "Out of Stock"
                                                          ]
                                                      else
                                                        D.div
                                                          [ DA.klass_
                                                              "inv-selector-quantity-controls"
                                                          ]
                                                          [ if currentQty > 0.0 then
                                                              D.div
                                                                [ DA.klass_
                                                                    "inv-selector-quantity-indicator"
                                                                ]
                                                                [ text_
                                                                    ( show
                                                                        currentQty
                                                                    )
                                                                ]
                                                            else D.span_ []
                                                          , D.button
                                                              [ DA.klass_
                                                                  "inv-selector-add-btn"
                                                              , DL.click_
                                                                  \evt -> do
                                                                    Event.stopPropagation
                                                                      ( PointerEvent.toEvent
                                                                          evt
                                                                      )
                                                                    addItemToCart
                                                                      menuItem
                                                                      qtyVal
                                                                      cartItems
                                                                      setCartItems
                                                                      setCartTotals
                                                                      setStatusMessage
                                                              ]
                                                              [ text_ "Add" ]
                                                          ]
                                                    ]
                                                ]
                                  )
                              ]
                ]
            ]
        ,
          -- Right side: Cart
          D.div
            [ DA.klass_ "inv-selector-selected-items-container" ]
            [ D.h4 [ DA.klass_ "inv-selector-selected-items-header" ]
                [ text_ "Selected Items" ]
            , (Tuple <$> cartItemsValue <*> inventoryPoll) <#~>
                \(Tuple cartItems inventory) ->
                  if null cartItems then
                    D.div [ DA.klass_ "inv-selector-empty-selection" ]
                      [ text_ "No items selected" ]
                  else
                    D.div
                      [ DA.klass_ "inv-selector-selected-items-list" ]
                      [ D.div
                          [ DA.klass_ "inv-selector-selected-item-header" ]
                          [ D.div [ DA.klass_ "inv-selector-col-item" ]
                              [ text_ "Item" ]
                          , D.div [ DA.klass_ "inv-selector-col-qty" ]
                              [ text_ "Qty" ]
                          , D.div [ DA.klass_ "inv-selector-col-price" ]
                              [ text_ "Price" ]
                          , D.div [ DA.klass_ "inv-selector-col-total" ]
                              [ text_ "Total" ]
                          , D.div [ DA.klass_ "inv-selector-col-actions" ]
                              [ text_ "" ]
                          ]
                      , D.div
                          [ DA.klass_ "inv-selector-selected-item-body" ]
                          ( cartItems <#> \(TransactionItem itemData) ->
                              let
                                itemName = findItemNameBySku
                                  itemData.transactionItemMenuItemSku
                                  inventory
                              in
                                D.div
                                  [ DA.klass_ "inv-selector-selected-item-row" ]
                                  [ D.div
                                      [ DA.klass_ "inv-selector-col-item" ]
                                      [ text_ itemName ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col-qty" ]
                                      [ text_ (show itemData.transactionItemQuantity) ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col-price" ]
                                      [ text_
                                          (formatPrice itemData.transactionItemPricePerUnit)
                                      ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col-total" ]
                                      [ text_ (formatPrice itemData.transactionItemTotal) ]
                                  , D.div
                                      [ DA.klass_ "inv-selector-col-actions" ]
                                      [ D.button
                                          [ DA.klass_ "inv-selector-remove-btn"
                                          , DL.click_ \_ -> do
                                              removeItemFromCart itemData.transactionItemId
                                                cartItems
                                                setCartItems
                                                setCartTotals
                                          ]
                                          [ text_ "✕" ]
                                      ]
                                  ]
                          )
                      ]
            , D.div
                [ DA.klass_ "price-calculation-panel" ]
                [ D.div
                    [ DA.klass_ "price-summary" ]
                    [ D.div
                        [ DA.klass_ "price-summary-row" ]
                        [ D.div
                            [ DA.klass_ "price-summary-label" ]
                            [ text_ "Subtotal:" ]
                        , D.div
                            [ DA.klass_ "price-summary-value" ]
                            [ cartTotalsValue <#~> \totals ->
                                text_ (formatDiscretePrice totals.subtotal)
                            ]
                        ]
                    , D.div
                        [ DA.klass_ "price-summary-row" ]
                        [ D.div
                            [ DA.klass_ "price-summary-label" ]
                            [ text_ "Tax:" ]
                        , D.div
                            [ DA.klass_ "price-summary-value" ]
                            [ cartTotalsValue <#~> \totals ->
                                text_ (formatDiscretePrice totals.taxTotal)
                            ]
                        ]
                    , D.div
                        [ DA.klass_ "price-summary-row total-row" ]
                        [ D.div
                            [ DA.klass_ "price-summary-label" ]
                            [ text_ "Total:" ]
                        , D.div
                            [ DA.klass_ "price-summary-value" ]
                            [ cartTotalsValue <#~> \totals ->
                                text_ (formatDiscretePrice totals.total)
                            ]
                        ]
                    ]
                , D.div
                    [ DA.klass_ "inv-selector-action-buttons" ]
                    [ D.button
                        [ DA.klass_ "inv-selector-clear-btn"
                        , DL.click_ \_ -> do
                            setCartItems []
                            setCartTotals emptyCartTotals
                            setStatusMessage "Selection cleared"
                            liftEffect $ Console.log "Selection cleared"
                        ]
                        [ text_ "Clear Selection" ]
                    , cartItemsValue <#~> \items ->
                        D.button
                          [ DA.klass_ "inv-selector-update-btn"
                          , DA.klass_ $ if null items then "disabled" else ""
                          , DA.disabled_ $ if null items then "disabled" else ""
                          , DL.click_ \_ -> do
                              updateTransactionItems items
                              setStatusMessage "Items added to transaction"
                              liftEffect $ Console.log
                                "Items added to transaction"
                          ]
                          [ text_ "Update Transaction" ]
                    ]
                ]
            ]
        ]
    , statusMessageValue <#~> \msg ->
        if msg == "" then D.div_ []
        else D.div
          [ DA.klass_ "inv-selector-status-message" ]
          [ text_ msg ]
    ]

  where
  -- Helper function to add items to cart
  addItemToCart
    :: MenuItem
    -> Number
    -> Array TransactionItem
    -> (Array TransactionItem -> Effect Unit)
    -> (CartTotals -> Effect Unit)
    -> (String -> Effect Unit)
    -> Effect Unit
  addItemToCart
    menuItem@(MenuItem record)
    qty
    currentItems
    setItems
    setTotals
    setStatusMessage = do
    if qty <= 0.0 then
      setStatusMessage "Quantity must be greater than 0"
    else do
      -- Calculate how many of this item are already in the cart
      let
        currentQtyInCart =
          case
            find (\(TransactionItem item) -> item.transactionItemMenuItemSku == record.sku)
              currentItems
            of
            Just (TransactionItem item) -> item.transactionItemQuantity
            Nothing -> 0.0

        -- Calculate the total requested quantity (existing cart items + new request)
        totalRequestedQty = currentQtyInCart + qty

      -- Check if the total requested quantity exceeds available inventory
      if totalRequestedQty > toNumber record.quantity then
        setStatusMessage $ "Cannot add " <> show qty <> " more items. Only "
          <> show (record.quantity - floor currentQtyInCart)
          <>
            " more available."
      else
        addItemToTransaction menuItem qty currentItems \newItems -> do
          let newTotals = calculateCartTotals newItems
          setTotals newTotals
          setItems newItems
          liftEffect $ Console.log $ "Added item to cart: " <> record.name
          setStatusMessage "Item added to cart"

  -- Helper function to remove items from cart
  removeItemFromCart
    :: UUID
    -> Array TransactionItem
    -> (Array TransactionItem -> Effect Unit)
    -> (CartTotals -> Effect Unit)
    -> Effect Unit
  removeItemFromCart itemId currentItems setItems setTotals = do
    removeItemFromTransaction itemId currentItems \newItems -> do
      let newTotals = calculateCartTotals newItems
      setTotals newTotals
      setItems newItems
      liftEffect $ Console.log $ "Removed item with ID: " <> show itemId