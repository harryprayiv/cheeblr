module Pages.Admin.State where

import Prelude

import Types.Admin (AdminSnapshot)

data AdminTab
  = TabOverview
  | TabLogViewer
  | TabFeedMonitor
  | TabEventStream
  | TabTransactions
  | TabSessions
  | TabRegisters
  | TabDomainEvents
  | TabActions

derive instance eqAdminTab :: Eq AdminTab

instance showAdminTab :: Show AdminTab where
  show TabOverview     = "Overview"
  show TabLogViewer    = "Logs"
  show TabFeedMonitor  = "Feed Monitor"
  show TabEventStream  = "Event Stream"
  show TabTransactions = "Transactions"
  show TabSessions     = "Sessions"
  show TabRegisters    = "Registers"
  show TabDomainEvents = "Domain Events"
  show TabActions      = "Actions"

allTabs :: Array AdminTab
allTabs =
  [ TabOverview
  , TabLogViewer
  , TabFeedMonitor
  , TabEventStream
  , TabTransactions
  , TabSessions
  , TabRegisters
  , TabDomainEvents
  , TabActions
  ]

data SnapshotStatus
  = SnapshotLoading
  | SnapshotLoaded AdminSnapshot
  | SnapshotError String