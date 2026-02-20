-- | DOM helpers for form input handling.
-- | These bridge Deku event handlers to value extraction.
module Cheeblr.UI.FormHelpers where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Web.Event.Event (Event, target)
import Web.HTML.HTMLInputElement as HTMLInput
import Web.HTML.HTMLSelectElement as HTMLSelect
import Unsafe.Coerce (unsafeCoerce)

-- | Extract the value from an input event.
-- | Works for <input> and <textarea> elements.
getInputValue :: Event -> Effect String
getInputValue evt =
  case target evt of
    Nothing -> pure ""
    Just t -> do
      let el = unsafeCoerce t :: HTMLInput.HTMLInputElement
      HTMLInput.value el

-- | Extract the value from a select change event.
getSelectValue :: Event -> Effect String
getSelectValue evt =
  case target evt of
    Nothing -> pure ""
    Just t -> do
      let el = unsafeCoerce t :: HTMLSelect.HTMLSelectElement
      HTMLSelect.value el
