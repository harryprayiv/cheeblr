module Cheeblr.UI.Transaction.TransactionPage where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.Transaction as TxnAPI
import Cheeblr.Core.Cart (CartItem, calculateTotals, emptyTotals)
import Cheeblr.Core.Product (Product(..), ProductList)
import Cheeblr.Core.Tax (defaultTaxRules)
import Cheeblr.UI.Inventory.Browser (inventoryBrowser)
import Cheeblr.UI.Transaction.CartView (cartView, CartActions)
import Cheeblr.UI.Transaction.CartManager (CartHandle, apiCartBackend, canAdd, localCartBackend, newCartHandle)
import Cheeblr.UI.Transaction.PaymentForm (PaymentEntry, paymentForm)
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Effect.Ref as Ref
import FRP.Poll (Poll)
import Types.UUID (UUID, genUUID)

----------------------------------------------------------------------
-- Transaction Page (replaces CreateTransaction.purs)
----------------------------------------------------------------------

-- | The main transaction creation page.
-- | Composed of three subcomponents:
-- |   1. Inventory browser (left panel)
-- |   2. Cart view (right panel, top)
-- |   3. Payment form (right panel, bottom)
-- |
-- | State flow:
-- |   Browser --[onSelect]--> CartManager --[Ref updates]--> CartView
-- |   CartView --[remove/clear]--> CartManager
-- |   PaymentForm --[onAddPayment]--> state
-- |   PaymentForm --[onFinalize]--> API
transactionPage
  :: Ref AuthContext
  -> Poll ProductList
  -> Nut
transactionPage authRef inventoryPoll = Deku.do
  -- Cart state (reactive signals for the UI)
  setCartItems /\ cartItemsPoll <- useState ([] :: Array CartItem)
  setCartTotals /\ cartTotalsPoll <- useState emptyTotals
  setPayments /\ paymentsPoll <- useState ([] :: Array (Discrete USD))

  -- Status
  setStatus /\ statusPoll <- useState ""
  setTransactionId /\ transactionIdPoll <- useState (Nothing :: Maybe UUID)

  let
    -- Sync cart state from handle to polls
    syncCart :: CartHandle -> Effect Unit
    syncCart handle = do
      items <- handle.getItems
      totals <- handle.getTotals
      setCartItems items
      setCartTotals (calculateTotals items)

    -- Add product to cart
    handleSelectProduct :: CartHandle -> Product -> Effect Unit
    handleSelectProduct handle product@(Product p) = do
      ok <- canAdd handle product 1
      if ok then do
        handle.addProduct product 1
        syncCart handle
        setStatus ""
      else
        setStatus ("Cannot add more " <> p.name <> " — insufficient stock")

    -- Remove item from cart
    handleRemoveItem :: CartHandle -> UUID -> Effect Unit
    handleRemoveItem handle itemId = do
      handle.removeProduct itemId
      syncCart handle

    -- Clear cart
    handleClearCart :: CartHandle -> Effect Unit
    handleClearCart handle = do
      handle.clear
      setCartItems []
      setCartTotals emptyTotals
      setStatus ""

    -- Update quantity (placeholder)
    handleUpdateQty :: CartHandle -> UUID -> Int -> Effect Unit
    handleUpdateQty handle itemId qty = do
      -- For now, remove and re-add. A proper implementation
      -- would use Cart.updateQuantity.
      pure unit

    -- Add payment
    handleAddPayment :: PaymentEntry -> Effect Unit
    handleAddPayment entry = do
      -- TODO: call TxnAPI.addPayment, update paymentsPoll
      setStatus "Payment added"

    -- Finalize transaction
    handleFinalize :: Maybe UUID -> Effect Unit
    handleFinalize mTxnId = case mTxnId of
      Nothing -> setStatus "No active transaction"
      Just txnId -> do
        setStatus "Finalizing..."
        launchAff_ do
          result <- TxnAPI.finalizeTransaction authRef txnId
          liftEffect case result of
            Right _ -> do
              setStatus "Transaction complete!"
              -- Reset cart state
              setCartItems []
              setCartTotals emptyTotals
              setPayments []
              setTransactionId Nothing
            Left err -> do
              Console.error err
              setStatus ("Error: " <> err)

  -- Initialize cart handle on load
  -- In practice, create the transaction via API first,
  -- then create the handle with the returned transaction ID.
  -- Simplified here: we generate a local UUID.

  D.div
    [ DA.klass_ "transaction-page" ]
    [ -- Status bar
      statusPoll <#~> \msg ->
        if msg == "" then D.span_ []
        else D.div [ DA.klass_ "transaction-status" ] [ text_ msg ]

    -- Two-panel layout
    , D.div
        [ DA.klass_ "transaction-layout" ]
        [ -- Left: Inventory Browser
          D.div
            [ DA.klass_ "transaction-left-panel" ]
            [ inventoryBrowser inventoryPoll
                (\product -> do
                  -- Create handle lazily on first add
                  -- A real implementation would maintain the handle in a Ref
                  txnId <- genUUID
                  handle <- newCartHandle txnId localCartBackend defaultTaxRules
                  handleSelectProduct handle product
                )
            ]

        -- Right: Cart + Payment
        , D.div
            [ DA.klass_ "transaction-right-panel" ]
            [ -- Cart
              cartView
                cartItemsPoll
                cartTotalsPoll
                inventoryPoll
                { onRemoveItem: \itemId -> do
                    -- Would need handle ref here
                    setStatus "Remove not yet wired"
                , onClearCart: do
                    setCartItems []
                    setCartTotals emptyTotals
                    setStatus "Cart cleared"
                , onUpdateQuantity: \_ _ -> pure unit
                }

            -- Payment
            , paymentForm
                cartTotalsPoll
                paymentsPoll
                handleAddPayment
                (handleFinalize Nothing)  -- TODO: wire transactionId
            ]
        ]
    ]

