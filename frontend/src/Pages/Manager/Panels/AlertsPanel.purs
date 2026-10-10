module Pages.Manager.Panels.AlertsPanel where

import Prelude

import Data.Array (null)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import FRP.Poll (Poll)
import Types.Manager (ActivitySummary, ManagerAlert(..))
import Types.RemoteData (RemoteData)
import UI.Remote (quietView, viewRemote)
import Utils.Formatting (formatCentsToDollars)

alertsPanel :: Poll (RemoteData ActivitySummary) -> Nut
alertsPanel =
  viewRemote quietView \snap ->
    let alerts = snap.asAlerts
    in if null alerts
       then D.div [ DA.klass_ "no-alerts" ] [ text_ "No active alerts" ]
       else D.div [ DA.klass_ "alerts-panel" ]
              [ D.h3_ [ text_ "Active Alerts" ]
              , D.div [ DA.klass_ "alerts-list" ]
                  (map renderAlert alerts)
              ]

renderAlert :: ManagerAlert -> Nut
renderAlert alert =
  D.div [ DA.klass_ $ "alert-card " <> shown.klass ]
    [ D.div [ DA.klass_ "alert-tag" ] [ text_ shown.label ]
    , D.div [ DA.klass_ "alert-detail" ] [ text_ shown.detail ]
    ]
  where
  shown = case alert of
    LowInventoryAlert a ->
      { klass: "alert-warning"
      , label: "Low Stock"
      , detail: a.name <> ": " <> show a.quantity
          <> " remaining (alert at " <> show a.threshold <> " or fewer)"
      }
    StaleTransactionAlert a ->
      { klass: "alert-info"
      , label: "Stale Transaction"
      , detail: "Sale " <> show a.saleId <> " has been open for "
          <> show a.elapsedSecs <> "s"
      }
    RegisterVarianceAlert a ->
      { klass: "alert-danger"
      , label: "Register Variance"
      , detail: "Register " <> show a.registerId <> ": " <> variance a.variance
      }

  -- Expected minus counted. A positive figure means cash is missing.
  variance cents =
    if cents >= 0 then "short by $" <> formatCentsToDollars cents
    else "over by $" <> formatCentsToDollars (negate cents)
