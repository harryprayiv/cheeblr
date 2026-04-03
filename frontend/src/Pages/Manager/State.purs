module Pages.Manager.State where

import Prelude

import Types.Manager (ActivitySummary)

data ManagerTab
  = TabActivity
  | TabAlerts
  | TabStats
  | TabReports
  | TabOverride

derive instance eqManagerTab :: Eq ManagerTab

instance showManagerTab :: Show ManagerTab where
  show TabActivity = "Activity"
  show TabAlerts   = "Alerts"
  show TabStats    = "Stats"
  show TabReports  = "Reports"
  show TabOverride = "Overrides"

allManagerTabs :: Array ManagerTab
allManagerTabs = [ TabActivity, TabAlerts, TabStats, TabReports, TabOverride ]

data ActivityStatus
  = ActivityLoading
  | ActivityLoaded ActivitySummary
  | ActivityError String