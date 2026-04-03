module Pages.Admin.Tabs.LogViewer where

import Prelude

import Config.Network (currentConfig)
import Data.Array (take, (:))
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect.Class.Console as Console
import Effect.Ref as Ref
import Pages.Admin.Components.SSEStatus (sseStatus)
import Services.AuthService (UserId)
import Types.Admin (LogEvent)
import Utils.SSE (SSEConnection, openSSE)
import Yoga.JSON (readJSON_)

maxLogEntries :: Int
maxLogEntries = 500

logViewer :: UserId -> Nut
logViewer userId = Deku.do
  setEntries  /\ entriesValue  <- useHot ([] :: Array LogEvent)
  setSseConn  /\ sseConnValue  <- useHot (Nothing :: Maybe SSEConnection)

  D.div [ DA.klass_ "log-viewer" ]
    [ D.div [ DA.klass_ "log-viewer-header" ]
        [ D.h3_ [ text_ "Log Stream" ]
        , sseConnValue <#~> \mConn ->
            case mConn of
              Nothing   -> D.span_ []
              Just conn -> sseStatus conn.status
        , D.div [ DA.klass_ "log-controls" ]
            [ D.button
                [ DA.klass_ "btn btn-primary"
                , DL.click_ \_ -> do
                    connRef <- Ref.new Nothing
                    let url = currentConfig.apiBaseUrl
                           <> "/admin/logs/stream"
                           <> "?authorization=Bearer+" <> userId
                    conn <- openSSE url \rawMsg ->
                      case readJSON_ rawMsg :: Maybe LogEvent of
                        Nothing  -> Console.warn $ "Failed to parse log: " <> rawMsg
                        Just evt -> do
                          cur <- Ref.read connRef
                          case cur of
                            Nothing -> pure unit
                            Just _  -> do
                              -- append to front, cap at max
                              setEntries <<< take maxLogEntries <<< (:) evt =<< pure []
                    Ref.write (Just conn) connRef
                    setSseConn (Just conn)
                ]
                [ text_ "Connect" ]
            , D.button
                [ DA.klass_ "btn btn-secondary"
                , DL.runOn DL.click $ sseConnValue <#> \mConn -> do
                    case mConn of
                      Just c  -> c.close *> setSseConn Nothing *> setEntries []
                      Nothing -> pure unit
                ]
                [ text_ "Disconnect" ]
            ]
        ]
    , entriesValue <#~> \entries ->
        D.div [ DA.klass_ "log-entries" ]
          ( map renderEntry entries )
    ]

renderEntry :: LogEvent -> Nut
renderEntry evt =
  D.div [ DA.klass_ $ "log-entry severity-" <> evt.leSeverity ]
    [ D.span [ DA.klass_ "log-severity"  ] [ text_ evt.leSeverity  ]
    , D.span [ DA.klass_ "log-component" ] [ text_ evt.leComponent ]
    , D.span [ DA.klass_ "log-message"   ] [ text_ evt.leMessage   ]
    ]