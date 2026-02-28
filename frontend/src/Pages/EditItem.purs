module Pages.EditItem where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Services.AuthService (AuthState, UserId)
import Types.Inventory (MenuItem)
import UI.Inventory.ItemForm (FormMode(..), itemForm, renderError)

data EditItemStatus
  = EditLoading
  | EditReady MenuItem
  | EditNotFound String
  | EditError String

page :: Poll AuthState -> UserId -> Poll EditItemStatus -> Nut
page _authPoll userId editStatus =
  editStatus <#~> case _ of
    EditLoading ->
      D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading item..." ]
    EditReady menuItem ->
      itemForm userId (EditMode menuItem)
    EditNotFound uuid ->
      renderError $ "Item with UUID " <> uuid <> " not found"
    EditError msg ->
      renderError msg