{-# LANGUAGE OverloadedStrings #-}

module Test.State.StockPullMachineSpec (spec) where

import Data.UUID (UUID)
import Test.Hspec

import State.StockPullMachine

actorId :: UUID
actorId = read "11111111-1111-1111-1111-111111111111"

-- actorId2 :: UUID
-- actorId2 = read "22222222-2222-2222-2222-222222222222"

pendingSt :: SomePullState
pendingSt = fromVertex PullPending

accepted :: SomePullState
accepted = fromVertex PullAccepted

pulling :: SomePullState
pulling = fromVertex PullPulling

fulfilled :: SomePullState
fulfilled = fromVertex PullFulfilled

cancelled :: SomePullState
cancelled = fromVertex PullCancelled

issue :: SomePullState
issue = fromVertex PullIssue

spec :: Spec
spec = describe "State.StockPullMachine" $ do
  describe "fromVertex / toPullVertex roundtrip" $ do
    it "Pending" $ toPullVertex (fromVertex PullPending) `shouldBe` PullPending
    it "Accepted" $ toPullVertex (fromVertex PullAccepted) `shouldBe` PullAccepted
    it "Pulling" $ toPullVertex (fromVertex PullPulling) `shouldBe` PullPulling
    it "Fulfilled" $ toPullVertex (fromVertex PullFulfilled) `shouldBe` PullFulfilled
    it "Cancelled" $ toPullVertex (fromVertex PullCancelled) `shouldBe` PullCancelled
    it "Issue" $ toPullVertex (fromVertex PullIssue) `shouldBe` PullIssue

  describe "valid transitions" $ do
    it "Pending + AcceptCmd → Accepted" $ do
      let (evt, next) = runPullCommand pendingSt (AcceptCmd actorId)
      toPullVertex next `shouldBe` PullAccepted
      case evt of
        PullWasAccepted a -> a `shouldBe` actorId
        _ -> expectationFailure $ "Expected PullWasAccepted, got: " <> show evt

    it "Pending + CancelCmd → Cancelled" $ do
      let (evt, next) = runPullCommand pendingSt (CancelCmd "No stock" actorId)
      toPullVertex next `shouldBe` PullCancelled
      case evt of
        PullWasCancelled r _ -> r `shouldBe` "No stock"
        _ -> expectationFailure $ "Expected PullWasCancelled, got: " <> show evt

    it "Accepted + StartPullCmd → Pulling" $ do
      let (_, next) = runPullCommand accepted (StartPullCmd actorId)
      toPullVertex next `shouldBe` PullPulling

    it "Accepted + CancelCmd → Cancelled" $ do
      let (_, next) = runPullCommand accepted (CancelCmd "Changed mind" actorId)
      toPullVertex next `shouldBe` PullCancelled

    it "Pulling + FulfillCmd → Fulfilled" $ do
      let (evt, next) = runPullCommand pulling (FulfillCmd actorId)
      toPullVertex next `shouldBe` PullFulfilled
      case evt of
        PullWasFulfilled a -> a `shouldBe` actorId
        _ -> expectationFailure $ "Expected PullWasFulfilled, got: " <> show evt

    it "Pulling + ReportIssueCmd → Issue" $ do
      let (evt, next) = runPullCommand pulling (ReportIssueCmd "Out of stock" actorId)
      toPullVertex next `shouldBe` PullIssue
      case evt of
        IssueWasReported note _ -> note `shouldBe` "Out of stock"
        _ -> expectationFailure $ "Expected IssueWasReported, got: " <> show evt

    it "Issue + RetryCmd → Accepted" $ do
      let (_, next) = runPullCommand issue (RetryCmd actorId)
      toPullVertex next `shouldBe` PullAccepted

    it "Issue + CancelCmd → Cancelled" $ do
      let (_, next) = runPullCommand issue (CancelCmd "Give up" actorId)
      toPullVertex next `shouldBe` PullCancelled

  describe "sink states reject all commands" $ do
    it "Fulfilled rejects AcceptCmd" $ do
      let (evt, next) = runPullCommand fulfilled (AcceptCmd actorId)
      toPullVertex next `shouldBe` PullFulfilled
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt

    it "Fulfilled rejects FulfillCmd" $ do
      let (evt, next) = runPullCommand fulfilled (FulfillCmd actorId)
      toPullVertex next `shouldBe` PullFulfilled
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt

    it "Cancelled rejects AcceptCmd" $ do
      let (evt, next) = runPullCommand cancelled (AcceptCmd actorId)
      toPullVertex next `shouldBe` PullCancelled
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt

    it "Cancelled rejects RetryCmd" $ do
      let (evt, next) = runPullCommand cancelled (RetryCmd actorId)
      toPullVertex next `shouldBe` PullCancelled
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt

  describe "invalid transitions" $ do
    it "Pending rejects StartPullCmd" $ do
      let (evt, next) = runPullCommand pendingSt (StartPullCmd actorId)
      toPullVertex next `shouldBe` PullPending
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt

    it "Pending rejects FulfillCmd" $ do
      let (evt, next) = runPullCommand pendingSt (FulfillCmd actorId)
      toPullVertex next `shouldBe` PullPending
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt

    it "Accepted rejects FulfillCmd" $ do
      let (evt, next) = runPullCommand accepted (FulfillCmd actorId)
      toPullVertex next `shouldBe` PullAccepted
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt

    it "Pulling rejects AcceptCmd" $ do
      let (evt, next) = runPullCommand pulling (AcceptCmd actorId)
      toPullVertex next `shouldBe` PullPulling
      case evt of
        InvalidPullCmd _ -> pure ()
        _ -> expectationFailure $ "Expected InvalidPullCmd, got: " <> show evt
