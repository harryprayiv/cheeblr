module UI.Transaction.CreateTransaction where

import Prelude

import API.Inventory (fetchInventory)
import API.Request (ApiError)
import API.Request as Request
import API.Sale as SaleApi
import Config.LiveView (defaultViewConfig)
import Data.Array (null)
import Data.Either (Either(..), either)
import Data.Tuple.Nested ((/\))
import Data.Validation.Semigroup (toEither)
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Services.CurrentSale as CurrentSale
import Services.SaleActions as SaleActions
import Types.Inventory (Inventory, MenuItem(..))
import Types.Register (Register)
import Types.RemoteData (RemoteData)
import Types.Transaction (TransactionStatus(..))
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)
import UI.Form (runFormWith)
import UI.Remote (onMount, useRemote)
import UI.Transaction.ActionBar (actionBar)
import UI.Transaction.CartView (cartView)
import UI.Transaction.InventoryPicker (inventoryPicker)
import UI.Transaction.Model (Activity(..), activityLabel, finalizeBlockers)
import UI.Transaction.PaymentPanel (paymentForm, paymentPanel, paymentStyle)

formatStatus :: TransactionStatus -> String
formatStatus = case _ of
  Created    -> "Created"
  InProgress -> "In Progress"
  Completed  -> "Completed"
  Voided     -> "Voided"
  Refunded   -> "Refunded"

statusClass :: TransactionStatus -> String
statusClass = case _ of
  Created    -> "created"
  InProgress -> "in-progress"
  Completed  -> "completed"
  Voided     -> "voided"
  Refunded   -> "refunded"

-- A 409 means the backend decided against the write from the sale's current
-- state. A 404 means a sale, line or payment on screen is gone. In both
-- cases the copy of the sale on screen may be out of date.
saleIsStale :: ApiError -> Boolean
saleIsStale err = Request.isRefusal 409 err || Request.isRefusal 404 err

createTransaction
  :: RemoteData Inventory
  -> Sale.SaleTransaction
  -> Register
  -> Nut
createTransaction initialInventory initialSale register = Deku.do
  setCurrent /\ currentV <- useHot initialSale
  currentV <#~> \sale ->
    saleScreen initialInventory sale register setCurrent

-- The screen holds the sale as the backend last returned it. It never edits
-- the sale locally and computes no money.
--
-- After a refused write the backend's message is shown. When the refusal
-- says the sale on screen is stale, the sale is read again. The inventory
-- is read again after every write, accepted or refused, because a refused
-- add usually means the stock figure on screen is stale.
saleScreen
  :: RemoteData Inventory
  -> Sale.SaleTransaction
  -> Register
  -> (Sale.SaleTransaction -> Effect Unit)
  -> Nut
saleScreen initialInventory initialSale register replaceSale = Deku.do
  setSale /\ saleV <- useHot initialSale
  setActivity /\ activityV <- useHot Idle
  setMessage /\ messageV <- useHot ""
  inventory <- useRemote initialInventory $
    fetchInventory defaultViewConfig.fetchConfig defaultViewConfig.mode
  form <- runFormWith paymentStyle paymentForm

  let
    saleId = initialSale.saleId

    perform
      :: Activity
      -> String
      -> Effect Unit
      -> Aff (Either ApiError Sale.SaleTransaction)
      -> Effect Unit
    perform activity doneMessage onDone request = do
      setActivity activity
      setMessage ""
      launchAff_ do
        result <- request
        case result of
          Right sale ->
            liftEffect do
              setSale sale
              setMessage doneMessage
              onDone
          Left err -> do
            liftEffect $ setMessage ("Error: " <> Request.describe err)
            when (saleIsStale err) do
              fresh <- SaleApi.getSale saleId
              liftEffect case fresh of
                Right sale -> setSale sale
                Left _ -> pure unit
        liftEffect do
          setActivity Idle
          inventory.refresh

    addItem menuItem@(MenuItem item) quantity =
      perform AddingItem ("Added " <> item.name <> " to cart") (pure unit)
        (SaleActions.addItem saleId menuItem quantity)

    removeItem itemId =
      perform RemovingItem "Item removed" (pure unit)
        (SaleActions.removeItem itemId)

    addPayment input =
      perform AddingPayment "Payment added to transaction" form.reset
        (SaleActions.addPayment saleId input)

    removePayment paymentId =
      perform RemovingPayment "Payment removed" (pure unit)
        (SaleActions.removePayment paymentId)

    clear =
      perform Clearing "Cart cleared" form.reset
        (SaleActions.clear saleId)

    finalize =
      perform Finalizing "Transaction completed successfully" form.reset
        (SaleActions.finalize saleId)

    newSale = do
      setActivity StartingSale
      setMessage ""
      launchAff_ do
        result <- CurrentSale.startNext initialSale
        liftEffect case result of
          Right fresh -> replaceSale fresh
          Left err -> do
            setMessage ("Error: " <> Request.describe err)
            setActivity Idle

    issues =
      ( \sale result ->
          { finalize: finalizeBlockers sale
          , payment: either identity (const []) (toEither result)
          }
      )
        <$> saleV
        <*> form.result

    issueList title entries =
      if null entries then D.div_ []
      else
        D.div [ DA.klass_ "inventory-errors-container" ]
          [ D.div [ DA.klass_ "inventory-errors-header" ] [ text_ title ]
          , D.ul [ DA.klass_ "inventory-errors-list" ]
              ( entries <#> \entry ->
                  D.li [ DA.klass_ "inventory-error" ] [ text_ entry ]
              )
          ]

  D.div
    [ DA.klass_ "transaction-container"
    , onMount inventory.refresh
    ]
    [ D.div [ DA.klass_ "transaction-content" ]
        [ inventoryPicker
            { inventory
            , sale: saleV
            , activity: activityV
            , addItem
            , report: setMessage
            }

        , D.div [ DA.klass_ "cart-container" ]
            [ D.div [ DA.klass_ "cart-header" ]
                [ D.h3_ [ text_ "Current Transaction" ] ]
            , cartView
                { sale: saleV
                , inventory: inventory.value
                , activity: activityV
                , removeItem
                }
            , paymentPanel
                { form
                , sale: saleV
                , activity: activityV
                , addPayment
                , removePayment
                }
            , issues <#~> \i ->
                D.div_
                  [ issueList "Before adding a payment:" i.payment
                  , issueList "Before completing the sale:" i.finalize
                  ]
            ]
        ]

    , actionBar
        { sale: saleV
        , activity: activityV
        , clear
        , finalize
        , newSale
        }

    , D.div [ DA.klass_ "status-message" ]
        [ text $
            ( \activity message ->
                if activity == Idle then message else activityLabel activity
            )
              <$> activityV
              <*> messageV
        ]

    , D.div [ DA.klass_ "register-status active" ]
        [ D.div [ DA.klass_ "register-info" ]
            [ text_
                ( "Register: " <> register.registerName
                    <> " (#"
                    <> show (register.registerId :: UUID)
                    <> ")"
                )
            ]
        , D.div [ DA.klass_ "transaction-status" ]
            [ D.span [ DA.klass_ "status-label" ]
                [ text_ "Transaction Status: " ]
            , D.span
                [ DA.klass $ saleV <#> \sale ->
                    "status-value " <> statusClass sale.saleStatus
                ]
                [ text (saleV <#> \sale -> formatStatus sale.saleStatus) ]
            ]
        ]
    ]

