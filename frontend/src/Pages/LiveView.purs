module Pages.LiveView where

import Prelude

import Config.LiveView (defaultViewConfig)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Services.AuthService (AuthState)
import Types.Inventory (Inventory)
import UI.Inventory.MenuLiveView (renderInventory)

data InventoryLoadStatus
  = InventoryLoading
  | InventoryLoaded Inventory
  | InventoryError String

page :: Poll AuthState -> Poll InventoryLoadStatus -> Nut
page _authPoll inventoryStatus =
  D.div
    [ DA.klass_ "page-container" ]
    [ inventoryStatus <#~> case _ of
        InventoryLoading ->
          D.div [ DA.klass_ "loading-indicator" ]
            [ text_ "Loading inventory..." ]
        InventoryError err ->
          D.div [ DA.klass_ "error-message" ]
            [ text_ $ "Error: " <> err ]
        InventoryLoaded inv ->
          renderInventory defaultViewConfig inv
    ]