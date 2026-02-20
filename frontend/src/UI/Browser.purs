module Cheeblr.UI.Inventory.Browser where

import Prelude

import Cheeblr.Core.Domain (categoryRegistry)
import Cheeblr.Core.Product (Product(..), ProductList(..), productInStock)
import Cheeblr.Core.Tag (toOptions, unTag)
import Cheeblr.Core.Money (formatCurrency)
import Cheeblr.UI.FormHelpers (getInputValue, getSelectValue)
import Data.Array (filter, null, sortBy)
import Data.String (Pattern(..), contains, toLower)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import FRP.Poll (Poll)

----------------------------------------------------------------------
-- Inventory Browser Component
----------------------------------------------------------------------

-- | A searchable, filterable product browser.
-- | Fires `onSelect` when a product is clicked.
inventoryBrowser
  :: Poll ProductList         -- reactive inventory data
  -> (Product -> Effect Unit) -- callback when a product is selected
  -> Nut
inventoryBrowser inventoryPoll onSelect = Deku.do
  setSearch /\ searchPoll <- useState ""
  setCategoryFilter /\ categoryFilterPoll <- useState ""

  let
    -- Filter products by search text and category
    filterProducts :: String -> String -> ProductList -> Array Product
    filterProducts searchText catFilter (ProductList items) =
      items
        # filter (\(Product p) ->
            let
              matchesSearch =
                searchText == "" ||
                contains (Pattern (toLower searchText)) (toLower p.name) ||
                contains (Pattern (toLower searchText)) (toLower p.brand)
              matchesCat =
                catFilter == "" ||
                unTag p.category == catFilter
            in
              matchesSearch && matchesCat && productInStock (Product p)
          )
        # sortBy (\(Product a) (Product b) -> compare a.sort b.sort)

  D.div
    [ DA.klass_ "inventory-browser" ]
    [ -- Search bar
      D.div
        [ DA.klass_ "browser-controls" ]
        [ D.input
            [ DA.klass_ "browser-search"
            , DA.xtype_ "text"
            , DA.placeholder_ "Search products..."
            , DL.input_ \evt -> do
                val <- getInputValue evt
                setSearch val
            ] []

        -- Category filter dropdown
        , D.select
            [ DA.klass_ "browser-category-filter"
            , DL.change_ \evt -> do
                val <- getSelectValue evt
                setCategoryFilter val
            ]
            ( [ D.option [ DA.value_ "" ] [ text_ "All Categories" ] ]
                <> (toOptions categoryRegistry <#> \opt ->
                      D.option
                        [ DA.value_ opt.value ]
                        [ text_ opt.label ]
                   )
            )
        ]

    -- Product grid (reactive)
    , searchPoll <#~> \searchText ->
        categoryFilterPoll <#~> \catFilter ->
          inventoryPoll <#~> \inventory ->
            let filtered = filterProducts searchText catFilter inventory in
            if null filtered then
              D.div [ DA.klass_ "browser-empty" ] [ text_ "No products match your search" ]
            else
              D.div [ DA.klass_ "browser-grid" ] (filtered <#> productCard onSelect)
    ]

----------------------------------------------------------------------
-- Product Card
----------------------------------------------------------------------

productCard :: (Product -> Effect Unit) -> Product -> Nut
productCard onSelect product@(Product p) =
  D.div
    [ DA.klass_ "product-card"
    , DL.click_ \_ -> onSelect product
    ]
    [ D.div
        [ DA.klass_ "product-card-header" ]
        [ D.span [ DA.klass_ "product-brand" ] [ text_ p.brand ]
        , D.span [ DA.klass_ "product-category" ] [ text_ (unTag p.category) ]
        ]
    , D.div
        [ DA.klass_ "product-card-name" ]
        [ text_ p.name ]
    , D.div
        [ DA.klass_ "product-card-footer" ]
        [ D.span [ DA.klass_ "product-price" ]
            [ text_ (formatCurrency p.price) ]
        , D.span [ DA.klass_ "product-stock" ]
            [ text_ (show p.quantity <> " in stock") ]
        ]
    , if p.meta.strain /= "" then
        D.div
          [ DA.klass_ "product-card-strain" ]
          [ text_ (p.meta.strain <> " • " <> p.meta.thc) ]
      else
        D.span_ []
    ]
