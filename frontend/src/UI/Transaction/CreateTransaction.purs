module UI.Transaction.CreateTransaction where

import Prelude

import API.Transaction as API
import Data.Array (filter, find, foldl, null, (:))
import Data.Array as Array
import Data.DateTime.Instant (toDateTime)
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
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners (runOn)
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, useState, (<#~>))
import Effect.Aff (launchAff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Now (now)
import FRP.Poll (Poll)
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Transaction (PaymentMethod(..), PaymentTransaction(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (parseUUID)
import Utils.CartUtils (addItemToCart, emptyCartTotals, formatDiscretePrice, formatPrice, removeItemFromCart)
import Utils.Formatting (findItemNameBySku, formatCentsToDollars)
import Utils.Money (formatMoney')
import Utils.UUIDGen (genUUID)
import Web.Event.Event (target)
import Web.Event.Event as Event
import Web.HTML.HTMLInputElement as Input
import Web.PointerEvent.PointerEvent as PointerEvent

createTransaction :: Poll Inventory -> Nut
createTransaction inventoryPoll = Deku.do
  -- Cart state
  setCartItems /\ cartItemsValue <- useHot []
  setCartTotals /\ cartTotalsValue <- useHot emptyCartTotals
  
  -- Transaction details
  setEmployee /\ employeeValue <- useState ""
  setRegisterId /\ registerIdValue <- useState ""
  setLocationId /\ locationIdValue <- useState ""
  
  -- Payment state
  setPaymentMethod /\ paymentMethodValue <- useState Cash
  setPaymentAmount /\ paymentAmountValue <- useState ""
  setTenderedAmount /\ tenderedAmountValue <- useState ""
  setPayments /\ paymentsValue <- useState []
  
  -- UI state
  setSearchText /\ searchTextValue <- useState ""
  setActiveCategory /\ activeCategoryValue <- useState "All Items"
  setQuantity /\ quantityValue <- useState 1.0
  setStatusMessage /\ statusMessageValue <- useState ""
  setIsProcessing /\ isProcessingValue <- useState false
  
  -- Payment reference/details
  setPaymentReference /\ paymentReferenceValue <- useState ""
  setAuthorizationCode /\ authorizationCodeValue <- useState ""
  setOtherPaymentType /\ otherPaymentTypeValue <- useState ""
  
  D.div
    [ DA.klass_ "transaction-container"
    , DL.load_ \_ -> do
        liftEffect $ Console.log "Transaction component loading"
        
        -- Generate UUIDs for transaction metadata
        void $ launchAff do
          employeeId <- liftEffect genUUID
          registerId <- liftEffect genUUID
          locationId <- liftEffect genUUID
          
          liftEffect do
            setEmployee (show employeeId)
            setRegisterId (show registerId)
            setLocationId (show locationId)
            
        liftEffect $ Console.log "Using global inventory state in CreateTransaction"
    ]
    [
      D.div
        [ DA.klass_ "transaction-content" ]
        [
          -- Left column: Inventory selection
          D.div
            [ DA.klass_ "inventory-selection" ]
            [
              D.div
                [ DA.klass_ "inventory-header" ]
                [ D.h3_ [ text_ "Select Items" ] ],
              
              -- Category tabs
              inventoryPoll <#~> \(Inventory items) ->
                let
                  categories = ["All Items"] <> 
                    (map (\(MenuItem i) -> show i.category) items # map trim # Array.nub # Array.sort)
                in
                  D.div
                    [ DA.klass_ "category-tabs" ]
                    (categories <#> \cat ->
                      D.div
                        [ DA.klass $ activeCategoryValue <#> \active ->
                            "category-tab" <> if active == cat then " active" else ""
                        , DL.click_ \_ -> setActiveCategory cat
                        ]
                        [ text_ cat ]
                    ),
              
              -- Search and quantity controls
              D.div
                [ DA.klass_ "inventory-controls" ]
                [
                  D.div
                    [ DA.klass_ "search-control" ]
                    [
                      D.input
                        [ DA.klass_ "search-input"
                        , DA.placeholder_ "Search inventory..."
                        , DA.value_ ""
                        , DL.input_ \evt -> do
                            for_ (target evt >>= Input.fromEventTarget) \el -> do
                              value <- Input.value el
                              setSearchText value
                        ]
                        []
                    ],
                  
                  D.div
                    [ DA.klass_ "quantity-control" ]
                    [
                      D.div
                        [ DA.klass_ "qty-label" ]
                        [ text_ "Quantity:" ],
                      D.input
                        [ DA.klass_ "qty-input"
                        , DA.xtype_ "number"
                        , DA.min_ "1"
                        , DA.step_ "1"
                        , DA.value_ "1"
                        , DL.input_ \evt -> do
                            for_ (target evt >>= Input.fromEventTarget) \el -> do
                              val <- Input.value el
                              case Number.fromString val of
                                Just num -> if num > 0.0 then setQuantity num else pure unit
                                Nothing -> pure unit
                        ]
                        []
                    ]
                ],
              
              -- Inventory table
              D.div
                [ DA.klass_ "inventory-items" ]
                [
                  inventoryPoll <#~> \(Inventory allItems) ->
                    searchTextValue <#~> \searchText ->
                      activeCategoryValue <#~> \activeCategory ->
                        let
                          -- Filter by category
                          categoryFiltered = 
                            if activeCategory == "All Items" then allItems
                            else filter (\(MenuItem i) -> show i.category == activeCategory) allItems
                            
                          -- Filter by search text
                          filteredItems =
                            if searchText == "" then categoryFiltered
                            else filter
                              (\(MenuItem item) -> 
                                contains (Pattern (toLower searchText)) (toLower item.name))
                              categoryFiltered
                        in
                          if null filteredItems then
                            D.div [ DA.klass_ "empty-result" ]
                              [ text_ "No items found" ]
                          else
                            D.div
                              [ DA.klass_ "inventory-table" ]
                              [
                                D.div
                                  [ DA.klass_ "inventory-table-header" ]
                                  [
                                    D.div [ DA.klass_ "col name-col" ] [ text_ "Name" ],
                                    D.div [ DA.klass_ "col brand-col" ] [ text_ "Brand" ],
                                    D.div [ DA.klass_ "col category-col" ] [ text_ "Category" ],
                                    D.div [ DA.klass_ "col price-col" ] [ text_ "Price" ],
                                    D.div [ DA.klass_ "col stock-col" ] [ text_ "In Stock" ],
                                    D.div [ DA.klass_ "col actions-col" ] [ text_ "Actions" ]
                                  ],
                                D.div
                                  [ DA.klass_ "inventory-table-body" ]
                                  (filteredItems <#> \menuItem@(MenuItem record) ->
                                    cartItemsValue <#~> \cartItems ->
                                      quantityValue <#~> \qtyVal ->
                                        let
                                          formattedPrice = "$" <> formatCentsToDollars (unwrap record.price)
                                          stockClass = if record.quantity <= 5 then "low-stock" else ""
                                          
                                          -- Check if already in cart
                                          existingItem = find 
                                            (\(TransactionItem item) -> item.menuItemSku == record.sku) 
                                            cartItems
                                            
                                          currentQty = case existingItem of
                                            Just (TransactionItem item) -> item.quantity
                                            Nothing -> 0.0
                                        in
                                          D.div
                                            [ DA.klass_ 
                                                ("inventory-row " <> 
                                                  if record.quantity <= 0 then "out-of-stock" else "")
                                            ]
                                            [
                                              D.div [ DA.klass_ "col name-col" ] [ text_ record.name ],
                                              D.div [ DA.klass_ "col brand-col" ] [ text_ record.brand ],
                                              D.div [ DA.klass_ "col category-col" ] 
                                                [ text_ (show record.category <> " - " <> record.subcategory) ],
                                              D.div [ DA.klass_ "col price-col" ] [ text_ formattedPrice ],
                                              D.div [ DA.klass_ ("col stock-col " <> stockClass) ] 
                                                [ text_ (show record.quantity) ],
                                              D.div [ DA.klass_ "col actions-col" ]
                                                [
                                                  if record.quantity <= 0 then
                                                    D.button
                                                      [ DA.klass_ "add-btn disabled"
                                                      , DA.disabled_ "true"
                                                      ]
                                                      [ text_ "Out of Stock" ]
                                                  else
                                                    D.div
                                                      [ DA.klass_ "quantity-controls" ]
                                                      [
                                                        if currentQty > 0.0 then
                                                          D.div
                                                            [ DA.klass_ "quantity-indicator" ]
                                                            [ text_ (show currentQty) ]
                                                        else 
                                                          D.span_ [],
                                                          
                                                        D.button
                                                          [ DA.klass_ "add-btn"
                                                          , DL.click_ \evt -> do
                                                              Event.stopPropagation (PointerEvent.toEvent evt)
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
            ],
          
          -- Right column: Cart and payment
          D.div
            [ DA.klass_ "cart-container" ]
            [
              D.div
                [ DA.klass_ "cart-header" ]
                [ D.h3_ [ text_ "Current Transaction" ] ],
              
              -- Selected items cart
              D.div
                [ DA.klass_ "cart-items" ]
                [
                  (Tuple <$> cartItemsValue <*> inventoryPoll) <#~> \(Tuple cartItems inventory) ->
                    if null cartItems then
                      D.div [ DA.klass_ "empty-cart" ]
                        [ text_ "No items selected" ]
                    else
                      D.div
                        [ DA.klass_ "cart-items-list" ]
                        [
                          D.div
                            [ DA.klass_ "cart-item-header" ]
                            [
                              D.div [ DA.klass_ "col item-col" ] [ text_ "Item" ],
                              D.div [ DA.klass_ "col qty-col" ] [ text_ "Qty" ],
                              D.div [ DA.klass_ "col price-col" ] [ text_ "Price" ],
                              D.div [ DA.klass_ "col total-col" ] [ text_ "Total" ],
                              D.div [ DA.klass_ "col actions-col" ] [ text_ "" ]
                            ],
                          D.div
                            [ DA.klass_ "cart-items-body" ]
                            (cartItems <#> \(TransactionItem itemData) ->
                              let
                                itemName = findItemNameBySku itemData.menuItemSku inventory
                              in
                                D.div
                                  [ DA.klass_ "cart-item-row" ]
                                  [
                                    D.div [ DA.klass_ "col item-col" ] [ text_ itemName ],
                                    D.div [ DA.klass_ "col qty-col" ] [ text_ (show itemData.quantity) ],
                                    D.div [ DA.klass_ "col price-col" ] [ text_ (formatPrice itemData.pricePerUnit) ],
                                    D.div [ DA.klass_ "col total-col" ] [ text_ (formatPrice itemData.total) ],
                                    D.div [ DA.klass_ "col actions-col" ]
                                      [
                                        D.button
                                          [ DA.klass_ "remove-btn"
                                          , DL.click_ \_ -> do
                                              removeItemFromCart 
                                                itemData.id 
                                                cartItems 
                                                setCartItems 
                                                setCartTotals
                                          ]
                                          [ text_ "✕" ]
                                      ]
                                  ]
                            )
                        ]
                ],
              
              -- Cart totals
              D.div
                [ DA.klass_ "cart-totals" ]
                [
                  D.div [ DA.klass_ "total-row" ]
                    [
                      D.div [ DA.klass_ "total-label" ] [ text_ "Subtotal:" ],
                      D.div [ DA.klass_ "total-value" ]
                        [ cartTotalsValue <#~> \totals -> text_ (formatDiscretePrice totals.subtotal) ]
                    ],
                  D.div [ DA.klass_ "total-row" ]
                    [
                      D.div [ DA.klass_ "total-label" ] [ text_ "Tax:" ],
                      D.div [ DA.klass_ "total-value" ]
                        [ cartTotalsValue <#~> \totals -> text_ (formatDiscretePrice totals.taxTotal) ]
                    ],
                  D.div [ DA.klass_ "total-row grand-total" ]
                    [
                      D.div [ DA.klass_ "total-label" ] [ text_ "Total:" ],
                      D.div [ DA.klass_ "total-value" ]
                        [ cartTotalsValue <#~> \totals -> text_ (formatDiscretePrice totals.total) ]
                    ]
                ],
              
              -- Payment methods
              D.div
                [ DA.klass_ "payment-section" ]
                [
                  D.div
                    [ DA.klass_ "payment-header" ]
                    [ text_ "Payment Options" ],
                  
                  D.div
                    [ DA.klass_ "payment-methods" ]
                    [
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if method == Cash then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod Cash
                        ]
                        [ text_ "Cash" ],
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if method == Credit then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod Credit
                        ]
                        [ text_ "Credit" ],
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if method == Debit then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod Debit
                        ]
                        [ text_ "Debit" ],
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if method == ACH then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod ACH
                        ]
                        [ text_ "ACH" ],
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if method == GiftCard then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod GiftCard
                        ]
                        [ text_ "Gift Card" ],
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if method == StoredValue then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod StoredValue
                        ]
                        [ text_ "Stored Value" ],
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if method == Mixed then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod Mixed
                        ]
                        [ text_ "Split Payment" ],
                      D.div
                        [ DA.klass $ paymentMethodValue <#> \method ->
                            "payment-method" <> if case method of
                              Other _ -> true
                              _ -> false
                            then " active" else ""
                        , DL.click_ \_ -> setPaymentMethod (Other "")
                        ]
                        [ text_ "Other" ]
                    ],
                  
                  -- Payment inputs
                  D.div
                    [ DA.klass_ "payment-inputs" ]
                    [
                      D.div
                        [ DA.klass_ "payment-input-row" ]
                        [
                          D.label [ DA.klass_ "payment-label" ] [ text_ "Amount:" ],
                          D.input
                            [ DA.klass_ "payment-field"
                            , DA.xtype_ "text"
                            , DA.value paymentAmountValue
                            , DL.input_ \evt -> do
                                for_ (target evt >>= Input.fromEventTarget) \el -> do
                                  value <- Input.value el
                                  setPaymentAmount value
                            ]
                            []
                        ],
                      
                      paymentMethodValue <#~> \method ->
                        if method == Cash then
                          D.div
                            [ DA.klass_ "payment-input-row" ]
                            [
                              D.label [ DA.klass_ "payment-label" ] [ text_ "Tendered:" ],
                              D.input
                                [ DA.klass_ "payment-field"
                                , DA.xtype_ "text"
                                , DA.value tenderedAmountValue
                                , DL.input_ \evt -> do
                                    for_ (target evt >>= Input.fromEventTarget) \el -> do
                                      value <- Input.value el
                                      setTenderedAmount value
                                ]
                                []
                            ]
                        else
                          D.div_ []
                    ],
                  
                  -- Add payment button
                  D.button
                    [ DA.klass_ "add-payment-btn"
                    , runOn DL.click $
                        (\payAmt tenderedAmt method currPayments payRef authCode -> do
                          case (Number.fromString payAmt) of
                            Nothing -> do
                              setStatusMessage "Invalid payment amount"
                            Just amount -> do
                              let
                                tenderedAmount = case Number.fromString tenderedAmt of
                                  Just t -> t
                                  Nothing -> amount
                                
                                paymentAmount = fromDiscrete' (Discrete (Int.floor (amount * 100.0)))
                                paymentTendered = fromDiscrete' (Discrete (Int.floor (tenderedAmount * 100.0)))
                                change = 
                                  if toDiscrete paymentTendered > toDiscrete paymentAmount then 
                                    fromDiscrete' (toDiscrete paymentTendered - toDiscrete paymentAmount)
                                  else 
                                    fromDiscrete' (Discrete 0)
                              
                              void $ launchAff do
                                paymentId <- liftEffect genUUID
                                transactionId <- liftEffect genUUID
                                
                                let
                                  newPayment = PaymentTransaction
                                    { id: paymentId
                                    , transactionId: transactionId
                                    , method: case method of
                                        Other "" -> Other "Custom Payment"
                                        other -> other
                                    , amount: paymentAmount
                                    , tendered: paymentTendered
                                    , change: change
                                    , reference: if payRef == "" then Nothing 
                                                 else Just payRef
                                    , approved: true
                                    , authorizationCode: if authCode == "" then Nothing
                                                         else Just authCode
                                    }
                                
                                liftEffect do
                                  setPayments (newPayment : currPayments)
                                  setPaymentAmount ""
                                  setTenderedAmount ""
                                  setPaymentReference ""
                                  setAuthorizationCode ""
                                  setOtherPaymentType ""
                                  setStatusMessage "Payment added"
                        ) <$> paymentAmountValue <*> tenderedAmountValue <*> paymentMethodValue <*> paymentsValue 
                          <*> paymentReferenceValue <*> authorizationCodeValue
                    ]
                    [ text_ "Add Payment" ],
                  
                  -- Existing payments
                  D.div
                    [ DA.klass_ "existing-payments" ]
                    [ paymentsValue <#~> \payments ->
                        if null payments then 
                          D.div_ []
                        else 
                          D.div
                            [ DA.klass_ "payments-container" ]
                            [
                              D.div [ DA.klass_ "payments-header" ] [ text_ "Current Payments:" ],
                              D.div_
                                (payments <#> \(PaymentTransaction p) ->
                                  D.div
                                    [ DA.klass_ "payment-item" ]
                                    [
                                      D.div [ DA.klass_ "payment-method" ] [ text_ (show p.method) ],
                                      D.div [ DA.klass_ "payment-amount" ] [ text_ (formatMoney' p.amount) ],
                                      D.button
                                        [ DA.klass_ "payment-remove"
                                        , runOn DL.click $
                                            (\currPayments -> do
                                              let
                                                updatedPayments = filter
                                                  (\(PaymentTransaction pay) -> pay.id /= p.id)
                                                  currPayments
                                              setPayments updatedPayments
                                            ) <$> paymentsValue
                                        ]
                                        [ text_ "✕" ]
                                    ]
                                )
                            ]
                    ]
                ]
            ]
        ],
      
      -- Bottom action bar
      D.div
        [ DA.klass_ "action-bar" ]
        [
          D.button
            [ DA.klass_ "cancel-btn"
            , DL.click_ \_ -> do
                setCartItems []
                setPayments []
                setCartTotals emptyCartTotals
                setStatusMessage "Transaction cleared"
            ]
            [ text_ "Cancel Transaction" ],
            
          D.div
            [ DA.klass_ "payment-summary" ]
            [
              (Tuple <$> cartTotalsValue <*> paymentsValue) <#~> \(Tuple totals payments) ->
                let
                  paymentTotal = foldl
                    (\acc (PaymentTransaction p) -> acc + toDiscrete p.amount)
                    (Discrete 0)
                    payments
                  remaining = totals.total - paymentTotal
                  paidClass = if remaining <= Discrete 0 then "paid" else "unpaid"
                in
                  D.div
                    [ DA.klass_ "remaining-balance" ]
                    [
                      D.div [ DA.klass_ "remaining-label" ] [ text_ "Remaining:" ],
                      D.div 
                        [ DA.klass_ ("remaining-amount " <> paidClass) ]
                        [ text_ (formatDiscretePrice (max (Discrete 0) remaining)) ]
                    ]
            ],
            
          D.button
            [ DA.klass_ "checkout-btn"
            , DA.disabled $ isProcessingValue <#> \isProcessing ->
                if isProcessing then "true" else ""
            , runOn DL.click $
                (\cartItems currPayments totals empId regId locId -> do
                  if null cartItems then do
                    setStatusMessage "Cannot complete: No items in transaction"
                  else do
                    let
                      paymentTotal = foldl
                        (\acc (PaymentTransaction p) -> acc + toDiscrete p.amount)
                        (Discrete 0)
                        currPayments
                    if paymentTotal < totals.total then do
                      setStatusMessage "Cannot complete: Payment amount is insufficient"
                    else do
                      setIsProcessing true
                      setStatusMessage "Processing transaction..."
                      
                      void $ launchAff do
                        transactionId <- liftEffect genUUID
                        currentTime <- liftEffect now
                        
                        let
                          curTime = toDateTime currentTime
                          
                          -- Update items and payments with transaction ID
                          updatedItems = map
                            (\(TransactionItem item) ->
                              TransactionItem (item { transactionId = transactionId }))
                            cartItems
                            
                          updatedPayments = map
                            (\(PaymentTransaction payment) ->
                              PaymentTransaction (payment { transactionId = transactionId }))
                            currPayments
                          
                          -- Parse UUIDs
                          employeeUUID = parseUUID empId
                          registerUUID = parseUUID regId
                          locationUUID = parseUUID locId
                        
                        case Tuple (Tuple employeeUUID registerUUID) locationUUID of
                          Tuple (Tuple (Just empId') (Just regId')) (Just locId') -> do
                            liftEffect $ Console.log $ "Creating transaction with ID: " <> show transactionId
                            
                            let
                              transaction = Transaction
                                { id: transactionId
                                , status: Completed
                                , created: toDateTime currentTime
                                , completed: Just curTime
                                , customer: Nothing
                                , employee: empId'
                                , register: regId'
                                , location: locId'
                                , items: updatedItems
                                , payments: updatedPayments
                                , subtotal: fromDiscrete' totals.subtotal
                                , discountTotal: fromDiscrete' totals.discountTotal
                                , taxTotal: fromDiscrete' totals.taxTotal
                                , total: fromDiscrete' totals.total
                                , transactionType: Sale
                                , isVoided: false
                                , voidReason: Nothing
                                , isRefunded: false
                                , refundReason: Nothing
                                , referenceTransactionId: Nothing
                                , notes: Nothing
                                }
                            
                            result <- API.createTransaction transaction
                            
                            liftEffect case result of
                              Right completedTx -> do
                                setCartItems []
                                setPayments []
                                setCartTotals emptyCartTotals
                                setStatusMessage "Transaction completed successfully"
                              Left err -> do
                                setStatusMessage $ "Error completing transaction: " <> err
                                
                          _ -> liftEffect $ setStatusMessage "Invalid employee, register or location ID"
                        
                        liftEffect $ setIsProcessing false
                ) <$> cartItemsValue <*> paymentsValue <*> cartTotalsValue 
                   <*> employeeValue <*> registerIdValue <*> locationIdValue
            ]
            [ cartTotalsValue <#~> \totals ->
                text_ ("Process Payment " <> formatDiscretePrice totals.total)
            ]
        ],
      
      -- Status message
      statusMessageValue <#~> \msg ->
        if msg == "" then
          D.div_ []
        else
          D.div
            [ DA.klass_ "status-message" ]
            [ text_ msg ]
    ]
  