{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Requires in cheeblr-backend.cabal build-depends:
--   websockets
--   wai-websockets

module Server.Feed (feedServerImpl) where

import Control.Concurrent.STM (atomically, readTChan, readTVarIO)
import Control.Exception (catch)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import Data.Int (Int64)
import Data.Maybe (listToMaybe)
import Data.Time (getCurrentTime)
import Network.HTTP.Types.Header (hContentType)
import Network.HTTP.Types.Status (status200, status400, status404)
import Network.Wai (pathInfo, responseLBS)
import Network.Wai.Handler.WebSockets (websocketsOr)
import qualified Network.WebSockets as WS
import Servant

import API.Feed (FeedAPI)
import Infrastructure.AvailabilityState (
  allAvailableItems,
  asLocName,
  asPublicLocId,
 )
import Infrastructure.Broadcast (
  Broadcaster (..),
  currentSeq,
  historyFrom,
  subChan,
  subscribe,
 )
import Server.Env (AppEnv (..))
import Types.Events.Availability (AvailabilityUpdate (..))
import Types.Public.AvailableItem (AvailableItem, aiInStock)
import Types.Public.FeedFrame (FeedStatus (..), mkFeedFrame)

-- ---------------------------------------------------------------------------
-- Top-level server
-- ---------------------------------------------------------------------------

feedServerImpl :: AppEnv -> Server FeedAPI
feedServerImpl env =
  (feedSubscribeApp env :<|> feedStatusHandler env)
    :<|> lexiconsApp
    :<|> feedSnapshotHandler env

-- ---------------------------------------------------------------------------
-- WebSocket subscription endpoint
-- ---------------------------------------------------------------------------

feedSubscribeApp :: AppEnv -> Maybe Int64 -> Tagged Handler Application
feedSubscribeApp env cursor =
  Tagged $
    websocketsOr WS.defaultConnectionOptions (wsHandler env cursor) fallback
  where
    fallback :: Application
    fallback _req resp =
      resp $ responseLBS status400 [] "WebSocket connection required"

wsHandler :: AppEnv -> Maybe Int64 -> WS.ServerApp
wsHandler env cursor pending = do
  conn <- WS.acceptRequest pending

  let
    sendFrame :: Int64 -> AvailabilityUpdate -> IO ()
    sendFrame s u = WS.sendTextData conn (Aeson.encode (mkFeedFrame s u))

  case cursor of
    -- Reconnect: replay broadcaster history since the given sequence number.
    Just c -> do
      history <- historyFrom (envAvailabilityBroadcaster env) c
      mapM_ (uncurry sendFrame) (toList history)

    -- Fresh connect: send the full current snapshot so the monitor shows
    -- live data immediately rather than waiting for the next inventory
    -- change to trigger a broadcaster event. Without this, the page is
    -- empty until something in the inventory changes.
    Nothing -> do
      st <- readTVarIO (envAvailabilityState env)
      now <- getCurrentTime
      seq' <- currentSeq (envAvailabilityBroadcaster env)
      let upds = map (`AvailabilityUpdate` now) (allAvailableItems st now)
      mapM_ (sendFrame seq') upds

  -- Subscribe to live events and stream them indefinitely.
  sub <- subscribe (envAvailabilityBroadcaster env)
  WS.withPingThread conn 30 (pure ()) $
    let loop = do
          upd <- atomically (readTChan (subChan sub))
          seq' <- currentSeq (envAvailabilityBroadcaster env)
          sendFrame seq' upd
          loop
     in loop `catch` (\(_ :: WS.ConnectionException) -> pure ())

-- ---------------------------------------------------------------------------
-- Status endpoint
-- ---------------------------------------------------------------------------

feedStatusHandler :: AppEnv -> Handler FeedStatus
feedStatusHandler env = liftIO $ do
  st <- readTVarIO (envAvailabilityState env)
  seq' <- currentSeq (envAvailabilityBroadcaster env)
  now <- getCurrentTime
  hist <- readTVarIO (bHistory (envAvailabilityBroadcaster env))
  let
    items = allAvailableItems st now
    inStockCount = length (filter aiInStock items)
    oldSeq = fst <$> listToMaybe (toList hist)
  pure
    FeedStatus
      { fsLocationId = asPublicLocId st
      , fsLocationName = asLocName st
      , fsCurrentSeq = seq'
      , fsItemCount = length items
      , fsInStockCount = inStockCount
      , fsOldestSeq = oldSeq
      }

-- ---------------------------------------------------------------------------
-- Snapshot endpoint (polling fallback)
-- ---------------------------------------------------------------------------

feedSnapshotHandler :: AppEnv -> Handler [AvailableItem]
feedSnapshotHandler env = liftIO $ do
  st <- readTVarIO (envAvailabilityState env)
  now <- getCurrentTime
  pure (allAvailableItems st now)

-- ---------------------------------------------------------------------------
-- Lexicons (embedded ATProto schema definitions)
-- ---------------------------------------------------------------------------

lexiconsApp :: Tagged Handler Application
lexiconsApp = Tagged $ \req resp ->
  case pathInfo req of
    ["app", "cheeblr", "inventory", "availableItem.json"] ->
      resp $ jsonResponse availableItemLexicon
    ["app", "cheeblr", "feed", "subscribe.json"] ->
      resp $ jsonResponse subscribeLexicon
    ["app", "cheeblr", "feed", "status.json"] ->
      resp $ jsonResponse statusLexicon
    _ ->
      resp $ responseLBS status404 [] "Lexicon not found"
  where
    jsonResponse body =
      responseLBS status200 [(hContentType, "application/json")] body

availableItemLexicon :: LBS.ByteString
availableItemLexicon =
  "{\"lexicon\":1,\"id\":\"app.cheeblr.inventory.availableItem\",\"defs\":{\"main\":{\"type\":\"object\",\"description\":\"The current publicly available state of one inventory item at one location.\",\"required\":[\"publicSku\",\"name\",\"brand\",\"category\",\"subcategory\",\"measureUnit\",\"perPackage\",\"thc\",\"cbg\",\"strain\",\"species\",\"dominantTerpene\",\"tags\",\"effects\",\"pricePerUnit\",\"availableQty\",\"inStock\",\"locationId\",\"locationName\",\"updatedAt\"],\"properties\":{\"publicSku\":{\"type\":\"string\",\"description\":\"Opaque public identifier for this item at this location.\"},\"name\":{\"type\":\"string\"},\"brand\":{\"type\":\"string\"},\"category\":{\"type\":\"string\",\"description\":\"Flower, Edibles, Vaporizers, etc.\"},\"subcategory\":{\"type\":\"string\"},\"measureUnit\":{\"type\":\"string\"},\"perPackage\":{\"type\":\"string\"},\"thc\":{\"type\":\"string\",\"description\":\"e.g. '25%'\"},\"cbg\":{\"type\":\"string\"},\"strain\":{\"type\":\"string\"},\"species\":{\"type\":\"string\",\"description\":\"Indica, Sativa, Hybrid, etc.\"},\"dominantTerpene\":{\"type\":\"string\"},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"effects\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"pricePerUnit\":{\"type\":\"integer\",\"description\":\"Price in cents.\"},\"availableQty\":{\"type\":\"integer\",\"description\":\"Units currently available to purchase. Never negative.\"},\"inStock\":{\"type\":\"boolean\"},\"locationId\":{\"type\":\"string\",\"description\":\"Stable public identifier for this location.\"},\"locationName\":{\"type\":\"string\"},\"updatedAt\":{\"type\":\"string\",\"format\":\"datetime\"}}}}}"

subscribeLexicon :: LBS.ByteString
subscribeLexicon =
  "{\"lexicon\":1,\"id\":\"app.cheeblr.feed.subscribe\",\"defs\":{\"main\":{\"type\":\"query\",\"description\":\"Subscribe to the real-time inventory availability feed for this location.\",\"parameters\":{\"type\":\"params\",\"properties\":{\"cursor\":{\"type\":\"integer\",\"description\":\"Resume from this sequence number. Omit to start from current position.\"}}},\"output\":{\"encoding\":\"application/json\",\"schema\":{\"$ref\":\"#/defs/frame\"}}},\"frame\":{\"type\":\"object\",\"required\":[\"seq\",\"type\",\"payload\",\"timestamp\"],\"properties\":{\"seq\":{\"type\":\"integer\"},\"type\":{\"type\":\"string\",\"const\":\"app.cheeblr.inventory.availableItem\"},\"payload\":{\"$ref\":\"app.cheeblr.inventory.availableItem#main\"},\"timestamp\":{\"type\":\"string\",\"format\":\"datetime\"}}}}}"

statusLexicon :: LBS.ByteString
statusLexicon =
  "{\"lexicon\":1,\"id\":\"app.cheeblr.feed.status\",\"defs\":{\"main\":{\"type\":\"query\",\"description\":\"Current status of this location's inventory feed.\",\"output\":{\"encoding\":\"application/json\",\"schema\":{\"type\":\"object\",\"required\":[\"locationId\",\"locationName\",\"currentSeq\",\"itemCount\"],\"properties\":{\"locationId\":{\"type\":\"string\"},\"locationName\":{\"type\":\"string\"},\"currentSeq\":{\"type\":\"integer\"},\"itemCount\":{\"type\":\"integer\"},\"inStockCount\":{\"type\":\"integer\"},\"oldestSeq\":{\"type\":\"integer\"}}}}}}}"
