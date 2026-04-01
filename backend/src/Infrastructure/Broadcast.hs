module Infrastructure.Broadcast
  ( Broadcaster (..)
  , newBroadcaster
  ) where

import Control.Concurrent.STM
import Data.Int                (Int64)
import Data.Sequence           (Seq)
import qualified Data.Sequence as Seq

-- Phase 2 adds publish, subscribe, historyFrom, currentSeq, Subscription.
-- For Phase 0 we only need the type and constructor so AppEnv can hold
-- broadcaster fields without any actual event routing yet.
data Broadcaster a = Broadcaster
  { bChan       :: TChan a
  , bHistory    :: TVar (Seq (Int64, a))
  , bMaxHistory :: Int
  , bNextSeq    :: TVar Int64
  }

newBroadcaster :: Int -> IO (Broadcaster a)
newBroadcaster maxHistory = Broadcaster
  <$> newBroadcastTChanIO
  <*> newTVarIO Seq.empty
  <*> pure maxHistory
  <*> newTVarIO 0