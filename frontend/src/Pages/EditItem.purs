module Pages.EditItem where

import Prelude

import API.Inventory (readInventory)
import Data.Array (find)
import Data.Maybe (Maybe(..))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Do as Deku
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.RemoteData (RemoteData(..))
import UI.Inventory.ItemForm (FormMode(..), itemForm, renderError)
import UI.Remote (RemoteView, onMount, useRemote, viewRemote)

testItemUUID :: String
testItemUUID = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

-- The route segment "test" stands for testItemUUID.
resolveSku :: String -> String
resolveSku raw = if raw == "test" then testItemUUID else raw

findItem :: String -> Inventory -> Maybe MenuItem
findItem sku (Inventory items) =
  find (\(MenuItem item) -> show item.sku == sku) items

itemView :: RemoteView
itemView =
  { notAsked: D.div_ []
  , loading: D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading item..." ]
  , failure: \err -> renderError ("Failed to fetch inventory: " <> err)
  }

-- The page reads the inventory itself when it is mounted and edits the item
-- whose SKU is in the route.
page :: String -> Nut
page rawSku = Deku.do
  inventory <- useRemote Loading readInventory
  let sku = resolveSku rawSku

  D.div [ onMount inventory.reload ]
    [ inventory.value # viewRemote itemView \found ->
        case findItem sku found of
          Just menuItem -> itemForm (EditMode menuItem)
          Nothing -> renderError $ "Item with UUID " <> sku <> " not found"
    ]
