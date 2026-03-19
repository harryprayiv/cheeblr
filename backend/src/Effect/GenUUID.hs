{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.GenUUID
  ( GenUUID (..)
  , nextUUID
  , runGenUUIDIO
  , runGenUUIDPure
  ) where

import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local

data GenUUID :: Effect where
  NextUUID :: GenUUID m UUID

type instance DispatchOf GenUUID = Dynamic

nextUUID :: GenUUID :> es => Eff es UUID
nextUUID = send NextUUID

runGenUUIDIO :: IOE :> es => Eff (GenUUID : es) a -> Eff es a
runGenUUIDIO = interpret $ \_ -> \case
  NextUUID -> liftIO nextRandom

runGenUUIDPure :: [UUID] -> Eff (GenUUID : es) a -> Eff es (a, [UUID])
runGenUUIDPure supply = reinterpret (runState supply) $ \_ -> \case
  NextUUID -> do
    uuids <- get
    case uuids of
      []       -> error "runGenUUIDPure: UUID supply exhausted"
      (u : us) -> put us >> pure u