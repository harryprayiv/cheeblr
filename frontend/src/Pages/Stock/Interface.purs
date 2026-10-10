module Pages.Stock.Interface where

import Prelude

import API.Request as Request
import API.Stock as API
import Data.Array (any, filter, length, null)
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import Effect.Unsafe (unsafePerformEffect)
import Pages.Admin.Components.SSEStatus (sseStatus)
import Pages.Stock.Components.AlertBanner (alertBanner, requestNotificationPermission, showPullNotification)
import Pages.Stock.Components.MessageThread (messageThread)
import Pages.Stock.Components.PullCard (pullCard)
import Types.Stock (PullAction(..), PullMessage, PullRequest)
import Types.UUID (UUID)
import UI.Leave (OnLeave)
import UI.Remote (onMount)
import Utils.Audio (AlertSound(..), playSound)
import Utils.SSE (SSEConnection, openSSE)
import Config.Entity (dummyLocationId)
import Types.Location (LocationId(..))

useRef :: forall a. a -> (Ref.Ref a -> Nut) -> Nut
useRef initial cont = unsafePerformEffect do
  ref <- Ref.new initial
  pure (cont ref)

page :: OnLeave -> Nut
page onLeave = Deku.do
  setQueue    /\ queueValue    <- useHot ([] :: Array PullRequest)
  setStatus   /\ statusValue   <- useHot ""
  setLoading  /\ loadingValue  <- useHot false
  setSelected /\ selectedValue <- useHot (Nothing :: Maybe UUID)
  setMessages /\ messagesValue <- useHot ([] :: Array PullMessage)
  setSseConn  /\ sseConnValue  <- useHot (Nothing :: Maybe SSEConnection)
  setNewPull  /\ newPullValue  <- useHot (Nothing :: Maybe PullRequest)
  prevQueueRef <- useRef ([] :: Array PullRequest)

  let
    loadMessages :: UUID -> Aff Unit
    loadMessages pullId = do
      result <- API.getMessages pullId
      liftEffect $ case result of
        Left err   -> setStatus $ "Message load error: " <> Request.describe err
        Right msgs -> setMessages msgs

    loadQueue :: Effect Unit
    loadQueue = launchAff_ do
      liftEffect $ setLoading true
      result <- API.getQueue (Just (LocationId dummyLocationId))
      liftEffect $ case result of
        Left err -> do
          setStatus $ "Error loading queue: " <> Request.describe err
          setLoading false
        Right pulls -> do
          prev <- Ref.read prevQueueRef
          let prevIds  = map _.prId prev
              newPulls = filter (\pr -> not (any (_ == pr.prId) prevIds)) pulls
          Ref.write pulls prevQueueRef
          setQueue pulls
          setStatus $ show (length pulls) <> " item(s) in queue"
          setLoading false

          when (not (null prev) && not (null newPulls)) $
            for_ newPulls \pr -> do
              playSound SoundInfo
              showPullNotification pr.prItemName (show pr.prId)
              setNewPull (Just pr)

    handleSelect :: UUID -> Effect Unit
    handleSelect pullId = do
      setSelected (Just pullId)
      setMessages []
      launchAff_ (loadMessages pullId)

    handleDeselect :: Effect Unit
    handleDeselect = do
      setSelected Nothing
      setMessages []

    handleAction :: UUID -> PullAction -> Effect Unit
    handleAction pullId action = launchAff_ do
      result <- case action of
        ActionAccept      -> API.acceptPull pullId
        ActionStart       -> API.startPull pullId
        ActionFulfill     -> API.fulfillPull pullId
        ActionRetry       -> API.retryPull pullId
        ActionCancel      -> API.cancelPull pullId "Cancelled"
        ActionReportIssue -> API.reportIssue pullId "Issue reported"
      liftEffect $ case result of
        Left err -> setStatus $ "Error: " <> Request.describe err
        Right _  -> do
          setStatus "Action completed"
          loadQueue

    connectSSE :: Effect Unit
    connectSSE = do
      requestNotificationPermission
      conn <- openSSE API.queueStreamUrl \_ -> loadQueue
      onLeave conn.close
      setSseConn (Just conn)

  D.div
    [ DA.klass_ "stock-interface"
    , onMount do
        loadQueue
        connectSSE
    ]
    [ D.div [ DA.klass_ "stock-header" ]
        [ D.h1_ [ text_ "Stock Room" ]
        , D.div [ DA.klass_ "stock-header-controls" ]
            [ sseConnValue <#~> \mConn ->
                case mConn of
                  Nothing   -> D.span_ []
                  Just conn -> sseStatus conn.status
            , D.button
                [ DA.klass_ "btn btn-primary"
                , DL.click_ \_ -> loadQueue
                ]
                [ text_ "Refresh" ]
            ]
        ]

    , alertBanner newPullValue handleSelect (setNewPull Nothing)

    , D.div [ DA.klass_ "status-bar" ] [ text statusValue ]

    , loadingValue <#~> \loading ->
        if loading
          then D.div [ DA.klass_ "loading-indicator" ] [ text_ "Loading..." ]
          else D.div_ []

    , D.div [ DA.klass_ "stock-layout" ]
        [ D.div [ DA.klass_ "stock-queue-panel" ]
            [ queueValue <#~> \queue ->
                if null queue
                  then D.div [ DA.klass_ "empty-queue" ] [ text_ "Queue is empty" ]
                  else D.div [ DA.klass_ "pull-queue" ]
                         ( map (\pr -> pullCard pr handleAction handleSelect) queue )
            ]

        , selectedValue <#~> \mSel ->
            case mSel of
              Nothing ->
                D.div [ DA.klass_ "stock-detail-panel stock-detail-empty" ]
                  [ text_ "Select a pull request to view its messages" ]
              Just pullId ->
                D.div [ DA.klass_ "stock-detail-panel" ]
                  [ D.div [ DA.klass_ "detail-header" ]
                      [ D.h3_ [ text_ "Messages" ]
                      , D.button
                          [ DA.klass_ "btn btn-sm"
                          , DL.click_ \_ -> handleDeselect
                          ]
                          [ text_ "✕" ]
                      ]
                  , messageThread messagesValue \msg -> launchAff_ do
                      result <- API.sendMessage pullId msg
                      case result of
                        Left err -> liftEffect $ setStatus $ "Send error: " <> Request.describe err
                        Right _  -> loadMessages pullId
                  ]
        ]
    ]

