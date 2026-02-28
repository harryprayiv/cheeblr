module Pages.CreateItem where

import Prelude

import Deku.Core (Nut)
import Effect (Effect)
import FRP.Poll (Poll)
import Services.AuthService (AuthState, UserId)
import UI.Inventory.ItemForm (FormMode(..), itemForm)

page :: Poll AuthState -> UserId -> String -> Effect Nut
page _authPoll userId uuid = pure (itemForm userId (CreateMode uuid))