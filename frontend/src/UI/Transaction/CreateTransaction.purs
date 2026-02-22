module UI.Transaction.CreateTransaction where

import Prelude

import Data.Array (filter, find, null, (:))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete', toDiscrete)
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Number as Number
import Data.String (Pattern(..), contains, toLower, trim)
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut, text)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners (runOn)
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, useState, (<#~>))
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import FRP.Poll (Poll)
import Services.AuthService (AuthContext)
import Services.TransactionService (getRemainingBalance, paymentsCoversTotal)
import Services.TransactionService as TransactionService
import Types.Inventory (Inventory(..), MenuItem(..), findItemNameBySku)
import Types.Register (Register)
import Types.Transaction (PaymentMethod(..), PaymentTransaction(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (UUID(..))
import Services.RegisterService (addItemToCart, emptyCartTotals, formatDiscretePrice, removeItemFromCart)
import Utils.Formatting (formatCentsToDollars)
import Web.Event.Event (target)
import Web.Event.Event as Event
import Web.HTML.HTMLInputElement as Input
import Web.PointerEvent.PointerEvent as PointerEvent

createTransaction :: Ref AuthContext -> Poll Inventory -> Poll Transaction -> Register -> Nut
createTransaction authRef inventoryPoll transactionPoll register = Deku.do
  -- Debug hook for inventory
  setDebugInfo /\ debugInfoValue <- useState ""
  
  -- Regular component state
  setCartItems /\ cartItemsValue <- useHot []
  setCartTotals /\ cartTotalsValue <- useHot emptyCartTotals
  setPayments /\ paymentsValue <- useState []
  setSearchText /\ searchTextValue <- useState ""
  setActiveCategory /\ activeCategoryValue <- useState "All Items"
  setQuantity /\ quantityValue <- useState 1
  setStatusMessage /\ statusMessageValue <- useState ""
  setIsProcessing /\ isProcessingValue <- useState false
  setPaymentMethod /\ paymentMethodValue <- useState Cash
  setPaymentAmount /\ paymentAmountValue <- useState ""
  setTenderedAmount /\ tenderedAmountValue <- useState ""
  setPaymentReference /\ paymentReferenceValue <- useState ""
  setAuthorizationCode /\ authorizationCodeValue <- useState ""
  setTransactionStatus /\ transactionStatusValue <- useState "CREATED"
  setInventoryErrors /\ inventoryErrorsValue <- useState []
  setCheckingInventory /\ checkingInventoryValue <- useState false

  -- Transaction handler
  let
    _ = transactionPoll <#> \(Transaction txData) -> do
      Console.log $ "Transaction received with ID: " <> show
        txData.transactionId
      setTransactionStatus (show txData.transactionStatus)
      setStatusMessage "Transaction ready"

      unless (null txData.transactionItems) do
        setCartItems txData.transactionItems
        setPayments txData.transactionPayments

        let
          subtotal = toDiscrete txData.transactionSubtotal
          taxTotal = toDiscrete txData.transactionTaxTotal
          total = toDiscrete txData.transactionTotal
          discountTotal = toDiscrete txData.transactionDiscountTotal

        setCartTotals
          { subtotal
          , taxTotal
          , total
          , discountTotal
          }

  D.div
    [ DA.klass_ "transaction-container"
    , DL.load_ \_ -> do
        liftEffect $ Console.log "CreateTransaction component loading with initialized transaction"
        liftEffect $ setDebugInfo "Waiting for inventory data..."
    ]
    [
      -- Debug Info Panel (NEW)
      D.div
        [ DA.klass_ "debug-panel"
        , DA.style_ "background: #f0f8ff; border: 2px solid blue; padding: 10px; margin: 10px; color: black;"
        ]
        [ D.h3 [ DA.style_ "margin: 0; color: blue;" ] [ text_ "Debug Information" ]
        , D.div_ [ text debugInfoValue ]
        , D.button
            [ DA.klass_ "debug-button"
            , DA.style_ "background: #0066cc; color: white; padding: 5px 10px; margin-top: 10px; border: none; cursor: pointer;"
            , DL.click_ \_ -> do
                let debugInfo = "Manual inventory check triggered"
                setDebugInfo debugInfo
                liftEffect $ Console.log debugInfo
                -- Force a state update to trigger re-render
                setActiveCategory "All Items"
            ]
            [ text_ "Force Refresh" ]
        ]
      
      -- Register status
      , D.div [ DA.klass_ "register-status active" ]
        [ D.div [ DA.klass_ "register-info" ]
            [ text_
                ( "Register: " <> register.registerName <> " (#"
                    <> show (register.registerId :: UUID)
                    <> ")"
                )
            ]
        , D.div
            [ DA.klass_ "transaction-status" ]
            [ D.span [ DA.klass_ "status-label" ]
                [ text_ "Transaction Status: " ]
            , D.span
                [ DA.klass $ transactionStatusValue <#> \status ->
                    "status-value " <> case status of
                      "Completed" -> "completed"
                      "CREATED" -> "created"
                      "In Progress" -> "in-progress"
                      _ -> ""
                ]
                [ text transactionStatusValue ]
            ]
        ]
      
      -- Debug info for inventory
      , D.div
          [ DA.klass_ "debug-info"
          , DA.style_
              "color: red; border: 1px solid red; padding: 5px; margin: 5px; background-color: #fff;"
          ]
          [ inventoryPoll <#~> \(Inventory items) ->
              D.div_
                [ D.div_ [ text_ ("Debug: Inventory has " <> show (Array.length items) <> " items") ]
                , if (Array.length items > 0) 
                    then D.div_ [ text_ "First few items: " ]
                    else D.div_ []
                , D.ul_ (Array.take 3 items <#> \(MenuItem item) ->
                    D.li_ [ text_ (item.name <> " - " <> show item.category <> " - Qty: " <> show item.quantity) ]
                  )
                ]
          ]
      
      , D.div
          [ DA.klass_ "transaction-content" ]
          [ D.div
              [ DA.klass_ "inventory-selection" ]
              [ D.div [ DA.klass_ "inventory-header" ]
                  [ D.h3_ [ text_ "Select Items" ] ]
              , inventoryPoll <#~> \(Inventory items) ->
                  let
                    categories = [ "All Items" ] <>
                      ( map (\(MenuItem i) -> show i.category) items
                          # map trim
                          # Array.nub
                          # Array.sort
                      )
                  in
                    D.div
                      [ DA.klass_ "category-tabs"
                      , DA.style_ "border: 1px solid green; padding: 5px; margin: 5px;" -- Highlight the categories
                      ]
                      ( categories <#> \cat ->
                          D.div
                            [ DA.klass $ activeCategoryValue <#> \active ->
                                "category-tab" <>
                                  if active == cat then " active" else ""
                            , DL.click_ \_ -> do
                                setActiveCategory cat
                                liftEffect $ Console.log $ "Category selected: " <> cat
                            ]
                            [ text_ cat ]
                      )
              , D.div
                  [ DA.klass_ "inventory-controls" ]
                  [ D.div
                      [ DA.klass_ "search-control" ]
                      [ D.input
                          [ DA.klass_ "search-input"
                          , DA.placeholder_ "Search inventory..."
                          , DA.value_ ""
                          , DL.input_ \evt -> do
                              for_ (target evt >>= Input.fromEventTarget) \el ->
                                do
                                  value <- Input.value el
                                  setSearchText value
                                  liftEffect $ Console.log $ "Search text: " <> value
                          ]
                          []
                      ]
                  , D.div
                      [ DA.klass_ "quantity-control" ]
                      [ D.div [ DA.klass_ "qty-label" ] [ text_ "Quantity:" ]
                      , D.input
                          [ DA.klass_ "qty-input"
                          , DA.xtype_ "number"
                          , DA.min_ "1"
                          , DA.step_ "1"
                          , DA.value_ "1"
                          , DL.input_ \evt -> do
                              for_ (target evt >>= Input.fromEventTarget) \el ->
                                do
                                  val <- Input.value el
                                  case Number.fromString val of
                                    Just num ->
                                      if num > 0.0 then setQuantity (Int.floor num)
                                      else pure unit
                                    Nothing -> pure unit
                          ]
                          []
                      ]
                  ]
              , D.div
                  [ DA.klass_ "inventory-items" ]
                  [ (Tuple <$> inventoryPoll <*> transactionPoll) <#~>
                      \(Tuple inventory transaction) ->
                        searchTextValue <#~> \searchText ->
                          activeCategoryValue <#~> \activeCategory ->
                            checkingInventoryValue <#~> \isChecking ->
                              let
                                Inventory allItems = inventory

                                -- Debug info (stored but not logged)
                                debugFilterInfo = "Filtering: Category=" <> activeCategory <>
                                  ", Items=" <> show (Array.length allItems) <>
                                  ", SearchText='" <> searchText <> "'"

                                categoryFiltered =
                                  if activeCategory == "All Items" then allItems
                                  else filter
                                    ( \(MenuItem i) -> show i.category ==
                                        activeCategory
                                    )
                                    allItems

                                filteredItems =
                                  if searchText == "" then categoryFiltered
                                  else filter
                                    ( \(MenuItem item) ->
                                        contains (Pattern (toLower searchText))
                                          (toLower item.name)
                                    )
                                    categoryFiltered

                                -- Debug info (stored but not logged)
                                debugFilterResults = "Filtered down to " <>
                                  show (Array.length categoryFiltered) <> " items by category, " <>
                                  show (Array.length filteredItems) <> " items after search"

                                isItemSelectDisabled = isChecking
                              in
                                D.div_
                                  [
                                    -- Display the debug info in the UI instead of console
                                    D.div
                                      [ DA.style_ "background: #ffeecc; padding: 5px; margin-bottom: 5px; border-radius: 5px;" ]
                                      [ text_ $ "Category filter: " <> show (Array.length categoryFiltered) <>
                                                " items | Final filtered: " <> show (Array.length filteredItems) <> " items" ]

                                    , if null filteredItems then
                                        D.div [ DA.klass_ "empty-result"
                                              , DA.style_ "background: #ffdddd; padding: 20px; text-align: center;" ]
                                          [ text_ "No items found" ]
                                    else
                                      D.div
                                        [ DA.klass_ "inventory-table"
                                        , DA.style_ "border: 2px solid green;"
                                        ]
                                        [ D.div
                                            [ DA.klass_ "inventory-table-header" ]
                                            [ D.div [ DA.klass_ "col name-col" ]
                                                [ text_ "Name" ]
                                            , D.div [ DA.klass_ "col brand-col" ]
                                                [ text_ "Brand" ]
                                            , D.div [ DA.klass_ "col category-col" ]
                                                [ text_ "Category" ]
                                            , D.div [ DA.klass_ "col price-col" ]
                                                [ text_ "Price" ]
                                            , D.div [ DA.klass_ "col stock-col" ]
                                                [ text_ "In Stock" ]
                                            , D.div [ DA.klass_ "col actions-col" ]
                                                [ text_ "Actions" ]
                                            ]
                                        , D.div
                                            [ DA.klass_ "inventory-table-body"
                                            , DA.style_ "min-height: 100px; background-color: #f9f9f9;"
                                            ]
                                            ( filteredItems <#>
                                                \menuItem@(MenuItem record) ->
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
  
                                                        existingItem = find
                                                          ( \(TransactionItem item) ->
                                                              item.transactionItemMenuItemSku ==
                                                                record.sku
                                                          )
                                                          cartItems
  
                                                        currentQty =
                                                          case existingItem of
                                                            Just (TransactionItem item) ->
                                                              item.transactionItemQuantity
                                                            Nothing -> 0
                                                      in
                                                        D.div
                                                          [ DA.klass_
                                                              ( "inventory-row " <>
                                                                  if
                                                                    record.quantity <=
                                                                      0 then
                                                                    "out-of-stock"
                                                                  else ""
                                                              )
                                                          , DA.style_ "border-bottom: 1px solid #ddd; padding: 8px 0;" -- Make rows more visible
                                                          ]
                                                          [ D.div
                                                              [ DA.klass_
                                                                  "col name-col"
                                                              ]
                                                              [ text_ record.name ]
                                                          , D.div
                                                              [ DA.klass_
                                                                  "col brand-col"
                                                              ]
                                                              [ text_ record.brand ]
                                                          , D.div
                                                              [ DA.klass_
                                                                  "col category-col"
                                                              ]
                                                              [ text_
                                                                  ( show
                                                                      record.category
                                                                      <> " - "
                                                                      <>
                                                                        record.subcategory
                                                                  )
                                                              ]
                                                          , D.div
                                                              [ DA.klass_
                                                                  "col price-col"
                                                              ]
                                                              [ text_ formattedPrice ]
                                                          , D.div
                                                              [ DA.klass_
                                                                  ( "col stock-col "
                                                                      <> stockClass
                                                                  )
                                                              ]
                                                              [ text_
                                                                  ( show
                                                                      record.quantity
                                                                  )
                                                              ]
                                                          , D.div
                                                              [ DA.klass_
                                                                  "col actions-col"
                                                              ]
                                                              [ if
                                                                  record.quantity <= 0
                                                                    ||
                                                                      isItemSelectDisabled then
                                                                  D.button
                                                                    [ DA.klass_
                                                                        "add-btn disabled"
                                                                    , DA.disabled_
                                                                        "true"
                                                                    ]
                                                                    [ text_
                                                                        if
                                                                          record.quantity
                                                                            <= 0 then
                                                                          "Out of Stock"
                                                                        else
                                                                          "Processing..."
                                                                    ]
                                                                else
                                                                  D.div
                                                                    [ DA.klass_
                                                                        "quantity-controls"
                                                                    ]
                                                                    [ if
                                                                        currentQty > 0 then
                                                                        D.div
                                                                          [ DA.klass_
                                                                              "quantity-indicator"
                                                                          ]
                                                                          [ text_
                                                                              ( show
                                                                                  currentQty
                                                                              )
                                                                          ]
                                                                      else D.span_ []
                                                                    , D.button
                                                                        [ DA.klass_
                                                                            "add-btn"
                                                                        , DL.click_
                                                                            \evt -> do
                                                                              Event.stopPropagation
                                                                                ( PointerEvent.toEvent
                                                                                    evt
                                                                                )
                                                                              let
                                                                                transactionId =
                                                                                  ( unwrap
                                                                                      transaction
                                                                                  ).transactionId
                                                                              addItemToCart
                                                                                authRef
                                                                                menuItem
                                                                                qtyVal
                                                                                cartItems
                                                                                transactionId
                                                                                setCartItems
                                                                                setCartTotals
                                                                                setStatusMessage
                                                                                setCheckingInventory
                                                                        ]
                                                                        [ text_ "Add"
                                                                        ]
                                                                    ]
                                                              ]
                                                          ]
                                            )
                                        ]
                                  ]
                  ]
              ]
          , D.div
              [ DA.klass_ "cart-container" ]
              [ D.div [ DA.klass_ "cart-header" ]
                  [ D.h3_ [ text_ "Current Transaction" ] ]
              , inventoryErrorsValue <#~> \errors ->
                  if null errors then D.div_ []
                  else
                    D.div [ DA.klass_ "inventory-errors-container" ]
                      [ D.div [ DA.klass_ "inventory-errors-header" ]
                          [ text_ "Inventory Issues:" ]
                      , D.ul [ DA.klass_ "inventory-errors-list" ]
                          ( errors <#> \err -> D.li
                              [ DA.klass_ "inventory-error" ]
                              [ text_ err ]
                          )
                      ]
              , D.div
                  [ DA.klass_ "cart-items" ]
                  [ ( Tuple <$> (Tuple <$> cartItemsValue <*> inventoryPoll) <*>
                        transactionPoll
                    ) <#~>
                      \(Tuple (Tuple cartItems inventory) _) ->
                        if null cartItems then
                          D.div [ DA.klass_ "empty-cart" ]
                            [ text_ "No items selected" ]
                        else
                          D.div
                            [ DA.klass_ "cart-items-list" ]
                            [ D.div
                                [ DA.klass_ "cart-item-header" ]
                                [ D.div [ DA.klass_ "col item-col" ]
                                    [ text_ "Item" ]
                                , D.div [ DA.klass_ "col qty-col" ]
                                    [ text_ "Qty" ]
                                , D.div [ DA.klass_ "col price-col" ]
                                    [ text_ "Price" ]
                                , D.div [ DA.klass_ "col total-col" ]
                                    [ text_ "Total" ]
                                , D.div [ DA.klass_ "col actions-col" ]
                                    [ text_ "" ]
                                ]
                            , D.div
                                [ DA.klass_ "cart-items-body" ]
                                ( cartItems <#> \(TransactionItem itemData) ->
                                    let
                                      itemName = findItemNameBySku
                                        itemData.transactionItemMenuItemSku
                                        inventory
                                    in
                                      D.div [ DA.klass_ "cart-item-row" ]
                                        [ D.div [ DA.klass_ "col item-col" ]
                                            [ text_ itemName ]
                                        , D.div [ DA.klass_ "col qty-col" ]
                                            [ text_ (show itemData.transactionItemQuantity) ]
                                        , D.div [ DA.klass_ "col price-col" ]
                                            [ text_ (formatDiscretePrice (toDiscrete itemData.transactionItemPricePerUnit)) ]
                                        , D.div [ DA.klass_ "col total-col" ]
                                            [ text_ (formatDiscretePrice (toDiscrete itemData.transactionItemTotal)) ]
                                        , D.div [ DA.klass_ "col actions-col" ]
                                            [ D.button
                                                [ DA.klass_ "remove-btn"
                                                , DL.click_ \_ -> do
                                                    removeItemFromCart
                                                      authRef
                                                      itemData.transactionItemId
                                                      cartItems
                                                      setCartItems
                                                      setCartTotals
                                                      setCheckingInventory
                                                ]
                                                [ text_ "✕" ]
                                            ]
                                        ]
                                )
                            ]
                  ]
              , D.div
                  [ DA.klass_ "cart-totals" ]
                  [ D.div [ DA.klass_ "total-row" ]
                      [ D.div [ DA.klass_ "total-label" ] [ text_ "Subtotal:" ]
                      , D.div [ DA.klass_ "total-value" ]
                          [ cartTotalsValue <#~> \totals -> text_
                              (formatDiscretePrice totals.subtotal)
                          ]
                      ]
                  , D.div [ DA.klass_ "total-row" ]
                      [ D.div [ DA.klass_ "total-label" ] [ text_ "Tax:" ]
                      , D.div [ DA.klass_ "total-value" ]
                          [ cartTotalsValue <#~> \totals -> text_
                              (formatDiscretePrice totals.taxTotal)
                          ]
                      ]
                  , D.div [ DA.klass_ "total-row grand-total" ]
                      [ D.div [ DA.klass_ "total-label" ] [ text_ "Total:" ]
                      , D.div [ DA.klass_ "total-value" ]
                          [ cartTotalsValue <#~> \totals -> text_
                              (formatDiscretePrice totals.total)
                          ]
                      ]
                  ]
              , D.div
                  [ DA.klass_ "payment-section" ]
                  [ D.div [ DA.klass_ "payment-header" ]
                      [ text_ "Payment Options" ]
                  , D.div
                      [ DA.klass_ "payment-methods" ]
                      [ D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if method == Cash then " active" else ""
                          , DL.click_ \_ -> setPaymentMethod Cash
                          ]
                          [ text_ "Cash" ]
                      , D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if method == Credit then " active" else ""
                          , DL.click_ \_ -> setPaymentMethod Credit
                          ]
                          [ text_ "Credit" ]
                      , D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if method == Debit then " active" else ""
                          , DL.click_ \_ -> setPaymentMethod Debit
                          ]
                          [ text_ "Debit" ]
                      , D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if method == ACH then " active" else ""
                          , DL.click_ \_ -> setPaymentMethod ACH
                          ]
                          [ text_ "ACH" ]
                      , D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if method == GiftCard then " active" else ""
                          , DL.click_ \_ -> setPaymentMethod GiftCard
                          ]
                          [ text_ "Gift Card" ]
                      , D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if method == StoredValue then " active" else ""
                          , DL.click_ \_ -> setPaymentMethod StoredValue
                          ]
                          [ text_ "Stored Value" ]
                      , D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if method == Mixed then " active" else ""
                          , DL.click_ \_ -> setPaymentMethod Mixed
                          ]
                          [ text_ "Split Payment" ]
                      , D.div
                          [ DA.klass $ paymentMethodValue <#> \method ->
                              "payment-method" <>
                                if
                                  case method of
                                    Other _ -> true
                                    _ -> false then " active"
                                else ""
                          , DL.click_ \_ -> setPaymentMethod (Other "")
                          ]
                          [ text_ "Other" ]
                      ]
                  , (Tuple <$> transactionPoll <*> isProcessingValue) <#~>
                      \(Tuple _ isProcessing) ->
                        D.div
                          [ DA.klass_ "payment-inputs" ]
                          [ D.div
                              [ DA.klass_ "payment-input-row" ]
                              [ D.label [ DA.klass_ "payment-label" ]
                                  [ text_ "Amount:" ]
                              , D.input
                                  [ DA.klass_ "payment-field"
                                  , DA.xtype_ "text"
                                  , DA.value paymentAmountValue
                                  , DA.disabled_
                                      (if isProcessing then "true" else "")
                                  , DL.input_ \evt -> do
                                      for_ (target evt >>= Input.fromEventTarget)
                                        \el -> do
                                          value <- Input.value el
                                          setPaymentAmount value
                                  ]
                                  []
                              ]
                          , paymentMethodValue <#~> \method ->
                              if method == Cash then
                                D.div
                                  [ DA.klass_ "payment-input-row" ]
                                  [ D.label [ DA.klass_ "payment-label" ]
                                      [ text_ "Tendered:" ]
                                  , D.input
                                      [ DA.klass_ "payment-field"
                                      , DA.xtype_ "text"
                                      , DA.value tenderedAmountValue
                                      , DA.disabled_
                                          (if isProcessing then "true" else "")
                                      , DL.input_ \evt -> do
                                          for_
                                            (target evt >>= Input.fromEventTarget)
                                            \el -> do
                                              value <- Input.value el
                                              setTenderedAmount value
                                      ]
                                      []
                                  ]
                              else D.div_ []
                          , paymentMethodValue <#~> \method ->
                              case method of
                                Credit -> D.div
                                  [ DA.klass_ "payment-input-row" ]
                                  [ D.label [ DA.klass_ "payment-label" ]
                                      [ text_ "Auth Code:" ]
                                  , D.input
                                      [ DA.klass_ "payment-field"
                                      , DA.xtype_ "text"
                                      , DA.value authorizationCodeValue
                                      , DA.disabled_
                                          (if isProcessing then "true" else "")
                                      , DL.input_ \evt -> do
                                          for_
                                            (target evt >>= Input.fromEventTarget)
                                            \el -> do
                                              value <- Input.value el
                                              setAuthorizationCode value
                                      ]
                                      []
                                  ]
                                _ -> D.div_ []
                          ]
                  , D.button
                      [ DA.klass_ "add-payment-btn"
                      , DA.disabled $ isProcessingValue <#> \isProcessing ->
                          if isProcessing then "true" else ""
                      , runOn DL.click $
                          ( \payAmt
                             tenderedAmt
                             method
                             currPayments
                             payRef
                             authCode
                             transaction -> do
                              case
                                (Tuple (Number.fromString payAmt) transaction)
                                of
                                Tuple (Just amount) txn -> do
                                  let
                                    tenderedAmount =
                                      case Number.fromString tenderedAmt of
                                        Just t -> t
                                        Nothing -> amount
  
                                    amountInCents = Int.floor (amount * 100.0)
                                    tenderedInCents = Int.floor
                                      (tenderedAmount * 100.0)
  
                                  void $ launchAff_ do
                                    result <- TransactionService.addPayment
                                      authRef
                                      (unwrap txn).transactionId
                                      method
                                      amountInCents
                                      tenderedInCents
                                      ( if payRef == "" && authCode == "" then
                                          Nothing
                                        else Just
                                          ( if payRef /= "" then payRef
                                            else authCode
                                          )
                                      )
  
                                    liftEffect $ case result of
                                      Right payment -> do
                                        setPayments (payment : currPayments)
                                        setPaymentAmount ""
                                        setTenderedAmount ""
                                        setPaymentReference ""
                                        setAuthorizationCode ""
                                        setStatusMessage
                                          "Payment added to transaction"
  
                                      Left err ->
                                        setStatusMessage $ "Payment error: " <>
                                          err
  
                                Tuple Nothing _ ->
                                  setStatusMessage "Invalid payment amount"
                          ) <$> paymentAmountValue
                            <*> tenderedAmountValue
                            <*> paymentMethodValue
                            <*> paymentsValue
                            <*> paymentReferenceValue
                            <*> authorizationCodeValue
                            <*> transactionPoll
                      ]
                      [ text_ "Add Payment" ]
                  , D.div
                      [ DA.klass_ "existing-payments" ]
                      [ paymentsValue <#~> \payments ->
                          if null payments then D.div_ []
                          else
                            D.div
                              [ DA.klass_ "payments-container" ]
                              [ D.div [ DA.klass_ "payments-header" ]
                                  [ text_ "Current Payments:" ]
                              , D.div_
                                  ( payments <#> \(PaymentTransaction p) ->
                                      D.div
                                        [ DA.klass_ "payment-item" ]
                                        [ D.div [ DA.klass_ "payment-method" ]
                                            [ text_ (show p.paymentMethod) ]
                                        , D.div [ DA.klass_ "payment-amount" ]
                                            [ text_ (show p.paymentAmount) ]
                                        , D.button
                                            [ DA.klass_ "payment-remove"
                                            , DA.disabled $ isProcessingValue <#>
                                                \isProcessing ->
                                                  if isProcessing then "true"
                                                  else ""
                                            , runOn DL.click $
                                                ( \currPayments -> do
                                                    void $ launchAff_ do
                                                      result <-
                                                        TransactionService.removePaymentTransaction
                                                          authRef
                                                          p.paymentId
                                                      liftEffect $ case result of
                                                        Right _ -> do
                                                          let
                                                            updatedPayments =
                                                              filter
                                                                ( \( PaymentTransaction
                                                                       pay
                                                                   ) -> pay.paymentId /=
                                                                    p.paymentId
                                                                )
                                                                currPayments
                                                          setPayments
                                                            updatedPayments
                                                          setStatusMessage
                                                            "Payment removed"
                                                        Left err ->
                                                          setStatusMessage $
                                                            "Error removing payment: "
                                                              <> err
                                                ) <$> paymentsValue
                                            ]
                                            [ text_ "✕" ]
                                        ]
                                  )
                              ]
                      ]
                  ]
              ]
          ]
      , D.div
          [ DA.klass_ "action-bar" ]
          [ D.button
              [ DA.klass_ "cancel-btn"
              , DA.disabled $ isProcessingValue <#> \p -> if p then "true" else ""
              , runOn DL.click $
                  ( \cartItems transaction -> do
                      if null cartItems then
                        setStatusMessage "No items to clear"
                      else do
                        setIsProcessing true
                        setStatusMessage "Clearing cart..."

                        void $ launchAff_ do
                          result <- TransactionService.clearTransaction
                            authRef
                            (unwrap transaction).transactionId

                          liftEffect $ case result of
                            Right _ -> do
                              setCartItems []
                              setPayments []
                              setCartTotals emptyCartTotals
                              setStatusMessage "Cart cleared"
                            Left err -> do
                              setStatusMessage $ "Error: " <> err

                          liftEffect $ setIsProcessing false
                  ) <$> cartItemsValue <*> transactionPoll
              ]
              [ text_ "Clear Items" ]
          , D.div
              [ DA.klass_ "payment-summary" ]
              [ (Tuple <$> cartTotalsValue <*> paymentsValue) <#~>
                  \(Tuple totals payments) ->
                    let
                      dummyTransaction = Transaction
                        { transactionId: UUID ""
                        , transactionStatus: InProgress
                        , transactionCreated: bottom
                        , transactionCompleted: Nothing
                        , transactionCustomerId: Nothing
                        , transactionEmployeeId: UUID ""
                        , transactionRegisterId: UUID ""
                        , transactionLocationId: UUID ""
                        , transactionItems: []
                        , transactionPayments: []
                        , transactionSubtotal: fromDiscrete' totals.subtotal
                        , transactionDiscountTotal: fromDiscrete' (Discrete 0)
                        , transactionTaxTotal: fromDiscrete' totals.taxTotal
                        , transactionTotal: fromDiscrete' totals.total
                        , transactionType: Sale
                        , transactionIsVoided: false
                        , transactionVoidReason: Nothing
                        , transactionIsRefunded: false
                        , transactionRefundReason: Nothing
                        , transactionReferenceTransactionId: Nothing
                        , transactionNotes: Nothing
                        }
  
                      remaining = getRemainingBalance payments dummyTransaction
                      paidClass =
                        if remaining <= Discrete 0 then "paid" else "unpaid"
                    in
                      D.div
                        [ DA.klass_ "remaining-balance" ]
                        [ D.div [ DA.klass_ "remaining-label" ]
                            [ text_ "Remaining:" ]
                        , D.div
                            [ DA.klass_ ("remaining-amount " <> paidClass) ]
                            [ text_
                                (formatDiscretePrice (max (Discrete 0) remaining))
                            ]
                        ]
              ]
          , D.button
              [ DA.klass_ "checkout-btn"
              , DA.disabled $ (Tuple <$> transactionPoll <*> isProcessingValue)
                  <#>
                    \(Tuple _ isProcessing) -> if isProcessing then "true" else ""
              , runOn DL.click $
                  ( \cartItems currPayments totals transaction -> do
                      if null cartItems then do
                        setStatusMessage
                          "Cannot complete: No items in transaction"
                      else do
                        let
                          dummyTransaction = Transaction
                            { transactionId: UUID ""
                            , transactionStatus: InProgress
                            , transactionCreated: bottom
                            , transactionCompleted: Nothing
                            , transactionCustomerId: Nothing
                            , transactionEmployeeId: UUID ""
                            , transactionRegisterId: UUID ""
                            , transactionLocationId: UUID ""
                            , transactionItems: []
                            , transactionPayments: []
                            , transactionSubtotal: fromDiscrete' (totals.subtotal)
                            , transactionDiscountTotal: fromDiscrete' (Discrete 0)
                            , transactionTaxTotal: fromDiscrete' (totals.taxTotal)
                            , transactionTotal: fromDiscrete' (totals.total)
                            , transactionType: Sale
                            , transactionIsVoided: false
                            , transactionVoidReason: Nothing
                            , transactionIsRefunded: false
                            , transactionRefundReason: Nothing
                            , transactionReferenceTransactionId: Nothing
                            , transactionNotes: Nothing
                            }
  
                        let
                          paymentCoversTotal = paymentsCoversTotal currPayments
                            dummyTransaction
  
                        if not paymentCoversTotal then do
                          setStatusMessage
                            "Cannot complete: Payment amount is insufficient"
                        else do
                          setIsProcessing true
                          setStatusMessage "Finalizing transaction..."
  
                          void $ launchAff_ do
                            result <- TransactionService.finalizeTransaction
                              authRef
                              (unwrap transaction).transactionId
                            liftEffect $ case result of
                              Right _ -> do
                                setCartItems []
                                setPayments []
                                setCartTotals emptyCartTotals
                                setTransactionStatus "Completed"
                                setInventoryErrors []
                                setStatusMessage
                                  "Transaction completed successfully"
                              Left err -> do
                                setStatusMessage $
                                  "Error finalizing transaction: " <> err
                            liftEffect $ setIsProcessing false
                  ) <$> cartItemsValue <*> paymentsValue <*> cartTotalsValue <*>
                    transactionPoll
              ]
              [ cartTotalsValue <#~> \totals ->
                  text_ ("Process Payment " <> formatDiscretePrice totals.total)
              ]
          ]
      , statusMessageValue <#~> \msg ->
          if msg == "" then D.div_ []
          else D.div [ DA.klass_ "status-message" ] [ text_ msg ]
      ]