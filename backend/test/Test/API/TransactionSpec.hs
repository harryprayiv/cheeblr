{-# LANGUAGE OverloadedStrings #-}

module Test.API.TransactionSpec (spec) where

import Test.Hspec
import Data.Aeson (encode, decode)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import API.Transaction

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testUUID :: UUID
testUUID = read "33333333-3333-3333-3333-333333333333"

testUUID2 :: UUID
testUUID2 = read "44444444-4444-4444-4444-444444444444"

testTime :: UTCTime
testTime = read "2024-06-15 10:30:00 UTC"

spec :: Spec
spec = describe "API.Transaction request/response types" $ do

  -- ──────────────────────────────────────────────
  -- AvailableInventory
  -- ──────────────────────────────────────────────
  describe "AvailableInventory JSON" $ do
    it "roundtrips through JSON" $ do
      let ai = AvailableInventory
            { availableTotal = 100
            , availableReserved = 25
            , availableActual = 75
            }
      decode (encode ai) `shouldBe` Just ai

    it "preserves all fields" $ do
      let ai = AvailableInventory 50 10 40
      case decode (encode ai) of
        Just ai' -> do
          availableTotal ai' `shouldBe` 50
          availableReserved ai' `shouldBe` 10
          availableActual ai' `shouldBe` 40
        Nothing -> expectationFailure "Failed to decode"

    it "handles zero values" $ do
      let ai = AvailableInventory 0 0 0
      decode (encode ai) `shouldBe` Just ai

  -- ──────────────────────────────────────────────
  -- ReservationRequest
  -- ──────────────────────────────────────────────
  describe "ReservationRequest JSON" $ do
    it "roundtrips through JSON" $ do
      let rr = ReservationRequest
            { reserveItemSku = testUUID
            , reserveTransactionId = testUUID2
            , reserveQuantity = 5
            }
      decode (encode rr) `shouldBe` Just rr

    it "preserves quantity" $ do
      let rr = ReservationRequest testUUID testUUID2 3
      case decode (encode rr) of
        Just rr' -> reserveQuantity rr' `shouldBe` 3
        Nothing  -> expectationFailure "Failed to decode"

  -- ──────────────────────────────────────────────
  -- OpenRegisterRequest
  -- ──────────────────────────────────────────────
  describe "OpenRegisterRequest JSON" $ do
    it "roundtrips through JSON" $ do
      let req = OpenRegisterRequest
            { openRegisterEmployeeId = testUUID
            , openRegisterStartingCash = 50000
            }
      decode (encode req) `shouldBe` Just req

    it "preserves starting cash" $ do
      let req = OpenRegisterRequest testUUID 25000
      case decode (encode req) of
        Just r  -> openRegisterStartingCash r `shouldBe` 25000
        Nothing -> expectationFailure "Failed to decode"

  -- ──────────────────────────────────────────────
  -- CloseRegisterRequest
  -- ──────────────────────────────────────────────
  describe "CloseRegisterRequest JSON" $ do
    it "roundtrips through JSON" $ do
      let req = CloseRegisterRequest
            { closeRegisterEmployeeId = testUUID
            , closeRegisterCountedCash = 48000
            }
      decode (encode req) `shouldBe` Just req

  -- ──────────────────────────────────────────────
  -- CloseRegisterResult
  -- ──────────────────────────────────────────────
  describe "CloseRegisterResult JSON" $ do
    it "roundtrips through JSON" $ do
      let reg = Register
            { registerId = testUUID
            , registerName = "Register 1"
            , registerLocationId = testUUID2
            , registerIsOpen = False
            , registerCurrentDrawerAmount = 48000
            , registerExpectedDrawerAmount = 50000
            , registerOpenedAt = Just testTime
            , registerOpenedBy = Just testUUID2
            , registerLastTransactionTime = Nothing
            }
      let result = CloseRegisterResult
            { closeRegisterResultRegister = reg
            , closeRegisterResultVariance = 2000
            }
      decode (encode result) `shouldBe` Just result

    it "preserves variance" $ do
      let reg = Register testUUID "Reg" testUUID2 False 0 0 Nothing Nothing Nothing
      let result = CloseRegisterResult reg 500
      case decode (encode result) of
        Just r  -> closeRegisterResultVariance r `shouldBe` 500
        Nothing -> expectationFailure "Failed to decode"

  -- ──────────────────────────────────────────────
  -- Register
  -- ──────────────────────────────────────────────
  describe "Register JSON" $ do
    it "roundtrips through JSON" $ do
      let reg = Register
            { registerId = testUUID
            , registerName = "Main Register"
            , registerLocationId = testUUID2
            , registerIsOpen = True
            , registerCurrentDrawerAmount = 50000
            , registerExpectedDrawerAmount = 50000
            , registerOpenedAt = Just testTime
            , registerOpenedBy = Just testUUID
            , registerLastTransactionTime = Nothing
            }
      decode (encode reg) `shouldBe` Just reg

    it "handles closed register with all Nothing optional fields" $ do
      let reg = Register testUUID "Reg" testUUID2 False 0 0 Nothing Nothing Nothing
      decode (encode reg) `shouldBe` Just reg

    it "handles open register with all Just optional fields" $ do
      let reg = Register
            { registerId = testUUID
            , registerName = "Reg"
            , registerLocationId = testUUID2
            , registerIsOpen = True
            , registerCurrentDrawerAmount = 50000
            , registerExpectedDrawerAmount = 50000
            , registerOpenedAt = Just testTime
            , registerOpenedBy = Just testUUID
            , registerLastTransactionTime = Just testTime
            }
      decode (encode reg) `shouldBe` Just reg

  -- ──────────────────────────────────────────────
  -- DailyReportRequest
  -- ──────────────────────────────────────────────
  describe "DailyReportRequest JSON" $ do
    it "roundtrips through JSON" $ do
      let req = DailyReportRequest
            { dailyReportDate = testTime
            , dailyReportLocationId = testUUID
            }
      decode (encode req) `shouldBe` Just req

  -- ──────────────────────────────────────────────
  -- DailyReportResult
  -- ──────────────────────────────────────────────
  describe "DailyReportResult JSON" $ do
    it "roundtrips through JSON" $ do
      let result = DailyReportResult
            { dailyReportCash = 10000
            , dailyReportCard = 5000
            , dailyReportOther = 1000
            , dailyReportTotal = 16000
            , dailyReportTransactions = 25
            }
      decode (encode result) `shouldBe` Just result

    it "handles zero report" $ do
      let result = DailyReportResult 0 0 0 0 0
      decode (encode result) `shouldBe` Just result

  -- ──────────────────────────────────────────────
  -- ComplianceReportRequest
  -- ──────────────────────────────────────────────
  describe "ComplianceReportRequest JSON" $ do
    it "roundtrips through JSON" $ do
      let req = ComplianceReportRequest
            { complianceReportStartDate = testTime
            , complianceReportEndDate = read "2024-06-30 23:59:59 UTC"
            , complianceReportLocationId = testUUID
            }
      decode (encode req) `shouldBe` Just req

  -- ──────────────────────────────────────────────
  -- ComplianceReportResult
  -- ──────────────────────────────────────────────
  describe "ComplianceReportResult JSON" $ do
    it "roundtrips through JSON" $ do
      let result = ComplianceReportResult
            { complianceReportContent = "All clear" }
      decode (encode result) `shouldBe` Just result

    it "handles empty content" $ do
      let result = ComplianceReportResult ""
      decode (encode result) `shouldBe` Just result
