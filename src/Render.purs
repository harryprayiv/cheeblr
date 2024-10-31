module Render where

import Prelude

import BudView (MenuItem(..), Inventory(..))
import Data.Array (snoc)
import Data.Tuple.Nested ((/\))
import Deku.Core (Nut, text_)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Effect (useState)
import Deku.Toplevel (runInBody)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Yoga.JSON (writeImpl)

-- Inventory options
categoryOptions :: Array String
categoryOptions =   [ "Flower"
                    , "Pre-Rolls"
                    , "Vaporizers"
                    , "Edibles"
                    , "Drinks"
                    , "Concentrates"
                    , "Topicals"
                    , "Tinctures"
                    , "Accessories"
                    ]


speciesOptions :: Array String
speciesOptions = ["Indica", "Sativa", "Hybrid"]

-- Function to save to JSON file (stub implementation)
saveInventory :: Inventory -> Aff Unit
saveInventory inventory = do
  let inventoryJson = writeImpl inventory
  liftEffect $ log ("Saving inventory: " <> inventoryJson)
  pure unit

-- Main application form
app :: Effect Unit
app = do
  -- Define state for each input field
  setName /\ name <- useState ""
  setCategory /\ category <- useState (categoryOptions[0])
  setSubcategory /\ subcategory <- useState "Live Resin" -- default example subcategory
  setSpecies /\ species <- useState (speciesOptions[0])
  setSku /\ sku <- useState ""
  setPrice /\ price <- useState 0.0
  setQuantity /\ quantity <- useState 1

  -- Handle form submission to add a new item
  let addItemToInventory :: Effect Unit
      addItemToInventory = do
        -- Create a new MenuItem from the form inputs
        let newItem = MenuItem { name, category, subcategory, species, sku, price, quantity }

        -- Update JSON with new item (appending to existing inventory)
        liftAff do
          -- Load current inventory (mocked as empty for simplicity)
          let currentInventory = Inventory []
          let updatedInventory = Inventory (snoc (case currentInventory of Inventory items -> items) newItem)
          saveInventory updatedInventory

        liftEffect $ log ("New item added: " <> show newItem)

  -- Render form
  void $ runInBody $ D.div []
    [ D.textarea
        [ DA.value_ name
        , DA.placeholder "Enter item name"
        , DL.runOn DL.input \e -> setName e
        ]
        []
    , D.select
        [ DL.runOn DL.change \e -> setCategory e ]
        (map (\opt -> D.option [DA.value opt, DA.selected (opt == category)] [text_ opt]) categoryOptions)
    , D.select
        [ DL.runOn DL.change \e -> setSpecies e ]
        (map (\opt -> D.option [DA.value opt, DA.selected (opt == species)] [text_ opt]) speciesOptions)
    , D.textarea
        [ DA.value_ sku
        , DA.placeholder "Enter SKU"
        , DL.runOn DL.input \e -> setSku e
        ]
        []
    , D.textarea
        [ DA.value_ (show price)
        , DA.placeholder "Enter price"
        , DL.runOn DL.input \e -> setPrice (read e :: Number)
        ]
        []
    , D.textarea
        [ DA.value_ (show quantity)
        , DA.placeholder "Enter quantity"
        , DL.runOn DL.input \e -> setQuantity (read e :: Int)
        ]
        []
    , D.button
        [ DL.runOn DL.click \_ -> addItemToInventory ]
        [ text_ "Add Item to Inventory" ]
    ]
