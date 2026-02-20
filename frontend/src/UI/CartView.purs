module Cheeblr.UI.Transaction.CartView where

import Prelude

import Cheeblr.Core.Cart (CartItem, CartTotals)
import Cheeblr.Core.Money (formatCurrency, zeroCents)
import Cheeblr.Core.Product (ProductList, findNameBySku)
import Data.Array (null)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks ((<#~>))
import Effect (Effect)
import FRP.Poll (Poll)
import Types.UUID (UUID)

----------------------------------------------------------------------
-- Cart Actions (callbacks from parent)
----------------------------------------------------------------------

type CartActions =
  { onRemoveItem :: UUID -> Effect Unit       -- remove by item ID
  , onClearCart :: Effect Unit
  , onUpdateQuantity :: UUID -> Int -> Effect Unit
  }

----------------------------------------------------------------------
-- Cart View Component
----------------------------------------------------------------------

-- | Display the current cart contents with item details and totals.
cartView
  :: Poll (Array CartItem)
  -> Poll CartTotals
  -> Poll ProductList       -- for looking up product names
  -> CartActions
  -> Nut
cartView itemsPoll totalsPoll productsPoll actions =
  D.div
    [ DA.klass_ "cart-view" ]
    [ D.div
        [ DA.klass_ "cart-header" ]
        [ D.h3_ [ text_ "Cart" ]
        , D.button
            [ DA.klass_ "cart-clear-btn"
            , DL.click_ \_ -> actions.onClearCart
            ]
            [ text_ "Clear" ]
        ]

    -- Cart items (reactive)
    , ((/\) <$> itemsPoll <*> productsPoll) <#~> \(items /\ products) ->
        if null items then
          D.div
            [ DA.klass_ "cart-empty" ]
            [ text_ "Cart is empty" ]
        else
          D.div
            [ DA.klass_ "cart-items" ]
            (items <#> cartItemRow products actions)

    -- Totals (reactive)
    , totalsPoll <#~> \totals ->
        cartTotalsDisplay totals
    ]

----------------------------------------------------------------------
-- Cart Item Row
----------------------------------------------------------------------

cartItemRow :: ProductList -> CartActions -> CartItem -> Nut
cartItemRow products actions item =
  D.div
    [ DA.klass_ "cart-item-row" ]
    [ D.div
        [ DA.klass_ "cart-item-info" ]
        [ D.span [ DA.klass_ "cart-item-name" ]
            [ text_ (findNameBySku item.sku products) ]
        , D.span [ DA.klass_ "cart-item-qty" ]
            [ text_ ("× " <> show item.quantity) ]
        ]
    , D.div
        [ DA.klass_ "cart-item-price" ]
        [ D.span [ DA.klass_ "cart-item-subtotal" ]
            [ text_ (formatCurrency item.subtotal) ]
        ]
    , D.button
        [ DA.klass_ "cart-item-remove"
        , DL.click_ \_ -> actions.onRemoveItem item.itemId
        ]
        [ text_ "✕" ]
    ]

----------------------------------------------------------------------
-- Totals Display
----------------------------------------------------------------------

cartTotalsDisplay :: CartTotals -> Nut
cartTotalsDisplay totals =
  D.div
    [ DA.klass_ "cart-totals" ]
    [ totalsRow "Subtotal" (formatCurrency totals.subtotal)
    , totalsRow "Tax" (formatCurrency totals.taxTotal)
    , if totals.discountTotal /= zeroCents then
        totalsRow "Discount" ("-" <> formatCurrency totals.discountTotal)
      else
        D.span_ []
    , D.div
        [ DA.klass_ "cart-total-row cart-total-final" ]
        [ D.span_ [ text_ "Total" ]
        , D.span [ DA.klass_ "cart-total-amount" ]
            [ text_ (formatCurrency totals.total) ]
        ]
    ]

totalsRow :: String -> String -> Nut
totalsRow label amount =
  D.div
    [ DA.klass_ "cart-total-row" ]
    [ D.span_ [ text_ label ]
    , D.span_ [ text_ amount ]
    ]
