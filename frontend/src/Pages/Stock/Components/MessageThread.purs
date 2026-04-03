module Pages.Stock.Components.MessageThread where

import Prelude

import Data.Array (null)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import FRP.Poll (Poll)
import Types.Stock (PullMessage)
import Effect (Effect)

messageThread
  :: Poll (Array PullMessage)
  -> (String -> Effect Unit)
  -> Nut
messageThread msgsPoll onSend = Deku.do
  setDraft /\ draftValue <- useHot ""

  D.div [ DA.klass_ "message-thread" ]
    [ D.div [ DA.klass_ "message-list" ]
        [ msgsPoll <#~> \msgs ->
            if null msgs
              then D.div [ DA.klass_ "no-messages" ] [ text_ "No messages" ]
              else D.div_ (map renderMsg msgs)
        ]
    , D.div [ DA.klass_ "message-compose" ]
        [ D.input
            [ DA.klass_ "message-input"
            , DA.placeholder_ "Type a message..."
            , DA.value draftValue
            , DL.input_ \_ -> pure unit
            ]
            []
        , D.button
            [ DA.klass_ "btn btn-primary"
            , DL.runOn DL.click $ draftValue <#> \draft -> do
                when (draft /= "") do
                  onSend draft
                  setDraft ""
            ]
            [ text_ "Send" ]
        ]
    ]

renderMsg :: PullMessage -> Nut
renderMsg msg =
  D.div [ DA.klass_ $ "message-item role-" <> msg.pmFromRole ]
    [ D.span [ DA.klass_ "message-role" ] [ text_ msg.pmFromRole ]
    , D.span [ DA.klass_ "message-text" ] [ text_ msg.pmMessage ]
    ]