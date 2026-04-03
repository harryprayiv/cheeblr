module Pages.Stock.Components.PullCard where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Effect (Effect)
import Types.Stock (PullAction(..), PullRequest, actionLabel, statusClass, validActions)
import Types.UUID (UUID)

pullCard
  :: PullRequest
  -> (UUID -> PullAction -> Effect Unit)
  -> Nut
pullCard pr onAction =
  D.div
    [ DA.klass_ $ "pull-card " <> statusClass pr.prStatus ]
    [ D.div [ DA.klass_ "pull-card-header" ]
        [ D.span [ DA.klass_ "pull-item-name" ] [ text_ pr.prItemName ]
        , D.span [ DA.klass_ $ "pull-status " <> statusClass pr.prStatus ]
            [ text_ pr.prStatus ]
        ]
    , D.div [ DA.klass_ "pull-card-body" ]
        [ D.div_ [ text_ $ "Quantity: " <> show pr.prQuantityNeeded ]
        , D.div_ [ text_ $ "TX: " <> show pr.prTransactionId ]
        ]
    , D.div [ DA.klass_ "pull-card-actions" ]
        ( map (\action ->
            D.button
              [ DA.klass_ $ "btn btn-sm " <> actionBtnClass action
              , DL.click_ \_ -> onAction pr.prId action
              ]
              [ text_ (actionLabel action) ]
          ) (validActions pr.prStatus)
        )
    ]

actionBtnClass :: PullAction -> String
actionBtnClass ActionFulfill     = "btn-success"
actionBtnClass ActionCancel      = "btn-danger"
actionBtnClass ActionReportIssue = "btn-warning"
actionBtnClass _                 = "btn-primary"