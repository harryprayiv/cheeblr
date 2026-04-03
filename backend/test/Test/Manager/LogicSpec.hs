{-# LANGUAGE OverloadedStrings #-}

module Test.Manager.LogicSpec (spec) where

import Data.Time          (UTCTime, addUTCTime)
import Data.UUID          (UUID)
import Test.Hspec ( Spec, describe, it, shouldBe )

import Server.Manager     (toTransactionSummary, buildDayStats, isManagerEvent)
import Types.Auth         (UserRole (..))
import Types.Events.Domain
    ( DomainEvent(InventoryEvt, TransactionEvt, RegisterEvt,
                  SessionEvt) )
import Types.Events.Inventory (InventoryEvent (..))
import Types.Events.Register  (RegisterEvent (..))
import Types.Events.Session   (SessionEvent (..))
import Types.Events.Transaction (TransactionEvent (..))
import Types.Location     (LocationId (..))
import Types.Transaction
    ( Transaction(..),
      TransactionStatus(Completed, Voided, InProgress),
      TransactionType(Sale) )
import Types.Admin
  ( TransactionSummary (..)
  , LocationDayStats (..)
  
  
  
  )


testUUID :: UUID
testUUID = read "11111111-1111-1111-1111-111111111111"

testUUID2 :: UUID
testUUID2 = read "22222222-2222-2222-2222-222222222222"

testTime :: UTCTime
testTime = read "2024-06-15 10:00:00 UTC"

midday :: UTCTime
midday = read "2024-06-15 12:00:00 UTC"

mkTx :: TransactionStatus -> UTCTime -> Int -> Transaction
mkTx status created total = Transaction
  { transactionId                     = testUUID
  , transactionStatus                 = status
  , transactionCreated                = created
  , transactionCompleted              = Nothing
  , transactionCustomerId             = Nothing
  , transactionEmployeeId             = testUUID2
  , transactionRegisterId             = testUUID2
  , transactionLocationId             = LocationId testUUID2
  , transactionItems                  = []
  , transactionPayments               = []
  , transactionSubtotal               = total
  , transactionDiscountTotal          = 0
  , transactionTaxTotal               = 0
  , transactionTotal                  = total
  , transactionType                   = Sale
  , transactionIsVoided               = False
  , transactionVoidReason             = Nothing
  , transactionIsRefunded             = False
  , transactionRefundReason           = Nothing
  , transactionReferenceTransactionId = Nothing
  , transactionNotes                  = Nothing
  }

spec :: Spec
spec = describe "Manager Logic" $ do

  describe "toTransactionSummary" $ do
    it "calculates elapsed seconds correctly" $ do
      let now = addUTCTime 120 testTime
          tx  = mkTx InProgress testTime 5000
          ts  = toTransactionSummary 1800 now tx
      tsElapsedSecs ts `shouldBe` 120

    it "marks stale when elapsed exceeds threshold" $ do
      let now = addUTCTime 2000 testTime
          tx  = mkTx InProgress testTime 5000
          ts  = toTransactionSummary 1800 now tx
      tsIsStale ts `shouldBe` True

    it "does not mark stale when under threshold" $ do
      let now = addUTCTime 60 testTime
          tx  = mkTx InProgress testTime 5000
          ts  = toTransactionSummary 1800 now tx
      tsIsStale ts `shouldBe` False

    it "exactly at threshold is not stale" $ do
      let now = addUTCTime 1800 testTime
          tx  = mkTx InProgress testTime 5000
          ts  = toTransactionSummary 1800 now tx
      tsIsStale ts `shouldBe` False

    it "preserves transaction total" $ do
      let now = addUTCTime 60 testTime
          tx  = mkTx Completed testTime 9999
          ts  = toTransactionSummary 1800 now tx
      tsTotal ts `shouldBe` 9999

    it "counts zero items for empty transaction" $ do
      let now = addUTCTime 60 testTime
          tx  = mkTx InProgress testTime 0
          ts  = toTransactionSummary 1800 now tx
      tsItemCount ts `shouldBe` 0

  describe "buildDayStats" $ do
    it "returns zeros for empty list" $ do
      let stats = buildDayStats [] midday
      ldsTxCount     stats `shouldBe` 0
      ldsRevenue     stats `shouldBe` 0
      ldsVoidCount   stats `shouldBe` 0
      ldsRefundCount stats `shouldBe` 0
      ldsAvgTxValue  stats `shouldBe` 0

    it "counts only completed transactions" $ do
      let txs =
            [ mkTx Completed testTime 1000
            , mkTx InProgress testTime 500
            , mkTx Voided    testTime 200
            ]
      let stats = buildDayStats txs midday
      ldsTxCount stats `shouldBe` 1

    it "sums revenue from completed transactions" $ do
      let txs =
            [ mkTx Completed testTime 1000
            , mkTx Completed testTime 2000
            , mkTx InProgress testTime 500
            ]
      let stats = buildDayStats txs midday
      ldsRevenue stats `shouldBe` 3000

    it "counts voided transactions" $ do
      let txs =
            [ (mkTx Completed testTime 1000) { transactionIsVoided = True }
            , mkTx Completed testTime 2000
            ]
      let stats = buildDayStats txs midday
      ldsVoidCount stats `shouldBe` 1

    it "counts refunded transactions" $ do
      let txs =
            [ (mkTx Completed testTime 1000) { transactionIsRefunded = True }
            , mkTx Completed testTime 2000
            ]
      let stats = buildDayStats txs midday
      ldsRefundCount stats `shouldBe` 1

    it "calculates average correctly" $ do
      let txs =
            [ mkTx Completed testTime 1000
            , mkTx Completed testTime 3000
            ]
      let stats = buildDayStats txs midday
      ldsAvgTxValue stats `shouldBe` 2000

    it "excludes transactions from other days" $ do
      let yesterday = read "2024-06-14 10:00:00 UTC" :: UTCTime
          txs =
            [ mkTx Completed testTime 1000
            , mkTx Completed yesterday 9999
            ]
      let stats = buildDayStats txs midday
      ldsTxCount stats `shouldBe` 1
      ldsRevenue stats `shouldBe` 1000

  describe "isManagerEvent" $ do
    it "passes TransactionEvt" $ do
      let evt = TransactionEvt $ TransactionVoided
            { teTxId      = testUUID
            , teReason    = "test"
            , teActorId   = testUUID2
            , teTimestamp = testTime
            }
      isManagerEvent evt `shouldBe` True

    it "passes RegisterEvt" $ do
      let evt = RegisterEvt $ RegisterOpened
            { reRegId        = testUUID
            , reEmpId        = testUUID2
            , reStartingCash = 50000
            , reTimestamp    = testTime
            }
      isManagerEvent evt `shouldBe` True

    it "filters out SessionEvt" $ do
      let evt = SessionEvt $ SessionCreated
            { sesUserId    = testUUID
            , sesRole      = Cashier
            , sesTimestamp = testTime
            }
      isManagerEvent evt `shouldBe` False

    it "filters out InventoryEvt" $ do
      let evt = InventoryEvt $ ItemDeleted
            { ieSku       = testUUID
            , ieItemName  = "Test"
            , ieTimestamp = testTime
            , ieActorId   = testUUID2
            }
      isManagerEvent evt `shouldBe` False