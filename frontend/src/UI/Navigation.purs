module Cheeblr.UI.Navigation where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import FRP.Poll (Poll)

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------

data Page
  = InventoryPage
  | CreateItemPage
  | EditItemPage         -- needs a product ID, handled by parent
  | TransactionPage
  | RegisterPage
  | ReportsPage

derive instance Eq Page

instance Show Page where
  show InventoryPage = "Inventory"
  show CreateItemPage = "Create Item"
  show EditItemPage = "Edit Item"
  show TransactionPage = "New Transaction"
  show RegisterPage = "Register"
  show ReportsPage = "Reports"

----------------------------------------------------------------------
-- Navigation Bar
----------------------------------------------------------------------

navBar :: Poll Page -> (Page -> Effect Unit) -> Nut
navBar currentPagePoll setPage =
  D.nav
    [ DA.klass_ "nav-bar" ]
    [ D.div
        [ DA.klass_ "nav-brand" ]
        [ text_ "cheeblr" ]
    , D.div
        [ DA.klass_ "nav-links" ]
        (mainPages <#> \page ->
          currentPagePoll <#~> \current ->
            D.button
              [ DA.klass_ $
                  if current == page then "nav-link nav-link-active"
                  else "nav-link"
              , DL.click_ \_ -> setPage page
              ]
              [ text_ (show page) ]
        )
    ]

-- | Pages shown in the nav bar.
mainPages :: Array Page
mainPages =
  [ InventoryPage
  , TransactionPage
  , RegisterPage
  , ReportsPage
  ]
