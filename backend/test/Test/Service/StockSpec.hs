{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Test.Service.StockSpec (spec) where

import Control.Monad (void)
import Data.IORef (newIORef, readIORef)
import qualified Data.Map.Strict as Map
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Servant (ServerError (..))
import Test.Hspec

import Effect.Clock (Clock, runClockPure)
import Effect.EventEmitter
import Effect.StockDb
import qualified Service.Stock as Svc
import State.StockPullMachine (PullVertex (..))
import Types.Events.Domain
import Types.Events
import Types.Location (LocationId (..))
import Types.Stock

pullId, txId, actorId :: UUID
pullId  = read "11111111-1111-1111-1111-111111111111"
txId    = read "22222222-2222-2222-2222-222222222222"
actorId = read "33333333-3333-3333-3333-333333333333"

locId :: LocationId
locId = LocationId (read "44444444-4444-4444-4444-444444444444")

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

mkPull :: PullVertex -> PullRequest
mkPull status =
  PullRequest
    { prId             = pullId
    , prTransactionId  = txId
    , prItemSku        = read "55555555-5555-5555-5555-555555555555"
    , prItemName       = "Test Item"
    , prQuantityNeeded = 2
    , prStatus         = status
    , prCashierId      = Nothing
    , prRegisterId     = Nothing
    , prLocationId     = locId
    , prCreatedAt      = testTime
    , prUpdatedAt      = testTime
    , prFulfilledAt    = Nothing
    }

storeWith :: PullVertex -> StockStore
storeWith status =
  emptyStockStore {ssRequests = Map.singleton pullId (mkPull status)}

type TestEffs =
  '[ StockDb
   , Clock
   , EventEmitter
   , Error ServerError
   , IOE
   ]

runTest :: StockStore -> Eff TestEffs a -> IO (Either ServerError a)
runTest store action =
  fmap (fmap fst)
    $ runEff
      . runErrorNoCallStack @ServerError
      . runEventEmitterNoop
      . runClockPure testTime
      . runStockDbPure store
    $ action

runTestWithEvents ::
  StockStore ->
  Eff TestEffs a ->
  IO (Either ServerError a, [DomainEvent])
runTestWithEvents store action = do
  ref <- newIORef []
  result <-
    fmap (fmap fst)
      $ runEff
        . runErrorNoCallStack @ServerError
        . runEventEmitterCollect ref
        . runClockPure testTime
        . runStockDbPure store
      $ action
  evts <- reverse <$> readIORef ref
  pure (result, evts)

shouldSucceed :: IO (Either ServerError a) -> IO a
shouldSucceed io = do
  result <- io
  case result of
    Left err ->
      expectationFailure ("Expected success but got HTTP " <> show (errHTTPCode err))
        >> error "unreachable"
    Right a -> pure a

shouldFailWith :: Int -> IO (Either ServerError a) -> IO ()
shouldFailWith code io = do
  result <- io
  case result of
    Left err -> errHTTPCode err `shouldBe` code
    Right _  -> expectationFailure $ "Expected HTTP " <> show code <> " but got success"

hasStatusChangedEvent :: [DomainEvent] -> Bool
hasStatusChangedEvent = any $ \case
  StockEvt (PullStatusChanged {}) -> True
  _                               -> False

