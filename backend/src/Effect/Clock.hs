{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.Clock (
  Clock (..),
  currentTime,
  runClockIO,
  runClockPure,
  runClockPureSequence,
) where

import Data.Time (UTCTime, getCurrentTime)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local

data Clock :: Effect where
  CurrentTime :: Clock m UTCTime

type instance DispatchOf Clock = Dynamic

currentTime :: (Clock :> es) => Eff es UTCTime
currentTime = send CurrentTime

runClockIO :: (IOE :> es) => Eff (Clock : es) a -> Eff es a
runClockIO = interpret $ \_ -> \case
  CurrentTime -> liftIO getCurrentTime

runClockPure :: UTCTime -> Eff (Clock : es) a -> Eff es a
runClockPure t = interpret $ \_ -> \case
  CurrentTime -> pure t

runClockPureSequence :: [UTCTime] -> Eff (Clock : es) a -> Eff es (a, [UTCTime])
runClockPureSequence supply = reinterpret (runState supply) $ \_ -> \case
  CurrentTime -> do
    times <- get
    case times of
      [] -> error "runClockPureSequence: time supply exhausted"
      (t : ts) -> put ts >> pure t
