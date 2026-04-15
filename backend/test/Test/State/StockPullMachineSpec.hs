{-# LANGUAGE OverloadedStrings #-}

module Test.State.StockPullMachineSpec (spec) where

import Data.UUID (UUID)
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import State.StockPullMachine

actorId :: UUID
actorId = read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

-- | Run a command from a vertex and return (event, resulting vertex).
step :: PullVertex -> PullCommand -> (PullEvent, PullVertex)
step v cmd =
  let (evt, next) = runPullCommand (fromVertex v) cmd
   in (evt, toPullVertex next)

isInvalid :: PullEvent -> Bool
isInvalid (InvalidPullCmd _) = True
isInvalid _ = False

genCommand :: Gen PullCommand
genCommand =
  Gen.choice
    [ pure (AcceptCmd actorId)
    , pure (StartPullCmd actorId)
    , pure (FulfillCmd actorId)
    , ReportIssueCmd <$> Gen.text (Range.linear 1 20) Gen.alphaNum <*> pure actorId
    , pure (RetryCmd actorId)
    , CancelCmd <$> Gen.text (Range.linear 1 20) Gen.alphaNum <*> pure actorId
    ]

spec :: Spec
spec = describe "StockPullMachine" $ do
  describe "valid transitions" $ do
    it "PullPending + Accept  → PullAccepted" $ do
      let (evt, next) = step PullPending (AcceptCmd actorId)
      evt `shouldBe` PullWasAccepted actorId
      next `shouldBe` PullAccepted

    it "PullPending + Cancel  → PullCancelled" $ do
      let (evt, next) = step PullPending (CancelCmd "reason" actorId)
      evt `shouldBe` PullWasCancelled "reason" actorId
      next `shouldBe` PullCancelled

    it "PullAccepted + Start  → PullPulling" $ do
      let (evt, next) = step PullAccepted (StartPullCmd actorId)
      evt `shouldBe` PullingWasStarted actorId
      next `shouldBe` PullPulling

    it "PullAccepted + Cancel → PullCancelled" $ do
      let (evt, next) = step PullAccepted (CancelCmd "reason" actorId)
      evt `shouldBe` PullWasCancelled "reason" actorId
      next `shouldBe` PullCancelled

    it "PullPulling + Fulfill → PullFulfilled" $ do
      let (evt, next) = step PullPulling (FulfillCmd actorId)
      evt `shouldBe` PullWasFulfilled actorId
      next `shouldBe` PullFulfilled

    it "PullPulling + Issue   → PullIssue" $ do
      let (evt, next) = step PullPulling (ReportIssueCmd "broken" actorId)
      evt `shouldBe` IssueWasReported "broken" actorId
      next `shouldBe` PullIssue

    it "PullIssue + Retry     → PullAccepted" $ do
      let (evt, next) = step PullIssue (RetryCmd actorId)
      evt `shouldBe` PullWasRetried actorId
      next `shouldBe` PullAccepted

    it "PullIssue + Cancel    → PullCancelled" $ do
      let (evt, next) = step PullIssue (CancelCmd "reason" actorId)
      evt `shouldBe` PullWasCancelled "reason" actorId
      next `shouldBe` PullCancelled

  describe "invalid transitions" $ do
    it "PullPending rejects StartPullCmd" $ do
      let (evt, next) = step PullPending (StartPullCmd actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullPending

    it "PullPending rejects FulfillCmd" $ do
      let (evt, next) = step PullPending (FulfillCmd actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullPending

    it "PullPending rejects RetryCmd" $ do
      let (evt, next) = step PullPending (RetryCmd actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullPending

    it "PullAccepted rejects FulfillCmd" $ do
      let (evt, next) = step PullAccepted (FulfillCmd actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullAccepted

    it "PullAccepted rejects AcceptCmd" $ do
      let (evt, next) = step PullAccepted (AcceptCmd actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullAccepted

    it "PullPulling rejects AcceptCmd" $ do
      let (evt, next) = step PullPulling (AcceptCmd actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullPulling

    it "PullPulling rejects CancelCmd" $ do
      let (evt, next) = step PullPulling (CancelCmd "r" actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullPulling

    it "PullIssue rejects FulfillCmd" $ do
      let (evt, next) = step PullIssue (FulfillCmd actorId)
      evt `shouldSatisfy` isInvalid
      next `shouldBe` PullIssue

  describe "sink state invariants (property)" $ do
    it "PullFulfilled absorbs every command" $ hedgehog $ do
      cmd <- forAll genCommand
      let (evt, next) = step PullFulfilled cmd
      assert (isInvalid evt)
      next === PullFulfilled

    it "PullCancelled absorbs every command" $ hedgehog $ do
      cmd <- forAll genCommand
      let (evt, next) = step PullCancelled cmd
      assert (isInvalid evt)
      next === PullCancelled
