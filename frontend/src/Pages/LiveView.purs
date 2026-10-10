module Pages.LiveView where

import Prelude

import Config.LiveView (defaultViewConfig)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Do as Deku
import GraphQL.API.Inventory (readInventoryGql)
import Types.RemoteData (RemoteData(..))
import UI.Inventory.MenuLiveView (renderInventory)
import UI.Remote (RemoteView, onMount, standardView, useRemote, viewRemote)

inventoryView :: RemoteView
inventoryView = (standardView "Loading inventory...")
  { failure = \err ->
      D.div [ DA.klass_ "error-message" ] [ text_ $ "Error: " <> err ]
  }

-- The page reads the inventory itself when it is mounted.
page :: Nut
page = Deku.do
  inventory <- useRemote Loading readInventoryGql

  D.div
    [ DA.klass_ "page-container"
    , onMount inventory.reload
    ]
    [ viewRemote inventoryView (renderInventory defaultViewConfig) inventory.value ]
