module Pages.CreateItem where

import Prelude

import Deku.Core (Nut)
import Effect (Effect)
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import UI.Inventory.CreateItem (createItem)

page :: Ref AuthContext -> String -> Effect Nut
page authRef uuid = pure (createItem authRef uuid)