module Pages.Manager.Panels.ReportsPanel where

import Prelude

import API.Manager (getDailyReport)
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
import Services.AuthService (UserId)
import Types.Manager (DailyReportResult)
import Utils.Formatting (formatCentsToDollars)

data ReportStatus
  = ReportIdle
  | ReportLoading
  | ReportLoaded DailyReportResult
  | ReportError String

reportsPanel :: UserId -> Nut
reportsPanel userId = Deku.do
  setReport /\ reportValue <- useHot ReportIdle

  D.div [ DA.klass_ "reports-panel" ]
    [ D.h3_ [ text_ "Daily Report" ]
    , D.button
        [ DA.klass_ "btn btn-primary"
        , DL.click_ \_ -> do
            setReport ReportLoading
            launchAff_ do
              result <- getDailyReport userId
                { dailyReportDate: "today"
                , dailyReportLocationId: ""
                }
              liftEffect $ case result of
                Left err -> setReport (ReportError err)
                Right r  -> setReport (ReportLoaded r)
        ]
        [ text_ "Generate Report" ]
    , reportValue <#~> case _ of
        ReportIdle ->
          D.div_ []
        ReportLoading ->
          D.div [ DA.klass_ "loading-indicator" ] [ text_ "Generating..." ]
        ReportError err ->
          D.div [ DA.klass_ "error-message" ] [ text_ err ]
        ReportLoaded r ->
          D.div [ DA.klass_ "report-results" ]
            [ D.div_ [ text_ $ "Revenue: $" <> formatCentsToDollars r.dailyReportTotal ]
            , D.div_ [ text_ $ "Transactions: " <> show r.dailyReportTransactions ]
            , D.div_ [ text_ $ "Cash: $" <> formatCentsToDollars r.dailyReportCash ]
            , D.div_ [ text_ $ "Card: $" <> formatCentsToDollars r.dailyReportCard ]
            ]
    ]