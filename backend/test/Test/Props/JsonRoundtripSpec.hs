{-# LANGUAGE OverloadedStrings #-}

module Test.Props.JsonRoundtripSpec (spec) where

import Data.Aeson (decode, encode)
import Hedgehog
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import Test.Gen

spec :: Spec
spec = describe "Props.JsonRoundtrip" $ do
  describe "Types.Transaction" $ do
    it "DiscountType" $ hedgehog $ do
      x <- forAll genDiscountType
      decode (encode x) === Just x

    it "TaxRecord" $ hedgehog $ do
      x <- forAll genTaxRecord
      decode (encode x) === Just x

    it "DiscountRecord" $ hedgehog $ do
      x <- forAll genDiscountRecord
      decode (encode x) === Just x

    it "TransactionItem" $ hedgehog $ do
      x <- forAll genTransactionItem
      decode (encode x) === Just x

    it "PaymentTransaction" $ hedgehog $ do
      x <- forAll genPaymentTransaction
      decode (encode x) === Just x

    it "Transaction" $ hedgehog $ do
      x <- forAll genTransaction
      decode (encode x) === Just x

  describe "Types.Inventory" $ do
    it "StrainLineage" $ hedgehog $ do
      x <- forAll genStrainLineage
      decode (encode x) === Just x

    it "MenuItem" $ hedgehog $ do
      x <- forAll genMenuItem
      decode (encode x) === Just x

    it "Inventory" $ hedgehog $ do
      x <- forAll genInventory
      decode (encode x) === Just x
