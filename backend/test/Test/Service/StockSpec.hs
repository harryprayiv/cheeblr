{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Test.Service.StockSpec (spec) where

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
import Types.Events.Stock
import Types.Location (LocationId (..))
import Types.Stock

pullId :: UUID
pullId = read "11111111-1111-1111-1111-111111111111"

actorId :: UUID
actorId = read "22222222-2222-2222-2222-222222222222"

locId :: LocationId
locId = LocationId (read "33333333-3333-3333-3333-333333333333")

testTime :: UTCTime
testTime = read "2024-01-01 00:00:00 UTC"

mkPr :: PullVertex -> PullRequest
mkPr status =
  PullRequest
    { prId = pullId
    , prTransactionId = read "44444444-4444-4444-4444-444444444444"
    , prItemSku = read "55555555-5555-5555-5555-555555555555"
    , prItemName = "Blue Dream"
    , prQuantityNeeded = 2
    , prStatus = status
    , prCashierId = Nothing
    , prRegisterId = Nothing
    , prLocationId = locId
    , prCreatedAt = testTime
    , prUpdatedAt = testTime
    , prFulfilledAt = Nothing
    }

storeWith :: PullVertex -> StockStore
storeWith v =
  StockStore
    { ssRequests = Map.singleton pullId (mkPr v)
    , ssMessages = Map.empty
    }

type TestEffs =
  '[ StockDb
   , Clock
   , EventEmitter
   , Error ServerError
   , IOE
   ]

runTest :: StockStore -> Eff TestEffs a -> IO (Either ServerError a)
runTest store action = do
  let stripped = fmap fst (runStockDbPure store action)
  runEff
    . runErrorNoCallStack @ServerError
    . runEventEmitterNoop
    . runClockPure testTime
    $ stripped

runTestWithEvents :: StockStore -> Eff TestEffs a -> IO (Either ServerError a, [DomainEvent])
runTestWithEvents store action = do
  ref <- newIORef []
  let stripped = fmap fst (runStockDbPure store action)
  result <-
    runEff
      . runErrorNoCallStack @ServerError
      . runEventEmitterCollect ref
      . runClockPure testTime
      $ stripped
  evts <- reverse <$> readIORef ref
  pure (result, evts)

shouldSucceed :: IO (Either ServerError a) -> IO a
shouldSucceed io = do
  result <- io
  case result of
    Left err -> do
      expectationFailure $ "Expected success but got HTTP " <> show (errHTTPCode err)
      error "unreachable"
    Right a -> pure a

shouldFailWith :: Int -> IO (Either ServerError a) -> IO ()
shouldFailWith code io = do
  result <- io
  case result of
    Left err -> errHTTPCode err `shouldBe` code
    Right _ -> expectationFailure $ "Expected HTTP " <> show code <> " but succeeded"

spec :: Spec
spec = describe "Service.Stock (pure interpreter)" $ do
  describe "acceptPull" $ do
    it "transitions Pending → Accepted" $ do
      pr <- shouldSucceed $ runTest (storeWith PullPending) (Svc.acceptPull pullId actorId)
      prStatus pr `shouldBe` PullAccepted

    it "rejects from Accepted with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullAccepted) (Svc.acceptPull pullId actorId)

    it "rejects from Fulfilled with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullFulfilled) (Svc.acceptPull pullId actorId)

    it "returns 404 for unknown pull" $
      shouldFailWith 404 $
        runTest emptyStockStore (Svc.acceptPull pullId actorId)

  describe "startPull" $ do
    it "transitions Accepted → Pulling" $ do
      pr <- shouldSucceed $ runTest (storeWith PullAccepted) (Svc.startPull pullId actorId)
      prStatus pr `shouldBe` PullPulling

    it "rejects from Pending with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullPending) (Svc.startPull pullId actorId)

  describe "fulfillPull" $ do
    it "transitions Pulling → Fulfilled" $ do
      pr <- shouldSucceed $ runTest (storeWith PullPulling) (Svc.fulfillPull pullId actorId)
      prStatus pr `shouldBe` PullFulfilled

    it "rejects from Accepted with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullAccepted) (Svc.fulfillPull pullId actorId)

  describe "reportIssue" $ do
    it "transitions Pulling → Issue" $ do
      pr <-
        shouldSucceed $
          runTest (storeWith PullPulling) (Svc.reportIssue pullId "No stock" actorId)
      prStatus pr `shouldBe` PullIssue

    it "rejects from Pending with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullPending) (Svc.reportIssue pullId "No stock" actorId)

  describe "retryPull" $ do
    it "transitions Issue → Accepted" $ do
      pr <- shouldSucceed $ runTest (storeWith PullIssue) (Svc.retryPull pullId actorId)
      prStatus pr `shouldBe` PullAccepted

    it "rejects from Pending with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullPending) (Svc.retryPull pullId actorId)

  describe "cancelPull" $ do
    it "cancels from Pending" $ do
      pr <-
        shouldSucceed $
          runTest (storeWith PullPending) (Svc.cancelPull pullId "No longer needed" actorId)
      prStatus pr `shouldBe` PullCancelled

    it "cancels from Issue" $ do
      pr <-
        shouldSucceed $
          runTest (storeWith PullIssue) (Svc.cancelPull pullId "Give up" actorId)
      prStatus pr `shouldBe` PullCancelled

    it "rejects from Fulfilled with 409" $
      shouldFailWith 409 $
        runTest (storeWith PullFulfilled) (Svc.cancelPull pullId "Too late" actorId)

  describe "event emission" $ do
    it "acceptPull emits PullStatusChanged" $ do
      (result, evts) <-
        runTestWithEvents
          (storeWith PullPending)
          (Svc.acceptPull pullId actorId)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [StockEvt (PullStatusChanged {sePullId = pid, seOldStatus = old, seNewStatus = new})] -> do
          pid `shouldBe` pullId
          old `shouldBe` PullPending
          new `shouldBe` PullAccepted
        _ ->
          expectationFailure $
            "Expected [PullStatusChanged], got: " <> show (length evts) <> " events"

    it "fulfillPull emits PullStatusChanged" $ do
      (result, evts) <-
        runTestWithEvents
          (storeWith PullPulling)
          (Svc.fulfillPull pullId actorId)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [StockEvt (PullStatusChanged {seNewStatus = new})] ->
          new `shouldBe` PullFulfilled
        _ ->
          expectationFailure $
            "Expected [PullStatusChanged fulfilled], got: " <> show (length evts) <> " events"

    it "cancelPull emits PullRequestCancelled" $ do
      (result, evts) <-
        runTestWithEvents
          (storeWith PullPending)
          (Svc.cancelPull pullId "No longer needed" actorId)
      result `shouldSatisfy` either (const False) (const True)
      case evts of
        [StockEvt (PullRequestCancelled {sePullId = pid, seReason = reason})] -> do
          pid `shouldBe` pullId
          reason `shouldBe` "No longer needed"
        _ ->
          expectationFailure $
            "Expected [PullRequestCancelled], got: " <> show (length evts) <> " events"

    it "rejected commands emit no events" $ do
      (_, evts) <-
        runTestWithEvents
          (storeWith PullFulfilled)
          (Svc.acceptPull pullId actorId)
      evts `shouldBe` []
