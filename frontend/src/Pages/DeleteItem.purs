module Pages.DeleteItem where

import Prelude

import API.Inventory (readInventory)
import Data.Maybe (Maybe(..))
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.Do as Deku
import Pages.EditItem (findItem, itemView, resolveSku)
import Types.Inventory (MenuItem(..))
import Types.RemoteData (RemoteData(..))
import UI.Inventory.DeleteItem (renderDeleteConfirmation)
import UI.Inventory.ItemForm (renderError)
import UI.Remote (onMount, useRemote, viewRemote)

-- The page reads the inventory itself when it is mounted and asks for
-- confirmation before deleting the item whose SKU is in the route.
page :: String -> Nut
page rawSku = Deku.do
  inventory <- useRemote Loading readInventory
  let sku = resolveSku rawSku

  D.div [ onMount inventory.reload ]
    [ inventory.value # viewRemote itemView \found ->
        case findItem sku found of
          Just (MenuItem item) -> renderDeleteConfirmation sku item.name
          Nothing -> renderError $ "Item with UUID " <> sku <> " not found"
    ]
