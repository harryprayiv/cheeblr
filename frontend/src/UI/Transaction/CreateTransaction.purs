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
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import FRP.Poll (Poll)
import Services.AuthService (AuthContext)
import Services.RegisterService (addItemToCart, emptyCartTotals, formatDiscretePrice, removeItemFromCart)
import Services.TransactionService (getRemainingBalance, paymentsCoversTotal)
import Services.TransactionService as TransactionService
import Types.Inventory (Inventory(..), MenuItem(..), findItemNameBySku)
import Types.Register (Register, CartTotals)
import Types.Transaction (PaymentMethod(..), PaymentTransaction(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (UUID(..))
import Utils.Formatting (formatCentsToDollars)
import Web.Event.Event (target)
import Web.HTML.HTMLInputElement as Input

-- Extracted helper, like doFavoriting in the realworld app.
-- Used in both the payment summary and checkout validation.
mkDummyTransaction :: CartTotals -> Transaction
mkDummyTransaction t = Transaction
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
  , transactionSubtotal: fromDiscrete' t.subtotal
  , transactionDiscountTotal: fromDiscrete' (Discrete 0)
  , transactionTaxTotal: fromDiscrete' t.taxTotal
  , transactionTotal: fromDiscrete' t.total
  , transactionType: Sale
  , transactionIsVoided: false
  , transactionVoidReason: Nothing
  , transactionIsRefunded: false
  , transactionRefundReason: Nothing
  , transactionReferenceTransactionId: Nothing
  , transactionNotes: Nothing
  }

--------------------------------------------------------------------------------
-- Inventory Search
--
-- Owns: searchText, activeCategory, quantity
-- Pattern: like `home` in realworld — takes polls it reads, setters it writes to
--------------------------------------------------------------------------------

inventorySearch
  :: Ref AuthContext
  -> Poll Inventory
  -> Poll Transaction
  -> Poll (Array TransactionItem)
  -> Poll Boolean
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (String -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Nut
inventorySearch authRef inventoryPoll transactionPoll cartItemsValue checkingValue setCartItems setCartTotals setStatus setChecking = Deku.do
  setSearch /\ searchValue <- useHot ""
  setCategory /\ categoryValue <- useHot "All Items"
  setQty /\ qtyValue <- useHot 1

  D.div [ DA.klass_ "inventory-selection" ]
    [ D.div [ DA.klass_ "inventory-header" ] [ D.h3_ [ text_ "Select Items" ] ]

    -- Category tabs
    , inventoryPoll <#~> \(Inventory items) ->
        let
          categories = [ "All Items" ] <>
            (map (\(MenuItem i) -> show i.category) items # map trim # Array.nub # Array.sort)
        in
          D.div [ DA.klass_ "category-tabs" ]
            ( categories <#> \cat ->
                D.div
                  [ DA.klass $ categoryValue <#> \active ->
                      "category-tab" <> if active == cat then " active" else ""
                  , DL.click_ \_ -> setCategory cat
                  ]
                  [ text_ cat ]
            )

    -- Search + quantity
    , D.div [ DA.klass_ "inventory-controls" ]
        [ D.div [ DA.klass_ "search-control" ]
            [ D.input
                [ DA.klass_ "search-input"
                , DA.placeholder_ "Search inventory..."
                , DA.value_ ""
                , DL.input_ \evt ->
                    for_ (target evt >>= Input.fromEventTarget) \el ->
                      Input.value el >>= setSearch
                ]
                []
            ]
        , D.div [ DA.klass_ "quantity-control" ]
            [ D.div [ DA.klass_ "qty-label" ] [ text_ "Quantity:" ]
            , D.input
                [ DA.klass_ "qty-input"
                , DA.xtype_ "number"
                , DA.min_ "1"
                , DA.step_ "1"
                , DA.value_ "1"
                , DL.input_ \evt ->
                    for_ (target evt >>= Input.fromEventTarget) \el -> do
                      val <- Input.value el
                      for_ (Number.fromString val) \n ->
                        when (n > 0.0) $ setQty (Int.floor n)
                ]
                []
            ]
        ]

    -- Filtered items table
        , D.div [ DA.klass_ "inventory-items" ]
            [ (Tuple <$> inventoryPoll <*> transactionPoll) <#~>
                \(Tuple (Inventory allItems) transaction) ->
            searchValue <#~> \search ->
              categoryValue <#~> \category ->
                checkingValue <#~> \isChecking ->
                  let
                    byCategory =
                      if category == "All Items" then allItems
                      else filter (\(MenuItem i) -> show i.category == category) allItems

                    filtered =
                      if search == "" then byCategory
                      else filter
                        (\(MenuItem i) -> contains (Pattern (toLower search)) (toLower i.name))
                        byCategory
                  in
                    if null filtered then
                      D.div [ DA.klass_ "empty-result" ] [ text_ "No items found" ]
                    else
                      D.div [ DA.klass_ "inventory-table" ]
                        [ D.div [ DA.klass_ "inventory-table-header" ]
                            [ D.div [ DA.klass_ "col name-col" ] [ text_ "Name" ]
                            , D.div [ DA.klass_ "col brand-col" ] [ text_ "Brand" ]
                            , D.div [ DA.klass_ "col category-col" ] [ text_ "Category" ]
                            , D.div [ DA.klass_ "col price-col" ] [ text_ "Price" ]
                            , D.div [ DA.klass_ "col stock-col" ] [ text_ "In Stock" ]
                            , D.div [ DA.klass_ "col actions-col" ] [ text_ "Actions" ]
                            ]
                        , D.div [ DA.klass_ "inventory-table-body" ]
                            ( filtered <#> \menuItem@(MenuItem rec) ->
                                cartItemsValue <#~> \cartItems ->
                                  qtyValue <#~> \qty ->
                                    let
                                      price = "$" <> formatCentsToDollars (unwrap rec.price)
                                      stockKls = if rec.quantity <= 5 then "low-stock" else ""
                                      inCart = case find (\(TransactionItem ti) -> ti.transactionItemMenuItemSku == rec.sku) cartItems of
                                        Just (TransactionItem ti) -> ti.transactionItemQuantity
                                        Nothing -> 0
                                    in
                                      D.div [ DA.klass_ ("inventory-row " <> if rec.quantity <= 0 then "out-of-stock" else "") ]
                                        [ D.div [ DA.klass_ "col name-col" ] [ text_ rec.name ]
                                        , D.div [ DA.klass_ "col brand-col" ] [ text_ rec.brand ]
                                        , D.div [ DA.klass_ "col category-col" ]
                                            [ text_ (show rec.category <> " - " <> rec.subcategory) ]
                                        , D.div [ DA.klass_ "col price-col" ] [ text_ price ]
                                        , D.div [ DA.klass_ ("col stock-col " <> stockKls) ]
                                            [ text_ (show rec.quantity) ]
                                        , D.div [ DA.klass_ "col actions-col" ]
                                            [ if rec.quantity <= 0 || isChecking then
                                                D.button [ DA.klass_ "add-btn disabled", DA.disabled_ "true" ]
                                                  [ text_ if rec.quantity <= 0 then "Out of Stock" else "Processing..." ]
                                              else
                                                D.div [ DA.klass_ "quantity-controls" ]
                                                  [ if inCart > 0
                                                      then D.div [ DA.klass_ "quantity-indicator" ] [ text_ (show inCart) ]
                                                      else D.span_ []
                                                  , D.button
                                                      [ DA.klass_ "add-btn"
                                                      , DL.click_ \_ ->
                                                          addItemToCart authRef menuItem qty cartItems
                                                            (unwrap transaction).transactionId
                                                            setCartItems setCartTotals setStatus setChecking
                                                      ]
                                                      [ text_ "Add" ]
                                                  ]
                                            ]
                                        ]
                            )
                        ]
        ]
    ]

--------------------------------------------------------------------------------
-- Cart
--
-- Owns: nothing (pure display + remove actions)
-- Pattern: like `articlePreview` — renders data, fires actions
--------------------------------------------------------------------------------

cart
  :: Ref AuthContext
  -> Poll Inventory
  -> Poll Transaction
  -> Poll (Array TransactionItem)
  -> Poll CartTotals
  -> Poll (Array String)
  -> (Array TransactionItem -> Effect Unit)
  -> (CartTotals -> Effect Unit)
  -> (Boolean -> Effect Unit)
  -> Nut
cart authRef inventoryPoll transactionPoll cartItemsValue totalsValue errorsValue setCartItems setCartTotals setChecking =
  D.div [ DA.klass_ "cart-container" ]
    [ D.div [ DA.klass_ "cart-header" ] [ D.h3_ [ text_ "Current Transaction" ] ]

    -- Inventory errors
    , errorsValue <#~> \errors ->
        if null errors then D.div_ []
        else D.div [ DA.klass_ "inventory-errors-container" ]
          [ D.div [ DA.klass_ "inventory-errors-header" ] [ text_ "Inventory Issues:" ]
          , D.ul [ DA.klass_ "inventory-errors-list" ]
              (errors <#> \e -> D.li [ DA.klass_ "inventory-error" ] [ text_ e ])
          ]

    -- Items list
    , D.div [ DA.klass_ "cart-items" ]
        [ (Tuple <$> (Tuple <$> cartItemsValue <*> inventoryPoll) <*> transactionPoll) <#~>
              \(Tuple (Tuple items inventory) _) ->
            if null items then
              D.div [ DA.klass_ "empty-cart" ] [ text_ "No items selected" ]
            else
              D.div [ DA.klass_ "cart-items-list" ]
                [ D.div [ DA.klass_ "cart-item-header" ]
                    [ D.div [ DA.klass_ "col item-col" ] [ text_ "Item" ]
                    , D.div [ DA.klass_ "col qty-col" ] [ text_ "Qty" ]
                    , D.div [ DA.klass_ "col price-col" ] [ text_ "Price" ]
                    , D.div [ DA.klass_ "col total-col" ] [ text_ "Total" ]
                    , D.div [ DA.klass_ "col actions-col" ] [ text_ "" ]
                    ]
                , D.div [ DA.klass_ "cart-items-body" ]
                    ( items <#> \(TransactionItem d) ->
                        D.div [ DA.klass_ "cart-item-row" ]
                          [ D.div [ DA.klass_ "col item-col" ]
                              [ text_ (findItemNameBySku d.transactionItemMenuItemSku inventory) ]
                          , D.div [ DA.klass_ "col qty-col" ]
                              [ text_ (show d.transactionItemQuantity) ]
                          , D.div [ DA.klass_ "col price-col" ]
                              [ text_ (formatDiscretePrice (toDiscrete d.transactionItemPricePerUnit)) ]
                          , D.div [ DA.klass_ "col total-col" ]
                              [ text_ (formatDiscretePrice (toDiscrete d.transactionItemTotal)) ]
                          , D.div [ DA.klass_ "col actions-col" ]
                              [ D.button
                                  [ DA.klass_ "remove-btn"
                                  , DL.click_ \_ ->
                                      removeItemFromCart authRef d.transactionItemId
                                        items setCartItems setCartTotals setChecking
                                  ]
                                  [ text_ "✕" ]
                              ]
                          ]
                    )
                ]
        ]

    -- Totals
    , D.div [ DA.klass_ "cart-totals" ]
        [ D.div [ DA.klass_ "total-row" ]
            [ D.div [ DA.klass_ "total-label" ] [ text_ "Subtotal:" ]
            , D.div [ DA.klass_ "total-value" ]
                [ totalsValue <#~> \t -> text_ (formatDiscretePrice t.subtotal) ]
            ]
        , D.div [ DA.klass_ "total-row" ]
            [ D.div [ DA.klass_ "total-label" ] [ text_ "Tax:" ]
            , D.div [ DA.klass_ "total-value" ]
                [ totalsValue <#~> \t -> text_ (formatDiscretePrice t.taxTotal) ]
            ]
        , D.div [ DA.klass_ "total-row grand-total" ]
            [ D.div [ DA.klass_ "total-label" ] [ text_ "Total:" ]
            , D.div [ DA.klass_ "total-value" ]
                [ totalsValue <#~> \t -> text_ (formatDiscretePrice t.total) ]
            ]
        ]
    ]

--------------------------------------------------------------------------------
-- Payment
--
-- Owns: paymentMethod, paymentAmount, tenderedAmount, reference, authCode
-- Pattern: like `login` or `settings` — owns form state, calls out via setters
--------------------------------------------------------------------------------

payment
  :: Ref AuthContext
  -> Poll Transaction
  -> Poll (Array PaymentTransaction)
  -> Poll CartTotals
  -> Poll Boolean
  -> (Array PaymentTransaction -> Effect Unit)
  -> (String -> Effect Unit)
  -> Nut
payment authRef transactionPoll paymentsValue totalsValue processingValue setPayments setStatus = Deku.do
  setMethod /\ methodValue <- useHot Cash
  setAmount /\ amountValue <- useHot ""
  setTendered /\ tenderedValue <- useHot ""
  setRef /\ refValue <- useHot ""
  setAuth /\ authValue <- useHot ""

  let
    methodBtn method label =
      D.div
        [ DA.klass $ methodValue <#> \cur ->
            "payment-method" <> if matchMethod cur method then " active" else ""
        , DL.click_ \_ -> setMethod method
        ]
        [ text_ label ]

    matchMethod a b = case Tuple a b of
      Tuple (Other _) (Other _) -> true
      _ -> a == b

    field label val setter disabled =
      D.div [ DA.klass_ "payment-input-row" ]
        [ D.label [ DA.klass_ "payment-label" ] [ text_ label ]
        , D.input
            [ DA.klass_ "payment-field"
            , DA.xtype_ "text"
            , DA.value val
            , DA.disabled_ (if disabled then "true" else "")
            , DL.input_ \evt ->
                for_ (target evt >>= Input.fromEventTarget) \el ->
                  Input.value el >>= setter
            ]
            []
        ]

  D.div [ DA.klass_ "payment-section" ]
    [ D.div [ DA.klass_ "payment-header" ] [ text_ "Payment Options" ]

    , D.div [ DA.klass_ "payment-methods" ]
        [ methodBtn Cash "Cash"
        , methodBtn Credit "Credit"
        , methodBtn Debit "Debit"
        , methodBtn ACH "ACH"
        , methodBtn GiftCard "Gift Card"
        , methodBtn StoredValue "Stored Value"
        , methodBtn Mixed "Split Payment"
        , methodBtn (Other "") "Other"
        ]

    , processingValue <#~> \busy ->
        D.div [ DA.klass_ "payment-inputs" ]
          [ field "Amount:" amountValue setAmount busy
          , methodValue <#~> \m ->
              if m == Cash then field "Tendered:" tenderedValue setTendered busy
              else D.div_ []
          , methodValue <#~> \m -> case m of
              Credit -> field "Auth Code:" authValue setAuth busy
              _ -> D.div_ []
          ]

    , D.button
        [ DA.klass_ "add-payment-btn"
        , DA.disabled $ processingValue <#> \p -> if p then "true" else ""
        , runOn DL.click $
            ( \amt tend method pays ref auth txn -> do
                case Number.fromString amt of
                  Just amount -> do
                    let
                      tendered = case Number.fromString tend of
                        Just t -> t
                        Nothing -> amount
                    void $ launchAff_ do
                      result <- TransactionService.addPayment authRef
                        (unwrap txn).transactionId method
                        (Int.floor (amount * 100.0))
                        (Int.floor (tendered * 100.0))
                        (if ref == "" && auth == "" then Nothing
                         else Just (if ref /= "" then ref else auth))
                      liftEffect $ case result of
                        Right p -> do
                          setPayments (p : pays)
                          setAmount ""
                          setTendered ""
                          setRef ""
                          setAuth ""
                          setStatus "Payment added to transaction"
                        Left err -> setStatus $ "Payment error: " <> err
                  Nothing -> setStatus "Invalid payment amount"
            ) <$> amountValue <*> tenderedValue <*> methodValue
              <*> paymentsValue <*> refValue <*> authValue <*> transactionPoll
        ]
        [ text_ "Add Payment" ]

    -- Existing payments
    , D.div [ DA.klass_ "existing-payments" ]
        [ paymentsValue <#~> \pays ->
            if null pays then D.div_ []
            else D.div [ DA.klass_ "payments-container" ]
              [ D.div [ DA.klass_ "payments-header" ] [ text_ "Current Payments:" ]
              , D.div_
                  ( pays <#> \(PaymentTransaction p) ->
                      D.div [ DA.klass_ "payment-item" ]
                        [ D.div [ DA.klass_ "payment-method" ] [ text_ (show p.paymentMethod) ]
                        , D.div [ DA.klass_ "payment-amount" ] [ text_ (show p.paymentAmount) ]
                        , D.button
                            [ DA.klass_ "payment-remove"
                            , DA.disabled $ processingValue <#> \b -> if b then "true" else ""
                            , runOn DL.click $ paymentsValue <#> \cur -> do
                                void $ launchAff_ do
                                  result <- TransactionService.removePaymentTransaction authRef p.paymentId
                                  liftEffect $ case result of
                                    Right _ -> do
                                      setPayments $ filter
                                        (\(PaymentTransaction x) -> x.paymentId /= p.paymentId) cur
                                      setStatus "Payment removed"
                                    Left err -> setStatus $ "Error removing payment: " <> err
                            ]
                            [ text_ "✕" ]
                        ]
                  )
              ]
        ]

    -- Remaining balance
    , D.div [ DA.klass_ "payment-summary" ]
        [ (Tuple <$> totalsValue <*> paymentsValue) <#~> \(Tuple totals pays) ->
            let
              remaining = getRemainingBalance pays (mkDummyTransaction totals)
              kls = if remaining <= Discrete 0 then "paid" else "unpaid"
            in
              D.div [ DA.klass_ "remaining-balance" ]
                [ D.div [ DA.klass_ "remaining-label" ] [ text_ "Remaining:" ]
                , D.div [ DA.klass_ ("remaining-amount " <> kls) ]
                    [ text_ (formatDiscretePrice (max (Discrete 0) remaining)) ]
                ]
        ]
    ]

--------------------------------------------------------------------------------
-- Main: wires the components together
-- Pattern: like Main.purs in the realworld app — creates shared state,
-- passes polls and setters down to each component
--------------------------------------------------------------------------------

createTransaction :: Ref AuthContext -> Poll Inventory -> Poll Transaction -> Register -> Nut
createTransaction authRef inventoryPoll transactionPoll register = Deku.do
  setCartItems /\ cartItemsValue <- useHot []
  setCartTotals /\ cartTotalsValue <- useHot emptyCartTotals
  setPayments /\ paymentsValue <- useState []
  setStatus /\ statusValue <- useState ""
  setProcessing /\ processingValue <- useState false
  setTxnStatus /\ txnStatusValue <- useState "CREATED"
  setErrors /\ errorsValue <- useState []
  setChecking /\ checkingValue <- useState false

  let
    _ = transactionPoll <#> \(Transaction td) -> do
      Console.log $ "Transaction received with ID: " <> show td.transactionId
      setTxnStatus (show td.transactionStatus)
      setStatus "Transaction ready"
      unless (null td.transactionItems) do
        setCartItems td.transactionItems
        setPayments td.transactionPayments
        setCartTotals
          { subtotal: toDiscrete td.transactionSubtotal
          , taxTotal: toDiscrete td.transactionTaxTotal
          , total: toDiscrete td.transactionTotal
          , discountTotal: toDiscrete td.transactionDiscountTotal
          }

  D.div [ DA.klass_ "transaction-container" ]
    [ -- Register status
      D.div [ DA.klass_ "register-status active" ]
        [ D.div [ DA.klass_ "register-info" ]
            [ text_ ("Register: " <> register.registerName <> " (#" <> show (register.registerId :: UUID) <> ")") ]
        , D.div [ DA.klass_ "transaction-status" ]
            [ D.span [ DA.klass_ "status-label" ] [ text_ "Transaction Status: " ]
            , D.span
                [ DA.klass $ txnStatusValue <#> \s -> "status-value " <> case s of
                    "Completed" -> "completed"
                    "CREATED" -> "created"
                    "In Progress" -> "in-progress"
                    _ -> ""
                ]
                [ text txnStatusValue ]
            ]
        ]

    -- Three components wired together
    , D.div [ DA.klass_ "transaction-content" ]
        [ inventorySearch authRef inventoryPoll transactionPoll
            cartItemsValue checkingValue
            setCartItems setCartTotals setStatus setChecking

        , cart authRef inventoryPoll transactionPoll
            cartItemsValue cartTotalsValue errorsValue
            setCartItems setCartTotals setChecking

        , payment authRef transactionPoll
            paymentsValue cartTotalsValue processingValue
            setPayments setStatus
        ]

    -- Action bar
    , D.div [ DA.klass_ "action-bar" ]
        [ D.button
            [ DA.klass_ "cancel-btn"
            , DA.disabled $ processingValue <#> \p -> if p then "true" else ""
            , runOn DL.click $
                ( \items txn -> do
                    if null items then setStatus "No items to clear"
                    else do
                      setProcessing true
                      setStatus "Clearing cart..."
                      void $ launchAff_ do
                        result <- TransactionService.clearTransaction authRef (unwrap txn).transactionId
                        liftEffect $ case result of
                          Right _ -> do
                            setCartItems []
                            setPayments []
                            setCartTotals emptyCartTotals
                            setStatus "Cart cleared"
                          Left err -> setStatus $ "Error: " <> err
                        liftEffect $ setProcessing false
                ) <$> cartItemsValue <*> transactionPoll
            ]
            [ text_ "Clear Items" ]

        , D.button
            [ DA.klass_ "checkout-btn"
            , DA.disabled $ processingValue <#> \p -> if p then "true" else ""
            , runOn DL.click $
                ( \items pays totals txn -> do
                    if null items then
                      setStatus "Cannot complete: No items in transaction"
                    else if not (paymentsCoversTotal pays (mkDummyTransaction totals)) then
                      setStatus "Cannot complete: Payment amount is insufficient"
                    else do
                      setProcessing true
                      setStatus "Finalizing transaction..."
                      void $ launchAff_ do
                        result <- TransactionService.finalizeTransaction authRef (unwrap txn).transactionId
                        liftEffect $ case result of
                          Right _ -> do
                            setCartItems []
                            setPayments []
                            setCartTotals emptyCartTotals
                            setTxnStatus "Completed"
                            setErrors []
                            setStatus "Transaction completed successfully"
                          Left err -> setStatus $ "Error finalizing transaction: " <> err
                        liftEffect $ setProcessing false
                ) <$> cartItemsValue <*> paymentsValue <*> cartTotalsValue <*> transactionPoll
            ]
            [ cartTotalsValue <#~> \t -> text_ ("Process Payment " <> formatDiscretePrice t.total) ]
        ]

    -- Status bar
    , statusValue <#~> \msg ->
        if msg == "" then D.div_ []
        else D.div [ DA.klass_ "status-message" ] [ text_ msg ]
    ]