module Infrastructure.SSE
  ( sseStream
  , sendEvent
  ) where

import           Control.Concurrent.STM    (atomically, readTChan)
import           Data.Aeson                (ToJSON, encode)
import           Data.Int                  (Int64)
import qualified Data.ByteString.Builder   as Builder
import           Data.Sequence             (Seq)
import qualified Data.Sequence             as Seq
import           Network.HTTP.Types        (status200)
import           Network.Wai               (Application, StreamingBody,
                                             responseStream)

import Infrastructure.Broadcast (Broadcaster, Subscription (..), currentSeq,
                                  historyFrom, subscribe)

-- | Serve a Broadcaster as an SSE stream over a WAI Application.
-- The optional cursor is the Last-Event-ID value from a reconnecting client.
-- History from that cursor is replayed before streaming live events.
sseStream :: ToJSON a => Broadcaster a -> Maybe Int64 -> Application
sseStream broadcaster mCursor _req respond = do
  history <- case mCursor of
    Nothing -> pure Seq.empty
    Just c  -> historyFrom broadcaster c
  sub <- subscribe broadcaster
  respond $ responseStream status200 headers (body history sub)
  where
    headers =
      [ ("Content-Type",  "text/event-stream")
      , ("Cache-Control", "no-cache")
      , ("Connection",    "keep-alive")
      ]

    body :: Seq (Int64, a) -> Subscription a -> StreamingBody
    body history sub write _flush = do
      mapM_ (\(seq', evt) -> sendEvent write seq' evt) (Seq.toList history)
      let loop = do
            evt  <- atomically $ readTChan (subChan sub)
            seq' <- currentSeq broadcaster
            sendEvent write seq' evt
            loop
      loop

sendEvent :: ToJSON a => (Builder.Builder -> IO ()) -> Int64 -> a -> IO ()
sendEvent write seq' evt = do
  write $  Builder.byteString "id: "
        <> Builder.string8 (show seq')
        <> Builder.byteString "\n"
  write $  Builder.byteString "data: "
        <> Builder.lazyByteString (encode evt)
        <> Builder.byteString "\n\n"