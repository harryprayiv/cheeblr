{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Effect.StockDbSpec (spec) where

import Data.Time (UTCTime)
import Data.UUID (UUID)
import Effectful (Eff, IOE, runEff)
import Test.Hspec

import Effect.StockDb
import State.StockPullMachine (PullVertex (..))
import Types.Location (LocationId (..))
import Types.Stock

-- ---------------------------------------------------------------------------
-- Fixed UUIDs
-- ---------------------------------------------------------------------------

pullId1, pullId2, pullId3 :: UUID
pullId1 = read "11111111-1111-1111-1111-111111111111"
pullId2 = read "22222222-2222-2222-2222-222222222222"
pullId3 = read "33333333-3333-3333-3333-333333333333"

txId1, txId2 :: UUID
txId1 = read "44444444-4444-4444-4444-444444444444"
txId2 = read "55555555-5555-5555-5555-555555555555"

itemSku1, itemSku2 :: UUID
itemSku1 = read "66666666-6666-6666-6666-666666666666"
itemSku2 = read "77777777-7777-7777-7777-777777777777"

msgId1 :: UUID
msgId1 = read "88888888-8888-8888-8888-888888888888"

senderId :: UUID
senderId = read "99999999-9999-9999-9999-999999999999"

locId :: LocationId
locId = LocationId (read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")

otherLocId :: LocationId
otherLocId = LocationId (read "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkPull :: UUID -> UUID -> UUID -> LocationId -> PullVertex -> PullRequest
mkPull pid tid sku loc status =
  PullRequest
    { prId = pid
    , prTransactionId = tid
    , prItemSku = sku
    , prItemName = "Test Item"
    , prQuantityNeeded = 1
    , prStatus = status
    , prCashierId = Nothing
    , prRegisterId = Nothing
    , prLocationId = loc
    , prCreatedAt = testTime
    , prUpdatedAt = testTime
    , prFulfilledAt = Nothing
    }

mkMsg :: UUID -> UUID -> PullMessage
mkMsg mid pullId =
  PullMessage
    { pmId = mid
    , pmPullRequestId = pullId
    , pmFromRole = "cashier"
    , pmSenderId = senderId
    , pmMessage = "Please hurry"
    , pmCreatedAt = testTime
    }

-- Run a StockDb action against the pure interpreter and return the result.
run :: StockStore -> Eff '[StockDb, IOE] a -> IO a
run store action = fst <$> runEff (runStockDbPure store action)

-- ---------------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Effect.StockDb (pure interpreter)" $ do
  describe "createPullRequest / getPullRequest" $ do
    it "round-trips a pull request" $ do
      let pr = mkPull pullId1 txId1 itemSku1 locId PullPending
      result <- run emptyStockStore $ do
        _ <- createPullRequest pr
        getPullRequest pullId1
      result `shouldBe` Just pr

    it "returns Nothing for an unknown id" $ do
      result <- run emptyStockStore (getPullRequest pullId1)
      result `shouldBe` Nothing

    it "stores multiple pull requests independently" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId2 itemSku2 locId PullAccepted
      (r1, r2) <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        (,) <$> getPullRequest pullId1 <*> getPullRequest pullId2
      r1 `shouldBe` Just pr1
      r2 `shouldBe` Just pr2

  describe "updatePullStatus" $ do
    it "transitions to the requested vertex" $ do
      let pr = mkPull pullId1 txId1 itemSku1 locId PullPending
      status <- run emptyStockStore $ do
        _ <- createPullRequest pr
        _ <- updatePullStatus pullId1 PullAccepted Nothing
        fmap (fmap prStatus) (getPullRequest pullId1)
      status `shouldBe` Just PullAccepted

    it "returns Left for an unknown pull" $ do
      result <-
        run
          emptyStockStore
          (updatePullStatus pullId1 PullAccepted Nothing)
      result `shouldBe` Left "Pull request not found"

  describe "getPendingPulls" $ do
    it "returns non-terminal pulls for the location" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId2 itemSku2 locId PullFulfilled
      pulls <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        getPendingPulls locId
      map prId pulls `shouldBe` [pullId1]

    it "excludes cancelled pulls" $ do
      let pr = mkPull pullId1 txId1 itemSku1 locId PullCancelled
      pulls <- run emptyStockStore $ do
        _ <- createPullRequest pr
        getPendingPulls locId
      pulls `shouldBe` []

    it "includes PullIssue pulls (not terminal)" $ do
      let pr = mkPull pullId1 txId1 itemSku1 locId PullIssue
      pulls <- run emptyStockStore $ do
        _ <- createPullRequest pr
        getPendingPulls locId
      map prId pulls `shouldBe` [pullId1]

    it "excludes pulls from other locations" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId2 itemSku2 otherLocId PullPending
      pulls <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        getPendingPulls locId
      map prId pulls `shouldBe` [pullId1]

  describe "getPullsByTransaction" $ do
    it "returns all pulls for a transaction regardless of status" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId1 itemSku2 locId PullFulfilled
        pr3 = mkPull pullId3 txId2 itemSku1 locId PullPending
      ids <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        _ <- createPullRequest pr3
        fmap (map prId) (getPullsByTransaction txId1)
      ids `shouldMatchList` [pullId1, pullId2]

    it "returns empty list for an unknown transaction" $ do
      pulls <- run emptyStockStore (getPullsByTransaction txId1)
      pulls `shouldBe` []

  describe "cancelPullsForTransaction" $ do
    it "cancels all non-terminal pulls for the transaction" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId1 itemSku2 locId PullAccepted
      (s1, s2) <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        cancelPullsForTransaction txId1 "voided"
        s1 <- fmap (fmap prStatus) (getPullRequest pullId1)
        s2 <- fmap (fmap prStatus) (getPullRequest pullId2)
        pure (s1, s2)
      s1 `shouldBe` Just PullCancelled
      s2 `shouldBe` Just PullCancelled

    it "does not cancel already-fulfilled pulls" $ do
      let pr = mkPull pullId1 txId1 itemSku1 locId PullFulfilled
      status <- run emptyStockStore $ do
        _ <- createPullRequest pr
        cancelPullsForTransaction txId1 "voided"
        fmap (fmap prStatus) (getPullRequest pullId1)
      status `shouldBe` Just PullFulfilled

    it "does not affect other transactions" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId2 itemSku2 locId PullPending
      status2 <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        cancelPullsForTransaction txId1 "voided"
        fmap (fmap prStatus) (getPullRequest pullId2)
      status2 `shouldBe` Just PullPending

  describe "cancelPullsForItem" $ do
    it "cancels only the pull with the matching sku in the transaction" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId1 itemSku2 locId PullPending
      (s1, s2) <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        cancelPullsForItem txId1 itemSku1 "item removed"
        s1 <- fmap (fmap prStatus) (getPullRequest pullId1)
        s2 <- fmap (fmap prStatus) (getPullRequest pullId2)
        pure (s1, s2)
      s1 `shouldBe` Just PullCancelled
      s2 `shouldBe` Just PullPending

    it "does not cancel the same sku in a different transaction" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId2 itemSku1 locId PullPending
      (s1, s2) <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        cancelPullsForItem txId1 itemSku1 "item removed"
        s1 <- fmap (fmap prStatus) (getPullRequest pullId1)
        s2 <- fmap (fmap prStatus) (getPullRequest pullId2)
        pure (s1, s2)
      s1 `shouldBe` Just PullCancelled
      s2 `shouldBe` Just PullPending

    it "does not cancel a fulfilled pull even if sku and tx match" $ do
      let pr = mkPull pullId1 txId1 itemSku1 locId PullFulfilled
      status <- run emptyStockStore $ do
        _ <- createPullRequest pr
        cancelPullsForItem txId1 itemSku1 "item removed"
        fmap (fmap prStatus) (getPullRequest pullId1)
      status `shouldBe` Just PullFulfilled

  describe "messages" $ do
    it "stores and retrieves messages for a pull" $ do
      let
        pr = mkPull pullId1 txId1 itemSku1 locId PullPending
        msg = mkMsg msgId1 pullId1
      msgs <- run emptyStockStore $ do
        _ <- createPullRequest pr
        _ <- addPullMessage pullId1 msg
        getPullMessages pullId1
      msgs `shouldBe` [msg]

    it "returns empty list for a pull with no messages" $ do
      let pr = mkPull pullId1 txId1 itemSku1 locId PullPending
      msgs <- run emptyStockStore $ do
        _ <- createPullRequest pr
        getPullMessages pullId1
      msgs `shouldBe` []

    it "does not mix messages between different pulls" $ do
      let
        pr1 = mkPull pullId1 txId1 itemSku1 locId PullPending
        pr2 = mkPull pullId2 txId2 itemSku2 locId PullPending
        msg = mkMsg msgId1 pullId1
      msgs2 <- run emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        _ <- addPullMessage pullId1 msg
        getPullMessages pullId2
      msgs2 `shouldBe` []
