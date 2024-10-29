module Render where

import Prelude

import BudView (Inventory(..), MenuItem(..))
import Data.Array (mapWithIndex)
import Data.Tuple.Nested ((/\))
import Deku.Core (Nut, text_)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks (useState)
import Deku.Toplevel (runInBody)
import Effect (Effect)
import Effect.Class.Console (log)

-- Define schema options for dropdowns
categoryOptions :: Array String
categoryOptions = ["Flower", "Vape"]

speciesOptions :: Array String
speciesOptions = ["Indica", "Sativa", "Hybrid"]

-- Text input field
renderTextInput :: String -> (String -> Effect Unit) -> Nut
renderTextInput value setValue = D.textarea
  [ DA.value value
  , DA.placeholder "Enter item name"
  , DL.runOn DL.input \event -> setValue event
  ]
  []

-- Dropdown component
renderDropdown :: Array String -> String -> (String -> Effect Unit) -> Nut
renderDropdown options selectedValue setValue = D.select
  [ DL.runOn DL.change \event -> setValue event
  ]
  (map (\opt -> D.option [DA.value opt, DA.selected (opt == selectedValue)] [text_ opt]) options)

-- Form to render both text input and dropdowns
renderForm :: { name :: String, category :: String, species :: String } -> (String -> Effect Unit) -> (String -> Effect Unit) -> (String -> Effect Unit) -> Nut
renderForm formState setName setCategory setSpecies = D.div_
  [ D.div_ [renderTextInput formState.name setName]
  , D.div_ [renderDropdown categoryOptions formState.category setCategory]
  , D.div_ [renderDropdown speciesOptions formState.species setSpecies]
  , D.button
      [ DL.runOn DL.click \_ -> log ("Submitted: " <> show formState)
      ]
      [ text_ "Submit Item" ]
  ]

app :: Effect Unit
app = do
  -- Define state for form fields
  setName /\ name <- useState ""
  setCategory /\ category <- useState (categoryOptions[0])
  setSpecies /\ species <- useState (speciesOptions[0])

  -- Render form with bound input fields
  void $ runInBody $ Deku.do
    renderForm
      { name, category, species }
      setName
      setCategory
      setSpecies
