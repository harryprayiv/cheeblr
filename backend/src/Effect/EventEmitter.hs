{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs            #-}
{-# LANGUAGE TypeFamilies     #-}
{-# LANGUAGE TypeOperators    #-}

module Effect.EventEmitter
  ( EventEmitter (..)
  , emit
  , runEventEmitterNoop
  , runEventEmitterCollect
  , runEventEmitterProd
  ) where

import Data.IORef               (IORef, modifyIORef')
import Data.UUID                (UUID)
import Effectful
import Effectful.Dispatch.Dynamic

import DB.Database              (DBPool)
import DB.Events                (insertDomainEvent)
import Infrastructure.Broadcast (Broadcaster, publish)
import Types.Events.Domain      (DomainEvent)
import Types.Location           (LocationId)
import Types.Trace              (TraceId)

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

runEventEmitterProd
  :: IOE :> es
  => DBPool
  -> Broadcaster DomainEvent
  -> Maybe TraceId
  -> Maybe UUID       -- actor
  -> Maybe LocationId -- location
  -> Eff (EventEmitter : es) a
  -> Eff es a
runEventEmitterProd pool broadcaster mTraceId mActorId mLocationId =
  interpret $ \_ (Emit evt) -> liftIO $ do
    insertDomainEvent pool mTraceId mActorId mLocationId evt
    publish broadcaster evt