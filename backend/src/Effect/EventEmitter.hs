{-# LANGUAGE DataKinds    #-}
{-# LANGUAGE GADTs        #-}
-- {-# LANGUAGE LambdaCase   #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}


module Effect.EventEmitter
  ( EventEmitter (..)
  , emit
  , runEventEmitterNoop
  , runEventEmitterCollect
  , runEventEmitterProd
  ) where

import Data.IORef                  (IORef, modifyIORef')
import Effectful
import Effectful.Dispatch.Dynamic

import Infrastructure.Broadcast    (Broadcaster, publish)
import Types.Events.Domain         (DomainEvent)

data EventEmitter :: Effect where
  Emit :: DomainEvent -> EventEmitter m ()

type instance DispatchOf EventEmitter = Dynamic

emit :: EventEmitter :> es => DomainEvent -> Eff es ()
emit = send . Emit

runEventEmitterNoop :: Eff (EventEmitter : es) a -> Eff es a
runEventEmitterNoop = interpret $ \_ (Emit _) -> pure ()

runEventEmitterCollect
  :: IOE :> es
  => IORef [DomainEvent]
  -> Eff (EventEmitter : es) a
  -> Eff es a
runEventEmitterCollect ref = interpret $ \_ (Emit evt) ->
  liftIO $ modifyIORef' ref (evt :)

-- The DB write (domain_events table) will be added in Phase 3 when
-- TraceId and request context are threaded through. For now, events
-- are published to the in-memory broadcaster only.
runEventEmitterProd
  :: IOE :> es
  => Broadcaster DomainEvent
  -> Eff (EventEmitter : es) a
  -> Eff es a
runEventEmitterProd broadcaster = interpret $ \_ (Emit evt) ->
  liftIO $ publish broadcaster evt