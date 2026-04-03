module Pages.Manager.Dashboard where

import Prelude

import API.Manager (getActivity)
import Data.Either (Either(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import FRP.Poll (Poll)
import Pages.Manager.Panels.ActivityFeed (activityFeed)
import Pages.Manager.Panels.AlertsPanel (alertsPanel)
import Pages.Manager.Panels.ReportsPanel (reportsPanel)
import Pages.Manager.Panels.StatsPanel (statsPanel)
import Pages.Manager.State
  ( ActivityStatus(..)
  , ManagerTab(..)
  , allManagerTabs
  )
import Services.AuthService (AuthState, UserId)

page :: Poll AuthState -> UserId -> Nut
page _authPoll userId = Deku.do
  setTab      /\ tabValue      <- useHot TabActivity
  setActivity /\ activityValue <- useHot ActivityLoading

  let loadActivity = launchAff_ do
        result <- getActivity userId
        liftEffect $ case result of
          Left err  -> setActivity (ActivityError err)
          Right act -> setActivity (ActivityLoaded act)

  D.div
    [ DA.klass_ "manager-dashboard"
    , DL.load_ \_ -> loadActivity
    ]
    [ D.div [ DA.klass_ "manager-header" ]
        [ D.h1 [ DA.klass_ "manager-title" ] [ text_ "Manager Dashboard" ]
        , D.button
            [ DA.klass_ "btn btn-sm"
            , DL.click_ \_ -> do
                setActivity ActivityLoading
                loadActivity
            ]
            [ text_ "Refresh" ]
        ]
    , D.div [ DA.klass_ "manager-tabs" ]
        ( map (\t ->
            D.button
              [ DA.klass $ tabValue <#> \active ->
                  "manager-tab" <> if active == t then " active" else ""
              , DL.click_ \_ -> setTab t
              ]
              [ text_ (show t) ]
          ) allManagerTabs
        )
    , tabValue <#~> case _ of
        TabActivity -> activityFeed activityValue
        TabAlerts   -> alertsPanel  activityValue
        TabStats    -> statsPanel   activityValue
        TabReports  -> reportsPanel userId
        TabOverride -> D.div_ [ text_ "Override panel — coming in Phase 8" ]
    ]