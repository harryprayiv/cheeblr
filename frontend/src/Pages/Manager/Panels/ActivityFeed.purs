module Pages.Manager.Panels.ActivityFeed where

import Prelude

import Data.Array (length, null)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Pages.Manager.State (ActivityStatus(..))
import Types.Transaction (TransactionStatus)

activityFeed :: Poll ActivityStatus -> Nut
activityFeed statusPoll =
  statusPoll <#~> case _ of
    ActivityLoading ->
      D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading activity..." ]
    ActivityError err ->
      D.div [ DA.klass_ "error-message" ] [ text_ err ]
    ActivityLoaded snap ->
      D.div [ DA.klass_ "activity-feed" ]
        [ D.h3_ [ text_ "Live Transactions" ]
        , D.div [ DA.klass_ "open-registers" ]
            [ text_ $ "Open Registers: " <> show (length snap.asOpenRegisters) ]
        , if null snap.asLiveTransactions
            then D.div [ DA.klass_ "empty-feed" ] [ text_ "No active transactions" ]
            else D.div [ DA.klass_ "tx-list" ]
                   (map renderTxSummary snap.asLiveTransactions)
        ]

renderTxSummary :: { tsId :: _, tsStatus :: TransactionStatus, tsElapsedSecs :: Int, tsItemCount :: Int, tsTotal :: Int, tsIsStale :: Boolean | _ } -> Nut
renderTxSummary tx =
  D.div [ DA.klass_ $ "tx-card" <> if tx.tsIsStale then " stale" else "" ]
    [ D.div [ DA.klass_ "tx-status" ] [ text_ (show tx.tsStatus) ]
    , D.div [ DA.klass_ "tx-elapsed" ] [ text_ (show tx.tsElapsedSecs <> "s") ]
    , D.div [ DA.klass_ "tx-items"   ] [ text_ (show tx.tsItemCount <> " items") ]
    ]