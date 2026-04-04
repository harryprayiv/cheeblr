{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-star-is-type #-}
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

module State.StockPullMachine (
  PullVertex (..),
  SPullVertex (..),
  SomePullState (..),
  PullState (..),
  PullCommand (..),
  PullEvent (..),
  runPullCommand,
  fromVertex,
  toPullVertex,
) where

import Crem.BaseMachine (ActionResult (..), pureResult)
import Crem.Render.RenderableVertices (RenderableVertices (..))
import Crem.Topology (Topology (..))
import Data.Aeson (FromJSON, ToJSON)
import Data.Functor.Identity (Identity, runIdentity)
import Data.OpenApi (ToSchema)
import Data.Singletons.Base.TH
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Generics (Generic)

-- Generic is derived outside the singletons splice, matching the pattern used
-- by TransactionMachine and RegisterMachine. Deriving Generic inside the splice
-- causes a duplicate Show instance on GHC 9.10 that propagates to any type
-- containing PullVertex (e.g. PullRequest, StockEvent, DomainEvent).
$( singletons
     [d|
       data PullVertex
         = PullPending
         | PullAccepted
         | PullPulling
         | PullFulfilled
         | PullCancelled
         | PullIssue
         deriving (Eq, Show)
       |]
 )

deriving instance Generic PullVertex
deriving instance Enum PullVertex
deriving instance Bounded PullVertex

instance ToJSON PullVertex
instance FromJSON PullVertex
instance ToSchema PullVertex

instance RenderableVertices PullVertex where
  vertices = [minBound .. maxBound]

type PullTopology =
  'Topology
    '[ '( 'PullPending, '[ 'PullPending, 'PullAccepted, 'PullCancelled])
     , '( 'PullAccepted, '[ 'PullAccepted, 'PullPulling, 'PullCancelled])
     , '( 'PullPulling, '[ 'PullPulling, 'PullFulfilled, 'PullIssue])
     , '( 'PullFulfilled, '[ 'PullFulfilled])
     , '( 'PullCancelled, '[ 'PullCancelled])
     , '( 'PullIssue, '[ 'PullIssue, 'PullAccepted, 'PullCancelled])
     ]

data PullState (v :: PullVertex) where
  PendingState :: PullState 'PullPending
  AcceptedState :: PullState 'PullAccepted
  PullingState :: PullState 'PullPulling
  FulfilledState :: PullState 'PullFulfilled
  CancelledState :: PullState 'PullCancelled
  IssueState :: PullState 'PullIssue

data SomePullState = forall v. SomePullState (SPullVertex v) (PullState v)

fromVertex :: PullVertex -> SomePullState
fromVertex PullPending = SomePullState SPullPending PendingState
fromVertex PullAccepted = SomePullState SPullAccepted AcceptedState
fromVertex PullPulling = SomePullState SPullPulling PullingState
fromVertex PullFulfilled = SomePullState SPullFulfilled FulfilledState
fromVertex PullCancelled = SomePullState SPullCancelled CancelledState
fromVertex PullIssue = SomePullState SPullIssue IssueState

toPullVertex :: SomePullState -> PullVertex
toPullVertex (SomePullState sv _) = case sv of
  SPullPending -> PullPending
  SPullAccepted -> PullAccepted
  SPullPulling -> PullPulling
  SPullFulfilled -> PullFulfilled
  SPullCancelled -> PullCancelled
  SPullIssue -> PullIssue

toSomePullState :: PullState v -> SomePullState
toSomePullState = \case
  PendingState -> SomePullState SPullPending PendingState
  AcceptedState -> SomePullState SPullAccepted AcceptedState
  PullingState -> SomePullState SPullPulling PullingState
  FulfilledState -> SomePullState SPullFulfilled FulfilledState
  CancelledState -> SomePullState SPullCancelled CancelledState
  IssueState -> SomePullState SPullIssue IssueState

data PullCommand
  = AcceptCmd UUID
  | StartPullCmd UUID
  | FulfillCmd UUID
  | ReportIssueCmd Text UUID
  | RetryCmd UUID
  | CancelCmd Text UUID
  deriving (Show, Eq, Generic)

data PullEvent
  = PullWasAccepted UUID
  | PullingWasStarted UUID
  | PullWasFulfilled UUID
  | IssueWasReported Text UUID
  | PullWasRetried UUID
  | PullWasCancelled Text UUID
  | InvalidPullCmd Text
  deriving (Show, Eq, Generic)

pullAction :: PullState v -> PullCommand -> ActionResult Identity PullTopology PullState v PullEvent
pullAction PendingState (AcceptCmd actor) =
  pureResult (PullWasAccepted actor) AcceptedState
pullAction PendingState (CancelCmd reason actor) =
  pureResult (PullWasCancelled reason actor) CancelledState
pullAction PendingState _ =
  pureResult (InvalidPullCmd "Invalid command in Pending state") PendingState
pullAction AcceptedState (StartPullCmd actor) =
  pureResult (PullingWasStarted actor) PullingState
pullAction AcceptedState (CancelCmd reason actor) =
  pureResult (PullWasCancelled reason actor) CancelledState
pullAction AcceptedState _ =
  pureResult (InvalidPullCmd "Invalid command in Accepted state") AcceptedState
pullAction PullingState (FulfillCmd actor) =
  pureResult (PullWasFulfilled actor) FulfilledState
pullAction PullingState (ReportIssueCmd note actor) =
  pureResult (IssueWasReported note actor) IssueState
pullAction PullingState _ =
  pureResult (InvalidPullCmd "Invalid command in Pulling state") PullingState
pullAction FulfilledState _ =
  pureResult (InvalidPullCmd "Pull request is fulfilled") FulfilledState
pullAction CancelledState _ =
  pureResult (InvalidPullCmd "Pull request is cancelled") CancelledState
pullAction IssueState (RetryCmd actor) =
  pureResult (PullWasRetried actor) AcceptedState
pullAction IssueState (CancelCmd reason actor) =
  pureResult (PullWasCancelled reason actor) CancelledState
pullAction IssueState _ =
  pureResult (InvalidPullCmd "Invalid command in Issue state") IssueState

runPullCommand :: SomePullState -> PullCommand -> (PullEvent, SomePullState)
runPullCommand (SomePullState _ st) cmd =
  case pullAction st cmd of
    ActionResult m ->
      let (evt, nextSt) = runIdentity m
       in (evt, toSomePullState nextSt)
