module Cheeblr.UI.Transaction.TransactionPage where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.Transaction as TxnAPI
import Cheeblr.Core.Cart (CartItem, calculateTotals, emptyTotals)
import Cheeblr.Core.Product (Product(..), ProductList)
import Cheeblr.Core.Tax (defaultTaxRules)
import Cheeblr.UI.Inventory.Browser (inventoryBrowser)
import Cheeblr.UI.Transaction.CartView (cartView)
import Cheeblr.UI.Transaction.CartManager (CartHandle, apiCartBackend, canAdd, newCartHandle)
import Cheeblr.UI.Transaction.PaymentForm (PaymentEntry, paymentForm)
import Data.Array (snoc)
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Effect.Unsafe (unsafePerformEffect)
import FRP.Poll (Poll)
import Types.UUID (UUID, genUUID)

-- | Main transaction page entry point.
-- | CartHandle state persists across re-renders via Ref.
-- | Handle is lazily initialized on first product add.
transactionPage
  :: Ref AuthContext
  -> Poll ProductList
  -> Nut
transactionPage authRef inventoryPoll =
  let
    -- Persistent mutable state created once per component mount
    handleRef :: Ref (Maybe { handle :: CartHandle, txnId :: UUID })
    handleRef = unsafePerformEffect (Ref.new Nothing)

    paymentsRef :: Ref (Array (Discrete USD))
    paymentsRef = unsafePerformEffect (Ref.new [])
  in
    transactionPageInner authRef inventoryPoll handleRef paymentsRef

transactionPageInner
  :: Ref AuthContext
  -> Poll ProductList
  -> Ref (Maybe { handle :: CartHandle, txnId :: UUID })
  -> Ref (Array (Discrete USD))
  -> Nut
transactionPageInner authRef inventoryPoll handleRef paymentsRef = Deku.do
  setCartItems /\ cartItemsPoll <- useState ([] :: Array CartItem)
  setCartTotals /\ cartTotalsPoll <- useState emptyTotals
  setPayments /\ paymentsPoll <- useState ([] :: Array (Discrete USD))
  setStatus /\ statusPoll <- useState ""

  let
    -- Lazy init: create CartHandle on first use
    ensureHandle :: Effect { handle :: CartHandle, txnId :: UUID }
    ensureHandle = do
      existing <- Ref.read handleRef
      case existing of
        Just state -> pure state
        Nothing -> do
          txnId <- genUUID
          handle <- newCartHandle txnId (apiCartBackend authRef txnId) defaultTaxRules
          let state = { handle, txnId }
          Ref.write (Just state) handleRef
          pure state

    -- Push CartHandle state into the UI Polls
    syncCart :: CartHandle -> Effect Unit
    syncCart handle = do
      items <- handle.getItems
      setCartItems items
      setCartTotals (calculateTotals items)

    -- Product selection from browser
    onSelectProduct :: Product -> Effect Unit
    onSelectProduct product@(Product p) = do
      { handle } <- ensureHandle
      ok <- canAdd handle product 1
      if ok then do
        handle.addProduct product 1
        syncCart handle
        setStatus ""
      else
        setStatus ("Cannot add more " <> p.name <> " — insufficient stock")

    -- Remove item from cart
    onRemoveItem :: UUID -> Effect Unit
    onRemoveItem itemId = do
      mState <- Ref.read handleRef
      case mState of
        Nothing -> pure unit
        Just { handle } -> do
          handle.removeProduct itemId
          syncCart handle

    -- Clear entire cart
    onClearCart :: Effect Unit
    onClearCart = do
      mState <- Ref.read handleRef
      case mState of
        Nothing -> pure unit
        Just { handle } -> do
          handle.clear
          setCartItems []
          setCartTotals emptyTotals
          setStatus ""

    -- Add a payment entry
    onAddPayment :: PaymentEntry -> Effect Unit
    onAddPayment entry = do
      current <- Ref.read paymentsRef
      let updated = snoc current entry.amount
      Ref.write updated paymentsRef
      setPayments updated
      setStatus "Payment added"

    -- Finalize the transaction
    onFinalize :: Effect Unit
    onFinalize = do
      mState <- Ref.read handleRef
      case mState of
        Nothing -> setStatus "No active transaction"
        Just { txnId } -> do
          setStatus "Finalizing..."
          launchAff_ do
            result <- TxnAPI.finalizeTransaction authRef txnId
            liftEffect case result of
              Right _ -> do
                setStatus "Transaction complete!"
                -- Reset all state for next transaction
                setCartItems []
                setCartTotals emptyTotals
                Ref.write [] paymentsRef
                setPayments []
                Ref.write Nothing handleRef
              Left err -> do
                Console.error err
                setStatus ("Error: " <> err)

  D.div
    [ DA.klass_ "transaction-page" ]
    [
      -- Status bar
      statusPoll <#~> \msg ->
        if msg == "" then D.span_ []
        else D.div [ DA.klass_ "transaction-status" ] [ text_ msg ]

    -- Two-panel layout
    , D.div
        [ DA.klass_ "transaction-layout" ]
        [
          -- Left: product browser
          D.div
            [ DA.klass_ "transaction-left-panel" ]
            [ inventoryBrowser inventoryPoll onSelectProduct ]

        -- Right: cart + payment
        , D.div
            [ DA.klass_ "transaction-right-panel" ]
            [
              cartView cartItemsPoll cartTotalsPoll inventoryPoll
                { onRemoveItem
                , onClearCart
                , onUpdateQuantity: \_ _ -> pure unit
                }

            , paymentForm cartTotalsPoll paymentsPoll
                onAddPayment
                onFinalize
            ]
        ]

    -- New Transaction button (reset)
    , D.div
        [ DA.klass_ "transaction-actions" ]
        [ D.button
            [ DA.klass_ "btn-secondary"
            , DL.click_ \_ -> do
                mState <- Ref.read handleRef
                case mState of
                  Nothing -> pure unit
                  Just { handle } -> handle.clear
                Ref.write Nothing handleRef
                Ref.write [] paymentsRef
                setCartItems []
                setCartTotals emptyTotals
                setPayments []
                setStatus ""
            ]
            [ text_ "New Transaction" ]
        ]
    ]