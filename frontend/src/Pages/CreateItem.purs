module Pages.CreateItem where


import Deku.Core (Nut)
import FRP.Poll (Poll)
import Services.AuthService (AuthState, UserId)
import UI.Inventory.ItemForm (FormMode(..), itemForm)

page :: Poll AuthState -> UserId -> String -> Nut
page _authPoll userId uuid = itemForm userId (CreateMode uuid)