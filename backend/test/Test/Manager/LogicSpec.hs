{-# LANGUAGE OverloadedStrings #-}

module Test.Manager.LogicSpec (spec) where

import Data.Time (UTCTime, addUTCTime)
import Data.UUID (UUID)
import Test.Hspec (Spec, describe, it, shouldBe)

import Server.Manager (buildDayStats, isManagerEvent, toTransactionSummary)
import Types.Admin (
  LocationDayStats (..),
  TransactionSummary (..),
 )
import Types.Auth (UserRole (..))
import Types.Events.Domain (
  DomainEvent (
    InventoryEvt,
    RegisterEvt,
    SessionEvt,
    TransactionEvt
  ),
 )
import Types.Events
import Types.Location (LocationId (..))
import Types.Transaction (
  Transaction (..),
  TransactionStatus (Completed, InProgress, Refunded, Voided),
  TransactionType (Return, Sale),
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
mkTx status created total =
  Transaction
    { transactionId = testUUID
    , transactionStatus = status
    , transactionCreated = created
    , transactionCompleted = Nothing
    , transactionCustomerId = Nothing
    , transactionEmployeeId = testUUID2
    , transactionRegisterId = testUUID2
    , transactionLocationId = LocationId testUUID2
    , transactionItems = []
    , transactionPayments = []
    , transactionSubtotal = total
    , transactionDiscountTotal = 0
    , transactionTaxTotal = 0
    , transactionTotal = total
    , transactionType = Sale
    , transactionIsVoided = False
    , transactionVoidReason = Nothing
    , transactionIsRefunded = False
    , transactionRefundReason = Nothing
    , transactionReferenceTransactionId = Nothing
    , transactionNotes = Nothing
    }

-- | A sale that was refunded: status Refunded and the flag set.
mkRefundedSale :: UTCTime -> Int -> Transaction
mkRefundedSale created total =
  (mkTx Refunded created total) {transactionIsRefunded = True}

-- | The return row a refund writes for a sale of the given total: type
-- Return, status Completed, the amounts negated.
mkReturn :: UTCTime -> Int -> Transaction
mkReturn created saleTotal =
  (mkTx Completed created (negate saleTotal))
    { transactionType = Return
    , transactionReferenceTransactionId = Just testUUID
    , transactionRefundReason = Just "refund"
    }

spec :: Spec
spec = describe "Manager Logic" $ do
  describe "toTransactionSummary" $ do
    it "calculates elapsed seconds correctly" $ do
      let
        now = addUTCTime 120 testTime
        tx = mkTx InProgress testTime 5000
        ts = toTransactionSummary 1800 now tx
      tsElapsedSecs ts `shouldBe` 120

    it "marks stale when elapsed exceeds threshold" $ do
      let
        now = addUTCTime 2000 testTime
        tx = mkTx InProgress testTime 5000
        ts = toTransactionSummary 1800 now tx
      tsIsStale ts `shouldBe` True

    it "does not mark stale when under threshold" $ do
      let
        now = addUTCTime 60 testTime
        tx = mkTx InProgress testTime 5000
        ts = toTransactionSummary 1800 now tx
      tsIsStale ts `shouldBe` False

    it "exactly at threshold is not stale" $ do
      let
        now = addUTCTime 1800 testTime
        tx = mkTx InProgress testTime 5000
        ts = toTransactionSummary 1800 now tx
      tsIsStale ts `shouldBe` False

    it "preserves transaction total" $ do
      let
        now = addUTCTime 60 testTime
        tx = mkTx Completed testTime 9999
        ts = toTransactionSummary 1800 now tx
      tsTotal ts `shouldBe` 9999

    it "counts zero items for empty transaction" $ do
      let
        now = addUTCTime 60 testTime
        tx = mkTx InProgress testTime 0
        ts = toTransactionSummary 1800 now tx
      tsItemCount ts `shouldBe` 0

  describe "buildDayStats" $ do
    it "returns zeros for empty list" $ do
      let stats = buildDayStats [] midday
      ldsTxCount stats `shouldBe` 0
      ldsRevenue stats `shouldBe` 0
      ldsVoidCount stats `shouldBe` 0
      ldsRefundCount stats `shouldBe` 0
      ldsAvgTxValue stats `shouldBe` 0

    it "counts only completed transactions" $ do
      let txs =
            [ mkTx Completed testTime 1000
            , mkTx InProgress testTime 500
            , mkTx Voided testTime 200
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
            [ (mkTx Completed testTime 1000) {transactionIsVoided = True}
            , mkTx Completed testTime 2000
            ]
      let stats = buildDayStats txs midday
      ldsVoidCount stats `shouldBe` 1

    it "counts refunded transactions" $ do
      let txs =
            [ (mkTx Completed testTime 1000) {transactionIsRefunded = True}
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
      let
        yesterday = read "2024-06-14 10:00:00 UTC" :: UTCTime
        txs =
          [ mkTx Completed testTime 1000
          , mkTx Completed yesterday 9999
          ]
      let stats = buildDayStats txs midday
      ldsTxCount stats `shouldBe` 1
      ldsRevenue stats `shouldBe` 1000

  describe "buildDayStats with refunds" $ do
    it "a sale refunded the same day adds nothing to revenue" $ do
      let txs =
            [ mkRefundedSale testTime 1000
            , mkReturn testTime 1000
            , mkTx Completed testTime 2000
            ]
      let stats = buildDayStats txs midday
      ldsRevenue stats `shouldBe` 2000

    it "a refunded sale is still counted as a transaction" $ do
      let txs =
            [ mkRefundedSale testTime 1000
            , mkReturn testTime 1000
            , mkTx Completed testTime 2000
            ]
      let stats = buildDayStats txs midday
      ldsTxCount stats `shouldBe` 2

    it "a return row is not counted as a transaction" $ do
      let txs = [mkReturn testTime 1000]
      let stats = buildDayStats txs midday
      ldsTxCount stats `shouldBe` 0

    it "a return row is not counted as a refunded sale" $ do
      let txs =
            [ mkRefundedSale testTime 1000
            , (mkReturn testTime 1000) {transactionIsRefunded = True}
            ]
      let stats = buildDayStats txs midday
      ldsRefundCount stats `shouldBe` 1

    it "counts a sale with status Refunded as refunded" $ do
      let txs =
            [ mkRefundedSale testTime 1000
            , mkReturn testTime 1000
            ]
      let stats = buildDayStats txs midday
      ldsRefundCount stats `shouldBe` 1

    it "a return for a sale of an earlier day lowers today's revenue" $ do
      let
        yesterday = read "2024-06-14 10:00:00 UTC" :: UTCTime
        txs =
          [ mkRefundedSale yesterday 1000
          , mkReturn testTime 1000
          , mkTx Completed testTime 2500
          ]
      let stats = buildDayStats txs midday
      ldsRevenue stats `shouldBe` 1500
      ldsTxCount stats `shouldBe` 1

    it "the average is revenue after returns over the number of sales" $ do
      let txs =
            [ mkRefundedSale testTime 1000
            , mkReturn testTime 1000
            , mkTx Completed testTime 3000
            ]
      let stats = buildDayStats txs midday
      ldsAvgTxValue stats `shouldBe` 1500

    it "a voided sale adds nothing to revenue" $ do
      let txs =
            [ (mkTx Voided testTime 1000) {transactionIsVoided = True}
            , mkTx Completed testTime 2000
            ]
      let stats = buildDayStats txs midday
      ldsRevenue stats `shouldBe` 2000
      ldsVoidCount stats `shouldBe` 1

  describe "isManagerEvent" $ do
    it "passes TransactionEvt" $ do
      let evt =
            TransactionEvt $
              TransactionVoided
                { teTxId = testUUID
                , teReason = "test"
                , teActorId = testUUID2
                , teTimestamp = testTime
                }
      isManagerEvent evt `shouldBe` True

    it "passes RegisterEvt" $ do
      let evt =
            RegisterEvt $
              RegisterOpened
                { reRegId = testUUID
                , reEmpId = testUUID2
                , reStartingCash = 50000
                , reTimestamp = testTime
                }
      isManagerEvent evt `shouldBe` True

    it "filters out SessionEvt" $ do
      let evt =
            SessionEvt $
              SessionCreated
                { sesUserId = testUUID
                , sesRole = Cashier
                , sesTimestamp = testTime
                }
      isManagerEvent evt `shouldBe` False

    it "filters out InventoryEvt" $ do
      let evt =
            InventoryEvt $
              ItemDeleted
                { ieSku = testUUID
                , ieItemName = "Test"
                , ieTimestamp = testTime
                , ieActorId = testUUID2
                }
      isManagerEvent evt `shouldBe` False