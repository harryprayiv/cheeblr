{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Feed (FeedAPI) where

import Data.Int (Int64)
import Servant

import Types.Public.AvailableItem (AvailableItem)
import Types.Public.FeedFrame (FeedStatus)

-- | Public, unauthenticated feed API.
--
-- These routes sit entirely outside the authenticated server.
--
-- /xrpc/app.cheeblr.feed.subscribe  WebSocket stream (Raw, upgraded by
--                                    wai-websockets). Accepts optional
--                                    ?cursor=N to replay history.
-- /xrpc/app.cheeblr.feed.status     Current feed status as JSON.
-- /lexicons                           Embedded ATProto lexicon JSON files.
-- /feed/snapshot                      Complete current state as JSON array.
--                                    Polling fallback for aggregators that
--                                    cannot maintain a persistent connection.
type FeedAPI =
  "xrpc"
    :> ( "app.cheeblr.feed.subscribe"
           :> QueryParam "cursor" Int64
           :> Raw
           :<|> "app.cheeblr.feed.status"
             :> Get '[JSON] FeedStatus
       )
    :<|> "lexicons" :> Raw
    :<|> "feed" :> "snapshot" :> Get '[JSON] [AvailableItem]