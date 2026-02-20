module Cheeblr.UI.StatusBar where

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
-- Status Level
----------------------------------------------------------------------

data StatusLevel
  = Info
  | Success
  | Warning
  | Error

levelClass :: StatusLevel -> String
levelClass Info = "status-info"
levelClass Success = "status-success"
levelClass Warning = "status-warning"
levelClass Error = "status-error"

----------------------------------------------------------------------
-- Status Message
----------------------------------------------------------------------

type StatusMessage =
  { level :: StatusLevel
  , text :: String
  }

----------------------------------------------------------------------
-- Status Bar Component
----------------------------------------------------------------------

-- | A simple status bar that shows/hides based on content.
statusBar :: Poll String -> Nut
statusBar messagePoll =
  messagePoll <#~> \msg ->
    if msg == "" then D.span_ []
    else
      D.div
        [ DA.klass_ "status-bar status-info" ]
        [ D.span [ DA.klass_ "status-text" ] [ text_ msg ]
        ]

-- | Status bar with level styling.
statusBarStyled :: Poll (Maybe StatusMessage) -> Nut
statusBarStyled msgPoll =
  msgPoll <#~> case _ of
    Nothing -> D.span_ []
    Just msg ->
      D.div
        [ DA.klass_ ("status-bar " <> levelClass msg.level) ]
        [ D.span [ DA.klass_ "status-text" ] [ text_ msg.text ] ]

----------------------------------------------------------------------
-- Dismissible status
----------------------------------------------------------------------

dismissibleStatus
  :: Poll String
  -> (String -> Effect Unit)   -- setter to clear it
  -> Nut
dismissibleStatus messagePoll clearMessage =
  messagePoll <#~> \msg ->
    if msg == "" then D.span_ []
    else
      D.div
        [ DA.klass_ "status-bar status-info status-dismissible" ]
        [ D.span [ DA.klass_ "status-text" ] [ text_ msg ]
        , D.button
            [ DA.klass_ "status-dismiss"
            , DL.click_ \_ -> clearMessage ""
            ]
            [ text_ "✕" ]
        ]
