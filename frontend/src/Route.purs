module Route where

import Prelude hiding ((/))

import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import FRP.Poll (Poll)
import Routing.Duplex (RouteDuplex', root, segment, string)
import Routing.Duplex.Generic as G
import Routing.Duplex.Generic.Syntax ((/))

data Route = LiveView | Create | Edit String | Delete String

derive instance Eq Route
derive instance Ord Route
derive instance genericRoute :: Generic Route _

instance Show Route where
  show = genericShow

route :: RouteDuplex' Route
route = root $ G.sum
  { "LiveView": G.noArgs
  , "Create": "create" / G.noArgs
  , "Edit": "edit" / (string segment)
  , "Delete": "delete" / (string segment)
  }

nav :: Poll Route -> Nut
nav currentRoute = D.nav [ DA.klass_ "navbar navbar-light" ]
  [ D.div [ DA.klass_ "container" ]
      [ D.div
          [ DA.klass_ "nav navbar-nav pull-xs-right d-flex" ]
          [ navItem LiveView "/#/" "LiveView" currentRoute
          , navItem Create "/#/create" "Create Item" currentRoute
          , navItem (Edit "test") "/#/edit/test" "Edit Test Item" currentRoute
          ]
      ]
  ]

navItem :: Route -> String -> String -> Poll Route -> Nut
navItem thisRoute href label currentRoute =
  D.div
    [ DA.klass_ "nav-item mx-2" ]
    [ D.a
        [ DA.href_ href
        , DA.klass $ currentRoute <#> \r ->
            "nav-link" <> if r == thisRoute then " active" else ""
        ]
        [ text_ label ]
    ]