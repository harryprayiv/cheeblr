module Cheeblr.Core.Cart where

import Prelude

import Cheeblr.Core.Product (Product(..), ProductList, findBySku)
import Cheeblr.Core.Tax (TaxResult, TaxRule, calculateTaxes, totalTax)
import Data.Array (filter, find, foldl, (:))
import Data.Finance.Currency (USD)
import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..))
import Types.UUID (UUID)
import Cheeblr.Core.Money (zeroCents) as Money

----------------------------------------------------------------------
-- Cart Item
----------------------------------------------------------------------

-- | A single item in the cart. This is the *pure* representation;
-- | TransactionItem (with server-assigned IDs) is the API representation.
-- | Mapping between them happens at the effect boundary.
type CartItem =
  { itemId :: UUID                     -- local or server-assigned
  , transactionId :: UUID              -- parent transaction
  , sku :: UUID                        -- product SKU
  , quantity :: Int
  , pricePerUnit :: Discrete USD
  , taxes :: Array TaxResult
  , subtotal :: Discrete USD           -- price * quantity
  , total :: Discrete USD              -- subtotal + taxes
  }

----------------------------------------------------------------------
-- Cart Totals
----------------------------------------------------------------------

type CartTotals =
  { subtotal :: Discrete USD
  , taxTotal :: Discrete USD
  , total :: Discrete USD
  , discountTotal :: Discrete USD
  }

emptyTotals :: CartTotals
emptyTotals =
  { subtotal: Money.zeroCents
  , taxTotal: Money.zeroCents
  , total: Money.zeroCents
  , discountTotal: Money.zeroCents
  }

----------------------------------------------------------------------
-- Cart State
----------------------------------------------------------------------

type Cart =
  { items :: Array CartItem
  , totals :: CartTotals
  }

emptyCart :: Cart
emptyCart = { items: [], totals: emptyTotals }

----------------------------------------------------------------------
-- Pure cart operations
----------------------------------------------------------------------

-- | Build a CartItem from a product, quantity, and tax rules.
-- | This is the single place where item-level totals are computed.
mkCartItem
  :: UUID                    -- itemId
  -> UUID                    -- transactionId
  -> Product
  -> Int                     -- quantity
  -> Array TaxRule
  -> CartItem
mkCartItem itemId transactionId (Product p) qty rules =
  let
    subtotal = p.price * Discrete qty
    taxes = calculateTaxes rules subtotal p.category
    taxAmount = totalTax taxes
  in
    { itemId
    , transactionId
    , sku: p.sku
    , quantity: qty
    , pricePerUnit: p.price
    , taxes
    , subtotal
    , total: subtotal + taxAmount
    }

-- | Recalculate totals from the current item list.
-- | This is the single source of truth for cart totals.
calculateTotals :: Array CartItem -> CartTotals
calculateTotals items =
  foldl accItem emptyTotals items
  where
  accItem :: CartTotals -> CartItem -> CartTotals
  accItem acc item =
    { subtotal: acc.subtotal + item.subtotal
    , taxTotal: acc.taxTotal + totalTax item.taxes
    , total: acc.total + item.total
    , discountTotal: acc.discountTotal   -- discounts applied separately
    }

-- | Add a product to the cart. If the SKU already exists,
-- | the quantity is merged and totals recalculated.
addItem
  :: UUID -> UUID -> Product -> Int -> Array TaxRule
  -> Array CartItem -> Array CartItem
addItem itemId txId product@(Product p) qty rules items =
  case find (\i -> i.sku == p.sku) items of
    Just existing ->
      -- Merge: rebuild the item with combined quantity
      let
        newQty = existing.quantity + qty
        merged = mkCartItem existing.itemId txId product newQty rules
      in
        map (\i -> if i.sku == p.sku then merged else i) items
    Nothing ->
      mkCartItem itemId txId product qty rules : items

-- | Remove an item from the cart by item ID.
removeItem :: UUID -> Array CartItem -> Array CartItem
removeItem itemId = filter (\i -> i.itemId /= itemId)

-- | Remove all items with a given SKU.
removeBySku :: UUID -> Array CartItem -> Array CartItem
removeBySku sku = filter (\i -> i.sku /= sku)

-- | Update quantity for an existing item. Recalculates item totals.
updateQuantity :: UUID -> Int -> Product -> Array TaxRule -> Array CartItem -> Array CartItem
updateQuantity itemId newQty product rules =
  map (\i ->
    if i.itemId == itemId
    then mkCartItem itemId i.transactionId product newQty rules
    else i
  )

-- | Clear all items.
clearItems :: Array CartItem -> Array CartItem
clearItems _ = []

----------------------------------------------------------------------
-- Inventory availability checks (pure)
----------------------------------------------------------------------

-- | Get the total quantity of a SKU currently in the cart.
cartQuantityForSku :: UUID -> Array CartItem -> Int
cartQuantityForSku sku items =
  case find (\i -> i.sku == sku) items of
    Just item -> item.quantity
    Nothing -> 0

-- | Check if adding `requestedQty` of a product is possible
-- | given current inventory and cart state.
canAddToCart :: Product -> Int -> Array CartItem -> Boolean
canAddToCart (Product p) requestedQty items =
  let
    inCart = cartQuantityForSku p.sku items
  in
    inCart + requestedQty <= p.quantity

-- | How many more of this product can be added?
availableToAdd :: Product -> Array CartItem -> Int
availableToAdd (Product p) items =
  max 0 (p.quantity - cartQuantityForSku p.sku items)

-- | Find items in the cart that exceed current inventory levels.
-- | Returns SKU and name of each problem item.
findUnavailable :: Array CartItem -> ProductList -> Array { sku :: UUID, name :: String, requested :: Int, available :: Int }
findUnavailable items products =
  items
    # filter (\item ->
        case findBySku item.sku products of
          Just (Product p) -> item.quantity > p.quantity
          Nothing -> true
      )
    # map (\item ->
        let
          info = case findBySku item.sku products of
            Just (Product p) -> { name: p.name, available: p.quantity }
            Nothing -> { name: "Unknown Item", available: 0 }
        in
          { sku: item.sku
          , name: info.name
          , requested: item.quantity
          , available: info.available
          }
      )

----------------------------------------------------------------------
-- Payment helpers (pure)
----------------------------------------------------------------------

-- | Total of all payments made so far.
totalPayments :: Array (Discrete USD) -> Discrete USD
totalPayments = foldl (+) Money.zeroCents

-- | Remaining balance to be paid.
remainingBalance :: CartTotals -> Array (Discrete USD) -> Discrete USD
remainingBalance totals payments =
  max Money.zeroCents (totals.total - totalPayments payments)

-- | Check if payments cover the total.
isFullyPaid :: CartTotals -> Array (Discrete USD) -> Boolean
isFullyPaid totals payments =
  totalPayments payments >= totals.total