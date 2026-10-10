module Pages.Admin.Tabs.LogViewer where

import Prelude

import API.Admin (logStreamUrl)
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
import Effect (Effect)
import Effect.Class.Console as Console
import Effect.Ref as Ref
import Pages.Admin.Components.SSEStatus (sseStatus)
import Types.Admin (LogEvent)
import UI.Leave (OnLeave)
import Utils.SSE (SSEConnection, openSSE)
import Yoga.JSON (readJSON_)

maxLogEntries :: Int
maxLogEntries = 500

logViewer :: OnLeave -> Nut
logViewer onLeave = Deku.do
  setEntries /\ entriesValue <- useHot ([] :: Array LogEvent)
  setSseConn /\ sseConnValue <- useHot (Nothing :: Maybe SSEConnection)

  let
    -- The entries received so far live in a Ref owned by the connection.
    -- Each message is put in front and the list is cut to maxLogEntries.
    connect :: Effect Unit
    connect = do
      entriesRef <- Ref.new ([] :: Array LogEvent)
      conn <- openSSE logStreamUrl \rawMsg ->
        case readJSON_ rawMsg :: Maybe LogEvent of
          Nothing -> Console.warn $ "Failed to parse log: " <> rawMsg
          Just evt -> do
            next <- Ref.modify (take maxLogEntries <<< (evt : _)) entriesRef
            setEntries next
      onLeave conn.close
      setEntries []
      setSseConn (Just conn)

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
                , DL.runOn DL.click $ sseConnValue <#> \mConn ->
                    case mConn of
                      Just _  -> pure unit
                      Nothing -> connect
                ]
                [ text_ "Connect" ]
            , D.button
                [ DA.klass_ "btn btn-secondary"
                , DL.runOn DL.click $ sseConnValue <#> \mConn ->
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