----------------------------------------------------------------------
-- Stateful version (with persistent CartHandle)
----------------------------------------------------------------------

-- | A more complete version that maintains the CartHandle in a Ref.
-- | Call `mkTransactionPage` in Effect to get the Nut.
mkTransactionPage
  :: Ref AuthContext
  -> Poll ProductList
  -> Effect Nut
mkTransactionPage authRef inventoryPoll = do
  -- Create transaction ID upfront
  txnId <- genUUID
  handleRef <- do
    handle <- newCartHandle txnId (apiCartBackend authRef) defaultTaxRules
    Ref.new handle

  pure $ transactionPageStateful authRef inventoryPoll handleRef txnId

transactionPageStateful
  :: Ref AuthContext
  -> Poll ProductList
  -> Ref CartHandle
  -> UUID
  -> Nut
transactionPageStateful authRef inventoryPoll handleRef txnId = Deku.do
  setCartItems /\ cartItemsPoll <- useState ([] :: Array CartItem)
  setCartTotals /\ cartTotalsPoll <- useState emptyTotals
  setPayments /\ paymentsPoll <- useState ([] :: Array (Discrete USD))
  setStatus /\ statusPoll <- useState ""

  let
    withHandle :: (CartHandle -> Effect Unit) -> Effect Unit
    withHandle f = do
      handle <- Ref.read handleRef
      f handle

    syncUI :: Effect Unit
    syncUI = withHandle \handle -> do
      items <- handle.getItems
      setCartItems items
      setCartTotals (calculateTotals items)

    onSelectProduct product@(Product p) = withHandle \handle -> do
      ok <- canAdd handle product 1
      if ok then do
        handle.addProduct product 1
        syncUI
        setStatus ""
      else
        setStatus ("Insufficient stock: " <> p.name)

    onRemoveItem itemId = withHandle \handle -> do
      handle.removeProduct itemId
      syncUI

    onClearCart = withHandle \handle -> do
      handle.clear
      setCartItems []
      setCartTotals emptyTotals

    cartActions :: CartActions
    cartActions =
      { onRemoveItem
      , onClearCart
      , onUpdateQuantity: \_ _ -> pure unit
      }

    onFinalize = do
      setStatus "Finalizing..."
      launchAff_ do
        result <- TxnAPI.finalizeTransaction authRef txnId
        liftEffect case result of
          Right _ -> do
            setStatus "Transaction complete!"
            setCartItems []
            setCartTotals emptyTotals
            setPayments []
          Left err -> setStatus ("Error: " <> err)

  D.div
    [ DA.klass_ "transaction-page" ]
    [ statusPoll <#~> \msg ->
        if msg == "" then D.span_ []
        else D.div [ DA.klass_ "transaction-status" ] [ text_ msg ]

    , D.div
        [ DA.klass_ "transaction-layout" ]
        [ D.div [ DA.klass_ "transaction-left-panel" ]
            [ inventoryBrowser inventoryPoll onSelectProduct ]

        , D.div [ DA.klass_ "transaction-right-panel" ]
            [ cartView cartItemsPoll cartTotalsPoll inventoryPoll cartActions
            , paymentForm cartTotalsPoll paymentsPoll
                (\_ -> pure unit)  -- TODO: wire payment API
                onFinalize
            ]
        ]
    ]
