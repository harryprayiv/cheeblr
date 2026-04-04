module Pages.Admin.Dashboard where

import Prelude

import API.Admin (getSnapshot)
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
import Pages.Admin.State (AdminTab (..), SnapshotStatus (..), allTabs)
import Pages.Admin.Tabs.FeedMonitor (feedMonitor)
import Pages.Admin.Tabs.LogViewer (logViewer)
import Pages.Admin.Tabs.Overview (overview)
import Services.AuthService (AuthState, UserId)

page :: Poll AuthState -> UserId -> Nut
page _authPoll userId = Deku.do
  setTab      /\ tabValue      <- useHot TabOverview
  setSnapshot /\ snapshotValue <- useHot SnapshotLoading

  let loadSnapshot = launchAff_ do
        result <- getSnapshot userId
        liftEffect $ case result of
          Left err   -> setSnapshot (SnapshotError err)
          Right snap -> setSnapshot (SnapshotLoaded snap)

  D.div
    [ DA.klass_ "admin-dashboard"
    , DL.load_ \_ -> loadSnapshot
    ]
    [ D.div [ DA.klass_ "admin-header" ]
        [ D.h1 [ DA.klass_ "admin-title" ] [ text_ "Admin Dashboard" ]
        , D.button
            [ DA.klass_ "btn btn-sm"
            , DL.click_ \_ -> do
                setSnapshot SnapshotLoading
                loadSnapshot
            ]
            [ text_ "Refresh" ]
        ]

    , D.div [ DA.klass_ "admin-tabs" ]
        ( map
            ( \t ->
                D.button
                  [ DA.klass $ tabValue <#> \active ->
                      "admin-tab" <> if active == t then " active" else ""
                  , DL.click_ \_ -> setTab t
                  ]
                  [ text_ (show t) ]
            )
            allTabs
        )

    , tabValue <#~> case _ of
        TabOverview     -> overview snapshotValue
        TabLogViewer    -> logViewer userId
        TabFeedMonitor  -> feedMonitor userId
        TabEventStream  -> D.div_ [ text_ "Event stream — coming soon" ]
        TabTransactions -> D.div_ [ text_ "Transactions — coming soon" ]
        TabSessions     -> D.div_ [ text_ "Sessions — coming soon" ]
        TabRegisters    -> D.div_ [ text_ "Registers — coming soon" ]
        TabDomainEvents -> D.div_ [ text_ "Domain Events — coming soon" ]
        TabActions      -> D.div_ [ text_ "Actions — coming soon" ]
    ]