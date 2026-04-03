module Pages.Manager.Panels.AlertsPanel where

import Prelude

import Data.Array (null)
import Data.Maybe (Maybe, fromMaybe)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Pages.Manager.State (ActivityStatus(..))

alertsPanel :: Poll ActivityStatus -> Nut
alertsPanel statusPoll =
  statusPoll <#~> case _ of
    ActivityLoading ->
      D.div [ DA.klass_ "loading-indicator" ] []
    ActivityError _ ->
      D.div [ DA.klass_ "error-message" ] []
    ActivityLoaded snap ->
      let alerts = snap.asAlerts
      in if null alerts
         then D.div [ DA.klass_ "no-alerts" ] [ text_ "No active alerts" ]
         else D.div [ DA.klass_ "alerts-panel" ]
                [ D.h3_ [ text_ "Active Alerts" ]
                , D.div [ DA.klass_ "alerts-list" ]
                    (map renderAlert alerts)
                ]

renderAlert :: { tag :: String, name :: Maybe String, quantity :: Maybe Int, elapsed :: Maybe Int, variance :: Maybe Int | _ } -> Nut
renderAlert alert =
  D.div [ DA.klass_ $ "alert-card " <> alertClass alert.tag ]
    [ D.div [ DA.klass_ "alert-tag" ] [ text_ (alertLabel alert.tag) ]
    , D.div [ DA.klass_ "alert-detail" ] [ text_ (alertDetail alert) ]
    ]
  where
  alertClass "LowInventoryAlert"     = "alert-warning"
  alertClass "StaleTransactionAlert" = "alert-info"
  alertClass "RegisterVarianceAlert" = "alert-danger"
  alertClass _                       = ""

  alertLabel "LowInventoryAlert"     = "Low Stock"
  alertLabel "StaleTransactionAlert" = "Stale Transaction"
  alertLabel "RegisterVarianceAlert" = "Register Variance"
  alertLabel t                       = t

  alertDetail a = case a.tag of
    "LowInventoryAlert"     ->
      fromMaybe "Unknown item" a.name <>
      " — " <> show (fromMaybe 0 a.quantity) <> " remaining"
    "StaleTransactionAlert" ->
      "Open for " <> show (fromMaybe 0 a.elapsed) <> "s"
    "RegisterVarianceAlert" ->
      "Variance: $" <> show (fromMaybe 0 a.variance)
    _ -> ""