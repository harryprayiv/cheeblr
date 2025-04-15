module UI.Transaction.CreateTransaction where

import Prelude

import Data.Array (filter, find, null, (:))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete')
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..), isNothing)
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
import Effect.Aff (launchAff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import Services.CashRegister (dummyEmployeeId, dummyLocationId, dummyRegisterId, dummyTransactionId)
import Services.RegisterService as RegisterService
import Services.TransactionService (startTransaction)
import Services.TransactionService as TransactionService
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Transaction (PaymentMethod(..), PaymentTransaction(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (parseUUID)
import Utils.CartUtils (addItemToCart, emptyCartTotals, formatDiscretePrice, formatPrice, removeItemFromCart)
import Utils.Formatting (findItemNameBySku, formatCentsToDollars)
import Utils.Storage (storeItem)
import Utils.TransactionUtils (calculateTotalPayments, paymentsCoversTotal, getRemainingBalance)
import Utils.UUIDGen (genUUID)
import Web.Event.Event (target)
import Web.Event.Event as Event
import Web.HTML (window)
import Web.HTML.HTMLInputElement as Input
import Web.HTML.Window (localStorage)
import Web.PointerEvent.PointerEvent as PointerEvent
import Web.Storage.Storage as Storage

createTransaction :: Poll Inventory -> Nut
createTransaction inventoryPoll = Deku.do

  setCartItems /\ cartItemsValue <- useHot []
  setCartTotals /\ cartTotalsValue <- useHot emptyCartTotals

  setEmployee /\ employeeValue <- useState ""
  setLocationId /\ locationIdValue <- useState ""

  setPaymentMethod /\ paymentMethodValue <- useState Cash
  setPaymentAmount /\ paymentAmountValue <- useState ""
  setTenderedAmount /\ tenderedAmountValue <- useState ""
  setPayments /\ paymentsValue <- useState []

  setSearchText /\ searchTextValue <- useState ""
  setActiveCategory /\ activeCategoryValue <- useState "All Items"
  setQuantity /\ quantityValue <- useState 1.0
  setStatusMessage /\ statusMessageValue <- useState ""
  setIsProcessing /\ isProcessingValue <- useState false

  setPaymentReference /\ paymentReferenceValue <- useState ""
  setAuthorizationCode /\ authorizationCodeValue <- useState ""
  setOtherPaymentType /\ otherPaymentTypeValue <- useState ""

  setRegister /\ registerValue <- useState Nothing
  setActiveTransaction /\ activeTransactionValue <- useState Nothing
  setTransactionStatus /\ transactionStatusValue <- useState "Not Started"
  setInventoryErrors /\ inventoryErrorsValue <- useState []
  setCheckingInventory /\ checkingInventoryValue <- useState false

  -- new state for tracking inventory operations
  setCheckingInventory /\ checkingInventoryValue <- useState false
  setInventoryErrors /\ inventoryErrorsValue <- useState []
  setTransactionStatus /\ transactionStatusValue <- useState "Not Started"

  D.div
    [ DA.klass_ "transaction-container"
    , DL.load_ \_ -> do
        liftEffect $ Console.log "Transaction component loading"

        -- Initialize register
        RegisterService.initializeRegister
          ( \register -> do
              setRegister (Just register)
              setStatusMessage
                ("Register #" <> show register.registerId <> " ready")
          )
          (\err -> setStatusMessage ("Register error: " <> err))

        -- Set up employee ID and location ID
        void $ launchAff do
          employeeId <- liftEffect genUUID
          locationId <- liftEffect genUUID

          liftEffect do
            setEmployee (show employeeId)
            setLocationId (show locationId)

        liftEffect $ Console.log
          "Using global inventory state in CreateTransaction"
    ]
    [
      -- Register status section
      registerValue <#~> \maybeRegister ->
        case maybeRegister of
          Nothing ->
            D.div [ DA.klass_ "register-status error" ]
              [ text_ "No active register. Please refresh to initialize." ]
          Just register ->
            D.div [ DA.klass_ "register-status active" ]
              [ D.div [ DA.klass_ "register-info" ]
                  [ text_
                      ( "Register: " <> register.registerName <> " (#"
                          <> show register.registerId
                          <> ")"
                      )
                  ]
              ,
                -- Transaction status display
                D.div
                  [ DA.klass_ "transaction-status" ]
                  [ D.span [ DA.klass_ "status-label" ]
                      [ text_ "Transaction Status: " ]
                  , D.span
                      [ DA.klass $ transactionStatusValue <#> \status ->
                          "status-value " <> case status of
                            "Completed" -> "completed"
                            "Created" -> "created"
                            "In Progress" -> "in-progress"
                            _ -> ""
                      ]
                      [ text transactionStatusValue ]
                  ,
                    -- Start transaction button
                    D.button
                      [ DA.klass_ "start-transaction-btn"
                      , DA.disabled $ registerValue <#> \maybeReg ->
                          if isNothing maybeReg then "true" else ""
                      , runOn DL.click $
                          ( \regVal empVal locVal -> do
                              void $ launchAff do
                                case Tuple regVal (parseUUID empVal) of
                                  Tuple (Just reg) (Just empId) -> do
                                    result <- startTransaction
                                      { employeeId: empId
                                      , registerId: reg.registerId
                                      , locationId: case parseUUID locVal of
                                          Just locId -> locId
                                          Nothing -> reg.registerLocationId
                                      }

                                    liftEffect $ case result of
                                      Right transaction -> do
                                        setActiveTransaction (Just transaction)
                                        setTransactionStatus "Created"
                                        setStatusMessage
                                          "New transaction started"

                                        -- Properly handle localStorage access
                                        let transId = unwrap transaction
                                        w <- window
                                        storage <- localStorage w
                                        Storage.setItem "activeTransactionId"
                                          (show transId.id)
                                          storage

                                      Left err ->
                                        setStatusMessage
                                          ( "Error starting transaction: " <>
                                              err
                                          )
                                  _ ->
                                    liftEffect $ setStatusMessage
                                      "Invalid employee or register ID"
                          ) <$> registerValue <*> employeeValue <*>
                            locationIdValue
                      ]
                      [ text_ "Start New Transaction" ]
                  ]
              ]
    , D.div
        [ DA.klass_ "transaction-content" ]
        [
          -- Inventory selection section
          D.div
            [ DA.klass_ "inventory-selection" ]
            [ D.div
                [ DA.klass_ "inventory-header" ]
                [ D.h3_ [ text_ "Select Items" ] ]
            ,
              -- Category tabs
              inventoryPoll <#~> \(Inventory items) ->
                let
                  categories = [ "All Items" ] <>
                    ( map (\(MenuItem i) -> show i.category) items # map trim
                        # Array.nub
                        # Array.sort
                    )
                in
                  D.div
                    [ DA.klass_ "category-tabs" ]
                    ( categories <#> \cat ->
                        D.div
                          [ DA.klass $ activeCategoryValue <#> \active ->
                              "category-tab" <>
                                if active == cat then " active" else ""
                          , DL.click_ \_ -> setActiveCategory cat
                          ]
                          [ text_ cat ]
                    )
            ,
              -- Search and quantity controls
              D.div
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
                        ]
                        []
                    ]
                , D.div
                    [ DA.klass_ "quantity-control" ]
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
                            for_ (target evt >>= Input.fromEventTarget) \el ->
                              do
                                val <- Input.value el
                                case Number.fromString val of
                                  Just num ->
                                    if num > 0.0 then setQuantity num
                                    else pure unit
                                  Nothing -> pure unit
                        ]
                        []
                    ]
                ]
            ,
              -- Inventory items list
              D.div
                [ DA.klass_ "inventory-items" ]
                [ (Tuple <$> inventoryPoll <*> activeTransactionValue) <#~>
                    \(Tuple (Inventory allItems) maybeTx) ->
                      searchTextValue <#~> \searchText ->
                        activeCategoryValue <#~> \activeCategory ->
                          checkingInventoryValue <#~> \isChecking ->
                            let
                              -- Filter items by category
                              categoryFiltered =
                                if activeCategory == "All Items" then allItems
                                else filter
                                  ( \(MenuItem i) -> show i.category ==
                                      activeCategory
                                  )
                                  allItems

                              -- Filter items by search text
                              filteredItems =
                                if searchText == "" then categoryFiltered
                                else filter
                                  ( \(MenuItem item) ->
                                      contains (Pattern (toLower searchText))
                                        (toLower item.name)
                                  )
                                  categoryFiltered

                              isItemSelectDisabled = isNothing maybeTx ||
                                isChecking
                            in
                              if null filteredItems then
                                D.div [ DA.klass_ "empty-result" ]
                                  [ text_ "No items found" ]
                              else
                                D.div
                                  [ DA.klass_ "inventory-table" ]
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
                                      [ DA.klass_ "inventory-table-body" ]
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

                                                  -- Check if item is already in cart
                                                  existingItem = find
                                                    ( \(TransactionItem item) ->
                                                        item.menuItemSku ==
                                                          record.sku
                                                    )
                                                    cartItems

                                                  currentQty =
                                                    case existingItem of
                                                      Just
                                                        (TransactionItem item) ->
                                                        item.quantity
                                                      Nothing -> 0.0
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
                                                                  else if
                                                                    isNothing
                                                                      maybeTx then
                                                                    "Start Transaction First"
                                                                  else
                                                                    "Processing..."
                                                              ]
                                                          else
                                                            D.div
                                                              [ DA.klass_
                                                                  "quantity-controls"
                                                              ]
                                                              [ if
                                                                  currentQty >
                                                                    0.0 then
                                                                  D.div
                                                                    [ DA.klass_
                                                                        "quantity-indicator"
                                                                    ]
                                                                    [ text_
                                                                        ( show
                                                                            currentQty
                                                                        )
                                                                    ]
                                                                else
                                                                  D.span_ []
                                                              , D.button
                                                                  [ DA.klass_
                                                                      "add-btn"
                                                                  , DL.click_
                                                                      \evt -> do
                                                                        Event.stopPropagation
                                                                          ( PointerEvent.toEvent
                                                                              evt
                                                                          )

                                                                        -- Add item to transaction
                                                                        case
                                                                          maybeTx
                                                                          of
                                                                          Nothing ->
                                                                            setStatusMessage
                                                                              "Start a transaction first"
                                                                          Just
                                                                            transaction ->
                                                                            do
                                                                              let
                                                                                transactionId =
                                                                                  ( unwrap
                                                                                      transaction
                                                                                  ).id
                                                                              -- Add item to cart using the backend's reservation system
                                                                              addItemToCart
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
        ,
          -- Cart/transaction details section
          D.div
            [ DA.klass_ "cart-container" ]
            [ D.div
                [ DA.klass_ "cart-header" ]
                [ D.h3_ [ text_ "Current Transaction" ] ]
            ,
              -- Inventory error messages
              inventoryErrorsValue <#~> \errors ->
                if null errors then
                  D.div_ []
                else
                  D.div
                    [ DA.klass_ "inventory-errors-container" ]
                    [ D.div [ DA.klass_ "inventory-errors-header" ]
                        [ text_ "Inventory Issues:" ]
                    , D.ul [ DA.klass_ "inventory-errors-list" ]
                        ( errors <#> \err ->
                            D.li [ DA.klass_ "inventory-error" ]
                              [ text_ err ]
                        )
                    ]
            ,
              -- Cart items list
              D.div
                [ DA.klass_ "cart-items" ]
                [ ( Tuple <$> (Tuple <$> cartItemsValue <*> inventoryPoll) <*>
                      activeTransactionValue
                  ) <#~>
                    \(Tuple (Tuple cartItems inventory) maybeTx) ->
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
                                      itemData.menuItemSku
                                      inventory
                                  in
                                    D.div
                                      [ DA.klass_ "cart-item-row" ]
                                      [ D.div [ DA.klass_ "col item-col" ]
                                          [ text_ itemName ]
                                      , D.div [ DA.klass_ "col qty-col" ]
                                          [ text_ (show itemData.quantity) ]
                                      , D.div [ DA.klass_ "col price-col" ]
                                          [ text_
                                              ( formatPrice
                                                  itemData.pricePerUnit
                                              )
                                          ]
                                      , D.div [ DA.klass_ "col total-col" ]
                                          [ text_ (formatPrice itemData.total) ]
                                      , D.div [ DA.klass_ "col actions-col" ]
                                          [ D.button
                                              [ DA.klass_ "remove-btn"
                                              , DL.click_ \_ -> do
                                                  -- Remove item from transaction/cart
                                                  case maybeTx of
                                                    Nothing ->
                                                      setStatusMessage
                                                        "Cannot remove: No active transaction"
                                                    Just _ -> do
                                                      removeItemFromCart
                                                        itemData.id
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
            ,
              -- Cart totals
              D.div
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
            ,
              -- Payment section
              D.div
                [ DA.klass_ "payment-section" ]
                [ D.div
                    [ DA.klass_ "payment-header" ]
                    [ text_ "Payment Options" ]
                ,
                  -- Payment method selection
                  D.div
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
                ,
                  -- Payment input fields
                  (Tuple <$> activeTransactionValue <*> isProcessingValue) <#~>
                    \(Tuple maybeTx isProcessing) ->
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
                                    if isNothing maybeTx || isProcessing then
                                      "true"
                                    else ""
                                , DL.input_ \evt -> do
                                    for_ (target evt >>= Input.fromEventTarget)
                                      \el -> do
                                        value <- Input.value el
                                        setPaymentAmount value
                                ]
                                []
                            ]
                        ,
                          -- Show tendered field only for cash payments
                          paymentMethodValue <#~> \method ->
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
                                        if isNothing maybeTx || isProcessing then
                                          "true"
                                        else ""
                                    , DL.input_ \evt -> do
                                        for_
                                          (target evt >>= Input.fromEventTarget)
                                          \el -> do
                                            value <- Input.value el
                                            setTenderedAmount value
                                    ]
                                    []
                                ]
                            else
                              D.div_ []
                        ,
                          -- Show Auth Code field for Credit payments
                          paymentMethodValue <#~> \method ->
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
                                        if isNothing maybeTx || isProcessing then
                                          "true"
                                        else ""
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
                ,
                  -- Add payment button
                  D.button
                    [ DA.klass_ "add-payment-btn"
                    , DA.disabled $ activeTransactionValue <#> \maybeTx ->
                        case maybeTx of
                          Just _ -> ""
                          Nothing -> "true"
                    , runOn DL.click $
                        ( \payAmt
                           tenderedAmt
                           method
                           currPayments
                           payRef
                           authCode
                           maybeTx -> do
                            case (Tuple (Number.fromString payAmt) maybeTx) of
                              Tuple (Just amount) (Just transaction) -> do
                                let
                                  tenderedAmount =
                                    case Number.fromString tenderedAmt of
                                      Just t -> t
                                      Nothing -> amount

                                  amountInCents = Int.floor (amount * 100.0)
                                  tenderedInCents = Int.floor
                                    (tenderedAmount * 100.0)

                                -- Use TransactionService to add payment
                                void $ launchAff do
                                  result <- TransactionService.addPayment
                                    (unwrap transaction).id
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
                                      -- Add new payment to the existing payments
                                      setPayments (payment : currPayments)

                                      -- Reset input fields
                                      setPaymentAmount ""
                                      setTenderedAmount ""
                                      setPaymentReference ""
                                      setAuthorizationCode ""
                                      setOtherPaymentType ""

                                      setStatusMessage
                                        "Payment added to transaction"

                                    Left err ->
                                      setStatusMessage $ "Payment error: " <>
                                        err

                              Tuple (Nothing) _ ->
                                setStatusMessage "Invalid payment amount"

                              Tuple _ Nothing ->
                                setStatusMessage "No active transaction"

                        ) <$> paymentAmountValue <*> tenderedAmountValue
                          <*> paymentMethodValue
                          <*> paymentsValue
                          <*> paymentReferenceValue
                          <*> authorizationCodeValue
                          <*> activeTransactionValue
                    ]
                    [ text_ "Add Payment" ]
                ,
                  -- Display existing payments
                  D.div
                    [ DA.klass_ "existing-payments" ]
                    [ paymentsValue <#~> \payments ->
                        if null payments then
                          D.div_ []
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
                                          [ text_ (show p.method) ]
                                      , D.div [ DA.klass_ "payment-amount" ]
                                          [ text_ (formatPrice p.amount) ]
                                      , D.button
                                          [ DA.klass_ "payment-remove"
                                          , DA.disabled $ activeTransactionValue
                                              <#> \maybeTx ->
                                                if isNothing maybeTx then "true"
                                                else ""
                                          , runOn DL.click $
                                              ( \currPayments maybeTx -> do
                                                  case maybeTx of
                                                    Nothing ->
                                                      setStatusMessage
                                                        "No active transaction"
                                                    Just transaction -> do
                                                      -- Call backend to remove payment
                                                      void $ launchAff do
                                                        result <-
                                                          TransactionService.removePaymentTransaction
                                                            p.id

                                                        liftEffect $
                                                          case result of
                                                            Right _ -> do
                                                              -- Update local state to remove payment
                                                              let
                                                                updatedPayments =
                                                                  filter
                                                                    ( \( PaymentTransaction
                                                                           pay
                                                                       ) ->
                                                                        pay.id
                                                                          /=
                                                                            p.id
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
                                              ) <$> paymentsValue <*>
                                                activeTransactionValue
                                          ]
                                          [ text_ "✕" ]
                                      ]
                                )
                            ]
                    ]
                ]
            ]
        ]
    ,
      -- Action buttons
      D.div
        [ DA.klass_ "action-bar" ]
        [
          -- Cancel transaction button
          D.button
            [ DA.klass_ "cancel-btn"
            , runOn DL.click $
                (\maybeTx -> 
                  case maybeTx of
                    Nothing -> do
                      -- No active transaction to cancel
                      setCartItems []
                      setPayments []
                      setCartTotals emptyCartTotals
                      setStatusMessage "Transaction cleared"
                    Just transaction -> do
                      -- Call backend to void transaction
                      void $ launchAff do
                        result <- TransactionService.voidTransaction
                          (unwrap transaction).id
                          "Cancelled by user"

                        liftEffect $ case result of
                          Right _ -> do
                            -- Reset the UI state
                            setCartItems []
                            setPayments []
                            setCartTotals emptyCartTotals
                            setActiveTransaction Nothing
                            setTransactionStatus "Not Started"
                            setStatusMessage "Transaction cancelled"
                            -- FIXED: Use storeItem instead of setItem
                            storeItem "activeTransactionId" ""

                          Left err ->
                            setStatusMessage $ "Error cancelling transaction: " <>
                              err
                ) <$> activeTransactionValue
            ]
            [ text_ "Cancel Transaction" ]
        ,
          -- Payment summary/remaining balance
          D.div
            [ DA.klass_ "payment-summary" ]
            [ (Tuple <$> cartTotalsValue <*> paymentsValue) <#~>
                \(Tuple totals payments) ->
                  let
                    paymentTotal = calculateTotalPayments payments
                    remaining = getRemainingBalance payments
                      (Transaction {
                        id: dummyTransactionId, -- Use your existing dummy UUID
                        status: InProgress,
                        created: bottom, -- Or current date if needed, but not likely needed for calculation
                        completed: Nothing,
                        customer: Nothing,
                        employee: dummyEmployeeId,
                        register: dummyRegisterId,
                        location: dummyLocationId,
                        items: [],
                        payments: [],
                        subtotal: fromDiscrete' totals.subtotal,
                        discountTotal: fromDiscrete' (Discrete 0),
                        taxTotal: fromDiscrete' totals.taxTotal,
                        total: fromDiscrete' totals.total,
                        transactionType: Sale,
                        isVoided: false,
                        voidReason: Nothing,
                        isRefunded: false,
                        refundReason: Nothing,
                        referenceTransactionId: Nothing,
                        notes: Nothing
                      })
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
        ,
          -- Process payment / finalize transaction button
          D.button
            [ DA.klass_ "checkout-btn"
            , DA.disabled $
                (Tuple <$> activeTransactionValue <*> isProcessingValue) <#>
                  \(Tuple maybeTx isProcessing) ->
                    if isNothing maybeTx || isProcessing then "true" else ""
            , runOn DL.click $
                ( \cartItems currPayments totals maybeTx -> do
                    case maybeTx of
                      Nothing ->
                        setStatusMessage "No active transaction to complete"
                      Just transaction -> do
                        if null cartItems then do
                          setStatusMessage
                            "Cannot complete: No items in transaction"
                        else do
                          -- Check if payment amount is sufficient
                          let
                            -- Complete Transaction object for compatibility with utils
                            transactionObj = Transaction
                              { id: dummyTransactionId,
                                status: InProgress,
                                created: bottom, -- A default value for DateTime
                                completed: Nothing,
                                customer: Nothing,
                                employee: dummyTransactionId,
                                register: dummyTransactionId,
                                location: dummyTransactionId,
                                items: [],
                                payments: [],
                                subtotal: fromDiscrete' totals.subtotal,
                                discountTotal: fromDiscrete' (Discrete 0),
                                taxTotal: fromDiscrete' totals.taxTotal,
                                total: fromDiscrete' totals.total,
                                transactionType: Sale,
                                isVoided: false,
                                voidReason: Nothing,
                                isRefunded: false,
                                refundReason: Nothing,
                                referenceTransactionId: Nothing,
                                notes: Nothing
                              }
                            paymentCoversTotal = paymentsCoversTotal
                              currPayments
                              transactionObj

                          if not paymentCoversTotal then do
                            setStatusMessage
                              "Cannot complete: Payment amount is insufficient"
                          else do
                            setIsProcessing true
                            setStatusMessage "Finalizing transaction..."

                            -- Call backend to finalize transaction
                            void $ launchAff do
                              result <- TransactionService.finalizeTransaction
                                (unwrap transaction).id

                              liftEffect $ case result of
                                Right _ -> do
                                  -- Reset UI state after successful finalization
                                  setCartItems []
                                  setPayments []
                                  setCartTotals emptyCartTotals
                                  setActiveTransaction Nothing
                                  setTransactionStatus "Completed"
                                  setInventoryErrors []
                                  setStatusMessage
                                    "Transaction completed successfully"
                                  storeItem "activeTransactionId" ""

                                Left err -> do
                                  setStatusMessage $
                                    "Error finalizing transaction: " <> err

                              liftEffect $ setIsProcessing false
                ) <$> cartItemsValue <*> paymentsValue <*> cartTotalsValue <*>
                  activeTransactionValue
            ]
            [ cartTotalsValue <#~> \totals ->
                text_ ("Process Payment " <> formatDiscretePrice totals.total)
            ]
        ]
    ,
      -- Status message display
      statusMessageValue <#~> \msg ->
        if msg == "" then
          D.div_ []
        else
          D.div
            [ DA.klass_ "status-message" ]
            [ text_ msg ]
    ]