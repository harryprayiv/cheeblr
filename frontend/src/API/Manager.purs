module API.Manager where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Config.Network (currentConfig)
import Data.Either (Either)
import Effect.Aff (Aff)
import Types.Inventory (MutationResponse)
import Types.Manager (ActivitySummary, DailyReportRequest, DailyReportResult, ManagerAlert)
import Types.UUID (UUID)

getActivity :: Aff (Either ApiError ActivitySummary)
getActivity = Request.get "/manager/activity"

getAlerts :: Aff (Either ApiError (Array ManagerAlert))
getAlerts = Request.get "/manager/alerts"

getDailyReport :: DailyReportRequest -> Aff (Either ApiError DailyReportResult)
getDailyReport req = Request.post "/manager/reports/daily" req

-- Needs capCanVoidTransaction (403). The backend takes the acting user from
-- the session and does not read orActorId, but the field is required in the
-- request body. Send the caller's own id.
overrideVoid :: UUID -> UUID -> String -> Aff (Either ApiError MutationResponse)
overrideVoid saleId actorId reason =
  Request.post ("/manager/override/void/" <> show saleId)
    { orActorId: actorId, orReason: reason }

-- Authenticated by the session cookie. See Utils.SSE.
activityStreamUrl :: String
activityStreamUrl = currentConfig.apiBaseUrl <> "/manager/activity/stream"
