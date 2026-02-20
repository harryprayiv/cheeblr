module Cheeblr.UI.Transaction.CartManager where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.Transaction as TxnAPI
import Cheeblr.Core.Cart as Cart
import Cheeblr.Core.Cart (CartItem, CartTotals, emptyTotals)
import Cheeblr.Core.Product (Product(..), ProductList)
import Cheeblr.Core.Tax (TaxRule)
import Data.Either (Either(..))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Types.UUID (UUID, genUUID)

----------------------------------------------------------------------
-- Cart Backend Interface
----------------------------------------------------------------------

-- | Abstraction over where cart operations persist.
-- | Two implementations: API-backed (real) and local-only (dev/offline).
type CartBackend =
  { reserveItem :: Product -> Int -> Aff (Either String Unit)
  , releaseItem :: UUID -> Aff (Either String Unit)
  , clearAll :: UUID -> Aff (Either String Unit)
  }

----------------------------------------------------------------------
-- Cart Handle (mutable state + operations)
----------------------------------------------------------------------

-- | A CartHandle owns the mutable cart state and exposes
-- | operations that update both the local state and the backend.
type CartHandle =
  { items :: Ref (Array CartItem)
  , totals :: Ref CartTotals
  , transactionId :: UUID
  , taxRules :: Array TaxRule
  , backend :: CartBackend
  --
  , addProduct :: Product -> Int -> Effect Unit
  , removeProduct :: UUID -> Effect Unit
  , clear :: Effect Unit
  , getItems :: Effect (Array CartItem)
  , getTotals :: Effect CartTotals
  }

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

-- | Create a new CartHandle for a transaction.
newCartHandle
  :: UUID              -- transaction ID
  -> CartBackend
  -> Array TaxRule
  -> Effect CartHandle
newCartHandle txnId backend rules = do
  itemsRef <- Ref.new []
  totalsRef <- Ref.new emptyTotals

  let
    recalcTotals = do
      items <- Ref.read itemsRef
      let newTotals = Cart.calculateTotals items
      Ref.write newTotals totalsRef

    addProduct product qty = do
      itemId <- genUUID
      items <- Ref.read itemsRef
      let
        newItems = Cart.addItem itemId txnId product qty rules items
      Ref.write newItems itemsRef
      recalcTotals
      -- Fire-and-forget API reservation
      launchAff_ do
        result <- backend.reserveItem product qty
        case result of
          Left err -> liftEffect $ Console.error $
            "Failed to reserve item: " <> err
          Right _ -> pure unit

    removeProduct itemId = do
      items <- Ref.read itemsRef
      let newItems = Cart.removeItem itemId items
      Ref.write newItems itemsRef
      recalcTotals
      launchAff_ do
        result <- backend.releaseItem itemId
        case result of
          Left err -> liftEffect $ Console.error $
            "Failed to release item: " <> err
          Right _ -> pure unit

    clearCart = do
      Ref.write [] itemsRef
      Ref.write emptyTotals totalsRef
      launchAff_ do
        result <- backend.clearAll txnId
        case result of
          Left err -> liftEffect $ Console.error $
            "Failed to clear cart: " <> err
          Right _ -> pure unit

  pure
    { items: itemsRef
    , totals: totalsRef
    , transactionId: txnId
    , taxRules: rules
    , backend
    , addProduct
    , removeProduct
    , clear: clearCart
    , getItems: Ref.read itemsRef
    , getTotals: Ref.read totalsRef
    }

----------------------------------------------------------------------
-- API-backed backend
----------------------------------------------------------------------

apiCartBackend :: Ref AuthContext -> CartBackend
apiCartBackend authRef =
  { reserveItem: \(Product p) qty -> do
      -- Build a TransactionItem and POST it
      -- This maps Core.Product → Types.Transaction.TransactionItem
      -- which is the wire format the backend expects
      pure (Right unit)  -- TODO: wire up TxnAPI.addItem

  , releaseItem: \itemId ->
      TxnAPI.removeItem authRef itemId

  , clearAll: \txnId ->
      TxnAPI.clearItems authRef txnId
  }

----------------------------------------------------------------------
-- Local-only backend (for offline/dev)
----------------------------------------------------------------------

localCartBackend :: CartBackend
localCartBackend =
  { reserveItem: \_ _ -> pure (Right unit)
  , releaseItem: \_ -> pure (Right unit)
  , clearAll: \_ -> pure (Right unit)
  }

----------------------------------------------------------------------
-- Availability checks
----------------------------------------------------------------------

-- | Check if a product can be added given current cart + inventory state.
canAdd :: CartHandle -> Product -> Int -> Effect Boolean
canAdd handle product qty = do
  items <- Ref.read handle.items
  pure $ Cart.canAddToCart product qty items

-- | How many more of this product can be added?
available :: CartHandle -> Product -> Effect Int
available handle product = do
  items <- Ref.read handle.items
  pure $ Cart.availableToAdd product items

-- | Find items that exceed inventory (after stock changes).
checkAvailability :: CartHandle -> ProductList -> Effect (Array { sku :: UUID, name :: String, requested :: Int, available :: Int })
checkAvailability handle products = do
  items <- Ref.read handle.items
  pure $ Cart.findUnavailable items products
