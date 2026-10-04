{-# LANGUAGE OverloadedStrings #-}

module Test.Domain.PricingSpec (spec) where

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

import Domain.Pricing
import Types.Inventory (ItemCategory (..))
import Types.Transaction (TaxCategory (..))

rate :: Int -> TaxRate
rate ppm = case mkTaxRate ppm of
  Just r  -> r
  Nothing -> error "rate: negative"

rule :: Maybe ItemCategory -> TaxCategory -> Int -> RoundingMode -> TaxRule
rule category taxCategory ppm mode =
  TaxRule
    { ruleItemCategory = category
    , ruleTaxCategory  = taxCategory
    , ruleRate         = rate ppm
    , ruleRounding     = mode
    , ruleDescription  = "test"
    }

genMode :: Gen RoundingMode
genMode = Gen.element [RoundHalfUp, RoundHalfEven, RoundDown]

genCategory :: Gen ItemCategory
genCategory =
  Gen.element
    [Flower, PreRolls, Vaporizers, Edibles, Drinks, Concentrates, Topicals, Tinctures, Accessories]

genRule :: Gen TaxRule
genRule =
  rule
    <$> Gen.maybe genCategory
    <*> Gen.element [RegularSalesTax, ExciseTax, CannabisTax, LocalTax, MedicalTax]
    <*> Gen.int (Range.linear 0 300000)
    <*> genMode

genRules :: Gen [TaxRule]
genRules = Gen.list (Range.linear 0 5) genRule

genPrice :: Gen Int
genPrice = Gen.int (Range.linear 0 1000000)

genQuantity :: Gen Int
genQuantity = Gen.int (Range.linear 1 1000)

spec :: Spec
spec = describe "Domain.Pricing" $ do

  describe "mkTaxRate" $ do
    it "accepts zero" $ fmap taxRatePpm (mkTaxRate 0) `shouldBe` Just 0
    it "accepts 6.25%" $ fmap taxRatePpm (mkTaxRate 62500) `shouldBe` Just 62500
    it "rejects a negative rate" $ mkTaxRate (-1) `shouldBe` Nothing

  describe "roundDiv" $ do
    it "half up takes exactly half upward" $ roundDiv RoundHalfUp 5 2 `shouldBe` 3
    it "half even takes 2.5 to 2" $ roundDiv RoundHalfEven 5 2 `shouldBe` 2
    it "half even takes 3.5 to 4" $ roundDiv RoundHalfEven 7 2 `shouldBe` 4
    it "down drops the fraction" $ roundDiv RoundDown 7 2 `shouldBe` 3
    it "an exact division is unchanged in every mode" $ do
      roundDiv RoundHalfUp 6 2 `shouldBe` 3
      roundDiv RoundHalfEven 6 2 `shouldBe` 3
      roundDiv RoundDown 6 2 `shouldBe` 3
    it "just under half rounds down in half up" $
      roundDiv RoundHalfUp 499999 1000000 `shouldBe` 0
    it "just over half rounds up in half even" $
      roundDiv RoundHalfEven 500001 1000000 `shouldBe` 1

  describe "taxOn" $ do
    it "5% of $10.50 is 52.5 cents: 53 half up" $
      taxOn RoundHalfUp (rate 50000) 1050 `shouldBe` 53
    it "5% of $10.50 is 52.5 cents: 52 half even" $
      taxOn RoundHalfEven (rate 50000) 1050 `shouldBe` 52
    it "5% of $10.50 is 52.5 cents: 52 down" $
      taxOn RoundDown (rate 50000) 1050 `shouldBe` 52
    it "5% of $11.50 is 57.5 cents: 58 half even" $
      taxOn RoundHalfEven (rate 50000) 1150 `shouldBe` 58
    it "8% of $19.99 is 159.92 cents: 160 half up" $
      taxOn RoundHalfUp (rate 80000) 1999 `shouldBe` 160
    it "8.875% of $100.00 is 887.5 cents: 888 half up" $
      taxOn RoundHalfUp (rate 88750) 10000 `shouldBe` 888
    it "a zero rate charges nothing" $
      taxOn RoundHalfUp (rate 0) 123456 `shouldBe` 0

    it "is within half a cent of the exact tax (half up, half even)" $ hedgehog $ do
      mode <- forAll (Gen.element [RoundHalfUp, RoundHalfEven])
      ppm  <- forAll (Gen.int (Range.linear 0 300000))
      base <- forAll (Gen.int (Range.linear 0 100000000))
      let amount = toInteger (taxOn mode (rate ppm) base)
          exact  = toInteger base * toInteger ppm
      assert (abs (2 * (amount * ratePerMillion - exact)) <= ratePerMillion)

    it "never exceeds the exact tax when rounding down" $ hedgehog $ do
      ppm  <- forAll (Gen.int (Range.linear 0 300000))
      base <- forAll (Gen.int (Range.linear 0 100000000))
      let amount = toInteger (taxOn RoundDown (rate ppm) base)
          exact  = toInteger base * toInteger ppm
      assert (amount * ratePerMillion <= exact)
      assert ((amount + 1) * ratePerMillion > exact)

    it "does not decrease when the base grows" $ hedgehog $ do
      mode  <- forAll genMode
      ppm   <- forAll (Gen.int (Range.linear 0 300000))
      base  <- forAll (Gen.int (Range.linear 0 100000000))
      extra <- forAll (Gen.int (Range.linear 0 100000))
      assert (taxOn mode (rate ppm) base <= taxOn mode (rate ppm) (base + extra))

  describe "rulesFor" $ do
    let everything = rule Nothing RegularSalesTax 62500 RoundHalfUp
        flowerOnly = rule (Just Flower) ExciseTax 107500 RoundHalfUp
        ediblesOnly = rule (Just Edibles) LocalTax 30000 RoundHalfUp
        rules = [everything, flowerOnly, ediblesOnly]
    it "keeps general rules and the category's own rules" $
      rulesFor Flower rules `shouldBe` [everything, flowerOnly]
    it "drops rules for other categories" $
      rulesFor Accessories rules `shouldBe` [everything]
    it "is empty when there are no rules" $
      rulesFor Flower [] `shouldBe` []

  describe "priceLine" $ do
    let salesTax = rule Nothing RegularSalesTax 62500 RoundHalfUp
        excise   = rule (Just Flower) ExciseTax 107500 RoundHalfUp

    it "prices a line with two taxes" $
      priceLine [salesTax, excise] Flower 1999 2
        `shouldBe` Right
          LinePricing
            { lineUnitPrice = 1999
            , lineQuantity  = 2
            , lineSubtotal  = 3998
            , lineTaxes     =
                [ LineTax RegularSalesTax (rate 62500) 250 "test"
                , LineTax ExciseTax (rate 107500) 430 "test"
                ]
            , lineTaxTotal  = 680
            , lineTotal     = 4678
            }

    it "charges only the general rule on another category" $
      fmap lineTaxTotal (priceLine [salesTax, excise] Accessories 1999 2)
        `shouldBe` Right 250

    it "charges no tax with no rules" $
      fmap lineTotal (priceLine [] Flower 1999 2) `shouldBe` Right 3998

    it "rejects a zero quantity" $
      priceLine [salesTax] Flower 1999 0 `shouldBe` Left (NonPositiveQuantity 0)

    it "rejects a negative quantity" $
      priceLine [salesTax] Flower 1999 (-3) `shouldBe` Left (NonPositiveQuantity (-3))

    it "rejects a negative unit price" $
      priceLine [salesTax] Flower (-1) 1 `shouldBe` Left (NegativeUnitPrice (-1))

    it "subtotal is unit price times quantity" $ hedgehog $ do
      rules    <- forAll genRules
      category <- forAll genCategory
      price    <- forAll genPrice
      quantity <- forAll genQuantity
      case priceLine rules category price quantity of
        Left err      -> annotateShow err >> failure
        Right pricing -> lineSubtotal pricing === price * quantity

    it "total is subtotal plus the stored tax amounts" $ hedgehog $ do
      rules    <- forAll genRules
      category <- forAll genCategory
      price    <- forAll genPrice
      quantity <- forAll genQuantity
      case priceLine rules category price quantity of
        Left err      -> annotateShow err >> failure
        Right pricing -> do
          lineTaxTotal pricing === sum (map lineTaxAmount (lineTaxes pricing))
          lineTotal pricing === lineSubtotal pricing + lineTaxTotal pricing

    it "has one stored tax per applicable rule" $ hedgehog $ do
      rules    <- forAll genRules
      category <- forAll genCategory
      price    <- forAll genPrice
      quantity <- forAll genQuantity
      case priceLine rules category price quantity of
        Left err      -> annotateShow err >> failure
        Right pricing ->
          length (lineTaxes pricing) === length (rulesFor category rules)

    it "no stored amount is negative" $ hedgehog $ do
      rules    <- forAll genRules
      category <- forAll genCategory
      price    <- forAll genPrice
      quantity <- forAll genQuantity
      case priceLine rules category price quantity of
        Left err      -> annotateShow err >> failure
        Right pricing -> do
          assert (lineSubtotal pricing >= 0)
          assert (all ((>= 0) . lineTaxAmount) (lineTaxes pricing))
