{-# LANGUAGE OverloadedStrings #-}

module Test.Manager.TypesSpec (spec) where

import Data.Aeson (decode, encode)
import Data.Maybe (isJust)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Types.Admin
import Types.Transaction (TransactionStatus (..))

testUUID :: UUID
testUUID = read "11111111-1111-1111-1111-111111111111"

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

spec :: Spec
spec = describe "Manager Types" $ do
  describe "TransactionSummary JSON" $ do
    it "roundtrips" $ do
      let ts =
            TransactionSummary
              { tsId = testUUID
              , tsStatus = InProgress
              , tsCreated = testTime
              , tsElapsedSecs = 120
              , tsItemCount = 3
              , tsTotal = 5000
              , tsIsStale = False
              }
      decode (encode ts) `shouldBe` Just ts

    it "stale flag roundtrips" $ do
      let ts = TransactionSummary testUUID Created testTime 9999 0 0 True
      (decode (encode ts) :: Maybe TransactionSummary) `shouldSatisfy` isJust

  describe "LocationDayStats JSON" $ do
    it "roundtrips" $ do
      let s =
            LocationDayStats
              { ldsTxCount = 10
              , ldsRevenue = 50000
              , ldsVoidCount = 1
              , ldsRefundCount = 0
              , ldsAvgTxValue = 5000
              }
      decode (encode s) `shouldBe` Just s

    it "handles zeroes" $ do
      let s = LocationDayStats 0 0 0 0 0
      decode (encode s) `shouldBe` Just s

  describe "ManagerAlert JSON" $ do
    it "LowInventoryAlert roundtrips" $ do
      let a = LowInventoryAlert testUUID "Blue Dream" 3 5
      decode (encode a) `shouldBe` Just a

    it "StaleTransactionAlert roundtrips" $ do
      let a = StaleTransactionAlert testUUID 1800
      decode (encode a) `shouldBe` Just a

    it "RegisterVarianceAlert roundtrips" $ do
      let a = RegisterVarianceAlert testUUID 500
      decode (encode a) `shouldBe` Just a

  describe "OverrideRequest JSON" $ do
    it "roundtrips" $ do
      let r = OverrideRequest {orActorId = testUUID, orReason = "Customer request"}
      decode (encode r) `shouldBe` Just r
