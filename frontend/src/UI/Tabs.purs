module UI.Tabs
  ( TabStyle
  , tabBar
  ) where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Effect (Effect)
import FRP.Poll (Poll)

-- bar is the class of the container. tab is the class of each button, and
-- the selected button also gets " active".
type TabStyle =
  { bar :: String
  , tab :: String
  }

-- A row of buttons, one per tab, labelled with show.
tabBar
  :: forall t
   . Eq t
  => Show t
  => TabStyle
  -> Array t
  -> Poll t
  -> (t -> Effect Unit)
  -> Nut
tabBar style tabs selected select =
  D.div [ DA.klass_ style.bar ]
    ( tabs <#> \t ->
        D.button
          [ DA.klass $ selected <#> \active ->
              style.tab <> if active == t then " active" else ""
          , DL.click_ \_ -> select t
          ]
          [ text_ (show t) ]
    )
