module Test.FormParser where

import Prelude

import Data.Either (Either(..), isLeft, isRight)
import Data.Maybe (Maybe(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import UI.Form.Parser (alphanumeric, cents, commaList, maxLen, measurementUnit, nonNegativeInt, optional, percentage, positiveInt, required, url, uuid)

spec :: Spec Unit
spec = describe "UI.Form.Parser" do

  describe "required" do
    it "rejects blank" $ required "   " `shouldEqual` Left "Required"
    it "trims" $ required "  Blue Dream " `shouldEqual` Right "Blue Dream"

  describe "optional" do
    it "blank is Nothing" $ optional nonNegativeInt "  " `shouldEqual` Right Nothing
    it "value is parsed" $ optional nonNegativeInt "4" `shouldEqual` Right (Just 4)
    it "bad value fails" $ optional nonNegativeInt "x" `shouldSatisfy` isLeft

  describe "chained text rules" do
    let name = required >=> alphanumeric >=> maxLen 10
    it "accepts a plain name" $ name "OG Kush" `shouldEqual` Right "OG Kush"
    it "rejects punctuation" $ name "OG_Kush!" `shouldSatisfy` isLeft
    it "rejects over-length" $ name "Abcdefghijk" `shouldSatisfy` isLeft
    it "rejects blank first" $ name "" `shouldEqual` Left "Required"

  describe "nonNegativeInt" do
    it "accepts zero" $ nonNegativeInt "0" `shouldEqual` Right 0
    it "trims" $ nonNegativeInt " 12 " `shouldEqual` Right 12
    it "rejects negative" $ nonNegativeInt "-1" `shouldSatisfy` isLeft
    it "rejects decimal" $ nonNegativeInt "1.5" `shouldSatisfy` isLeft

  describe "positiveInt" do
    it "rejects zero" $ positiveInt "0" `shouldSatisfy` isLeft
    it "accepts one" $ positiveInt "1" `shouldEqual` Right 1

  describe "cents" do
    it "19.99 is 1999" $ cents "19.99" `shouldEqual` Right 1999
    it "29.99 is 2999" $ cents "29.99" `shouldEqual` Right 2999
    it "whole dollars" $ cents "12" `shouldEqual` Right 1200
    it "one decimal place" $ cents "12.5" `shouldEqual` Right 1250
    it "leading zero cents" $ cents "7.05" `shouldEqual` Right 705
    it "zero" $ cents "0" `shouldEqual` Right 0
    it "rejects three decimals" $ cents "1.234" `shouldSatisfy` isLeft
    it "rejects negative" $ cents "-1.00" `shouldSatisfy` isLeft
    it "rejects text" $ cents "abc" `shouldSatisfy` isLeft
    it "rejects blank" $ cents "" `shouldSatisfy` isLeft
    it "rejects overflow" $ cents "21474836.00" `shouldEqual` Left "Amount is too large"
    it "accepts the largest amount" $ cents "21474835.99" `shouldEqual` Right 2147483599

  describe "percentage" do
    it "accepts with sign" $ percentage "25.5%" `shouldEqual` Right "25.5%"
    it "rejects without sign" $ percentage "25.5" `shouldSatisfy` isLeft
    it "rejects over 100" $ percentage "101%" `shouldSatisfy` isLeft
    it "accepts 100" $ percentage "100%" `shouldSatisfy` isRight

  describe "measurementUnit" do
    it "accepts g" $ measurementUnit "g" `shouldEqual` Right "g"
    it "is case-insensitive" $ measurementUnit "OZ" `shouldEqual` Right "OZ"
    it "rejects unknown" $ measurementUnit "furlong" `shouldSatisfy` isLeft

  describe "url" do
    it "accepts https" $ url "https://leafly.com/strains/og-kush" `shouldSatisfy` isRight
    it "rejects bare host" $ url "leafly.com" `shouldSatisfy` isLeft

  describe "uuid" do
    it "accepts a UUID" $
      (void (uuid "4e58b3e6-3fd4-425c-b6a3-4f033a76859c")) `shouldEqual` Right unit
    it "rejects junk" $ (void (uuid "not-a-uuid")) `shouldSatisfy` isLeft

  describe "commaList" do
    it "splits and trims" $ commaList "a, b ,c" `shouldEqual` Right [ "a", "b", "c" ]
    it "drops blanks" $ commaList "a,, ,b" `shouldEqual` Right [ "a", "b" ]
    it "blank is empty" $ commaList "" `shouldEqual` Right []
