module Pages.Admin.Tabs.Overview where

import Prelude

import Data.Array (length)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Pages.Admin.State (SnapshotStatus(..))

overview :: Poll SnapshotStatus -> Nut
overview statusPoll =
  statusPoll <#~> case _ of
    SnapshotLoading ->
      D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading snapshot..." ]

    SnapshotError err ->
      D.div [ DA.klass_ "error-message" ] [ text_ $ "Error: " <> err ]

    SnapshotLoaded snap ->
      D.div [ DA.klass_ "admin-overview" ]
        [ D.h2 [ DA.klass_ "admin-section-title" ] [ text_ "System Overview" ]

        , D.div [ DA.klass_ "overview-grid" ]
            [ statCard "Uptime"
                (show snap.snapshotUptimeSeconds <> "s")

            , statCard "Environment"
                snap.snapshotEnvironment

            , statCard "Active Sessions"
                (show (length snap.snapshotActiveSessions))

            , statCard "Open Registers"
                (show (length snap.snapshotOpenRegisters))

            , statCard "Items in Stock"
                (show snap.snapshotAvailabilitySummary.avInStockCount <>
                 " / " <>
                 show snap.snapshotAvailabilitySummary.avTotalItems)

            , statCard "Low Stock Items"
                (show snap.snapshotInventorySummary.invLowStockCount)

            , statCard "Log Buffer Depth"
                (show snap.snapshotBroadcasterStats.bcLogDepth)

            , statCard "Domain Events Seq"
                (show snap.snapshotBroadcasterStats.bcAvailabilitySeq)

            , statCard "DB Pool Size"
                (show snap.snapshotDbStats.dbPoolSize)
            ]
        ]

statCard :: String -> String -> Nut
statCard label value =
  D.div [ DA.klass_ "stat-card" ]
    [ D.div [ DA.klass_ "stat-label" ] [ text_ label ]
    , D.div [ DA.klass_ "stat-value" ] [ text_ value ]
    ]