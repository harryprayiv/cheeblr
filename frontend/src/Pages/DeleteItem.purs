module Pages.DeleteItem where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Services.AuthService (AuthState, UserId)
import UI.Inventory.DeleteItem (renderDeleteConfirmation)
import UI.Inventory.ItemForm (renderError)

data DeleteItemStatus
  = DeleteLoading
  | DeleteReady String String  -- itemId, itemName
  | DeleteNotFound String
  | DeleteError String

page :: Poll AuthState -> UserId -> Poll DeleteItemStatus -> Nut
page _authPoll userId deleteStatus =
  deleteStatus <#~> case _ of
    DeleteLoading ->
      D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading item..." ]
    DeleteReady itemId itemName ->
      renderDeleteConfirmation userId itemId itemName
    DeleteNotFound uuid ->
      renderError $ "Item with UUID " <> uuid <> " not found"
    DeleteError msg ->
      renderError msg