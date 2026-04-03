{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Infrastructure.SSE
  ( sseStream
  , sendEvent
  ) where

import           Control.Concurrent.STM    (atomically, readTChan)
import           Data.Aeson                (ToJSON, encode)
import           Data.Int                  (Int64)
import qualified Data.ByteString.Builder   as Builder
import qualified Data.ByteString.Char8     as B8
import qualified Data.CaseInsensitive      as CI
import           Data.Foldable             (toList)
import           Data.Sequence             (Seq)
import qualified Data.Sequence             as Seq
import           Network.HTTP.Types        (status200)
import           Network.Wai               (Application, StreamingBody,
                                             responseStream)

import Infrastructure.Broadcast (Broadcaster, Subscription (..), currentSeq,
                                  historyFrom, subscribe)

sseStream :: forall a. ToJSON a => Broadcaster a -> Maybe Int64 -> Application
sseStream broadcaster mCursor _req respond = do
  history <- case mCursor of
    Nothing -> pure Seq.empty
    Just c  -> historyFrom broadcaster c
  sub <- subscribe broadcaster
  respond $ responseStream status200 sseHeaders (sseBody history sub)
  where
    sseHeaders =
      [ (CI.mk (B8.pack "Content-Type"),  B8.pack "text/event-stream")
      , (CI.mk (B8.pack "Cache-Control"), B8.pack "no-cache")
      , (CI.mk (B8.pack "Connection"),    B8.pack "keep-alive")
      ]

    sseBody :: Seq (Int64, a) -> Subscription a -> StreamingBody
    sseBody history sub write _flush = do
      mapM_ (uncurry (sendEvent write)) (toList history)
      let loop = do
            evt  <- atomically $ readTChan (subChan sub)
            seq' <- currentSeq broadcaster
            sendEvent write seq' evt
            loop
      loop

sendEvent :: ToJSON a => (Builder.Builder -> IO ()) -> Int64 -> a -> IO ()
sendEvent write seq' evt = do
  write $  Builder.byteString (B8.pack "id: ")
        <> Builder.string8 (show seq')
        <> Builder.byteString (B8.pack "\n")
  write $  Builder.byteString (B8.pack "data: ")
        <> Builder.lazyByteString (encode evt)
        <> Builder.byteString (B8.pack "\n\n")