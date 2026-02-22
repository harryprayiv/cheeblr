module UI.Inventory.MenuLiveView where

import Prelude

import Config.LiveView (LiveViewConfig, defaultViewConfig)
import Data.Array (filter, length, sortBy)
import Data.Newtype (unwrap)
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners (load_) as DL
import Deku.Hooks ((<#~>))
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import Types.Inventory (Inventory(..), MenuItem(..), StrainLineage(..), compareMenuItems, generateClassName)
import Utils.Formatting (formatCentsToDollars, summarizeLongText)

createMenuLiveView :: Poll Inventory -> Poll Boolean -> Poll String -> Nut
createMenuLiveView inventoryPoll loadingPoll errorPoll =
  D.div
    [ DA.klass_ "page-container"
    , DL.load_ \_ -> do
        liftEffect $ Console.log "LiveView component mounting..."
    ]
    [ D.div
        [ DA.klass_ "status-container" ]
        [ loadingPoll <#~> \isLoading ->
            if isLoading then
              D.div [ DA.klass_ "loading-indicator" ]
                [ text_ "Loading data..." ]
            else
              D.div_ []
        , errorPoll <#~> \error ->
            if error /= "" then
              D.div [ DA.klass_ "error-message" ]
                [ text_ error ]
            else
              D.div_ []
        ]
    , D.div
        [ DA.klass_ "inventory-container" ]
        [ inventoryPoll <#~> \inventory ->
            renderInventory defaultViewConfig inventory
        ]
    ]

renderInventory :: LiveViewConfig -> Inventory -> Nut
renderInventory config (Inventory items) =
  let
    filteredItems =
      if config.hideOutOfStock then filter
        (\(MenuItem item) -> item.quantity > 0)
        items
      else items

    sortedItems = sortBy (compareMenuItems config) filteredItems
  in
    D.div
      [ DA.klass_ "container" ]
      [ if length items == 0 then
          D.div [ DA.klass_ "empty-inventory" ]
            [ text_ "No items in inventory" ]
        else
          D.div [ DA.klass_ "inventory-grid" ]
            (map renderItem sortedItems)
      , D.div [ DA.klass_ "inventory-stats" ]
          [ text $ pure $ "Total items: " <> show (length items) ]
      ]

renderItem :: MenuItem -> Nut
renderItem (MenuItem record) =
  let
    StrainLineage meta = record.strain_lineage
    className = generateClassName
      { category: record.category
      , subcategory: record.subcategory
      , species: meta.species
      }

    -- Format price using the cents value from unwrapping Discrete USD
    formattedPrice = "$" <> formatCentsToDollars (unwrap record.price)
    formattedDescription = summarizeLongText record.description
  in
    D.div
      [ DA.klass_ ("inventory-item-card " <> className) ]
      [ D.div [ DA.klass_ "item-header" ]
          [ D.div []
              [ D.div [ DA.klass_ "item-brand" ] [ text_ record.brand ]
              , D.div [ DA.klass_ "item-name" ]
                  [ text_ ("'" <> record.name <> "'") ]
              ]
          , D.div [ DA.klass_ "item-img" ]
              [ D.img [ DA.alt_ "product image", DA.src_ meta.img ] [] ]
          ]
      , D.div [ DA.klass_ "item-category" ]
          [ text_ (show record.category <> " - " <> record.subcategory) ]
      , D.div [ DA.klass_ "item-species" ]
          [ text_ ("Species: " <> show meta.species) ]
      , D.div [ DA.klass_ "item-strain_lineage" ]
          [ text_ ("Strain: " <> meta.strain) ]
      , D.div [ DA.klass_ "item-price" ]
          [ text_
              ( formattedPrice <> " (" <> record.per_package <> " "
                  <> record.measure_unit
                  <> ")"
              )
          ]
      , D.div [ DA.klass_ "item-description" ]
          [ text_ (formattedDescription) ]
      , D.div [ DA.klass_ "item-quantity" ]
          [ text_ ("in stock: " <> show record.quantity) ]
      , D.div [ DA.klass_ "item-actions" ]
          [ D.a
              [ DA.klass_ "action-button edit-button"
              , DA.href_ ("/#/edit/" <> show record.sku)
              , DA.title_ "Edit item"
              ]
              [ D.i [ DA.klass_ "button-icon ion-edit" ] []
              , text_ "Edit"
              ]
          , D.a
              [ DA.klass_ "action-button delete-button"
              , DA.href_ ("/#/delete/" <> show record.sku)
              , DA.title_ "Delete item"
              ]
              [ D.i [ DA.klass_ "button-icon ion-trash-a" ] []
              , text_ "Delete"
              ]
          ]
      ]