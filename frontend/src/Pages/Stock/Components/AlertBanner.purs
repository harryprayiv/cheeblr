module Pages.Stock.Components.AlertBanner where

import Prelude

import Data.Maybe (Maybe(..))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks ((<#~>))
import Effect (Effect)
import FRP.Poll (Poll)
import Types.Stock (PullRequest)
import Types.UUID (UUID)

-- Notification API only — audio is handled in Utils.Audio via purescript-web-html.
foreign import showPullNotification :: String -> String -> Effect Unit
foreign import requestNotificationPermission :: Effect Unit

alertBanner
  :: Poll (Maybe PullRequest)
  -> (UUID -> Effect Unit)
  -> Effect Unit
  -> Nut
alertBanner newPullValue onSelect onDismiss =
  newPullValue <#~> \mPr ->
    case mPr of
      Nothing -> D.div_ []
      Just pr ->
        D.div [ DA.klass_ "alert-banner" ]
          [ D.span [ DA.klass_ "alert-icon" ] [ text_ "🔔" ]
          , D.span [ DA.klass_ "alert-text" ]
              [ text_ $ "New pull request: " <> pr.prItemName ]
          , D.button
              [ DA.klass_ "btn btn-sm btn-primary"
              , DL.click_ \_ -> do
                  onSelect pr.prId
                  onDismiss
              ]
              [ text_ "View" ]
          , D.button
              [ DA.klass_ "btn btn-sm"
              , DL.click_ \_ -> onDismiss
              ]
              [ text_ "✕" ]
          ]