{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- Observers: the three event streams, kept open for the whole run, and
-- what every accepted command must put on them.
--
-- An observer is the frontend's EventSource as the test sees it: one GET
-- with the session cookie, frames of "id:" and "data:" lines, decoded
-- here with the same small JSON parsers as everything else in the suite.
-- The admin stream carries every domain event; the manager's activity
-- stream the transaction events; the stock queue stream the stock events.
--
-- Responsiveness is a number here: the lag of an event is the time from
-- the command's HTTP answer arriving to the event arriving on a stream.
-- A negative lag means the event arrived before the answer, which is the
-- usual case, since the backend emits before it answers.
module Model.Observe
  ( Stream (..)
  , Observers
  , Frame (..)
  , Expect (..)
  , StreamReport (..)
  , openObservers
  , closeObservers
  , watermark
  , awaitExpected
  , framesSince
  , streamsFor
  , replayCheck
  , lagSummary
  ) where

import Control.Concurrent (forkIO, killThread, threadDelay, ThreadId)
import Control.Exception (SomeException, try)
import Control.Monad (forM, forM_, unless)
import Data.Aeson (Value (..), decode)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as LBS
import Data.IORef
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, diffUTCTime, getCurrentTime)
import qualified Network.HTTP.Client as HC
import Network.HTTP.Types.Status (statusCode)
import Text.Read (readMaybe)

import Model.Client (Http (..))

data Stream = AdminEvents | ManagerActivity | StockQueue
  deriving (Eq, Ord, Show, Enum, Bounded)

streamPath :: Stream -> String
streamPath AdminEvents     = "/admin/events/stream"
streamPath ManagerActivity = "/manager/activity/stream"
streamPath StockQueue      = "/stock/queue/stream"

-- The streams an event with the given outer tag must appear on.
streamsFor :: Text -> [Stream]
streamsFor outer =
  AdminEvents
    : [ManagerActivity | outer == "TransactionEvt"]
    ++ [StockQueue | outer == "StockEvt"]

data Frame = Frame
  { frameId      :: Integer
  , frameArrived :: UTCTime
  , frameOuter   :: Text
  , frameInner   :: Text
  , frameKey     :: Maybe Text
    -- ^ the sale, register or pull's sale the event is about
  , frameData    :: BS.ByteString
  }
  deriving (Eq, Show)

data Tap = Tap
  { tapFrames :: IORef [Frame]
    -- ^ newest first
  , tapCount  :: IORef Int
  , tapBad    :: IORef [String]
    -- ^ frames that did not decode, and the connection's end
  }

data Observers = Observers
  { obsTaps    :: Map Stream Tap
  , obsThreads :: [ThreadId]
  , obsLags    :: IORef [(Stream, Double)]
    -- ^ every lag measured, in milliseconds
  }

-- One SSE frame: the lines between two blank lines.
parseFrame :: BS.ByteString -> Either String (Integer, BS.ByteString)
parseFrame chunk =
  case (readMaybe . B8.unpack =<< field "id: ", field "data: ") of
    (Just i, Just d) -> Right (i, d)
    _                -> Left ("frame without id and data: " <> take 200 (B8.unpack chunk))
  where
    field prefix =
      case [BS.drop (BS.length prefix) l | l <- B8.lines chunk, prefix `BS.isPrefixOf` l] of
        (v : _) -> Just v
        []      -> Nothing

-- The tags and the key of an event as the backend encodes it: Aeson's
-- {tag, contents} for both the DomainEvent and the event inside it.
decodeEvent :: BS.ByteString -> Either String (Text, Text, Maybe Text)
decodeEvent raw =
  case decode (LBS.fromStrict raw) of
    Just (Object o)
      | Just (String outer) <- KM.lookup "tag" o
      , Just (Object c) <- KM.lookup "contents" o
      , Just (String inner) <- KM.lookup "tag" c ->
          Right (outer, inner, key c)
    _ -> Left ("event did not decode: " <> take 200 (B8.unpack raw))
  where
    str o k = case KM.lookup k o of
      Just (String s) -> Just s
      _               -> Nothing
    obj o k = case KM.lookup k o of
      Just (Object x) -> Just x
      _               -> Nothing
    key c =
      case [ v | Just v <- [str c "teTxId", str c "reRegId", obj c "teTx" >>= (`str` "transactionId"), obj c "sePull" >>= (`str` "prTransactionId")] ] of
        (v : _) -> Just v
        []      -> Nothing

