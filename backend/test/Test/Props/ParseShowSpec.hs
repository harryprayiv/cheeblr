{-# LANGUAGE OverloadedStrings #-}

module Test.Props.ParseShowSpec (spec) where

import qualified Data.Text as T
import           Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import           Test.Hspec
import           Test.Hspec.Hedgehog (hedgehog)

import           DB.Transaction
import           Test.Gen
import           Types.Transaction

spec :: Spec
spec = describe "Props.ParseShow" $ do

  describe "showStatus / parseTransactionStatus" $ do
    it "roundtrips all statuses" $ hedgehog $ do
      s <- forAll genTransactionStatus
      parseTransactionStatus (T.unpack (showStatus s)) === s

  describe "showTransactionType / parseTransactionType" $ do
    it "roundtrips all transaction types" $ hedgehog $ do
      t <- forAll genTransactionType
      parseTransactionType (T.unpack (showTransactionType t)) === t

  describe "showTaxCategory / parseTaxCategory" $ do
    it "roundtrips all tax categories" $ hedgehog $ do
      c <- forAll genTaxCategory
      parseTaxCategory (T.unpack (showTaxCategory c)) === c

  describe "showPaymentMethod / parsePaymentMethod" $ do
    it "roundtrips standard payment methods" $ hedgehog $ do
      m <- forAll $ Gen.element [Cash, Debit, Credit, ACH, GiftCard, StoredValue, Mixed]
      parsePaymentMethod (T.unpack (showPaymentMethod m)) === m

    it "roundtrips Other with arbitrary text payload" $ hedgehog $ do
      t <- forAll $ Gen.text (Range.linear 1 30) Gen.alphaNum
      parsePaymentMethod (T.unpack (showPaymentMethod (Other t))) === Other t

  describe "showDiscountType" $ do
    it "produces a known discriminator for every DiscountType" $ hedgehog $ do
      dt <- forAll genDiscountType
      let discriminator = showDiscountType dt
          known = ["PERCENT_OFF", "AMOUNT_OFF", "BUY_ONE_GET_ONE", "CUSTOM"]
      assert (discriminator `elem` known)