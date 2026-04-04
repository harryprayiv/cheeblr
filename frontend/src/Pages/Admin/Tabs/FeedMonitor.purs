module Pages.Admin.Tabs.FeedMonitor where

import Prelude

import Config.Network (currentConfig)
import Data.Array (null, take, (:))
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Data.Number.Format (fixed, toStringWith)
import Data.Tuple.Nested ((/\))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect (Effect)
import Effect.Class.Console as Console
import Effect.Ref as Ref
import Services.AuthService (UserId)
import Types.Feed (FeedFrame)
import Utils.WebSocket (WSConnection, closeWebSocket, openWebSocket, toWsUrl)
import Yoga.JSON (readJSON_)

maxFrames :: Int
maxFrames = 100

formatPrice :: Int -> String
formatPrice cents =
  "$" <> toStringWith (fixed 2) (toNumber cents / 100.0)

feedMonitor :: UserId -> Nut
feedMonitor _userId = Deku.do
  setFrames    /\ framesValue    <- useHot ([] :: Array FeedFrame)
  setStatus    /\ statusValue    <- useHot "Disconnected"
  setConnected /\ connectedValue <- useHot false
  setWsConn    /\ wsConnValue    <- useHot (Nothing :: Maybe WSConnection)

  let
    wsUrl :: String
    wsUrl = toWsUrl currentConfig.apiBaseUrl
         <> "/xrpc/app.cheeblr.feed.subscribe"

    connect :: Effect Unit
    connect = do
      connRef  <- Ref.new Nothing
      -- Accumulator ref so we can prepend without reading the Poll
      frameRef <- Ref.new ([] :: Array FeedFrame)
      conn <- openWebSocket wsUrl
        { onMessage: \raw -> case (readJSON_ raw :: Maybe FeedFrame) of
            Nothing    -> Console.warn $ "Failed to parse feed frame: " <> raw
            Just frame -> do
              mConn <- Ref.read connRef
              case mConn of
                Nothing -> pure unit
                Just _  -> do
                  cur <- Ref.read frameRef
                  let next = take maxFrames (frame : cur)
                  Ref.write next frameRef
                  setFrames next
        , onOpen:  do
            setStatus "Connected"
            setConnected true
        , onClose: do
            setStatus "Disconnected"
            setConnected false
            setWsConn Nothing
        , onError: do
            setStatus "Error"
            setConnected false
        }
      Ref.write (Just conn) connRef
      setWsConn (Just conn)
      setStatus "Connecting..."

  D.div [ DA.klass_ "feed-monitor" ]
    [ D.div [ DA.klass_ "feed-monitor-header" ]
        [ D.h3_ [ text_ "Public Inventory Feed" ]
        , D.div [ DA.klass_ "feed-status-bar" ]
            [ D.span
                [ DA.klass $ connectedValue <#> \c ->
                    "feed-status-dot " <> if c then "connected" else "disconnected"
                ]
                []
            , D.span [ DA.klass_ "feed-status-text" ] [ text statusValue ]
            ]
        , D.div [ DA.klass_ "feed-controls" ]
            [ D.button
                [ DA.klass_ "btn btn-primary"
                , DL.click_ \_ -> connect
                ]
                [ text_ "Connect" ]
            , D.button
                [ DA.klass_ "btn btn-secondary"
                , DL.runOn DL.click $ wsConnValue <#> \mConn ->
                    case mConn of
                      Nothing   -> pure unit
                      Just conn -> do
                        closeWebSocket conn
                        setWsConn Nothing
                        setStatus "Disconnected"
                        setConnected false
                ]
                [ text_ "Disconnect" ]
            , D.button
                [ DA.klass_ "btn btn-secondary"
                , DL.click_ \_ -> setFrames []
                ]
                [ text_ "Clear" ]
            ]
        ]

    , framesValue <#~> \frames ->
        if null frames
          then D.div [ DA.klass_ "feed-empty" ]
                 [ text_ "No frames received. Click Connect to start the feed." ]
          else D.div [ DA.klass_ "feed-frames" ]
                 ( map renderFrame (take maxFrames frames) )
    ]

renderFrame :: FeedFrame -> Nut
renderFrame frame =
  D.div [ DA.klass_ "feed-frame" ]
    [ D.div [ DA.klass_ "feed-frame-header" ]
        [ D.span [ DA.klass_ "feed-seq" ]
            [ text_ $ "#" <> show frame.seq <> " " ]
        , D.span [ DA.klass_ "feed-sku" ]
            [ text_ $ frame.payload.publicSku <> " " ]
        , D.span [ DA.klass_ "feed-name" ]
            [ text_ $ frame.payload.name <> " " ]
        , D.span [ DA.klass_ "feed-brand" ]
            [ text_ $ frame.payload.brand <> " · " ]
        , D.span [ DA.klass_ "feed-category" ]
            [ text_ $ frame.payload.category <> " " ]
        , D.span
            [ DA.klass_ $ "feed-stock-badge " <>
                if frame.payload.inStock then "in-stock" else "out-of-stock"
            ]
            [ text_ if frame.payload.inStock then "In Stock" else "Out of Stock" ]
        ]
    , D.div [ DA.klass_ "feed-frame-body" ]
        [ D.div_ [ text_ $ "Qty available: " <> show frame.payload.availableQty ]
        , D.div_ [ text_ $ "Price: " <> formatPrice frame.payload.pricePerUnit ]
        , D.div_ [ text_ $ "THC: " <> frame.payload.thc
                         <> "  CBG: " <> frame.payload.cbg ]
        , D.div_ [ text_ $ "Strain: " <> frame.payload.strain
                         <> " (" <> frame.payload.species <> ")" ]
        , D.div_ [ text_ $ "Location: " <> frame.payload.locationName ]
        , D.div_ [ text_ $ "Updated: " <> frame.payload.updatedAt ]
        ]
    ]