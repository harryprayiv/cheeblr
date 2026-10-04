module Pages.Manager.State where

import Prelude

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