module UI.Transaction.CartView
  ( CartProps
  , cartView
  ) where

import Prelude

import Data.Array (null)
import Data.Tuple (Tuple(..))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks ((<#~>))
import Effect (Effect)
import FRP.Poll (Poll)
import Types.Inventory (Inventory(..), findItemNameBySku)
import Types.Primitives.Money (SaleMoney, saleMoneyDiscrete)
import Types.Primitives.Quantity (saleQuantityCount)
import Types.RemoteData (RemoteData(..))
import Types.Transaction.Sale as Sale
import Types.UUID (UUID)
import UI.Transaction.Model (Activity, isBusy)
import Utils.Money (formatDiscretePrice)

type CartProps =
  { sale :: Poll Sale.SaleTransaction
  , inventory :: Poll (RemoteData Inventory)
  , activity :: Poll Activity
  , removeItem :: UUID -> Effect Unit
  }

money :: SaleMoney -> String
money = formatDiscretePrice <<< saleMoneyDiscrete

-- The cart lines and the totals, both read straight from the sale the
-- backend returned.
cartView :: CartProps -> Nut
cartView props =
  D.div_
    [ D.div [ DA.klass_ "cart-items" ]
        [ (Tuple <$> props.sale <*> props.inventory) <#~> \(Tuple sale inventory) ->
            if null sale.saleItems then
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
                    (map (line (known inventory)) sale.saleItems)
                ]
        ]
    , D.div [ DA.klass_ "cart-totals" ]
        [ totalRow "total-row" "Subtotal:" _.saleSubtotal
        , totalRow "total-row" "Tax:" _.saleTaxTotal
        , totalRow "total-row grand-total" "Total:" _.saleTotal
        ]
    ]
  where
  -- Item names come from the inventory. Without one, lines show the
  -- fallback name from findItemNameBySku.
  known = case _ of
    Success inventory -> inventory
    _ -> Inventory []

  busy = isBusy <$> props.activity

  line inventory item =
    D.div [ DA.klass_ "cart-item-row" ]
      [ D.div [ DA.klass_ "col item-col" ]
          [ text_ (findItemNameBySku item.itemMenuItemSku inventory) ]
      , D.div [ DA.klass_ "col qty-col" ]
          [ text_ (show (saleQuantityCount item.itemQuantity)) ]
      , D.div [ DA.klass_ "col price-col" ]
          [ text_ (money item.itemPricePerUnit) ]
      , D.div [ DA.klass_ "col total-col" ]
          [ text_ (money item.itemTotal) ]
      , D.div [ DA.klass_ "col actions-col" ]
          [ D.button
              [ DA.klass_ "remove-btn"
              , DA.disabled $ busy <#> \b -> if b then "true" else ""
              , DL.click_ \_ -> props.removeItem item.itemId
              ]
              [ text_ "✕" ]
          ]
      ]

  totalRow rowClass label field =
    D.div [ DA.klass_ rowClass ]
      [ D.div [ DA.klass_ "total-label" ] [ text_ label ]
      , D.div [ DA.klass_ "total-value" ]
          [ text (props.sale <#> \sale -> money (field sale)) ]
      ]
