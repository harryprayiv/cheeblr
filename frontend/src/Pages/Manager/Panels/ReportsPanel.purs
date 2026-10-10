module Pages.Manager.Panels.ReportsPanel where

import Prelude

import API.Manager (getDailyReport)
import Config.Entity (dummyLocationId)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Effect.Class (liftEffect)
import Effect.Now (nowDateTime)
import Types.RemoteData (RemoteData(..))
import UI.Remote (standardView, useRemote, viewRemote)
import Utils.Formatting (formatCentsToDollars)

-- The request carries the current time and the configured location because
-- the backend decodes both fields. The backend then reports its own UTC
-- day and does not read either of them.
reportsPanel :: Nut
reportsPanel = Deku.do
  report <- useRemote NotAsked do
    date <- liftEffect nowDateTime
    getDailyReport
      { dailyReportDate: date
      , dailyReportLocationId: dummyLocationId
      }

  D.div [ DA.klass_ "reports-panel" ]
    [ D.h3_ [ text_ "Daily Report" ]
    , D.button
        [ DA.klass_ "btn btn-primary"
        , DL.click_ \_ -> report.reload
        ]
        [ text_ "Generate Report" ]
    , report.value # viewRemote (standardView "Generating...") \r ->
        D.div [ DA.klass_ "report-results" ]
          [ D.div_ [ text_ $ "Revenue: $" <> formatCentsToDollars r.dailyReportTotal ]
          , D.div_ [ text_ $ "Transactions: " <> show r.dailyReportTransactions ]
          , D.div_ [ text_ $ "Cash: $" <> formatCentsToDollars r.dailyReportCash ]
          , D.div_ [ text_ $ "Card: $" <> formatCentsToDollars r.dailyReportCard ]
          ]
    ]