spec :: Spec
spec = describe "Service.Stock (pure interpreter)" $ do

  describe "acceptPull" $ do
    it "succeeds from PullPending → PullAccepted" $ do
      pr <- shouldSucceed $ runTest (storeWith PullPending) (Svc.acceptPull pullId actorId)
      prStatus pr `shouldBe` PullAccepted

    it "rejects from PullAccepted with 409" $
      shouldFailWith 409 $ runTest (storeWith PullAccepted) (Svc.acceptPull pullId actorId)

    it "rejects from PullPulling with 409" $
      shouldFailWith 409 $ runTest (storeWith PullPulling) (Svc.acceptPull pullId actorId)

    it "rejects from PullFulfilled with 409" $
      shouldFailWith 409 $ runTest (storeWith PullFulfilled) (Svc.acceptPull pullId actorId)

    it "rejects from PullCancelled with 409" $
      shouldFailWith 409 $ runTest (storeWith PullCancelled) (Svc.acceptPull pullId actorId)

    it "returns 404 when pull not found" $
      shouldFailWith 404 $ runTest emptyStockStore (Svc.acceptPull pullId actorId)

    it "emits PullStatusChanged on success" $ do
      (_, evts) <- runTestWithEvents (storeWith PullPending) (Svc.acceptPull pullId actorId)
      evts `shouldSatisfy` hasStatusChangedEvent

    it "emits no events on state machine rejection" $ do
      (_, evts) <- runTestWithEvents (storeWith PullFulfilled) (Svc.acceptPull pullId actorId)
      evts `shouldBe` []

  describe "startPull" $ do
    it "succeeds from PullAccepted → PullPulling" $ do
      pr <- shouldSucceed $ runTest (storeWith PullAccepted) (Svc.startPull pullId actorId)
      prStatus pr `shouldBe` PullPulling

    it "rejects from PullPending with 409" $
      shouldFailWith 409 $ runTest (storeWith PullPending) (Svc.startPull pullId actorId)

    it "rejects from PullPulling with 409" $
      shouldFailWith 409 $ runTest (storeWith PullPulling) (Svc.startPull pullId actorId)

    it "returns 404 when pull not found" $
      shouldFailWith 404 $ runTest emptyStockStore (Svc.startPull pullId actorId)

    it "emits PullStatusChanged on success" $ do
      (_, evts) <- runTestWithEvents (storeWith PullAccepted) (Svc.startPull pullId actorId)
      evts `shouldSatisfy` hasStatusChangedEvent

  describe "fulfillPull" $ do
    it "succeeds from PullPulling → PullFulfilled" $ do
      pr <- shouldSucceed $ runTest (storeWith PullPulling) (Svc.fulfillPull pullId actorId)
      prStatus pr `shouldBe` PullFulfilled

    it "rejects from PullAccepted with 409" $
      shouldFailWith 409 $ runTest (storeWith PullAccepted) (Svc.fulfillPull pullId actorId)

    it "rejects from PullPending with 409" $
      shouldFailWith 409 $ runTest (storeWith PullPending) (Svc.fulfillPull pullId actorId)

    it "returns 404 when pull not found" $
      shouldFailWith 404 $ runTest emptyStockStore (Svc.fulfillPull pullId actorId)

    it "emits PullStatusChanged on success" $ do
      (_, evts) <- runTestWithEvents (storeWith PullPulling) (Svc.fulfillPull pullId actorId)
      evts `shouldSatisfy` hasStatusChangedEvent

  describe "reportIssue" $ do
    it "succeeds from PullPulling → PullIssue" $ do
      pr <- shouldSucceed $
        runTest (storeWith PullPulling) (Svc.reportIssue pullId "broken" actorId)
      prStatus pr `shouldBe` PullIssue

    it "rejects from PullPending with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullPending) (Svc.reportIssue pullId "broken" actorId)

    it "rejects from PullAccepted with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullAccepted) (Svc.reportIssue pullId "broken" actorId)

    it "returns 404 when pull not found" $
      shouldFailWith 404 $
        runTest emptyStockStore (Svc.reportIssue pullId "broken" actorId)

  describe "retryPull" $ do
    it "succeeds from PullIssue → PullAccepted" $ do
      pr <- shouldSucceed $ runTest (storeWith PullIssue) (Svc.retryPull pullId actorId)
      prStatus pr `shouldBe` PullAccepted

    it "rejects from PullPulling with 409" $
      shouldFailWith 409 $ runTest (storeWith PullPulling) (Svc.retryPull pullId actorId)

    it "rejects from PullPending with 409" $
      shouldFailWith 409 $ runTest (storeWith PullPending) (Svc.retryPull pullId actorId)

    it "returns 404 when pull not found" $
      shouldFailWith 404 $ runTest emptyStockStore (Svc.retryPull pullId actorId)

    it "emits PullStatusChanged on success" $ do
      (_, evts) <- runTestWithEvents (storeWith PullIssue) (Svc.retryPull pullId actorId)
      evts `shouldSatisfy` hasStatusChangedEvent

  describe "cancelPull" $ do
    it "succeeds from PullPending → PullCancelled" $ do
      pr <- shouldSucceed $
        runTest (storeWith PullPending) (Svc.cancelPull pullId "test" actorId)
      prStatus pr `shouldBe` PullCancelled

    it "succeeds from PullAccepted → PullCancelled" $ do
      pr <- shouldSucceed $
        runTest (storeWith PullAccepted) (Svc.cancelPull pullId "test" actorId)
      prStatus pr `shouldBe` PullCancelled

    it "succeeds from PullIssue → PullCancelled" $ do
      pr <- shouldSucceed $
        runTest (storeWith PullIssue) (Svc.cancelPull pullId "test" actorId)
      prStatus pr `shouldBe` PullCancelled

    it "rejects from PullFulfilled with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullFulfilled) (Svc.cancelPull pullId "test" actorId)

    it "rejects from PullPulling with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullPulling) (Svc.cancelPull pullId "test" actorId)

    it "returns 404 when pull not found" $
      shouldFailWith 404 $
        runTest emptyStockStore (Svc.cancelPull pullId "test" actorId)

    it "emits PullRequestCancelled on success" $ do
      (_, evts) <-
        runTestWithEvents (storeWith PullPending) (Svc.cancelPull pullId "test" actorId)
      let cancelEvts = [() | StockEvt (PullRequestCancelled {}) <- evts]
      cancelEvts `shouldSatisfy` (not . null)

  describe "full happy-path sequences" $ do
    it "Pending → Accepted → Pulling → Fulfilled" $ do
      finalStatus <- shouldSucceed $ runTest (storeWith PullPending) $ do
        void $ Svc.acceptPull  pullId actorId
        void $ Svc.startPull   pullId actorId
        prStatus <$> Svc.fulfillPull pullId actorId
      finalStatus `shouldBe` PullFulfilled

    it "Pending → Accepted → Pulling → Issue → Accepted → Pulling → Fulfilled" $ do
      finalStatus <- shouldSucceed $ runTest (storeWith PullPending) $ do
        void $ Svc.acceptPull  pullId actorId
        void $ Svc.startPull   pullId actorId
        void $ Svc.reportIssue pullId "first attempt failed" actorId
        void $ Svc.retryPull   pullId actorId
        void $ Svc.startPull   pullId actorId
        prStatus <$> Svc.fulfillPull pullId actorId
      finalStatus `shouldBe` PullFulfilled

    it "Pending → Cancelled emits PullRequestCancelled" $ do
      (_, evts) <-
        runTestWithEvents (storeWith PullPending) (Svc.cancelPull pullId "cancelled" actorId)
      let cancelEvts = [() | StockEvt (PullRequestCancelled {}) <- evts]
      length cancelEvts `shouldBe` 1