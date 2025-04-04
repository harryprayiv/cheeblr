module UI.Transaction.CreateTransaction where

import Prelude

import API.Inventory (readInventory)
import Data.Array (find, filter, foldl, length, null, (:))
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Finance.Money.Extended (fromDiscrete', toDiscrete)
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.String (Pattern(..), contains, trim)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners (runOn)
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import Effect.Aff (launchAff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Types.Inventory (Inventory(..), InventoryResponse(..), MenuItem(..))
import UI.Transaction.LiveCart (liveCart)
import Utils.Money (formatMoney', fromDollars, toDollars)
import Utils.UUIDGen (genUUID)
import Web.Event.Event (target)
import API.Transaction (createTransaction) as API
import Data.DateTime.Instant (toDateTime)
import Data.Tuple (Tuple(..))
import Effect.Now (now)
import Types.Transaction (PaymentMethod(..), PaymentTransaction(..), TaxCategory(..), Transaction(..), TransactionItem(..), TransactionStatus(..), TransactionType(..))
import Types.UUID (parseUUID)
import Web.HTML.HTMLInputElement as Input

-- Helper functions
updateNumpad
  :: String -> (String -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
updateNumpad digit setNumpadValue setItemQuantity = do
  -- Get the current value
  numpadValue <- readNumpadValueST

  -- Only allow one decimal point
  let
    newValue =
      if digit == "." && contains (Pattern ".") numpadValue then numpadValue
      else numpadValue <> digit

  -- Update both displays
  setNumpadValue newValue
  setItemQuantity newValue

-- We need this stub since we can't directly read from Poll in an Effect
readNumpadValueST :: Effect String
readNumpadValueST = pure ""

-- Helper to read float values
readFloat :: String -> Maybe Number
readFloat str = Number.fromString (trim str)

-- Helper to process valid items
processValidItem
  :: Number
  -> MenuItem
  -> Discrete USD
  -> Discrete USD
  -> Discrete USD
  -> Array TransactionItem
  -> (Discrete USD -> Effect Unit)
  -> (Discrete USD -> Effect Unit)
  -> (Discrete USD -> Effect Unit)
  -> (Array TransactionItem -> Effect Unit)
  -> (Maybe MenuItem -> Effect Unit)
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
processValidItem
  qtyNum
  menuItem@(MenuItem item)
  currSubtotal
  currTaxTotal
  currTotal
  currItems
  setSubtotal
  setTaxTotal
  setTotal
  setItems
  setSelectedItem
  setStatusMessage
  setNumpadValue
  setItemQuantity = do
  void $ launchAff do
    itemId <- liftEffect genUUID
    transactionId <- liftEffect genUUID

    let
      priceInDollars = toDollars item.price
      price = fromDollars priceInDollars
      priceAsDiscrete = fromDiscrete' price

      qtyAsInt = Int.floor qtyNum
      itemSubtotal = fromDiscrete' (price * (Discrete qtyAsInt))

      taxRate = 0.1
      taxRateInt = Int.floor (taxRate * 100.0)

      subtotalAsInt = case toDiscrete itemSubtotal of
        Discrete n -> n

      taxAmountInt = (subtotalAsInt * taxRateInt) / 100

      itemTaxTotal = fromDiscrete' (Discrete taxAmountInt)

      itemTotal = itemSubtotal + itemTaxTotal

      newItem = TransactionItem
        { id: itemId
        , transactionId: transactionId
        , menuItemSku: item.sku
        , quantity: qtyNum
        , pricePerUnit: priceAsDiscrete
        , discounts: []
        , taxes:
            [ { category: RegularSalesTax
              , rate: taxRate
              , amount: itemTaxTotal
              , description: "Sales Tax"
              }
            ]
        , subtotal: itemSubtotal
        , total: itemTotal
        }

    liftEffect do
      setSubtotal (currSubtotal + toDiscrete itemSubtotal)
      setTaxTotal (currTaxTotal + toDiscrete itemTaxTotal)
      setTotal (currTotal + toDiscrete itemTotal)

      setItems (newItem : currItems)
      setSelectedItem Nothing
      setStatusMessage "Item added to transaction"
      setNumpadValue ""
      setItemQuantity "1"

formatCentsToDollars :: Int -> String
formatCentsToDollars cents =
  let
    dollars = cents / 100
    centsRemaining = cents `mod` 100
    centsStr =
      if centsRemaining < 10 then "0" <> show centsRemaining
      else show centsRemaining
  in
    show dollars <> "." <> centsStr

createTransaction :: Nut
createTransaction = Deku.do
  -- State for cart and transaction
  setItems /\ itemsValue <- useState []
  setPayments /\ paymentsValue <- useState []

  -- Transaction data
  setEmployee /\ employeeValue <- useState ""
  setRegisterId /\ registerIdValue <- useState ""
  setLocationId /\ locationIdValue <- useState ""
  setSubtotal /\ subtotalValue <- useState (Discrete 0)
  setDiscountTotal /\ discountTotalValue <- useState (Discrete 0)
  setTaxTotal /\ taxTotalValue <- useState (Discrete 0)
  setTotal /\ totalValue <- useState (Discrete 0)

  -- Inventory and search
  setInventory /\ inventoryValue <- useState (Inventory [])

  -- Selected item and quantity
  setSelectedItem /\ selectedItemValue <- useState Nothing
  setItemQuantity /\ itemQuantityValue <- useState "1"

  -- Payment information
  setPaymentMethod /\ paymentMethodValue <- useState Cash
  setPaymentAmount /\ paymentAmountValue <- useState ""
  setTenderedAmount /\ tenderedAmountValue <- useState ""

  -- UI state
  setStatusMessage /\ statusMessageValue <- useState ""
  setIsProcessing /\ isProcessingValue <- useState false
  setActiveCategory /\ activeCategoryValue <- useState "All Items"
  setNumpadValue /\ numpadValueValue <- useState ""

  -- Function to update items from inventory selector
  let
    handleUpdateItems :: Array TransactionItem -> Effect Unit
    handleUpdateItems newItems = do
      -- Calculate totals from new items
      let
        calcTotals = foldl
          ( \acc (TransactionItem item) ->
              { subtotal: acc.subtotal + (toDiscrete item.subtotal)
              , tax: acc.tax +
                  ( foldl (\taxAcc tax -> taxAcc + (toDiscrete tax.amount))
                      (Discrete 0)
                      item.taxes
                  )
              , total: acc.total + (toDiscrete item.total)
              }
          )
          { subtotal: Discrete 0, tax: Discrete 0, total: Discrete 0 }
          newItems

      -- Update transaction state
      setItems newItems
      setSubtotal calcTotals.subtotal
      setTaxTotal calcTotals.tax
      setTotal calcTotals.total
      setStatusMessage "Transaction items updated"

  D.div
    [ DA.klass_ "tx-main-container"
    , DL.load_ \_ -> do
        liftEffect $ Console.log "Transaction component loading"

        void $ launchAff do
          employeeId <- liftEffect genUUID
          registerId <- liftEffect genUUID
          locationId <- liftEffect genUUID

          liftEffect do
            setEmployee (show employeeId)
            setRegisterId (show registerId)
            setLocationId (show locationId)

        void $ launchAff do
          result <- readInventory
          liftEffect case result of
            Right (InventoryData inventory@(Inventory items)) -> do
              Console.log $ "Loaded " <> show (length items) <>
                " inventory items"
              setInventory inventory
              setStatusMessage ""
            Right (Message msg) -> do
              Console.error $ "API Message: " <> msg
              setStatusMessage $ "Error: " <> msg
            Left err -> do
              Console.error $ "Failed to load inventory: " <> err
              setStatusMessage $ "Error loading inventory: " <> err
    ]
    [
      -- Content area with cart and inventory
      D.div
        [ DA.klass_ "tx-content-area" ]
        [
          -- Cart container
          D.div
            [ DA.klass_ "tx-cart-container" ]
            [
              -- Cart header with column titles
              D.div
                [ DA.klass_ "tx-cart-header" ]
                [ D.div
                    [ DA.klass_ "tx-item-details" ]
                    [ D.div [ DA.klass_ "tx-item-quantity" ] [ text_ "Qty" ]
                    , D.div [ DA.klass_ "tx-item-name" ] [ text_ "Item" ]
                    ]
                , D.div [ DA.klass_ "tx-item-price" ] [ text_ "Price" ]
                , D.div [ DA.klass_ "tx-item-total" ] [ text_ "Total" ]
                , D.div [ DA.klass_ "tx-item-actions" ] [ text_ "" ]
                ]
            ,
              -- Scrollable cart items area
              D.div
                [ DA.klass_ "tx-cart-items" ]
                [ itemsValue <#~> \items ->
                    if null items then
                      D.div [ DA.klass_ "tx-empty-cart" ]
                        [ text_ "No items added yet" ]
                    else
                      D.div_
                        ( items <#> \(TransactionItem item) ->
                            let
                              taxTotal = foldl
                                (\acc tax -> acc + (toDiscrete tax.amount))
                                (Discrete 0)
                                item.taxes
                              taxTotalMoney = fromDiscrete' taxTotal
                            in
                              D.div
                                [ DA.klass_ "tx-cart-item" ]
                                [ D.div
                                    [ DA.klass_ "tx-item-details" ]
                                    [ D.div [ DA.klass_ "tx-item-quantity" ]
                                        [ text_ (show item.quantity) ]
                                    , D.div [ DA.klass_ "tx-item-name" ]
                                        [ inventoryValue <#~>
                                            \(Inventory invItems) ->
                                              let
                                                itemInfo = find
                                                  ( \(MenuItem i) -> i.sku ==
                                                      item.menuItemSku
                                                  )
                                                  invItems
                                              in
                                                case itemInfo of
                                                  Just (MenuItem i) -> text_
                                                    i.name
                                                  Nothing -> text_
                                                    "Unknown Item"
                                        ]
                                    ]
                                , D.div [ DA.klass_ "tx-item-price" ]
                                    [ text_ (formatMoney' item.pricePerUnit) ]
                                , D.div [ DA.klass_ "tx-item-total" ]
                                    [ text_ (formatMoney' item.total) ]
                                , D.div
                                    [ DA.klass_ "tx-item-actions" ]
                                    [ D.button
                                        [ DA.klass_ "tx-delete-btn"
                                        , runOn DL.click $
                                            ( \currItems
                                               currSubtotal
                                               currTaxTotal
                                               currTotal -> do
                                                let
                                                  updatedItems = filter
                                                    ( \(TransactionItem i) ->
                                                        i.id /= item.id
                                                    )
                                                    currItems
                                                setSubtotal
                                                  ( currSubtotal - toDiscrete
                                                      item.subtotal
                                                  )
                                                setTaxTotal
                                                  (currTaxTotal - taxTotal)
                                                setTotal
                                                  ( currTotal - toDiscrete
                                                      item.total
                                                  )
                                                setItems updatedItems
                                                setStatusMessage
                                                  "Item removed from transaction"
                                            ) <$> itemsValue <*> subtotalValue
                                              <*> taxTotalValue
                                              <*> totalValue
                                        ]
                                        [ text_ "✕" ]
                                    ]
                                ]
                        )

                ]
            ,
              -- Cart totals area
              D.div
                [ DA.klass_ "tx-cart-totals" ]
                [ D.div
                    [ DA.klass_ "tx-total-row" ]
                    [ D.div_ [ text_ "Subtotal" ]
                    , D.div_
                        [ subtotalValue <#~> \amount -> text_
                            (formatMoney' (fromDiscrete' amount))
                        ]
                    ]
                , D.div
                    [ DA.klass_ "tx-total-row" ]
                    [ D.div_ [ text_ "Tax" ]
                    , D.div_
                        [ taxTotalValue <#~> \amount -> text_
                            (formatMoney' (fromDiscrete' amount))
                        ]
                    ]
                , D.div
                    [ DA.klass_ "tx-grand-total" ]
                    [ D.div_ [ text_ "Total" ]
                    , D.div_
                        [ totalValue <#~> \amount -> text_
                            (formatMoney' (fromDiscrete' amount))
                        ]
                    ]
                ]
            ]
        ,
          -- Inventory container - now using LiveInventoryView component 
          D.div
            [ DA.klass_ "tx-inventory-container" ]
            [ liveCart handleUpdateItems inventoryValue ]
        ]
    ,
      -- Bottom area with payment options
      D.div
        [ DA.klass_ "tx-bottom-area" ]
        [
          -- Payment panel
          D.div
            [ DA.klass_ "tx-payment-panel" ]
            [ D.div
                [ DA.klass_ "tx-payment-header" ]
                [ text_ "Payment Options" ]
            ,
              -- Payment methods
              D.div
                [ DA.klass_ "tx-payment-methods" ]
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
                    [ text_ "Credit Card" ]
                , D.div
                    [ DA.klass $ paymentMethodValue <#> \method ->
                        "payment-method" <>
                          if method == Debit then " active" else ""
                    , DL.click_ \_ -> setPaymentMethod Debit
                    ]
                    [ text_ "Debit Card" ]
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
                    [ text_ "Split" ]
                , D.div
                    [ DA.klass $ paymentMethodValue <#> \method ->
                        "payment-method" <>
                          if method == Other "" then " active" else ""
                    , DL.click_ \_ -> setPaymentMethod (Other "")
                    ]
                    [ text_ "Other" ]
                ]
            ,
              -- Payment amount inputs (only show when payment method is selected)
              D.div
                [ DA.klass_ "tx-payment-inputs mt-4" ]
                [ D.div
                    [ DA.klass_ "tx-payment-input-row" ]
                    [ D.label [ DA.klass_ "tx-payment-label" ]
                        [ text_ "Amount:" ]
                    , D.input
                        [ DA.klass_ "tx-payment-field"
                        , DA.xtype_ "text"
                        , DA.value paymentAmountValue
                        , DL.input_ \evt -> do
                            for_ (target evt >>= Input.fromEventTarget) \el ->
                              do
                                value <- Input.value el
                                setPaymentAmount value
                        ]
                        []
                    ]
                ,
                  -- Show tendered amount only for cash payments
                  paymentMethodValue <#~> \method ->
                    if method == Cash then
                      D.div
                        [ DA.klass_ "tx-payment-input-row" ]
                        [ D.label [ DA.klass_ "tx-payment-label" ]
                            [ text_ "Tendered:" ]
                        , D.input
                            [ DA.klass_ "tx-payment-field"
                            , DA.xtype_ "text"
                            , DA.value tenderedAmountValue
                            , DL.input_ \evt -> do
                                for_ (target evt >>= Input.fromEventTarget)
                                  \el -> do
                                    value <- Input.value el
                                    setTenderedAmount value
                            ]
                            []
                        ]
                    else
                      D.div_ []
                ]
            ,
              -- Display existing payments
              D.div
                [ DA.klass_ "tx-existing-payments" ]
                [ paymentsValue <#~> \payments ->
                    if null payments then D.div_ []
                    else D.div
                      [ DA.klass_ "tx-payments-container" ]
                      [ D.div [ DA.klass_ "tx-payments-header" ]
                          [ text_ "Current Payments:" ]
                      , D.div_
                          ( payments <#> \(PaymentTransaction p) ->
                              D.div
                                [ DA.klass_ "tx-payment-item" ]
                                [ D.div [ DA.klass_ "tx-payment-method" ]
                                    [ text_ (show p.method) ]
                                , D.div [ DA.klass_ "tx-payment-amount" ]
                                    [ text_ (formatMoney' p.amount) ]
                                , D.button
                                    [ DA.klass_ "tx-payment-remove"
                                    , runOn DL.click $
                                        ( \currPayments -> do
                                            let
                                              updatedPayments = filter
                                                ( \(PaymentTransaction pay) ->
                                                    pay.id /= p.id
                                                )
                                                currPayments
                                            setPayments updatedPayments
                                        ) <$> paymentsValue
                                    ]
                                    [ text_ "✕" ]
                                ]
                          )
                      ]
                ]
            ,
              -- Payment totals
              D.div
                [ DA.klass_ "tx-payment-summary" ]
                [ (Tuple <$> totalValue <*> paymentsValue) <#~>
                    \(Tuple total payments) ->
                      let
                        paymentTotal = foldl
                          ( \acc (PaymentTransaction p) ->
                              acc + toDiscrete p.amount
                          )
                          (Discrete 0)
                          payments
                        remaining = total - paymentTotal
                        paidClass =
                          if remaining <= Discrete 0 then "tx-paid"
                          else "tx-unpaid"
                      in
                        D.div
                          [ DA.klass_ "tx-payment-remaining" ]
                          [ D.div [ DA.klass_ "tx-remaining-label" ]
                              [ text_ "Remaining:" ]
                          , D.div
                              [ DA.klass_ ("tx-remaining-amount " <> paidClass)
                              ]
                              [ text_
                                  ( formatMoney'
                                      ( fromDiscrete'
                                          (max (Discrete 0) remaining)
                                      )
                                  )
                              ]
                          ]
                ]
            ,
              -- Add payment button
              D.button
                [ DA.klass_ "tx-add-payment-btn"
                , runOn DL.click $
                    ( \payAmt tenderedAmt method currPayments ->
                        do
                          case (readFloat payAmt) of
                            Nothing -> do
                              setStatusMessage "Invalid payment amount"
                            Just amount -> do
                              let
                                tenderedAmount = case readFloat tenderedAmt of
                                  Just t -> t
                                  Nothing -> amount

                                paymentAmount = fromDiscrete'
                                  (Discrete (Int.floor (amount * 100.0)))
                                paymentTendered = fromDiscrete'
                                  ( Discrete
                                      (Int.floor (tenderedAmount * 100.0))
                                  )
                                change =
                                  if
                                    toDiscrete paymentTendered > toDiscrete
                                      paymentAmount then fromDiscrete'
                                    ( toDiscrete paymentTendered - toDiscrete
                                        paymentAmount
                                    )
                                  else fromDiscrete' (Discrete 0)

                              void $ launchAff do
                                paymentId <- liftEffect genUUID
                                transactionId <- liftEffect genUUID

                                let
                                  newPayment = PaymentTransaction
                                    { id: paymentId
                                    , transactionId: transactionId
                                    , method: method
                                    , amount: paymentAmount
                                    , tendered: paymentTendered
                                    , change: change
                                    , reference: Nothing
                                    , approved: true
                                    , authorizationCode: Nothing
                                    }

                                liftEffect do
                                  setPayments (newPayment : currPayments)
                                  setPaymentAmount ""
                                  setTenderedAmount ""
                                  setStatusMessage "Payment added"
                    ) <$> paymentAmountValue <*> tenderedAmountValue
                      <*> paymentMethodValue
                      <*> paymentsValue
                ]
                [ text_ "Add Payment" ]
            ,
              -- Payment action buttons
              D.div
                [ DA.klass_ "tx-payment-actions" ]
                [ D.button
                    [ DA.klass_ "tx-cancel-btn"
                    , DL.click_ \_ -> do
                        setItems []
                        setPayments []
                        setSubtotal (Discrete 0)
                        setDiscountTotal (Discrete 0)
                        setTaxTotal (Discrete 0)
                        setTotal (Discrete 0)
                        setStatusMessage "Transaction cleared"
                    ]
                    [ text_ "Cancel Sale" ]
                , D.button
                    [ DA.klass_ "tx-checkout-btn"
                    , DA.disabled $ isProcessingValue <#> \isProcessing ->
                        if isProcessing then "true" else ""
                    , runOn DL.click $
                        ( \currItems
                           currPayments
                           currTotal
                           empId
                           regId
                           locId
                           discTotal
                           taxTotal ->
                            do
                              if null currItems then do
                                setStatusMessage
                                  "Cannot complete: No items in transaction"
                              else do
                                let
                                  paymentTotal = foldl
                                    ( \acc (PaymentTransaction p) ->
                                        acc + toDiscrete p.amount
                                    )
                                    (Discrete 0)
                                    currPayments
                                if paymentTotal < currTotal then do
                                  setStatusMessage
                                    "Cannot complete: Payment amount is insufficient"
                                else do
                                  setIsProcessing true
                                  setStatusMessage "Processing transaction..."

                                  void $ launchAff do
                                    transactionId <- liftEffect genUUID
                                    currentTime <- liftEffect now

                                    let
                                      curTime = toDateTime currentTime
                                      updatedItems = map
                                        ( \(TransactionItem item) ->
                                            TransactionItem
                                              ( item
                                                  { transactionId =
                                                      transactionId
                                                  }
                                              )
                                        )
                                        currItems

                                      updatedPayments = map
                                        ( \(PaymentTransaction payment) ->
                                            PaymentTransaction
                                              ( payment
                                                  { transactionId =
                                                      transactionId
                                                  }
                                              )
                                        )
                                        currPayments

                                      employeeUUID = parseUUID empId
                                      registerUUID = parseUUID regId
                                      locationUUID = parseUUID locId

                                    case
                                      Tuple (Tuple employeeUUID registerUUID)
                                        locationUUID
                                      of
                                      Tuple (Tuple (Just empId') (Just regId'))
                                        (Just locId') -> do
                                        liftEffect $ Console.log $
                                          "Creating transaction with ID: " <>
                                            show transactionId

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
                                            , subtotal: fromDiscrete'
                                                ( currTotal - taxTotal +
                                                    discTotal
                                                )
                                            , discountTotal: fromDiscrete'
                                                discTotal
                                            , taxTotal: fromDiscrete' taxTotal
                                            , total: fromDiscrete' currTotal
                                            , transactionType: Sale
                                            , isVoided: false
                                            , voidReason: Nothing
                                            , isRefunded: false
                                            , refundReason: Nothing
                                            , referenceTransactionId: Nothing
                                            , notes: Nothing
                                            }

                                        result <- API.createTransaction
                                          transaction

                                        liftEffect case result of
                                          Right completedTx -> do
                                            setItems []
                                            setPayments []
                                            setSubtotal (Discrete 0)
                                            setDiscountTotal (Discrete 0)
                                            setTaxTotal (Discrete 0)
                                            setTotal (Discrete 0)
                                            setStatusMessage
                                              "Transaction completed successfully"
                                          Left err -> do
                                            setStatusMessage $
                                              "Error completing transaction: "
                                                <> err

                                      _ -> liftEffect $ setStatusMessage
                                        "Invalid employee, register or location ID"

                                    liftEffect $ setIsProcessing false
                        ) <$> itemsValue <*> paymentsValue <*> totalValue
                          <*> employeeValue
                          <*> registerIdValue
                          <*> locationIdValue
                          <*> discountTotalValue
                          <*> taxTotalValue
                    ]
                    [ totalValue <#~> \totalVal ->
                        text_
                          ( "Process Payment " <> formatMoney'
                              (fromDiscrete' totalVal)
                          )
                    ]
                ]
            ]
        ]
    ,
      -- Status message (placed outside any other container as a floating element)
      statusMessageValue <#~> \msg ->
        if msg == "" then D.div_ []
        else D.div
          [ DA.klass_ "tx-status-message" ]
          [ text_ msg ]
    ]

-- -- CSS styles for the transaction component
-- styles :: String
-- styles = """
-- .tx-main-container {
--   display: flex;
--   flex-direction: column;
--   height: 100vh;
--   font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
-- }

-- .tx-content-area {
--   display: flex;
--   flex: 1;
--   overflow: hidden;
-- }

-- .tx-cart-container {
--   flex: 2;
--   display: flex;
--   flex-direction: column;
--   border-right: 1px solid #ddd;
--   overflow: hidden;
-- }

-- .tx-cart-header {
--   display: flex;
--   padding: 0.75rem;
--   font-weight: bold;
--   font-size: 1.1rem;
--   margin-top: 0.5rem;
--   padding-top: 0.5rem;
--   border-top: 1px solid #ddd;
-- }

-- /* Inventory Section */
-- .tx-inventory-container {
--   flex: 3;
--   display: flex;
--   flex-direction: column;
--   overflow: hidden;
-- }

-- /* Payment Section */
-- .tx-bottom-area {
--   display: flex;
--   border-top: 1px solid #ddd;
--   min-height: 250px; /* Ensure enough space for payment panel */
-- }

-- .tx-payment-panel {
--   flex: 1;
--   padding: 1rem;
--   background-color: #f9f9f9;
-- }

-- .tx-payment-header {
--   font-weight: bold;
--   margin-bottom: 1rem;
--   font-size: 1.1rem;
-- }

-- .tx-payment-methods {
--   display: flex;
--   flex-wrap: wrap;
--   gap: 0.5rem;
--   margin-bottom: 1rem;
-- }

-- .payment-method {
--   padding: 0.5rem 0.75rem;
--   background-color: #eee;
--   border: 1px solid #ddd;
--   border-radius: 4px;
--   cursor: pointer;
--   transition: all 0.2s ease;
-- }

-- .payment-method:hover {
--   background-color: #e0e0e0;
-- }

-- .payment-method.active {
--   background-color: #3498db;
--   color: white;
--   border-color: #2980b9;
-- }

-- .tx-payment-input-row {
--   display: flex;
--   align-items: center;
--   margin-bottom: 0.5rem;
-- }

-- .tx-payment-label {
--   width: 80px;
--   font-weight: 500;
-- }

-- .tx-payment-field {
--   flex: 1;
--   padding: 0.5rem;
--   border: 1px solid #ddd;
--   border-radius: 4px;
--   font-size: 1rem;
-- }

-- .tx-existing-payments {
--   margin-top: 1rem;
-- }

-- .tx-payments-container {
--   border-top: 1px solid #ddd;
--   padding-top: 0.5rem;
-- }

-- .tx-payments-header {
--   font-weight: 600;
--   margin-bottom: 0.5rem;
-- }

-- .tx-payment-item {
--   display: flex;
--   align-items: center;
--   padding: 0.25rem 0;
-- }

-- .tx-payment-method {
--   flex: 1;
-- }

-- .tx-payment-amount {
--   flex: 1;
--   text-align: right;
--   font-weight: 500;
-- }

-- .tx-payment-remove {
--   margin-left: 0.5rem;
--   color: #e74c3c;
--   background: none;
--   border: none;
--   cursor: pointer;
--   font-weight: bold;
-- }

-- .tx-payment-summary {
--   margin: 1rem 0;
--   padding-top: 0.5rem;
--   border-top: 1px solid #ddd;
-- }

-- .tx-payment-remaining {
--   display: flex;
--   justify-content: space-between;
--   font-weight: bold;
--   font-size: 1.1rem;
-- }

-- .tx-remaining-label {
--   font-weight: 600;
-- }

-- .tx-remaining-amount.tx-paid {
--   color: #2ecc71;
-- }

-- .tx-remaining-amount.tx-unpaid {
--   color: #e74c3c;
-- }

-- .tx-add-payment-btn {
--   width: 100%;
--   padding: 0.75rem;
--   background-color: #3498db;
--   color: white;
--   border: none;
--   border-radius: 4px;
--   margin: 1rem 0;
--   cursor: pointer;
--   font-weight: 600;
--   transition: background-color 0.2s;
-- }

-- .tx-add-payment-btn:hover {
--   background-color: #2980b9;
-- }

-- .tx-payment-actions {
--   display: flex;
--   gap: 0.5rem;
-- }

-- .tx-cancel-btn {
--   flex: 1;
--   padding: 0.75rem;
--   background-color: #e74c3c;
--   color: white;
--   border: none;
--   border-radius: 4px;
--   font-weight: bold;
--   cursor: pointer;
--   transition: background-color 0.2s;
-- }

-- .tx-cancel-btn:hover {
--   background-color: #c0392b;
-- }

-- .tx-checkout-btn {
--   flex: 2;
--   padding: 0.75rem;
--   background-color: #2ecc71;
--   color: white;
--   border: none;
--   border-radius: 4px;
--   font-weight: bold;
--   cursor: pointer;
--   transition: background-color 0.2s;
-- }

-- .tx-checkout-btn:hover {
--   background-color: #27ae60;
-- }

-- .tx-checkout-btn:disabled {
--   background-color: #95a5a6;
--   cursor: not-allowed;
-- }

-- /* Status Message */
-- .tx-status-message {
--   position: fixed;
--   bottom: 1rem;
--   right: 1rem;
--   padding: 0.75rem 1.5rem;
--   background-color: #2ecc71;
--   color: white;
--   border-radius: 4px;
--   box-shadow: 0 2px 5px rgba(0,0,0,0.2);
--   animation: fadeOut 3s forwards;
--   animation-delay: 2s;
--   z-index: 100;
-- }

-- @keyframes fadeOut {
--   from { opacity: 1; }
--   to { opacity: 0; visibility: hidden; }
-- }
--   background-color: #f5f5f5;
--   border-bottom: 1px solid #ddd;
-- }

-- .tx-cart-items {
--   flex: 1;
--   overflow-y: auto;
--   padding: 0 0.5rem;
-- }

-- .tx-empty-cart {
--   padding: 2rem;
--   text-align: center;
--   color: #95a5a6;
-- }

-- .tx-cart-item {
--   display: flex;
--   padding: 0.5rem;
--   border-bottom: 1px solid #eee;
--   align-items: center;
-- }

-- .tx-item-details {
--   flex: 3;
--   display: flex;
-- }

-- .tx-item-quantity {
--   min-width: 40px;
--   text-align: center;
--   font-weight: 500;
-- }

-- .tx-item-name {
--   margin-left: 0.5rem;
-- }

-- .tx-item-price {
--   flex: 1;
--   text-align: right;
-- }

-- .tx-item-total {
--   flex: 1;
--   text-align: right;
-- }

-- .tx-item-actions {
--   flex: 1;
--   display: flex;
--   justify-content: center;
-- }

-- .tx-delete-btn {
--   background-color: #e74c3c;
--   color: white;
--   border: none;
--   border-radius: 50%;
--   width: 24px;
--   height: 24px;
--   display: flex;
--   align-items: center;
--   justify-content: center;
--   cursor: pointer;
-- }

-- .tx-delete-btn:hover {
--   background-color: #c0392b;
-- }

-- .tx-cart-totals {
--   padding: 1rem;
--   background-color: #f9f9f9;
--   border-top: 1px solid #ddd;
-- }

-- .tx-total-row {
--   display: flex;
--   justify-content: space-between;
--   margin-bottom: 0.5rem;
-- }

-- .tx-grand-total {
--   display: flex;
--   justify-content: space-between;
--   font-weight: bold;