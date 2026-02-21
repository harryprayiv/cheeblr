module Cheeblr.UI.Transaction.CartManager where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.Transaction as TxnAPI
import Cheeblr.Core.Cart as Cart
import Cheeblr.Core.Cart (CartItem, CartTotals, emptyTotals)
import Cheeblr.Core.Money (toMoney)
import Cheeblr.Core.Product (Product(..), ProductList)
import Cheeblr.Core.Tax (TaxRule)
import Data.Either (Either(..))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Int (toNumber)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Types.Transaction (TransactionItem(..))
import Types.UUID (UUID, genUUID)

type CartBackend =
  { reserveItem :: Product -> Int -> Aff (Either String Unit)
  , releaseItem :: UUID -> Aff (Either String Unit)
  , clearAll :: UUID -> Aff (Either String Unit)
  }

type CartHandle =
  { items :: Ref (Array CartItem)
  , totals :: Ref CartTotals
  , transactionId :: UUID
  , taxRules :: Array TaxRule
  , backend :: CartBackend

  , addProduct :: Product -> Int -> Effect Unit
  , removeProduct :: UUID -> Effect Unit
  , clear :: Effect Unit
  , getItems :: Effect (Array CartItem)
  , getTotals :: Effect CartTotals
  }

newCartHandle
  :: UUID
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

      -- Fire-and-forget API sync
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

-- | API-backed cart that syncs with the transaction server.
-- | Takes the authRef and the transaction ID to scope API calls.
apiCartBackend :: Ref AuthContext -> UUID -> CartBackend
apiCartBackend authRef txnId =
  { reserveItem: \(Product p) qty -> do
      itemId <- liftEffect genUUID
      let
        subtotal = p.price * Discrete qty
        item = TransactionItem
          { id: itemId
          , transactionId: txnId
          , menuItemSku: p.sku
          , quantity: toNumber qty
          , pricePerUnit: toMoney p.price
          , discounts: []
          , taxes: []   -- server calculates taxes
          , subtotal: toMoney subtotal
          , total: toMoney subtotal  -- server recalculates with tax
          }
      void <$> TxnAPI.addItem authRef item

  , releaseItem: \itemId ->
      TxnAPI.removeItem authRef itemId

  , clearAll: \txId ->
      TxnAPI.clearItems authRef txId
  }

-- | Local-only cart backend (no API calls).
-- | Useful for offline mode or testing.
localCartBackend :: CartBackend
localCartBackend =
  { reserveItem: \_ _ -> pure (Right unit)
  , releaseItem: \_ -> pure (Right unit)
  , clearAll: \_ -> pure (Right unit)
  }

canAdd :: CartHandle -> Product -> Int -> Effect Boolean
canAdd handle product qty = do
  items <- Ref.read handle.items
  pure $ Cart.canAddToCart product qty items

available :: CartHandle -> Product -> Effect Int
available handle product = do
  items <- Ref.read handle.items
  pure $ Cart.availableToAdd product items

checkAvailability :: CartHandle -> ProductList -> Effect (Array { sku :: UUID, name :: String, requested :: Int, available :: Int })
checkAvailability handle products = do
  items <- Ref.read handle.items
  pure $ Cart.findUnavailable items products