readStream :: Http -> Text -> Stream -> Tap -> IO ()
readStream http token stream tap = do
  initial <- HC.parseRequest (httpBase http <> streamPath stream)
  let request =
        initial
          { HC.requestHeaders  = [("Accept", "text/event-stream"), ("Cookie", "cheeblr_session=" <> TE.encodeUtf8 token)]
          , HC.responseTimeout = HC.responseTimeoutNone
          }
  outcome <- try $ HC.withResponse request (httpManager http) $ \response -> do
    unless (statusCode (HC.responseStatus response) == 200) $
      modifyIORef' (tapBad tap) (("stream answered " <> show (statusCode (HC.responseStatus response))) :)
    let loop buffer = do
          chunk <- HC.brRead (HC.responseBody response)
          if BS.null chunk
            then modifyIORef' (tapBad tap) ("stream closed by the backend" :)
            else do
              rest <- consume (buffer <> chunk)
              loop rest
        consume buffer =
          case BS.breakSubstring "\n\n" buffer of
            (one, rest) | not (BS.null rest) -> do
              now <- getCurrentTime
              case parseFrame one of
                Left err -> modifyIORef' (tapBad tap) (err :)
                Right (i, d) ->
                  case decodeEvent d of
                    Left err -> modifyIORef' (tapBad tap) (err :)
                    Right (outer, inner, k) -> do
                      modifyIORef' (tapFrames tap) (Frame i now outer inner k d :)
                      modifyIORef' (tapCount tap) (+ 1)
              consume (BS.drop 2 rest)
            _ -> pure buffer
    loop BS.empty
  case outcome of
    Left (e :: SomeException) -> modifyIORef' (tapBad tap) (("stream reader stopped: " <> show e) :)
    Right ()                  -> pure ()

-- Opens the three streams with the given session and waits until each
-- has answered, so that no event of the run is missed.
openObservers :: Http -> Text -> IO Observers
openObservers http token = do
  taps <- forM [minBound .. maxBound] $ \stream -> do
    frames <- newIORef []
    count  <- newIORef 0
    bad    <- newIORef []
    let tap = Tap frames count bad
    tid <- forkIO (readStream http token stream tap)
    pure (stream, tap, tid)
  lags <- newIORef []
  -- Give the connections a moment to be established before commands start.
  threadDelay 300000
  pure
    Observers
      { obsTaps    = Map.fromList [(stream, tap) | (stream, tap, _) <- taps]
      , obsThreads = [tid | (_, _, tid) <- taps]
      , obsLags    = lags
      }

closeObservers :: Observers -> IO ()
closeObservers observers = forM_ (obsThreads observers) killThread

-- How many frames each stream has delivered so far.
watermark :: Observers -> IO (Map Stream Int)
watermark observers = traverse (readIORef . tapCount) (obsTaps observers)

-- The frames a stream delivered after a watermark, oldest first.
framesSince :: Observers -> Map Stream Int -> Stream -> IO [Frame]
framesSince observers marks stream = do
  let tap = obsTaps observers Map.! stream
  frames <- readIORef (tapFrames tap)
  count  <- readIORef (tapCount tap)
  let before = Map.findWithDefault 0 stream marks
  pure (reverse (take (count - before) frames))

-- An event a command must produce: its two tags and the id it is about.
data Expect = Expect
  { exOuter :: Text
  , exInner :: Text
  , exKey   :: Text
  }
  deriving (Eq, Show)

data StreamReport = StreamReport
  { srMissing :: [(Stream, Expect)]
    -- ^ expected but not delivered within the wait
  , srBad     :: [(Stream, String)]
    -- ^ frames that did not decode, and streams that closed
  }
  deriving (Eq, Show)

