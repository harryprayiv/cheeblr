module Pages.CreateItem where

import Prelude

import Deku.Core (Nut)
import Effect (Effect)
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import UI.Inventory.ItemForm (FormMode(..), itemForm)

-- | UUID is generated in Main's matcher, passed here.
page :: Ref AuthContext -> String -> Effect Nut
page authRef uuid = pure (itemForm authRef (CreateMode uuid))