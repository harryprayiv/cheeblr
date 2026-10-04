{-# LANGUAGE OverloadedStrings #-}

module Test.Domain.SaleRulesSpec (spec) where

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import Domain.SaleRules

spec :: Spec
spec = describe "Domain.SaleRules" $ do

  describe "formatCents" $ do
    it "formats whole dollars" $ formatCents 1200 `shouldBe` "$12.00"
    it "pads single-digit cents" $ formatCents 705 `shouldBe` "$7.05"
    it "formats under a dollar" $ formatCents 52 `shouldBe` "$0.52"
    it "formats zero" $ formatCents 0 `shouldBe` "$0.00"
    it "formats a negative amount" $ formatCents (-5) `shouldBe` "-$0.05"

  describe "changeDue" $ do
    it "an exact payment has no change" $
      changeDue 2052 2052 `shouldBe` Right 0
    it "returns the difference" $
      changeDue 2052 4000 `shouldBe` Right 1948
    it "rejects a zero amount" $
      changeDue 0 1000 `shouldBe` Left (NonPositiveAmount 0)
    it "rejects a negative amount" $
      changeDue (-100) 1000 `shouldBe` Left (NonPositiveAmount (-100))
    it "rejects tendering less than the amount" $
      changeDue 2052 2000 `shouldBe` Left (TenderedBelowAmount 2052 2000)

    it "amount plus change equals tendered" $ hedgehog $ do
      amount <- forAll (Gen.int (Range.linear 1 10000000))
      extra  <- forAll (Gen.int (Range.linear 0 10000000))
      case changeDue amount (amount + extra) of
        Left err     -> annotateShow err >> failure
        Right change -> do
          change === extra
          assert (change >= 0)

  describe "paymentErrorText" $ do
    it "describes a non-positive amount" $
      paymentErrorText (NonPositiveAmount 0)
        `shouldBe` "Payment amount must be greater than zero, got $0.00"
    it "describes a short tender" $
      paymentErrorText (TenderedBelowAmount 2052 2000)
        `shouldBe` "Tendered $20.00 is less than the payment amount $20.52"

  describe "finalizeProblems" $ do
    it "is empty when items exist and payment covers the total" $
      finalizeProblems 2 2052 2052 `shouldBe` []
    it "is empty when overpaid" $
      finalizeProblems 2 2052 3000 `shouldBe` []
    it "reports an empty sale" $
      finalizeProblems 0 0 0 `shouldBe` ["No items in transaction"]
    it "reports the shortfall" $
      finalizeProblems 2 2052 2000 `shouldBe` ["Payment is short by $0.52"]
    it "reports an unpaid sale" $
      finalizeProblems 1 1000 0 `shouldBe` ["Payment is short by $10.00"]

    it "has no problems exactly when there are items and payment covers the total" $ hedgehog $ do
      items <- forAll (Gen.int (Range.linear 0 20))
      total <- forAll (Gen.int (Range.linear 0 1000000))
      paid  <- forAll (Gen.int (Range.linear 0 1000000))
      null (finalizeProblems items total paid) === (items > 0 && paid >= total)
