{-# LANGUAGE OverloadedStrings #-}

module Test.API.AdminSpec (spec) where

import Data.Aeson (decode, encode, toJSON)
import Data.Maybe (isJust)
import Data.UUID (UUID)
import Test.Hspec

import Data.Int (Int64)
import Types.Admin

testUUID :: UUID
testUUID = read "11111111-1111-1111-1111-111111111111"

spec :: Spec
spec = describe "API.Admin types" $ do
  describe "AdminAction JSON roundtrip" $ do
    it "RevokeSession" $ do
      let a = RevokeSession testUUID
      decode (encode a) `shouldBe` Just a

    it "ClearRateLimitForIp" $ do
      let a = ClearRateLimitForIp "192.168.1.100"
      decode (encode a) `shouldBe` Just a

    it "ForceCloseRegister" $ do
      let a = ForceCloseRegister testUUID "Shift end"
      decode (encode a) `shouldBe` Just a

    it "SetLowStockThreshold" $ do
      let a = SetLowStockThreshold 3
      decode (encode a) `shouldBe` Just a

    it "TriggerSnapshotExport" $
      decode (encode TriggerSnapshotExport) `shouldBe` Just TriggerSnapshotExport

  describe "DomainEventRow JSON" $ do
    it "roundtrips" $ do
      let row =
            DomainEventRow
              { derSeq = 42 :: Int64
              , derId = testUUID
              , derType = "transaction.created"
              , derAggregateId = testUUID
              , derTraceId = Nothing
              , derActorId = Just testUUID
              , derLocationId = Nothing
              , derPayload = toJSON ("test" :: String)
              , derOccurredAt = read "2024-01-01 00:00:00 UTC"
              }
      decode (encode row) `shouldBe` Just row

  describe "SessionInfo JSON" $ do
    it "roundtrips" $ do
      let si =
            SessionInfo
              { siSessionId = testUUID
              , siUserId = testUUID
              , siRole = read "Admin"
              , siCreatedAt = read "2024-01-01 00:00:00 UTC"
              , siLastSeen = read "2024-01-01 01:00:00 UTC"
              }
      decode (encode si) `shouldBe` Just si

  describe "LogPage" $ do
    it "serialises with required fields" $ do
      let page = LogPage {lpEntries = [], lpNextCursor = Nothing, lpTotal = 0}
      (decode (encode page) :: Maybe LogPage) `shouldSatisfy` isJust

  describe "DomainEventPage" $ do
    it "serialises empty page" $ do
      let page = DomainEventPage {depEvents = [], depNextCursor = Nothing, depTotal = 0}
      (decode (encode page) :: Maybe DomainEventPage) `shouldSatisfy` isJust

  describe "TransactionPage" $ do
    it "serialises empty page" $ do
      let page = TransactionPage {tpTransactions = [], tpNextCursor = Nothing, tpTotal = 0}
      (decode (encode page) :: Maybe TransactionPage) `shouldSatisfy` isJust
