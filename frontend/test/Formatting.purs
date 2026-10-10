module Test.Formatting where

import Prelude

import Data.Date (canonicalDate)
import Data.DateTime (DateTime(..))
import Data.Enum (toEnum)
import Data.Maybe (Maybe(..))
import Data.Time (Time(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Utils.Formatting
  ( parseCommaList
  , formatCentsToDollars
  , formatCentsToDecimal
  , formatCentsToDisplayDollars
  , formatDateTime
  , formatDollarAmount
  , ensureNumber
  , ensureInt
  , invertOrdering
  , summarizeLongText
  )

spec :: Spec Unit
spec = describe "Utils.Formatting" do

  describe "parseCommaList" do
    it "parses comma-separated values" do
      parseCommaList "a, b, c" `shouldEqual` ["a", "b", "c"]
    it "trims whitespace" do
      parseCommaList "  foo ,  bar  " `shouldEqual` ["foo", "bar"]
    it "returns empty array for empty string" do
      parseCommaList "" `shouldEqual` []
    it "handles single item" do
      parseCommaList "hello" `shouldEqual` ["hello"]
    it "filters out empty segments" do
      parseCommaList "a,,b" `shouldEqual` ["a", "b"]

  describe "formatCentsToDollars" do
    it "formats zero" do
      formatCentsToDollars 0 `shouldEqual` "0.00"
    it "formats whole dollar" do
      formatCentsToDollars 100 `shouldEqual` "1.00"
    it "formats cents" do
      formatCentsToDollars 2999 `shouldEqual` "29.99"
    it "formats small cents" do
      formatCentsToDollars 5 `shouldEqual` "0.05"
    it "formats single cent" do
      formatCentsToDollars 1 `shouldEqual` "0.01"
    it "formats large amount" do
      formatCentsToDollars 10000 `shouldEqual` "100.00"
    it "keeps the sign of a negative amount" do
      formatCentsToDollars (-250) `shouldEqual` "-2.50"
    it "keeps the sign of a negative amount under a dollar" do
      formatCentsToDollars (-5) `shouldEqual` "-0.05"
    it "formats a negative whole dollar" do
      formatCentsToDollars (-100) `shouldEqual` "-1.00"

  describe "formatCentsToDecimal" do
    it "formats zero" do
      formatCentsToDecimal 0 `shouldEqual` "0.0"
    it "formats whole dollar amount" do
      formatCentsToDecimal 100 `shouldEqual` "1.0"
    it "formats typical price" do
      formatCentsToDecimal 2999 `shouldEqual` "29.99"

  describe "formatCentsToDisplayDollars" do
    it "converts cents string to dollars" do
      formatCentsToDisplayDollars "2999" `shouldEqual` "29.99"
    it "handles zero" do
      formatCentsToDisplayDollars "0" `shouldEqual` "0.0"
    it "returns original for non-numeric" do
      formatCentsToDisplayDollars "abc" `shouldEqual` "abc"

  describe "formatDollarAmount" do
    it "formats number with two decimals" do
      formatDollarAmount "29.9" `shouldEqual` "29.90"
    it "truncates to two decimals" do
      formatDollarAmount "29.999" `shouldEqual` "29.99"
    it "adds decimals to whole number" do
      formatDollarAmount "29" `shouldEqual` "29.00"
    it "returns empty for empty" do
      formatDollarAmount "" `shouldEqual` ""
    it "returns original for non-numeric" do
      formatDollarAmount "abc" `shouldEqual` "abc"

  describe "ensureNumber" do
    it "parses valid number" do
      ensureNumber "3.14" `shouldEqual` "3.14"
    it "returns 0.0 for invalid" do
      ensureNumber "abc" `shouldEqual` "0.0"
    it "handles empty string" do
      ensureNumber "" `shouldEqual` "0.0"

  describe "ensureInt" do
    it "parses valid int" do
      ensureInt "42" `shouldEqual` "42"
    it "returns 0 for invalid" do
      ensureInt "abc" `shouldEqual` "0"

  describe "invertOrdering" do
    it "inverts LT to GT" do
      invertOrdering LT `shouldEqual` GT
    it "inverts GT to LT" do
      invertOrdering GT `shouldEqual` LT
    it "keeps EQ as EQ" do
      invertOrdering EQ `shouldEqual` EQ

  describe "summarizeLongText" do
    it "returns short text unchanged" do
      summarizeLongText "Short text" `shouldEqual` "Short text"
    it "truncates long text with ellipsis" do
      let longText = "This is a very long description that goes on and on and on and on and on and should be truncated at some point because it exceeds the maximum length"
      let result = summarizeLongText longText

      (result /= longText) `shouldEqual` true
    it "replaces newlines with spaces" do
      summarizeLongText "line1\nline2" `shouldEqual` "line1 line2"
    it "condenses multiple spaces" do
      summarizeLongText "too   many    spaces" `shouldEqual` "too many spaces"

  describe "formatDateTime" do
    it "writes a UTC time with padded month, day, hour and minute" do
      let
        made = do
          y <- toEnum 2026
          m <- toEnum 3
          d <- toEnum 7
          h <- toEnum 9
          mi <- toEnum 4
          sec <- toEnum 0
          ms <- toEnum 0
          pure (DateTime (canonicalDate y m d) (Time h mi sec ms))
      (formatDateTime <$> made) `shouldEqual` Just "2026-03-07 09:04 UTC"
