module Pages.CreateItem where

import Prelude

import Data.Tuple.Nested ((/\))
import Deku.Control (text)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Types.UUID (genUUID)
import UI.Inventory.ItemForm (FormMode(..), itemForm)

-- The page owns the SKU of the item being created. After a successful
-- create it draws a new SKU, which rebuilds the form empty. A second item
-- created from the same page therefore never reuses the first one's SKU.
page :: String -> Nut
page firstSku = Deku.do
  setSku /\ skuV <- useHot firstSku
  setNotice /\ noticeV <- useHot ""

  let
    onCreated message = do
      setNotice ("Success: " <> message)
      next <- genUUID
      setSku (show next)

  D.div_
    [ D.div [ DA.klass_ "mt-4 text-center" ] [ text noticeV ]
    , skuV <#~> \sku -> itemForm (CreateMode { sku, onCreated })
    ]
