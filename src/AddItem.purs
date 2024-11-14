module AddItem where

import Prelude

import Data.Array (all, null)
import Data.Foldable (for_, traverse_)
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing)
import Data.String (Pattern(..), Replacement(..), replaceAll)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.DOM.Self as Self
import Deku.Do as Deku
import Deku.Hooks (guard, guardWith, useDyn, useDynAtBeginning, useRef, useState, useState')
import Deku.Toplevel (runInBody)
import Effect (Effect)
import Effect.Class (liftEffect)
import Web.Event.Event (target)
import Web.HTML (window)
import Web.HTML.HTMLInputElement (fromEventTarget, value)
import Web.HTML.Window (alert)
import Web.UIEvent.KeyboardEvent (code, toEvent)

-- Input styling
inputKls :: String
inputKls =
  """rounded-md border-gray-300 shadow-sm
     border-2 mr-2 border-solid
     focus:border-indigo-500 focus:ring-indigo-500
     sm:text-sm"""

buttonClass :: String -> String
buttonClass color =
  replaceAll (Pattern "COLOR") (Replacement color)
    """mb-3 inline-flex items-center rounded-md
       border border-transparent bg-COLOR-600 px-3 py-2
       text-sm font-medium leading-4 text-white shadow-sm
       hover:bg-COLOR-700 focus:outline-none focus:ring-2
       focus:ring-COLOR-500 focus:ring-offset-2"""

-- Main app with multiple fields
app :: Effect Unit
app = void $ runInBody Deku.do
  -- Initialize state for each input field
  setSku /\ sku <- useState ""
  setBrand /\ brand <- useState ""
  setCategory /\ category <- useState ""
  setItem /\ item <- useState ""

  -- Create references for each input field to get Poll (Maybe String) values
  skuRef <- useRef Nothing (Just <$> sku)
  brandRef <- useRef Nothing (Just <$> brand)
  categoryRef <- useRef Nothing (Just <$> category)

  -- Define Poll Boolean to track form validity by checking if all fields are non-empty
  let isNonEmpty = map (\s -> s /= "") <<< map (fromMaybe "")
  let skuValid = isNonEmpty skuRef
  let brandValid = isNonEmpty brandRef
  let categoryValid = isNonEmpty categoryRef
  let isFormValid = pure (\a b c -> a && b && c) <*> skuValid <*> brandValid <*> categoryValid

  -- Define the top-level form with multiple input fields
  let top =
        D.div_
          [ D.input
              [ DA.placeholder_ "SKU"
              , Self.selfT_ setSku
              , DA.klass_ inputKls
              ]
              []
          , D.input
              [ DA.placeholder_ "Brand"
              , Self.selfT_ setBrand
              , DA.klass_ inputKls
              ]
              []
          , D.input
              [ DA.placeholder_ "Category"
              , Self.selfT_ setCategory
              , DA.klass_ inputKls
              ]
              []
          , guard isFormValid $
              D.button
                [ DL.click_ \_ -> do
                    traverse_ (\set -> set "") [setSku, setBrand, setCategory] -- Clear inputs after submission
                , DA.klass_ $ buttonClass "green"
                ]
                [ text_ "Add" ]
          ]

  -- Display area for the item added (if applicable)
  D.div_
    [ top
    , Deku.do
        { value: itemVal } <- useDynAtBeginning item
        D.div_ [ text_ itemVal ]
    ]