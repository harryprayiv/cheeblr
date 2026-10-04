module Pages.Admin.Dashboard where

import API.Admin (getSnapshot)
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import FRP.Poll (Poll)
import Pages.Admin.State (AdminTab(..), allTabs)
import Pages.Admin.Tabs.FeedMonitor (feedMonitor)
import Pages.Admin.Tabs.LogViewer (logViewer)
import Pages.Admin.Tabs.Overview (overview)
import Services.AuthService (AuthState, UserId)
import Types.RemoteData (RemoteData(..))
import UI.Remote (onMount, useRemote)
import UI.Tabs (tabBar)

page :: Poll AuthState -> UserId -> Nut
page _authPoll userId = Deku.do
  setTab /\ tabValue <- useHot TabOverview
  snapshot <- useRemote Loading (getSnapshot userId)

  D.div
    [ DA.klass_ "admin-dashboard"
    , onMount snapshot.reload
    ]
    [ D.div [ DA.klass_ "admin-header" ]
        [ D.h1 [ DA.klass_ "admin-title" ] [ text_ "Admin Dashboard" ]
        , D.button
            [ DA.klass_ "btn btn-sm"
            , DL.click_ \_ -> snapshot.reload
            ]
            [ text_ "Refresh" ]
        ]

    , tabBar { bar: "admin-tabs", tab: "admin-tab" } allTabs tabValue setTab

    , tabValue <#~> case _ of
        TabOverview     -> overview snapshot.value
        TabLogViewer    -> logViewer userId
        TabFeedMonitor  -> feedMonitor userId
        TabEventStream  -> D.div_ [ text_ "Event stream — coming soon" ]
        TabTransactions -> D.div_ [ text_ "Transactions — coming soon" ]
        TabSessions     -> D.div_ [ text_ "Sessions — coming soon" ]
        TabRegisters    -> D.div_ [ text_ "Registers — coming soon" ]
        TabDomainEvents -> D.div_ [ text_ "Domain Events — coming soon" ]
        TabActions      -> D.div_ [ text_ "Actions — coming soon" ]
    ]