module Pages.Manager.Panels.StatsPanel where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Pages.Manager.State (ActivityStatus(..))
import Utils.Formatting (formatCentsToDollars)

statsPanel :: Poll ActivityStatus -> Nut
statsPanel statusPoll =
  statusPoll <#~> case _ of
    ActivityLoading ->
      D.div [ DA.klass_ "loading-indicator" ] []
    ActivityError err ->
      D.div [ DA.klass_ "error-message" ] []
    ActivityLoaded snap ->
      let s = snap.asTodayStats
      in D.div [ DA.klass_ "stats-panel" ]
          [ D.h3_ [ text_ "Today's Stats" ]
          , D.div [ DA.klass_ "stats-grid" ]
              [ statRow "Transactions"  (show s.ldsTxCount)
              , statRow "Revenue"       ("$" <> formatCentsToDollars s.ldsRevenue)
              , statRow "Avg Tx Value"  ("$" <> formatCentsToDollars s.ldsAvgTxValue)
              , statRow "Voids"         (show s.ldsVoidCount)
              , statRow "Refunds"       (show s.ldsRefundCount)
              ]
          ]

statRow :: String -> String -> Nut
statRow label value =
  D.div [ DA.klass_ "stat-row" ]
    [ D.span [ DA.klass_ "stat-row-label" ] [ text_ label ]
    , D.span [ DA.klass_ "stat-row-value" ] [ text_ value ]
    ]