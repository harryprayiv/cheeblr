{-# LANGUAGE OverloadedStrings #-}

module Test.Domain.TaxRuleSpec (spec) where

import Data.Maybe (fromJust)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Test.Hspec

import Domain.Pricing
import Domain.TaxRule
import Types.Inventory (ItemCategory (..))
import Types.Location (LocationId (..))
import Types.Transaction (TaxCategory (..))

uuid :: String -> UUID
uuid = fromJust . UUID.fromString

storeA :: LocationId
storeA = LocationId (uuid "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")

storeB :: LocationId
storeB = LocationId (uuid "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")

day :: Integer -> Int -> Int -> UTCTime
day y m d = UTCTime (fromGregorian y m d) (secondsToDiffTime 0)

pricingRule :: TaxCategory -> Int -> TaxRule
pricingRule category ppm =
  TaxRule
    { ruleItemCategory = Nothing
    , ruleTaxCategory  = category
    , ruleRate         = fromJust (mkTaxRate ppm)
    , ruleRounding     = RoundHalfUp
    , ruleDescription  = "test"
    }

stored :: Maybe LocationId -> UTCTime -> Maybe UTCTime -> TaxRule -> StoredTaxRule
stored location from to rule =
  StoredTaxRule
    { storedRuleId        = uuid "11111111-1111-1111-1111-111111111111"
    , storedLocation      = location
    , storedEffectiveFrom = from
    , storedEffectiveTo   = to
    , storedRule          = rule
    }

spec :: Spec
spec = describe "Domain.TaxRule" $ do

  describe "inForce" $ do
    let rule = pricingRule RegularSalesTax 62500
        open = stored Nothing (day 2026 1 1) Nothing rule
        closed = stored Nothing (day 2026 1 1) (Just (day 2026 7 1)) rule
        onlyA = stored (Just storeA) (day 2026 1 1) Nothing rule

    it "applies on its first day" $
      inForce storeA (day 2026 1 1) open `shouldBe` True
    it "does not apply before it starts" $
      inForce storeA (day 2025 12 31) open `shouldBe` False
    it "applies indefinitely with no end" $
      inForce storeA (day 2040 1 1) open `shouldBe` True
    it "applies the day before its end" $
      inForce storeA (day 2026 6 30) closed `shouldBe` True
    it "does not apply at its end" $
      inForce storeA (day 2026 7 1) closed `shouldBe` False
    it "a rule with no location applies everywhere" $
      inForce storeB (day 2026 3 1) open `shouldBe` True
    it "a located rule applies at its location" $
      inForce storeA (day 2026 3 1) onlyA `shouldBe` True
    it "a located rule does not apply elsewhere" $
      inForce storeB (day 2026 3 1) onlyA `shouldBe` False

  describe "activeRules" $ do
    let sales   = pricingRule RegularSalesTax 62500
        oldRate = pricingRule ExciseTax 100000
        newRate = pricingRule ExciseTax 107500
        local   = pricingRule LocalTax 30000
        rules =
          [ stored Nothing (day 2020 1 1) Nothing sales
          , stored Nothing (day 2020 1 1) (Just (day 2026 7 1)) oldRate
          , stored Nothing (day 2026 7 1) Nothing newRate
          , stored (Just storeB) (day 2020 1 1) Nothing local
          ]

    it "picks the old rate before a change" $
      activeRules storeA (day 2026 6 30) rules `shouldBe` [sales, oldRate]
    it "picks the new rate from the day of a change" $
      activeRules storeA (day 2026 7 1) rules `shouldBe` [sales, newRate]
    it "adds a location's own rules" $
      activeRules storeB (day 2026 7 1) rules `shouldBe` [sales, newRate, local]
    it "is empty when nothing is stored" $
      activeRules storeA (day 2026 7 1) [] `shouldBe` []

  describe "codes" $ do
    it "rounding codes round-trip" $
      mapM (parseRoundingCode . roundingCode) [RoundHalfUp, RoundHalfEven, RoundDown]
        `shouldBe` Right [RoundHalfUp, RoundHalfEven, RoundDown]
    it "an unknown rounding code is an error" $
      parseRoundingCode "NEAREST" `shouldBe` Left "Unknown rounding mode: NEAREST"
    it "tax category codes round-trip" $
      mapM
        (parseTaxCategoryCode . taxCategoryCode)
        [RegularSalesTax, ExciseTax, CannabisTax, LocalTax, MedicalTax, NoTax]
        `shouldBe` Right [RegularSalesTax, ExciseTax, CannabisTax, LocalTax, MedicalTax, NoTax]
    it "an unknown tax category code is an error" $
      parseTaxCategoryCode "VAT" `shouldBe` Left "Unknown tax category: VAT"
    it "item category codes round-trip" $
      mapM
        (parseItemCategoryCode . itemCategoryCode)
        [Flower, PreRolls, Vaporizers, Edibles, Drinks, Concentrates, Topicals, Tinctures, Accessories]
        `shouldBe` Right [Flower, PreRolls, Vaporizers, Edibles, Drinks, Concentrates, Topicals, Tinctures, Accessories]
    it "an unknown item category code is an error" $
      parseItemCategoryCode "Seeds" `shouldBe` Left "Unknown item category: Seeds"
