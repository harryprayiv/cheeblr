module Test.ValidatorsV where

import Prelude

import Data.Either (Either(..), isLeft, isRight)
import Data.Validation.Semigroup (V, toEither)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Inventory
  ( ItemCategory(..)
  , Species(..)
  , StrainLineage(..)
  , validateCategory
  , validateSpecies
  , validateStrainLineage
  )
import Utils.Validation
  ( validateInt
  , validateNumber
  , validatePercentage
  , validateString
  , validateUrl
  )

toE :: forall e a. V e a -> Either e a
toE = toEither

validLineage :: { thc :: String, cbg :: String, strain :: String, creator :: String, species :: String, dominant_terpene :: String, terpenes :: String, lineage :: String, leafly_url :: String, img :: String }
validLineage =
  { thc:             "25%"
  , cbg:             "0.5%"
  , strain:          "OG Kush"
  , creator:         "Unknown"
  , species:         "Indica"
  , dominant_terpene: "Myrcene"
  , terpenes:        "Myrcene, Limonene"
  , lineage:         "Hindu Kush, Chemdawg"
  , leafly_url:      "https://leafly.com/strains/og-kush"
  , img:             "https://example.com/img.jpg"
  }

spec :: Spec Unit
spec = describe "V-returning validators" do

  describe "validateString" do
    it "accepts non-empty string" $
      toE (validateString "Name" "hello") `shouldSatisfy` isRight
    it "accepts string with internal spaces" $
      toE (validateString "Name" "OG Kush") `shouldSatisfy` isRight
    it "accepts single character" $
      toE (validateString "Name" "X") `shouldSatisfy` isRight
    it "rejects empty string" $
      toE (validateString "Name" "") `shouldSatisfy` isLeft
    it "rejects whitespace-only" $
      toE (validateString "Name" "   ") `shouldSatisfy` isLeft
    it "rejects single space" $
      toE (validateString "Name" " ") `shouldSatisfy` isLeft
    it "error is non-empty array" $
      case toE (validateString "SKU" "") of
        Left errs -> (errs /= []) `shouldEqual` true
        Right _   -> false `shouldEqual` true
    it "valid result preserves value" $
      toE (validateString "Name" "OG Kush") `shouldEqual` Right "OG Kush"

  describe "validatePercentage" do
    it "accepts integer percentage" $
      toE (validatePercentage "THC" "25%") `shouldSatisfy` isRight
    it "accepts decimal percentage" $
      toE (validatePercentage "THC" "25.50%") `shouldSatisfy` isRight
    it "accepts 100%" $
      toE (validatePercentage "THC" "100%") `shouldSatisfy` isRight
    it "accepts 0%" $
      toE (validatePercentage "CBG" "0%") `shouldSatisfy` isRight
    it "accepts single-digit" $
      toE (validatePercentage "CBG" "5%") `shouldSatisfy` isRight
    it "rejects value without percent sign" $
      toE (validatePercentage "THC" "25") `shouldSatisfy` isLeft
    it "rejects empty" $
      toE (validatePercentage "THC" "") `shouldSatisfy` isLeft
    it "rejects negative" $
      toE (validatePercentage "THC" "-5%") `shouldSatisfy` isLeft
    it "rejects over 100%" $
      toE (validatePercentage "THC" "101%") `shouldSatisfy` isLeft
    it "valid result preserves string" $
      toE (validatePercentage "THC" "25%") `shouldEqual` Right "25%"
    it "decimal result preserved" $
      toE (validatePercentage "THC" "25.50%") `shouldEqual` Right "25.50%"

  describe "validateNumber" do
    it "accepts positive decimal" $
      toE (validateNumber "Price" "29.99") `shouldSatisfy` isRight
    it "accepts zero" $
      toE (validateNumber "Price" "0") `shouldSatisfy` isRight
    it "accepts whole number" $
      toE (validateNumber "Price" "10") `shouldSatisfy` isRight
    it "rejects negative number" $
      toE (validateNumber "Price" "-1") `shouldSatisfy` isLeft
    it "rejects non-numeric text" $
      toE (validateNumber "Price" "abc") `shouldSatisfy` isLeft
    it "rejects empty" $
      toE (validateNumber "Price" "") `shouldSatisfy` isLeft
    it "correct numeric value for 29.99" $
      toE (validateNumber "Price" "29.99") `shouldEqual` Right 29.99
    it "correct numeric value for 0" $
      toE (validateNumber "Price" "0") `shouldEqual` Right 0.0
    it "correct numeric value for 100" $
      toE (validateNumber "Price" "100") `shouldEqual` Right 100.0

  describe "validateInt" do
    it "accepts zero" $
      toE (validateInt "Qty" "0") `shouldSatisfy` isRight
    it "accepts positive integer" $
      toE (validateInt "Qty" "42") `shouldSatisfy` isRight
    it "accepts large integer" $
      toE (validateInt "Qty" "1000") `shouldSatisfy` isRight
    it "rejects negative integer" $
      toE (validateInt "Qty" "-1") `shouldSatisfy` isLeft
    it "rejects decimal" $
      toE (validateInt "Qty" "1.5") `shouldSatisfy` isLeft
    it "rejects text" $
      toE (validateInt "Qty" "abc") `shouldSatisfy` isLeft
    it "rejects empty" $
      toE (validateInt "Qty" "") `shouldSatisfy` isLeft
    it "correct value for 10" $
      toE (validateInt "Qty" "10") `shouldEqual` Right 10
    it "correct value for 0" $
      toE (validateInt "Qty" "0") `shouldEqual` Right 0

  describe "validateUrl" do
    it "accepts https URL" $
      toE (validateUrl "Leafly" "https://leafly.com") `shouldSatisfy` isRight
    it "accepts URL with path" $
      toE (validateUrl "Leafly" "https://leafly.com/strains/og-kush") `shouldSatisfy` isRight
    it "accepts URL with subdomain" $
      toE (validateUrl "Img" "https://cdn.example.com/image.jpg") `shouldSatisfy` isRight
    it "rejects plain text" $
      toE (validateUrl "Leafly" "not a url") `shouldSatisfy` isLeft
    it "rejects empty" $
      toE (validateUrl "Leafly" "") `shouldSatisfy` isLeft
    it "rejects bare domain" $
      toE (validateUrl "URL" "example.com") `shouldSatisfy` isLeft
    it "valid result preserves string" $
      toE (validateUrl "URL" "https://example.com") `shouldEqual` Right "https://example.com"

  describe "validateCategory" do
    it "Flower"        $ toE (validateCategory "cat" "Flower")        `shouldEqual` Right Flower
    it "PreRolls"      $ toE (validateCategory "cat" "PreRolls")      `shouldEqual` Right PreRolls
    it "Vaporizers"    $ toE (validateCategory "cat" "Vaporizers")    `shouldEqual` Right Vaporizers
    it "Edibles"       $ toE (validateCategory "cat" "Edibles")       `shouldEqual` Right Edibles
    it "Drinks"        $ toE (validateCategory "cat" "Drinks")        `shouldEqual` Right Drinks
    it "Concentrates"  $ toE (validateCategory "cat" "Concentrates")  `shouldEqual` Right Concentrates
    it "Topicals"      $ toE (validateCategory "cat" "Topicals")      `shouldEqual` Right Topicals
    it "Tinctures"     $ toE (validateCategory "cat" "Tinctures")     `shouldEqual` Right Tinctures
    it "Accessories"   $ toE (validateCategory "cat" "Accessories")   `shouldEqual` Right Accessories
    it "rejects invalid" $
      toE (validateCategory "cat" "Widgets") `shouldSatisfy` isLeft
    it "rejects empty" $
      toE (validateCategory "cat" "") `shouldSatisfy` isLeft
    it "rejects lowercase" $
      toE (validateCategory "cat" "flower") `shouldSatisfy` isLeft

  describe "validateSpecies" do
    it "Indica"                $ toE (validateSpecies "sp" "Indica")                `shouldEqual` Right Indica
    it "IndicaDominantHybrid"  $ toE (validateSpecies "sp" "IndicaDominantHybrid")  `shouldEqual` Right IndicaDominantHybrid
    it "Hybrid"                $ toE (validateSpecies "sp" "Hybrid")                `shouldEqual` Right Hybrid
    it "SativaDominantHybrid"  $ toE (validateSpecies "sp" "SativaDominantHybrid")  `shouldEqual` Right SativaDominantHybrid
    it "Sativa"                $ toE (validateSpecies "sp" "Sativa")                `shouldEqual` Right Sativa
    it "rejects invalid" $
      toE (validateSpecies "sp" "NotASpecies") `shouldSatisfy` isLeft
    it "rejects empty" $
      toE (validateSpecies "sp" "") `shouldSatisfy` isLeft

  describe "validateStrainLineage" do
    it "accepts valid lineage" $
      toE (validateStrainLineage validLineage) `shouldSatisfy` isRight

    it "rejects invalid THC (missing %)" $
      toE (validateStrainLineage (validLineage { thc = "25" })) `shouldSatisfy` isLeft

    it "rejects negative THC" $
      toE (validateStrainLineage (validLineage { thc = "-1%" })) `shouldSatisfy` isLeft

    it "rejects invalid CBG (missing %)" $
      toE (validateStrainLineage (validLineage { cbg = "0.5" })) `shouldSatisfy` isLeft

    it "rejects invalid species" $
      toE (validateStrainLineage (validLineage { species = "NotASpecies" })) `shouldSatisfy` isLeft

    it "rejects invalid leafly URL" $
      toE (validateStrainLineage (validLineage { leafly_url = "not a url" })) `shouldSatisfy` isLeft

    it "rejects invalid img URL" $
      toE (validateStrainLineage (validLineage { img = "not a url" })) `shouldSatisfy` isLeft

    it "rejects empty strain name" $
      toE (validateStrainLineage (validLineage { strain = "" })) `shouldSatisfy` isLeft

    it "rejects empty creator" $
      toE (validateStrainLineage (validLineage { creator = "" })) `shouldSatisfy` isLeft

    it "parses terpenes as comma list" $
      case toE (validateStrainLineage validLineage) of
        Right (StrainLineage sl) -> sl.terpenes `shouldEqual` [ "Myrcene", "Limonene" ]
        Left _                   -> false `shouldEqual` true

    it "parses lineage as comma list" $
      case toE (validateStrainLineage validLineage) of
        Right (StrainLineage sl) -> sl.lineage `shouldEqual` [ "Hindu Kush", "Chemdawg" ]
        Left _                   -> false `shouldEqual` true

    it "preserves species as data type" $
      case toE (validateStrainLineage validLineage) of
        Right (StrainLineage sl) -> sl.species `shouldEqual` Indica
        Left _                   -> false `shouldEqual` true

    it "preserves THC string" $
      case toE (validateStrainLineage validLineage) of
        Right (StrainLineage sl) -> sl.thc `shouldEqual` "25%"
        Left _                   -> false `shouldEqual` true

    it "preserves dominantTerpene" $
      case toE (validateStrainLineage validLineage) of
        Right (StrainLineage sl) -> sl.dominant_terpene `shouldEqual` "Myrcene"
        Left _                   -> false `shouldEqual` true

    it "accumulates multiple errors" $
      case toE (validateStrainLineage (validLineage { thc = "bad", species = "bad", leafly_url = "bad" })) of
        Left errs -> (errs /= []) `shouldEqual` true
        Right _   -> false `shouldEqual` true