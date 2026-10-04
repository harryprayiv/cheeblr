module UI.Transaction.InventoryPicker
  ( PickerProps
  , inventoryPicker
  ) where

import Prelude

import Data.Array (null)
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Tuple.Nested ((/\))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect (Effect)
import FRP.Poll (Poll)
import Types.Inventory (Inventory, ItemCategory, MenuItem(..))
import Types.RemoteData (RemoteData(..))
import Types.Transaction.Sale as Sale
import UI.Remote (Remote, standardView, viewRemote)
import UI.Transaction.Model (Activity, addBlocker, categoriesIn, isBusy, quantityInCart, visibleItems)
import Utils.Formatting (formatCentsToDollars)
import Web.Event.Event (target)
import Web.HTML.HTMLInputElement (fromEventTarget, value) as Input

type PickerProps =
  { inventory :: Remote Inventory
  , sale :: Poll Sale.SaleTransaction
  , activity :: Poll Activity
  , addItem :: MenuItem -> Int -> Effect Unit
  , report :: String -> Effect Unit
  }

-- The left side of the transaction screen: category tabs, search, quantity
-- and the inventory table. The table is rebuilt only when the inventory or a
-- filter changes. Cart counts and button states inside each row follow the
-- sale and activity Polls without rebuilding the row.
inventoryPicker :: PickerProps -> Nut
inventoryPicker props = Deku.do
  setSearch /\ searchV <- useHot ""
  setCategory /\ categoryV <- useHot (Nothing :: Maybe ItemCategory)
  setQuantity /\ quantityV <- useHot 1

  let
    visible =
      ( \inventory search category ->
          visibleItems { search, category } <$> inventory
      )
        <$> props.inventory.value
        <*> searchV
        <*> categoryV

    categoryTab label category =
      D.div
        [ DA.klass $ categoryV <#> \active ->
            "category-tab" <> if active == category then " active" else ""
        , DL.click_ \_ -> setCategory category
        ]
        [ text_ label ]

    row menuItem@(MenuItem record) =
      let
        outOfStock = record.quantity <= 0
        inCart = props.sale <#> \sale ->
          quantityInCart record.sku sale.saleItems
        disabled = props.activity <#> \activity ->
          outOfStock || isBusy activity
      in
        D.div
          [ DA.klass_ $
              "inventory-row " <> if outOfStock then "out-of-stock" else ""
          ]
          [ D.div [ DA.klass_ "col name-col" ] [ text_ record.name ]
          , D.div [ DA.klass_ "col brand-col" ] [ text_ record.brand ]
          , D.div [ DA.klass_ "col category-col" ]
              [ text_ (show record.category <> " - " <> record.subcategory) ]
          , D.div [ DA.klass_ "col price-col" ]
              [ text_ ("$" <> formatCentsToDollars (unwrap record.price)) ]
          , D.div
              [ DA.klass_ $
                  "col stock-col " <>
                    if record.quantity <= 5 then "low-stock" else ""
              ]
              [ text_ (show record.quantity) ]
          , D.div [ DA.klass_ "col actions-col" ]
              [ D.div [ DA.klass_ "quantity-controls" ]
                  [ D.div
                      [ DA.klass $ inCart <#> \n ->
                          if n > 0 then "quantity-indicator" else "hidden"
                      ]
                      [ text (show <$> inCart) ]
                  , D.button
                      [ DA.klass $ disabled <#> \d ->
                          if d then "add-btn disabled" else "add-btn"
                      , DA.disabled $ disabled <#> \d ->
                          if d then "true" else ""
                      , DL.runOn DL.click $
                          ( \quantity sale activity ->
                              if isBusy activity then pure unit
                              else case addBlocker quantity menuItem sale.saleItems of
                                Just reason -> props.report reason
                                Nothing -> props.addItem menuItem quantity
                          )
                            <$> quantityV
                            <*> props.sale
                            <*> props.activity
                      ]
                      [ text $ props.activity <#> \activity ->
                          if outOfStock then "Out of Stock"
                          else if isBusy activity then "Processing..."
                          else "Add"
                      ]
                  ]
              ]
          ]

    table items =
      if null items then
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
          , D.div [ DA.klass_ "inventory-table-body" ] (map row items)
          ]

  D.div [ DA.klass_ "inventory-selection" ]
    [ D.div [ DA.klass_ "inventory-header" ]
        [ D.h3_ [ text_ "Select Items" ]
        , D.button
            [ DA.klass_ "btn btn-sm"
            , DL.click_ \_ -> props.inventory.reload
            ]
            [ text_ "Refresh" ]
        ]

    , props.inventory.value <#~> case _ of
        Success inventory ->
          D.div [ DA.klass_ "category-tabs" ]
            ( [ categoryTab "All Items" Nothing ]
                <> (categoriesIn inventory <#> \c -> categoryTab (show c) (Just c))
            )
        _ -> D.div_ []

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
                      raw <- Input.value el
                      case Int.fromString raw of
                        Just n | n > 0 -> setQuantity n
                        _ -> pure unit
                ]
                []
            ]
        ]

    , D.div [ DA.klass_ "inventory-items" ]
        [ viewRemote (standardView "Loading inventory...") table visible ]
    ]
