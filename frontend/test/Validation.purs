module Test.Validation where

import Prelude

import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Utils.Validation
  ( runValidation
  , nonEmpty
  , alphanumeric
  , extendedAlphanumeric
  , percentage
  , dollarAmount
  , validMeasurementUnit
  , validUrl
  , positiveInteger
  , nonNegativeInteger
  , fraction
  , commaList
  , validUUID
  , maxLength
  , allOf
  , anyOf
  )

spec :: Spec Unit
spec = describe "Utils.Validation" do

  describe "nonEmpty" do
    it "rejects empty string" do
      runValidation nonEmpty "" `shouldEqual` false
    it "rejects whitespace-only string" do
      runValidation nonEmpty "   " `shouldEqual` false
    it "accepts non-empty string" do
      runValidation nonEmpty "hello" `shouldEqual` true
    it "accepts string with spaces" do
      runValidation nonEmpty "hello world" `shouldEqual` true

  describe "alphanumeric" do
    it "accepts letters" do
      runValidation alphanumeric "Hello" `shouldEqual` true
    it "accepts numbers" do
      runValidation alphanumeric "123" `shouldEqual` true
    it "accepts letters numbers and spaces" do
      runValidation alphanumeric "Hello World 123" `shouldEqual` true
    it "accepts hyphens" do
      runValidation alphanumeric "pre-rolls" `shouldEqual` true
    it "rejects special characters" do
      runValidation alphanumeric "hello@world" `shouldEqual` false
    it "rejects empty string" do
      runValidation alphanumeric "" `shouldEqual` false

  describe "extendedAlphanumeric" do
    it "accepts basic alphanumeric" do
      runValidation extendedAlphanumeric "Hello123" `shouldEqual` true
    it "accepts ampersand" do
      runValidation extendedAlphanumeric "Ben & Jerry" `shouldEqual` true
    it "accepts apostrophe" do
      runValidation extendedAlphanumeric "Mike's" `shouldEqual` true
    it "accepts parentheses" do
      runValidation extendedAlphanumeric "Item (special)" `shouldEqual` true
    it "accepts periods" do
      runValidation extendedAlphanumeric "3.5g Pack" `shouldEqual` true
    it "accepts plus sign" do
      runValidation extendedAlphanumeric "THC+CBD" `shouldEqual` true

  describe "percentage" do
    it "accepts whole number with percent" do
      runValidation percentage "25%" `shouldEqual` true
    it "accepts decimal with percent" do
      runValidation percentage "25.50%" `shouldEqual` true
    it "accepts single digit" do
      runValidation percentage "5%" `shouldEqual` true
    it "accepts 100%" do
      runValidation percentage "100%" `shouldEqual` true
    it "rejects without percent sign" do
      runValidation percentage "25" `shouldEqual` false
    it "rejects negative" do
      runValidation percentage "-5%" `shouldEqual` false
    it "rejects too many decimals" do
      runValidation percentage "25.123%" `shouldEqual` false
    it "rejects empty" do
      runValidation percentage "" `shouldEqual` false

  describe "dollarAmount" do
    it "accepts zero" do
      runValidation dollarAmount "0" `shouldEqual` true
    it "accepts whole number" do
      runValidation dollarAmount "29" `shouldEqual` true
    it "accepts decimal" do
      runValidation dollarAmount "29.99" `shouldEqual` true
    it "accepts zero decimal" do
      runValidation dollarAmount "0.01" `shouldEqual` true
    it "rejects negative" do
      runValidation dollarAmount "-1.00" `shouldEqual` false
    it "rejects non-numeric" do
      runValidation dollarAmount "abc" `shouldEqual` false
    it "rejects empty" do
      runValidation dollarAmount "" `shouldEqual` false

  describe "validMeasurementUnit" do
    it "accepts grams" do
      runValidation validMeasurementUnit "g" `shouldEqual` true
    it "accepts milligrams" do
      runValidation validMeasurementUnit "mg" `shouldEqual` true
    it "accepts ounces" do
      runValidation validMeasurementUnit "oz" `shouldEqual` true
    it "accepts ml" do
      runValidation validMeasurementUnit "ml" `shouldEqual` true
    it "accepts eighth" do
      runValidation validMeasurementUnit "eighth" `shouldEqual` true
    it "accepts fraction form" do
      runValidation validMeasurementUnit "1/8" `shouldEqual` true
    it "is case insensitive" do
      runValidation validMeasurementUnit "G" `shouldEqual` true
    it "rejects invalid unit" do
      runValidation validMeasurementUnit "foobar" `shouldEqual` false
    it "accepts ea" do
      runValidation validMeasurementUnit "ea" `shouldEqual` true

  describe "validUrl" do
    it "accepts https url" do
      runValidation validUrl "https://example.com" `shouldEqual` true
    it "accepts http url" do
      runValidation validUrl "http://example.com" `shouldEqual` true
    it "accepts url with path" do
      runValidation validUrl "https://leafly.com/strains/og-kush" `shouldEqual` true
    it "accepts www prefix" do
      runValidation validUrl "https://www.example.com" `shouldEqual` true
    it "rejects plain text" do
      runValidation validUrl "not a url" `shouldEqual` false

  describe "positiveInteger" do
    it "accepts positive number" do
      runValidation positiveInteger "1" `shouldEqual` true
    it "accepts large number" do
      runValidation positiveInteger "9999" `shouldEqual` true
    it "rejects zero" do
      runValidation positiveInteger "0" `shouldEqual` false
    it "rejects negative" do
      runValidation positiveInteger "-1" `shouldEqual` false
    it "rejects decimal" do
      runValidation positiveInteger "1.5" `shouldEqual` false

  describe "nonNegativeInteger" do
    it "accepts zero" do
      runValidation nonNegativeInteger "0" `shouldEqual` true
    it "accepts positive" do
      runValidation nonNegativeInteger "42" `shouldEqual` true
    it "rejects negative" do
      runValidation nonNegativeInteger "-1" `shouldEqual` false
    it "rejects decimal" do
      runValidation nonNegativeInteger "1.5" `shouldEqual` false
    it "rejects text" do
      runValidation nonNegativeInteger "abc" `shouldEqual` false

  describe "fraction" do
    it "accepts simple fraction" do
      runValidation fraction "1/2" `shouldEqual` true
    it "accepts larger fraction" do
      runValidation fraction "3/4" `shouldEqual` true
    it "rejects whole number" do
      runValidation fraction "5" `shouldEqual` false
    it "rejects decimal" do
      runValidation fraction "0.5" `shouldEqual` false

  describe "commaList" do
    it "accepts single item" do
      runValidation commaList "hello" `shouldEqual` true
    it "accepts comma-separated items" do
      runValidation commaList "hello,world,foo" `shouldEqual` true
    it "accepts empty string" do
      runValidation commaList "" `shouldEqual` true

  describe "validUUID" do
    it "accepts valid uuid" do
      runValidation validUUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c" `shouldEqual` true
    it "rejects invalid uuid" do
      runValidation validUUID "not-a-uuid" `shouldEqual` false
    it "rejects empty" do
      runValidation validUUID "" `shouldEqual` false

  describe "maxLength" do
    it "accepts string within limit" do
      runValidation (maxLength 10) "hello" `shouldEqual` true
    it "accepts string at limit" do
      runValidation (maxLength 5) "hello" `shouldEqual` true
    it "rejects string over limit" do
      runValidation (maxLength 3) "hello" `shouldEqual` false

  describe "allOf" do
    it "passes when all rules pass" do
      runValidation (allOf [ nonEmpty, alphanumeric ]) "hello" `shouldEqual` true
    it "fails when any rule fails" do
      runValidation (allOf [ nonEmpty, alphanumeric ]) "" `shouldEqual` false
    it "fails when later rule fails" do
      runValidation (allOf [ nonEmpty, alphanumeric ]) "hello@" `shouldEqual` false

  describe "anyOf" do
    it "passes when first rule passes" do
      runValidation (anyOf [ nonNegativeInteger, fraction ]) "5" `shouldEqual` true
    it "passes when second rule passes" do
      runValidation (anyOf [ nonNegativeInteger, fraction ]) "1/2" `shouldEqual` true
    it "fails when no rules pass" do
      runValidation (anyOf [ nonNegativeInteger, fraction ]) "abc" `shouldEqual` false