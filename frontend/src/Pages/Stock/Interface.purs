module Pages.Stock.Interface where

import Prelude

import API.Stock as API
import Data.Array (length, null)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import FRP.Poll (Poll)
import Pages.Stock.Components.PullCard (pullCard)
import Services.AuthService (AuthState, UserId)
import Types.Stock (PullAction(..), PullRequest)
import Types.UUID (UUID)
import Deku.Control (text, text_)

page :: Poll AuthState -> UserId -> Nut
page _authPoll userId = Deku.do
  setQueue   /\ queueValue   <- useHot ([] :: Array PullRequest)
  setStatus  /\ statusValue  <- useHot ""
  setLoading /\ loadingValue <- useHot false

  let
    loadQueue = launchAff_ do
      liftEffect $ setLoading true
      result <- API.getQueue userId Nothing
      liftEffect $ case result of
        Left err -> do
          setStatus $ "Error: " <> err
          setLoading false
        Right pulls -> do
          setQueue pulls
          setStatus $ show (length pulls) <> " items in queue"
          setLoading false

    handleAction :: UUID -> PullAction -> Effect Unit
    handleAction pullId action = launchAff_ do
      result <- case action of
        ActionAccept      -> API.acceptPull  userId pullId
        ActionStart       -> API.startPull   userId pullId
        ActionFulfill     -> API.fulfillPull userId pullId
        ActionRetry       -> API.retryPull   userId pullId
        ActionCancel      -> API.reportIssue userId pullId "Cancelled"
        ActionReportIssue -> API.reportIssue userId pullId "Issue reported"
      liftEffect $ case result of
        Left err -> setStatus $ "Error: " <> err
        Right _  -> do
          setStatus "Action completed"
          loadQueue

  D.div
    [ DA.klass_ "stock-interface"
    , DL.load_ \_ -> loadQueue
    ]
    [ D.div [ DA.klass_ "stock-header" ]
        [ D.h1_ [ text_ "Stock Room" ]
        , D.button
            [ DA.klass_ "btn btn-primary"
            , DL.click_ \_ -> loadQueue
            ]
            [ text_ "Refresh" ]
        ]
    , D.div [ DA.klass_ "status-bar" ] [ text statusValue ]
    , loadingValue <#~> \loading ->
        if loading
          then D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading..." ]
          else D.div_ []
    , queueValue <#~> \queue ->
        if null queue
          then D.div [ DA.klass_ "empty-queue" ] [ text_ "Queue is empty" ]
          else D.div [ DA.klass_ "pull-queue" ]
                 (map (\pr -> pullCard pr handleAction) queue)
    ]