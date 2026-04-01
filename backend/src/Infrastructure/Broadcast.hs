module Infrastructure.Broadcast
  ( Broadcaster (..)
  , Subscription (..)
  , newBroadcaster
  , publish
  , subscribe
  , historyFrom
  , currentSeq
  ) where

import Control.Concurrent.STM
import Data.Int                (Int64)
import Data.Sequence           (Seq)
import qualified Data.Sequence as Seq

data Broadcaster a = Broadcaster
  { bChan       :: TChan a
  , bHistory    :: TVar (Seq (Int64, a))
  , bMaxHistory :: Int
  , bNextSeq    :: TVar Int64
  }

data Subscription a = Subscription
  { subChan    :: TChan a
  , subInitSeq :: Int64
  }

newBroadcaster :: Int -> IO (Broadcaster a)
newBroadcaster maxHistory = Broadcaster
  <$> newBroadcastTChanIO
  <*> newTVarIO Seq.empty
  <*> pure maxHistory
  <*> newTVarIO 0

publish :: Broadcaster a -> a -> IO ()
publish b evt = atomically $ do
  seq' <- readTVar (bNextSeq b)
  writeTVar (bNextSeq b) (seq' + 1)
  writeTChan (bChan b) evt
  modifyTVar' (bHistory b) $ \h ->
    let h' = h Seq.|> (seq', evt)
    in if Seq.length h' > bMaxHistory b then Seq.drop 1 h' else h'

subscribe :: Broadcaster a -> IO (Subscription a)
subscribe b = atomically $ do
  ch   <- dupTChan (bChan b)
  seq' <- readTVar (bNextSeq b)
  pure Subscription { subChan = ch, subInitSeq = seq' }

historyFrom :: Broadcaster a -> Int64 -> IO (Seq (Int64, a))
historyFrom b cursor = atomically $
  Seq.filter (\(s, _) -> s > cursor) <$> readTVar (bHistory b)

currentSeq :: Broadcaster a -> IO Int64
currentSeq b = readTVarIO (bNextSeq b)