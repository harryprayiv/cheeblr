{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds         #-}

module Test.Effect.StockDbSpec (spec) where

import qualified Data.Map.Strict as Map
import           Data.Time       (UTCTime)
import           Data.UUID       (UUID)
import Effectful ( runPureEff, Eff, runPureEff )
import           Test.Hspec

import Effect.StockDb
import State.StockPullMachine (PullVertex (..))
import Types.Location         (LocationId (..))
import Types.Stock

locId :: LocationId
locId = LocationId (read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")

locId2 :: LocationId
locId2 = LocationId (read "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

pullId :: UUID
pullId = read "11111111-1111-1111-1111-111111111111"

pullId2 :: UUID
pullId2 = read "22222222-2222-2222-2222-222222222222"

txId :: UUID
txId = read "33333333-3333-3333-3333-333333333333"

actorId :: UUID
actorId = read "44444444-4444-4444-4444-444444444444"

msgId :: UUID
msgId = read "55555555-5555-5555-5555-555555555555"

testTime :: UTCTime
testTime = read "2024-01-01 00:00:00 UTC"

mkPullRequest :: UUID -> LocationId -> PullVertex -> PullRequest
mkPullRequest pid loc status = PullRequest
  { prId             = pid
  , prTransactionId  = txId
  , prItemSku        = read "66666666-6666-6666-6666-666666666666"
  , prItemName       = "Blue Dream"
  , prQuantityNeeded = 2
  , prStatus         = status
  , prCashierId      = Nothing
  , prRegisterId     = Nothing
  , prLocationId     = loc
  , prCreatedAt      = testTime
  , prUpdatedAt      = testTime
  , prFulfilledAt    = Nothing
  }

mkMessage :: UUID -> UUID -> PullMessage
mkMessage mid pid = PullMessage
  { pmId            = mid
  , pmPullRequestId = pid
  , pmFromRole      = "cashier"
  , pmSenderId      = actorId
  , pmMessage       = "Please bring 2 units"
  , pmCreatedAt     = testTime
  }

runPure :: StockStore -> Eff '[StockDb] a -> IO (a, StockStore)
runPure store action = pure $ runPureEff $ runStockDbPure store action

spec :: Spec
spec = describe "Effect.StockDb pure interpreter" $ do

  describe "createPullRequest / getPullRequest" $ do
    it "creates and retrieves a pull request" $ do
      let pr = mkPullRequest pullId locId PullPending
      (result, store) <- runPure emptyStockStore (createPullRequest pr)
      result `shouldBe` Right ()
      Map.size (ssRequests store) `shouldBe` 1

    it "getPullRequest returns Nothing for unknown id" $ do
      (result, _) <- runPure emptyStockStore (getPullRequest pullId)
      result `shouldBe` Nothing

    it "getPullRequest returns Just after creation" $ do
      let pr = mkPullRequest pullId locId PullPending
      (result, _) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr
        getPullRequest pullId
      result `shouldBe` Just pr

  describe "updatePullStatus" $ do
    it "updates status of existing request" $ do
      let pr = mkPullRequest pullId locId PullPending
      (result, store) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr
        updatePullStatus pullId PullAccepted Nothing
      result `shouldBe` Right ()
      case Map.lookup pullId (ssRequests store) of
        Just pr' -> prStatus pr' `shouldBe` PullAccepted
        Nothing  -> expectationFailure "Pull request not found after update"

    it "returns Left for unknown pull request" $ do
      (result, _) <- runPure emptyStockStore $
        updatePullStatus pullId PullAccepted Nothing
      result `shouldBe` Left "Pull request not found"

  describe "getPendingPulls" $ do
    it "returns empty for empty store" $ do
      (result, _) <- runPure emptyStockStore (getPendingPulls locId)
      result `shouldBe` []

    it "returns pending pulls for location" $ do
      let pr = mkPullRequest pullId locId PullPending
      (result, _) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr
        getPendingPulls locId
      length result `shouldBe` 1

    it "excludes fulfilled pulls" $ do
      let pr = mkPullRequest pullId locId PullFulfilled
      (result, _) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr
        getPendingPulls locId
      result `shouldBe` []

    it "excludes cancelled pulls" $ do
      let pr = mkPullRequest pullId locId PullCancelled
      (result, _) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr
        getPendingPulls locId
      result `shouldBe` []

    it "filters by location" $ do
      let pr1 = mkPullRequest pullId  locId  PullPending
          pr2 = mkPullRequest pullId2 locId2 PullPending
      (result, _) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        getPendingPulls locId
      length result `shouldBe` 1

  describe "cancelPullsForTransaction" $ do
    it "cancels all active pulls for a transaction" $ do
      let pr1 = mkPullRequest pullId  locId PullPending
          pr2 = mkPullRequest pullId2 locId PullAccepted
      (_, store) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr1
        _ <- createPullRequest pr2
        cancelPullsForTransaction txId "Voided"
      let statuses = map prStatus $ Map.elems (ssRequests store)
      all (== PullCancelled) statuses `shouldBe` True

    it "does not cancel fulfilled pulls" $ do
      let pr = mkPullRequest pullId locId PullFulfilled
      (_, store) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr
        cancelPullsForTransaction txId "Voided"
      case Map.lookup pullId (ssRequests store) of
        Just pr' -> prStatus pr' `shouldBe` PullFulfilled
        Nothing  -> expectationFailure "Pull request missing"

  describe "addPullMessage / getPullMessages" $ do
    it "adds and retrieves messages" $ do
      let pr  = mkPullRequest pullId locId PullPending
          msg = mkMessage msgId pullId
      (result, _) <- runPure emptyStockStore $ do
        _ <- createPullRequest pr
        _ <- addPullMessage pullId msg
        getPullMessages pullId
      length result `shouldBe` 1

    it "returns empty messages for unknown pull" $ do
      (result, _) <- runPure emptyStockStore (getPullMessages pullId)
      result `shouldBe` []