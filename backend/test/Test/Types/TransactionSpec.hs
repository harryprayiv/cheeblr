{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Types.TransactionSpec (spec) where

import DB.Transaction (
  parseDiscountType,
  parsePaymentMethod,
  parseTaxCategory,
  parseTransactionStatus,
  parseTransactionType,
 )
import Data.Aeson (Result (..), decode, encode, fromJSON, toJSON)
import Data.Scientific (fromFloatDigits)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Test.Hspec
import Types.Location (LocationId (..))
import Types.Transaction

-- ──────────────────────────────────────────────
-- Fixtures
-- ──────────────────────────────────────────────

testUUID :: UUID
testUUID = read "33333333-3333-3333-3333-333333333333"

testUUID2 :: UUID
testUUID2 = read "44444444-4444-4444-4444-444444444444"

testTime :: UTCTime
testTime = read "2024-06-15 10:30:00 UTC"

mkTestTaxRecord :: TaxRecord
mkTestTaxRecord =
  TaxRecord
    { taxCategory = RegularSalesTax
    , taxRate = fromFloatDigits (0.08 :: Double)
    , taxAmount = 80
    , taxDescription = "Sales Tax"
    }

mkTestDiscount :: DiscountRecord
mkTestDiscount =
  DiscountRecord
    { discountType = PercentOff (fromFloatDigits (10.0 :: Double))
    , discountAmount = 100
    , discountReason = "Loyalty discount"
    , discountApprovedBy = Just testUUID
    }

mkTestTransactionItem :: TransactionItem
mkTestTransactionItem =
  TransactionItem
    { transactionItemId = testUUID
    , transactionItemTransactionId = testUUID2
    , transactionItemMenuItemSku = read "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    , transactionItemQuantity = 2
    , transactionItemPricePerUnit = 1000
    , transactionItemDiscounts = [mkTestDiscount]
    , transactionItemTaxes = [mkTestTaxRecord]
    , transactionItemSubtotal = 2000
    , transactionItemTotal = 1980
    }

mkTestPayment :: PaymentTransaction
mkTestPayment =
  PaymentTransaction
    { paymentId = testUUID
    , paymentTransactionId = testUUID2
    , paymentMethod = Cash
    , paymentAmount = 5000
    , paymentTendered = 6000
    , paymentChange = 1000
    , paymentReference = Nothing
    , paymentApproved = True
    , paymentAuthorizationCode = Nothing
    }

mkTestTransaction :: Transaction
mkTestTransaction =
  Transaction
    { transactionId = testUUID
    , transactionStatus = InProgress
    , transactionCreated = testTime
    , transactionCompleted = Nothing
    , transactionCustomerId = Nothing
    , transactionEmployeeId = testUUID2
    , transactionRegisterId = testUUID2
    , transactionLocationId = LocationId testUUID2
    , transactionItems = [mkTestTransactionItem]
    , transactionPayments = [mkTestPayment]
    , transactionSubtotal = 2000
    , transactionDiscountTotal = 100
    , transactionTaxTotal = 80
    , transactionTotal = 1980
    , transactionType = Sale
    , transactionIsVoided = False
    , transactionVoidReason = Nothing
    , transactionIsRefunded = False
    , transactionRefundReason = Nothing
    , transactionReferenceTransactionId = Nothing
    , transactionNotes = Nothing
    }

spec :: Spec
spec = describe "Types.Transaction" $ do
  -- ──────────────────────────────────────────────
  -- TransactionStatus
  -- ──────────────────────────────────────────────
  describe "TransactionStatus" $ do
    it "has correct ordering" $ do
      (Created < InProgress) `shouldBe` True
      (InProgress < Completed) `shouldBe` True
      (Completed < Voided) `shouldBe` True
      (Voided < Refunded) `shouldBe` True

    it "roundtrips through JSON" $ do
      let statuses = [Created, InProgress, Completed, Voided, Refunded]
      mapM_ (\s -> fromJSON (toJSON s) `shouldBe` Success s) statuses

    it "Show/Read roundtrip" $ do
      read (show Created) `shouldBe` Created
      read (show InProgress) `shouldBe` InProgress
      read (show Completed) `shouldBe` Completed

  describe "parseTransactionStatus" $ do
    it "parses CREATED" $ parseTransactionStatus "CREATED" `shouldBe` Created
    it "parses IN_PROGRESS" $ parseTransactionStatus "IN_PROGRESS" `shouldBe` InProgress
    it "parses COMPLETED" $ parseTransactionStatus "COMPLETED" `shouldBe` Completed
    it "parses VOIDED" $ parseTransactionStatus "VOIDED" `shouldBe` Voided
    it "parses REFUNDED" $ parseTransactionStatus "REFUNDED" `shouldBe` Refunded

  -- ──────────────────────────────────────────────
  -- TransactionType
  -- ──────────────────────────────────────────────
  describe "TransactionType" $ do
    it "has correct ordering" $ do
      (Sale < Return) `shouldBe` True
      (Return < Exchange) `shouldBe` True

    it "roundtrips through JSON" $ do
      let types = [Sale, Return, Exchange, InventoryAdjustment, ManagerComp, Administrative]
      mapM_ (\t -> fromJSON (toJSON t) `shouldBe` Success t) types

  describe "parseTransactionType" $ do
    it "parses SALE" $ parseTransactionType "SALE" `shouldBe` Sale
    it "parses RETURN" $ parseTransactionType "RETURN" `shouldBe` Return
    it "parses EXCHANGE" $ parseTransactionType "EXCHANGE" `shouldBe` Exchange
    it "parses INVENTORY_ADJUSTMENT" $ parseTransactionType "INVENTORY_ADJUSTMENT" `shouldBe` InventoryAdjustment
    it "parses MANAGER_COMP" $ parseTransactionType "MANAGER_COMP" `shouldBe` ManagerComp
    it "parses ADMINISTRATIVE" $ parseTransactionType "ADMINISTRATIVE" `shouldBe` Administrative

  -- ──────────────────────────────────────────────
  -- PaymentMethod
  -- ──────────────────────────────────────────────
  describe "PaymentMethod" $ do
    it "roundtrips standard methods through JSON" $ do
      let methods = [Cash, Debit, Credit, ACH, GiftCard, StoredValue, Mixed]
      mapM_ (\m -> fromJSON (toJSON m) `shouldBe` Success m) methods

    it "serializes Other with prefix" $ do
      toJSON (Other "Crypto") `shouldBe` toJSON ("Other:Crypto" :: String)

    it "deserializes Other: prefix" $ do
      fromJSON (toJSON ("Other:Bitcoin" :: String)) `shouldBe` Success (Other "Bitcoin")

  describe "parsePaymentMethod" $ do
    it "parses CASH" $ parsePaymentMethod "CASH" `shouldBe` Cash
    it "parses Cash" $ parsePaymentMethod "Cash" `shouldBe` Cash
    it "parses DEBIT" $ parsePaymentMethod "DEBIT" `shouldBe` Debit
    it "parses Debit" $ parsePaymentMethod "Debit" `shouldBe` Debit
    it "parses CREDIT" $ parsePaymentMethod "CREDIT" `shouldBe` Credit
    it "parses Credit" $ parsePaymentMethod "Credit" `shouldBe` Credit
    it "parses ACH" $ parsePaymentMethod "ACH" `shouldBe` ACH
    it "parses GIFT_CARD" $ parsePaymentMethod "GIFT_CARD" `shouldBe` GiftCard
    it "parses GiftCard" $ parsePaymentMethod "GiftCard" `shouldBe` GiftCard
    it "parses STORED_VALUE" $ parsePaymentMethod "STORED_VALUE" `shouldBe` StoredValue
    it "parses StoredValue" $ parsePaymentMethod "StoredValue" `shouldBe` StoredValue
    it "parses MIXED" $ parsePaymentMethod "MIXED" `shouldBe` Mixed
    it "parses Mixed" $ parsePaymentMethod "Mixed" `shouldBe` Mixed
    it "parses OTHER: prefix" $ parsePaymentMethod "OTHER:Crypto" `shouldBe` Other "Crypto"
    it "parses Other: prefix" $ parsePaymentMethod "Other:Bitcoin" `shouldBe` Other "Bitcoin"
    it "wraps unknown as Other" $ parsePaymentMethod "SomethingNew" `shouldBe` Other "SomethingNew"

  describe "PaymentMethod FromJSON" $ do
    it "parses CASH from JSON" $ fromJSON (toJSON ("CASH" :: String)) `shouldBe` (Success Cash :: Result PaymentMethod)
    it "parses Cash from JSON" $ fromJSON (toJSON ("Cash" :: String)) `shouldBe` (Success Cash :: Result PaymentMethod)
    it "parses DEBIT from JSON" $ fromJSON (toJSON ("DEBIT" :: String)) `shouldBe` (Success Debit :: Result PaymentMethod)
    it "parses OTHER: from JSON" $
      fromJSON (toJSON ("OTHER:Check" :: String)) `shouldBe` (Success (Other "Check") :: Result PaymentMethod)

  -- ──────────────────────────────────────────────
  -- TaxCategory
  -- ──────────────────────────────────────────────
  describe "TaxCategory" $ do
    it "roundtrips through JSON" $ do
      let cats = [RegularSalesTax, ExciseTax, CannabisTax, LocalTax, MedicalTax, NoTax]
      mapM_ (\c -> fromJSON (toJSON c) `shouldBe` Success c) cats

  describe "parseTaxCategory" $ do
    it "parses REGULAR_SALES_TAX" $ parseTaxCategory "REGULAR_SALES_TAX" `shouldBe` RegularSalesTax
    it "parses RegularSalesTax" $ parseTaxCategory "RegularSalesTax" `shouldBe` RegularSalesTax
    it "parses EXCISE_TAX" $ parseTaxCategory "EXCISE_TAX" `shouldBe` ExciseTax
    it "parses ExciseTax" $ parseTaxCategory "ExciseTax" `shouldBe` ExciseTax
    it "parses CANNABIS_TAX" $ parseTaxCategory "CANNABIS_TAX" `shouldBe` CannabisTax
    it "parses CannabisTax" $ parseTaxCategory "CannabisTax" `shouldBe` CannabisTax
    it "parses LOCAL_TAX" $ parseTaxCategory "LOCAL_TAX" `shouldBe` LocalTax
    it "parses LocalTax" $ parseTaxCategory "LocalTax" `shouldBe` LocalTax
    it "parses MEDICAL_TAX" $ parseTaxCategory "MEDICAL_TAX" `shouldBe` MedicalTax
    it "parses MedicalTax" $ parseTaxCategory "MedicalTax" `shouldBe` MedicalTax
    it "parses NO_TAX" $ parseTaxCategory "NO_TAX" `shouldBe` NoTax
    it "parses NoTax" $ parseTaxCategory "NoTax" `shouldBe` NoTax

  -- ──────────────────────────────────────────────
  -- DiscountType
  -- ──────────────────────────────────────────────
  describe "DiscountType" $ do
    describe "parseDiscountType" $ do
      it "parses PERCENT_OFF with value" $
        parseDiscountType "PERCENT_OFF" (Just 1500) `shouldBe` PercentOff 15.0

      it "parses AMOUNT_OFF with value" $
        parseDiscountType "AMOUNT_OFF" (Just 500) `shouldBe` AmountOff 500

      it "parses BUY_ONE_GET_ONE with value" $
        parseDiscountType "BUY_ONE_GET_ONE" (Just 0) `shouldBe` BuyOneGetOne

      it "parses BUY_ONE_GET_ONE without value" $
        parseDiscountType "BUY_ONE_GET_ONE" Nothing `shouldBe` BuyOneGetOne

      it "parses unknown type as Custom" $
        parseDiscountType "EMPLOYEE_DISCOUNT" (Just 300) `shouldBe` Custom "EMPLOYEE_DISCOUNT" 300

      it "defaults to AmountOff 0 for unknown without value" $
        parseDiscountType "UNKNOWN" Nothing `shouldBe` AmountOff 0

    -- ──────────────────────────────────────────────
    -- TaxRecord JSON
    -- ──────────────────────────────────────────────
    describe "TaxRecord JSON" $ do
      it "preserves category" $ do
        case decode (encode mkTestTaxRecord) of
          Just t -> taxCategory t `shouldBe` RegularSalesTax
          Nothing -> expectationFailure "Failed to decode"

      it "preserves amount" $ do
        case decode (encode mkTestTaxRecord) of
          Just t -> taxAmount t `shouldBe` 80
          Nothing -> expectationFailure "Failed to decode"

    -- ──────────────────────────────────────────────
    -- DiscountRecord JSON
    -- ──────────────────────────────────────────────
    describe "DiscountRecord JSON" $ do
      it "preserves approved_by" $ do
        case decode (encode mkTestDiscount) of
          Just d -> discountApprovedBy d `shouldBe` Just testUUID
          Nothing -> expectationFailure "Failed to decode"

      it "handles Nothing approved_by" $ do
        let d = mkTestDiscount {discountApprovedBy = Nothing}
        case decode (encode d) of
          Just d' -> discountApprovedBy d' `shouldBe` Nothing
          Nothing -> expectationFailure "Failed to decode"

    -- ──────────────────────────────────────────────
    -- TransactionItem JSON
    -- ──────────────────────────────────────────────
    describe "TransactionItem JSON" $ do
      it "preserves quantity" $ do
        case decode (encode mkTestTransactionItem) of
          Just ti -> transactionItemQuantity ti `shouldBe` 2
          Nothing -> expectationFailure "Failed to decode"

      it "preserves nested taxes" $ do
        case decode (encode mkTestTransactionItem) of
          Just ti -> length (transactionItemTaxes ti) `shouldBe` 1
          Nothing -> expectationFailure "Failed to decode"

      it "preserves nested discounts" $ do
        case decode (encode mkTestTransactionItem) of
          Just ti -> length (transactionItemDiscounts ti) `shouldBe` 1
          Nothing -> expectationFailure "Failed to decode"

    -- ──────────────────────────────────────────────
    -- PaymentTransaction JSON
    -- ──────────────────────────────────────────────
    describe "PaymentTransaction JSON" $ do
      it "preserves amount fields" $ do
        case decode (encode mkTestPayment) of
          Just p -> do
            paymentAmount p `shouldBe` 5000
            paymentTendered p `shouldBe` 6000
            paymentChange p `shouldBe` 1000
          Nothing -> expectationFailure "Failed to decode"

    -- ──────────────────────────────────────────────
    -- Transaction JSON
    -- ──────────────────────────────────────────────
    describe "Transaction JSON" $ do
      it "preserves status" $ do
        case decode (encode mkTestTransaction) of
          Just t -> transactionStatus t `shouldBe` InProgress
          Nothing -> expectationFailure "Failed to decode"

      it "preserves items" $ do
        case decode (encode mkTestTransaction) of
          Just t -> length (transactionItems t) `shouldBe` 1
          Nothing -> expectationFailure "Failed to decode"

      it "preserves payments" $ do
        case decode (encode mkTestTransaction) of
          Just t -> length (transactionPayments t) `shouldBe` 1
          Nothing -> expectationFailure "Failed to decode"

      it "preserves optional fields as Nothing" $ do
        case decode (encode mkTestTransaction) of
          Just t -> do
            transactionCompleted t `shouldBe` Nothing
            transactionCustomerId t `shouldBe` Nothing
            transactionVoidReason t `shouldBe` Nothing
            transactionRefundReason t `shouldBe` Nothing
            transactionNotes t `shouldBe` Nothing
          Nothing -> expectationFailure "Failed to decode"

      it "preserves optional fields as Just" $ do
        let tx =
              mkTestTransaction
                { transactionCompleted = Just testTime
                , transactionCustomerId = Just testUUID
                , transactionVoidReason = Just "Test void"
                , transactionNotes = Just "Test note"
                }
        case decode (encode tx) of
          Just t -> do
            transactionCompleted t `shouldBe` Just testTime
            transactionCustomerId t `shouldBe` Just testUUID
            transactionVoidReason t `shouldBe` Just "Test void"
            transactionNotes t `shouldBe` Just "Test note"
          Nothing -> expectationFailure "Failed to decode"

      it "handles voided transaction" $ do
        let tx =
              mkTestTransaction
                { transactionStatus = Voided
                , transactionIsVoided = True
                , transactionVoidReason = Just "Customer request"
                }
        case decode (encode tx) of
          Just t -> do
            transactionIsVoided t `shouldBe` True
            transactionVoidReason t `shouldBe` Just "Customer request"
          Nothing -> expectationFailure "Failed to decode"

      it "handles refunded transaction with reference" $ do
        let tx =
              mkTestTransaction
                { transactionStatus = Refunded
                , transactionIsRefunded = True
                , transactionRefundReason = Just "Defective"
                , transactionReferenceTransactionId = Just testUUID2
                }
        case decode (encode tx) of
          Just t -> do
            transactionIsRefunded t `shouldBe` True
            transactionReferenceTransactionId t `shouldBe` Just testUUID2
          Nothing -> expectationFailure "Failed to decode"

      it "handles all transaction types" $ do
        let types = [Sale, Return, Exchange, InventoryAdjustment, ManagerComp, Administrative]
        mapM_
          ( \ty -> do
              let tx = mkTestTransaction {transactionType = ty}
              case decode (encode tx) of
                Just t -> transactionType t `shouldBe` ty
                Nothing -> expectationFailure $ "Failed to decode " ++ show ty
          )
          types

    -- ──────────────────────────────────────────────
    -- InventoryReservation JSON
    -- ──────────────────────────────────────────────
    describe "InventoryReservation JSON" $ do
      it "roundtrips through JSON" $ do
        let r =
              InventoryReservation
                { reservationItemSku = testUUID
                , reservationTransactionId = testUUID2
                , reservationQuantity = 5
                , reservationStatus = "Reserved"
                }
        decode (encode r) `shouldBe` Just r

    -- ──────────────────────────────────────────────
    -- Ledger types JSON
    -- ──────────────────────────────────────────────
    describe "LedgerEntryType JSON" $ do
      it "roundtrips all variants" $ do
        let types = [SaleEntry, Tax, Discount, Payment, Refund, Void, Adjustment, Fee]
        mapM_ (\t -> fromJSON (toJSON t) `shouldBe` Success t) types

    describe "AccountType JSON" $ do
      it "roundtrips all variants" $ do
        let types = [Asset, Liability, Equity, Revenue, Expense]
        mapM_ (\t -> fromJSON (toJSON t) `shouldBe` Success t) types

    describe "Account JSON" $ do
      it "roundtrips through JSON" $ do
        let acct =
              Account
                { accountId = testUUID
                , accountCode = "1000"
                , accountName = "Cash"
                , accountIsDebitNormal = True
                , accountParentAccountId = Nothing
                , accountType = Asset
                }
        decode (encode acct) `shouldBe` Just acct

    describe "LedgerEntry JSON" $ do
      it "roundtrips through JSON" $ do
        let entry =
              LedgerEntry
                { ledgerEntryId = testUUID
                , ledgerEntryTransactionId = testUUID2
                , ledgerEntryAccountId = testUUID
                , ledgerEntryAmount = 5000
                , ledgerEntryIsDebit = True
                , ledgerEntryTimestamp = testTime
                , ledgerEntryType = SaleEntry
                , ledgerEntryDescription = "Sale payment"
                }
        decode (encode entry) `shouldBe` Just entry

    -- ──────────────────────────────────────────────
    -- Compliance types JSON
    -- ──────────────────────────────────────────────
    describe "VerificationType JSON" $ do
      it "roundtrips all variants" $ do
        let types =
              [ AgeVerification
              , MedicalCardVerification
              , IDScan
              , VisualInspection
              , PatientRegistration
              , PurchaseLimitCheck
              ]
        mapM_ (\t -> fromJSON (toJSON t) `shouldBe` Success t) types

    describe "VerificationStatus JSON" $ do
      it "roundtrips all variants" $ do
        let statuses = [VerifiedStatus, FailedStatus, ExpiredStatus, NotRequiredStatus]
        mapM_ (\s -> fromJSON (toJSON s) `shouldBe` Success s) statuses

    describe "ReportingStatus JSON" $ do
      it "roundtrips all variants" $ do
        let statuses = [NotRequired, Pending, Submitted, Acknowledged, Failed]
        mapM_ (\s -> fromJSON (toJSON s) `shouldBe` Success s) statuses

    describe "InventoryStatus JSON" $ do
      it "roundtrips all variants" $ do
        let statuses =
              [ Available
              , OnHold
              , Reserved
              , Sold
              , Damaged
              , Expired
              , InTransit
              , UnderReview
              , Recalled
              ]
        mapM_ (\s -> fromJSON (toJSON s) `shouldBe` Success s) statuses

    describe "CustomerVerification JSON" $ do
      it "roundtrips through JSON" $ do
        let cv =
              CustomerVerification
                { customerVerificationId = testUUID
                , customerVerificationCustomerId = testUUID2
                , customerVerificationType = AgeVerification
                , customerVerificationStatus = VerifiedStatus
                , customerVerificationVerifiedBy = testUUID
                , customerVerificationVerifiedAt = testTime
                , customerVerificationExpiresAt = Nothing
                , customerVerificationNotes = Just "Checked ID"
                , customerVerificationDocumentId = Just "DL-12345"
                }
        decode (encode cv) `shouldBe` Just cv

    describe "ComplianceRecord JSON" $ do
      it "roundtrips through JSON" $ do
        let cr =
              ComplianceRecord
                { complianceRecordId = testUUID
                , complianceRecordTransactionId = testUUID2
                , complianceRecordVerifications = []
                , complianceRecordIsCompliant = True
                , complianceRecordRequiresStateReporting = False
                , complianceRecordReportingStatus = NotRequired
                , complianceRecordReportedAt = Nothing
                , complianceRecordReferenceId = Nothing
                , complianceRecordNotes = Nothing
                }
        decode (encode cr) `shouldBe` Just cr
