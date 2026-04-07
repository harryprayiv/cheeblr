{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Service.Stock (
  acceptPull,
  startPull,
  fulfillPull,
  reportIssue,
  retryPull,
  cancelPull,
  addMessage,
) where

import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import Effectful
import Effectful.Error.Static
import Servant (ServerError (..), err404, err409, err500)

import Effect.Clock
import Effect.EventEmitter
import Effect.GenUUID
import Effect.StockDb
import State.StockPullMachine
import Types.Events.Domain (DomainEvent (..))
import Types.Events
import Types.Stock

loadPull ::
  (StockDb :> es, Error ServerError :> es) =>
  UUID ->
  Eff es (PullRequest, SomePullState)
loadPull pullId = do
  mPr <- getPullRequest pullId
  case mPr of
    Nothing -> throwError err404 {errBody = "Pull request not found"}
    Just pr -> pure (pr, fromVertex (prStatus pr))

guardPullEvent :: (Error ServerError :> es) => PullEvent -> Eff es ()
guardPullEvent (InvalidPullCmd msg) =
  throwError err409 {errBody = LBS.fromStrict (TE.encodeUtf8 msg)}
guardPullEvent _ = pure ()

transition ::
  (StockDb :> es, EventEmitter :> es, Clock :> es, Error ServerError :> es) =>
  UUID ->
  PullCommand ->
  (PullRequest -> PullEvent -> SomePullState -> PullRequest) ->
  Eff es PullRequest
transition pullId cmd applyResult = do
  (pr, someState) <- loadPull pullId
  let
    oldVertex = toPullVertex someState
    (evt, next) = runPullCommand someState cmd
    newVertex = toPullVertex next
  guardPullEvent evt
  result <- updatePullStatus pullId newVertex Nothing
  case result of
    Left err -> throwError err500 {errBody = LBS.fromStrict (TE.encodeUtf8 err)}
    Right () -> do
      now <- currentTime
      emit $
        StockEvt $
          PullStatusChanged
            pullId
            oldVertex
            newVertex
            (actorFromCmd cmd)
            now
      pure (applyResult pr evt next)

actorFromCmd :: PullCommand -> UUID
actorFromCmd (AcceptCmd a)        = a
actorFromCmd (StartPullCmd a)     = a
actorFromCmd (FulfillCmd a)       = a
actorFromCmd (ReportIssueCmd _ a) = a
actorFromCmd (RetryCmd a)         = a
actorFromCmd (CancelCmd _ a)      = a

acceptPull ::
  (StockDb :> es, EventEmitter :> es, Clock :> es, Error ServerError :> es) =>
  UUID -> UUID -> Eff es PullRequest
acceptPull pullId actorId =
  transition pullId (AcceptCmd actorId) $ \pr _ next ->
    pr {prStatus = toPullVertex next}

startPull ::
  (StockDb :> es, EventEmitter :> es, Clock :> es, Error ServerError :> es) =>
  UUID -> UUID -> Eff es PullRequest
startPull pullId actorId =
  transition pullId (StartPullCmd actorId) $ \pr _ next ->
    pr {prStatus = toPullVertex next}

fulfillPull ::
  (StockDb :> es, EventEmitter :> es, Clock :> es, Error ServerError :> es) =>
  UUID -> UUID -> Eff es PullRequest
fulfillPull pullId actorId =
  transition pullId (FulfillCmd actorId) $ \pr _ next ->
    pr {prStatus = toPullVertex next}

reportIssue ::
  (StockDb :> es, EventEmitter :> es, Clock :> es, Error ServerError :> es) =>
  UUID -> Text -> UUID -> Eff es PullRequest
reportIssue pullId note actorId =
  transition pullId (ReportIssueCmd note actorId) $ \pr _ next ->
    pr {prStatus = toPullVertex next}

retryPull ::
  (StockDb :> es, EventEmitter :> es, Clock :> es, Error ServerError :> es) =>
  UUID -> UUID -> Eff es PullRequest
retryPull pullId actorId =
  transition pullId (RetryCmd actorId) $ \pr _ next ->
    pr {prStatus = toPullVertex next}

cancelPull ::
  (StockDb :> es, EventEmitter :> es, Clock :> es, Error ServerError :> es) =>
  UUID -> Text -> UUID -> Eff es PullRequest
cancelPull pullId reason actorId = do
  (pr, someState) <- loadPull pullId
  let
    (evt, next) = runPullCommand someState (CancelCmd reason actorId)
    newVertex = toPullVertex next
  guardPullEvent evt
  result <- updatePullStatus pullId newVertex Nothing
  case result of
    Left err -> throwError err500 {errBody = LBS.fromStrict (TE.encodeUtf8 err)}
    Right () -> do
      now <- currentTime
      emit $ StockEvt $ PullRequestCancelled pullId reason now
      pure pr {prStatus = newVertex}

-- | Add a message to a pull request and emit a domain event.
-- Previously this function used pullId as the message UUID (a primary-key
-- collision bug). GenUUID is now in the constraint so each message gets a
-- unique ID. The server handler must route through runStockEff for SSE
-- emission to work.
addMessage ::
  ( StockDb :> es
  , EventEmitter :> es
  , Clock :> es
  , GenUUID :> es
  , Error ServerError :> es
  ) =>
  UUID -> UUID -> Text -> Text -> Eff es PullMessage
addMessage pullId senderId fromRole msg = do
  _ <- loadPull pullId
  now   <- currentTime
  msgId <- nextUUID          -- was: let msgId = pullId  (bug: PK collision)
  let
    pm =
      PullMessage
        { pmId            = msgId
        , pmPullRequestId = pullId
        , pmFromRole      = fromRole
        , pmSenderId      = senderId
        , pmMessage       = msg
        , pmCreatedAt     = now
        }
  result <- addPullMessage pullId pm
  case result of
    Left err -> throwError err500 {errBody = LBS.fromStrict (TE.encodeUtf8 err)}
    Right () -> do
      emit $ StockEvt $ PullMessageAdded pullId pm now
      pure pm