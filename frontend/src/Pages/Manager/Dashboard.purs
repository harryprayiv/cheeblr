module Pages.Manager.Dashboard where

import API.Manager (getActivity)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import FRP.Poll (Poll)
import Pages.Manager.Panels.ActivityFeed (activityFeed)
import Pages.Manager.Panels.AlertsPanel (alertsPanel)
import Pages.Manager.Panels.ReportsPanel (reportsPanel)
import Pages.Manager.Panels.StatsPanel (statsPanel)
import Pages.Manager.State (ManagerTab(..), allManagerTabs)
import Services.AuthService (AuthState, UserId)
import Types.RemoteData (RemoteData(..))
import UI.Remote (onMount, useRemote)
import UI.Tabs (tabBar)

page :: Poll AuthState -> UserId -> Nut
page _authPoll userId = Deku.do
  setTab /\ tabValue <- useHot TabActivity
  activity <- useRemote Loading (getActivity userId)

  D.div
    [ DA.klass_ "manager-dashboard"
    , onMount activity.reload
    ]
    [ D.div [ DA.klass_ "manager-header" ]
        [ D.h1 [ DA.klass_ "manager-title" ] [ text_ "Manager Dashboard" ]
        , D.button
            [ DA.klass_ "btn btn-sm"
            , DL.click_ \_ -> activity.reload
            ]
            [ text_ "Refresh" ]
        ]
    , tabBar { bar: "manager-tabs", tab: "manager-tab" }
        allManagerTabs
        tabValue
        setTab
    , tabValue <#~> case _ of
        TabActivity -> activityFeed activity.value
        TabAlerts   -> alertsPanel  activity.value
        TabStats    -> statsPanel   activity.value
        TabReports  -> reportsPanel userId
        TabOverride -> D.div_ [ text_ "Override panel — coming in Phase 8" ]
    ]