-- Waits for every expected event on every stream that must carry it, and
-- records each one's lag against the time the command was answered.
awaitExpected :: Observers -> Map Stream Int -> UTCTime -> [Expect] -> IO StreamReport
awaitExpected observers marks answeredAt expects = do
  let wanted = [(stream, e) | e <- expects, stream <- streamsFor (exOuter e)]
  missing <- go (60 :: Int) wanted
  bad <- forM (Map.toList (obsTaps observers)) $ \(stream, tap) -> do
    errors <- readIORef (tapBad tap)
    pure [(stream, err) | err <- errors]
  pure (StreamReport missing (concat bad))
  where
    matches e f = frameOuter f == exOuter e && frameInner f == exInner e && frameKey f == Just (exKey e)
    go _ [] = pure []
    go 0 wanted = pure wanted
    go n wanted = do
      still <- fmap concat . forM wanted $ \(stream, e) -> do
        frames <- framesSince observers marks stream
        case filter (matches e) frames of
          (f : _) -> do
            let lagMs = realToFrac (diffUTCTime (frameArrived f) answeredAt) * 1000 :: Double
            modifyIORef' (obsLags observers) ((stream, lagMs) :)
            pure []
          [] -> pure [(stream, e)]
      if null still
        then pure []
        else threadDelay 50000 >> go (n - 1) still

-- Reconnects to the admin stream with the cursor set just before the
-- first frame of a sequence and compares what the backend replays with
-- what was delivered live. Returns the first difference, if any.
replayCheck :: Http -> Text -> Observers -> Map Stream Int -> IO (Maybe String)
replayCheck http token observers marks = do
  live <- framesSince observers marks AdminEvents
  case live of
    [] -> pure Nothing
    (first : _) -> do
      initial <- HC.parseRequest (httpBase http <> streamPath AdminEvents <> "?cursor=" <> show (frameId first - 1))
      let request =
            initial
              { HC.requestHeaders  = [("Accept", "text/event-stream"), ("Cookie", "cheeblr_session=" <> TE.encodeUtf8 token)]
              , HC.responseTimeout = HC.responseTimeoutNone
              }
          wantedCount = length live
      collected <- newIORef BS.empty
      done <- newIORef False
      trouble <- newIORef ""
      tid <- forkIO $ do
        outcome <- try @SomeException $ HC.withResponse request (httpManager http) $ \response -> do
          unless (statusCode (HC.responseStatus response) == 200) $
            writeIORef trouble ("the reconnect answered " <> show (statusCode (HC.responseStatus response)))
          let loop = do
                chunk <- HC.brRead (HC.responseBody response)
                unless (BS.null chunk) $ do
                  modifyIORef' collected (<> chunk)
                  buffer <- readIORef collected
                  if length (completeFrames buffer) >= wantedCount then writeIORef done True else loop
          loop
        case outcome of
          Left e   -> writeIORef trouble ("the reconnect failed: " <> show e)
          Right () -> pure ()
      waitFor (40 :: Int) done
      killThread tid
      buffer <- readIORef collected
      problem <- readIORef trouble
      let replayed = mapMaybe (either (const Nothing) Just . parseFrame) (completeFrames buffer)
          liveIds  = [(frameId f, frameData f) | f <- live]
      pure $
        if take wantedCount replayed == liveIds
          then Nothing
          else
            Just
              ( "live:     " <> show (map fst liveIds)
                  <> "\nreplayed: " <> show (map fst (take wantedCount replayed))
                  <> (if null problem then "" else "\n" <> problem)
                  <> (if map snd (take wantedCount replayed) == map snd liveIds then "" else "\nthe replayed events differ from the live ones in content as well")
              )
  where
    -- Only frames terminated by a blank line; a trailing partial frame
    -- is still being received and is not counted.
    completeFrames buffer =
      case BS.breakSubstring "\n\n" buffer of
        (one, rest) | not (BS.null rest) -> [one | not (BS.null one)] <> completeFrames (BS.drop 2 rest)
        _                                -> []
    waitFor 0 _ = pure ()
    waitFor n done = do
      finished <- readIORef done
      unless finished (threadDelay 50000 >> waitFor (n - 1) done)

-- Median and worst lag per stream, in milliseconds, over the whole run.
lagSummary :: Observers -> IO [(Stream, Int, Double, Double)]
lagSummary observers = do
  lags <- readIORef (obsLags observers)
  pure
    [ (stream, length xs, median xs, maximum xs)
    | stream <- [minBound .. maxBound]
    , let xs = sort [l | (s, l) <- lags, s == stream]
    , not (null xs)
    ]
  where
    median xs = xs !! (length xs `div` 2)
