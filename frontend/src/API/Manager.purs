module API.Manager where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Manager (ActivitySummary, ManagerAlertRaw, DailyReportResult)
import Types.Inventory (MutationResponse)

getActivity :: UserId -> Aff (Either String ActivitySummary)
getActivity userId = Request.authGet userId "/manager/activity"

getAlerts :: UserId -> Aff (Either String (Array ManagerAlertRaw))
getAlerts userId = Request.authGet userId "/manager/alerts"

getDailyReport
  :: UserId
  -> { dailyReportDate :: String, dailyReportLocationId :: String }
  -> Aff (Either String DailyReportResult)
getDailyReport userId req =
  Request.authPost userId "/manager/reports/daily" req

overrideVoid :: UserId -> String -> String -> String -> Aff (Either String MutationResponse)
overrideVoid userId txId actorId reason =
  Request.authPost userId ("/manager/override/void/" <> txId)
    { orActorId: actorId, orReason: reason }

activityStreamUrl :: String -> String -> String
activityStreamUrl apiBase token =
  apiBase <> "/manager/activity/stream?authorization=Bearer+" <> token