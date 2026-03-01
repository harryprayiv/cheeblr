module Test.Money where

import Prelude

import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..), isJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Utils.Money
  ( fromDollars
  , toDollars
  , formatDiscretePrice
  , parseMoneyString
  )

spec :: Spec Unit
spec = describe "Utils.Money" do

  describe "fromDollars" do
    it "converts whole dollars to cents" do
      fromDollars 1.0 `shouldEqual` Discrete 100
    it "converts fractional dollars" do
      fromDollars 29.99 `shouldEqual` Discrete 2999
    it "converts zero" do
      fromDollars 0.0 `shouldEqual` Discrete 0
    it "converts small amount" do
      fromDollars 0.01 `shouldEqual` Discrete 1

  describe "toDollars" do
    it "converts cents to dollars" do
      toDollars (Discrete 2999) `shouldEqual` 29.99
    it "converts zero" do
      toDollars (Discrete 0) `shouldEqual` 0.0
    it "converts 100 cents to 1 dollar" do
      toDollars (Discrete 100) `shouldEqual` 1.0

  describe "fromDollars/toDollars roundtrip" do
    it "roundtrips 29.99" do
      toDollars (fromDollars 29.99) `shouldEqual` 29.99
    it "roundtrips 0.0" do
      toDollars (fromDollars 0.0) `shouldEqual` 0.0
    it "roundtrips 100.0" do
      toDollars (fromDollars 100.0) `shouldEqual` 100.0

  describe "formatDiscretePrice" do
    it "formats zero" do
      formatDiscretePrice (Discrete 0) `shouldEqual` "0.00"
    it "formats typical price" do
      formatDiscretePrice (Discrete 2999) `shouldEqual` "29.99"
    it "formats whole dollar" do
      formatDiscretePrice (Discrete 100) `shouldEqual` "1.00"

  describe "parseMoneyString" do
    it "parses valid dollar amount" do
      parseMoneyString "29.99" `shouldEqual` Just (Discrete 2999)
    it "parses whole dollar" do
      parseMoneyString "10" `shouldEqual` Just (Discrete 1000)
    it "parses zero" do
      parseMoneyString "0" `shouldEqual` Just (Discrete 0)
    it "returns Nothing for invalid" do
      parseMoneyString "abc" `shouldEqual` Nothing
    it "trims whitespace" do
      parseMoneyString "  29.99  " `shouldSatisfy` isJust