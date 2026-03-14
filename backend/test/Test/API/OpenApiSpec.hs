{-# LANGUAGE OverloadedStrings #-}

module Test.API.OpenApiSpec (spec) where

import Test.Hspec
import Control.Lens
import Data.Maybe (isJust)
import Data.OpenApi
import Data.Text (Text)

import API.OpenApi (cheeblrOpenApi)

hasPath :: FilePath -> Bool
hasPath p = isJust $ cheeblrOpenApi ^. paths . at p

hasSchema :: Text -> Bool
hasSchema s = isJust $ cheeblrOpenApi ^. components . schemas . at s

spec :: Spec
spec = describe "API.OpenApi" $ do

  describe "info fields" $ do
    it "has correct title" $
      cheeblrOpenApi ^. info . title `shouldBe` "Cheeblr API"

    it "has correct version" $
      cheeblrOpenApi ^. info . version `shouldBe` "1.0"

    it "has description" $
      cheeblrOpenApi ^. info . description
        `shouldBe` Just "Cannabis dispensary POS and inventory management API"

  describe "paths" $ do
    it "includes /inventory"         $ hasPath "/inventory"         `shouldBe` True
    it "includes /session"           $ hasPath "/session"           `shouldBe` True
    it "includes /graphql/inventory" $ hasPath "/graphql/inventory" `shouldBe` True
    it "includes /transaction"       $ hasPath "/transaction"       `shouldBe` True
    it "includes /register"          $ hasPath "/register"          `shouldBe` True
    it "includes /openapi.json"      $ hasPath "/openapi.json"      `shouldBe` True

    it "has more than 10 paths" $
      length (cheeblrOpenApi ^. paths) `shouldSatisfy` (> 10)

  describe "component schemas" $ do
    it "includes MenuItem"           $ hasSchema "MenuItem"           `shouldBe` True
    it "includes StrainLineage"      $ hasSchema "StrainLineage"      `shouldBe` True
    it "includes Inventory"          $ hasSchema "Inventory"          `shouldBe` True
    it "includes MutationResponse"   $ hasSchema "MutationResponse"   `shouldBe` True
    it "includes SessionResponse"    $ hasSchema "SessionResponse"    `shouldBe` True
    it "includes UserCapabilities"   $ hasSchema "UserCapabilities"   `shouldBe` True
    it "includes UserRole"           $ hasSchema "UserRole"           `shouldBe` True
    it "includes Transaction"        $ hasSchema "Transaction"        `shouldBe` True
    it "includes TransactionItem"    $ hasSchema "TransactionItem"    `shouldBe` True
    it "includes PaymentTransaction" $ hasSchema "PaymentTransaction" `shouldBe` True
    it "includes Register"           $ hasSchema "Register"           `shouldBe` True
    it "includes GQLRequest"         $ hasSchema "GQLRequest"         `shouldBe` True
    it "includes GQLResponse"        $ hasSchema "GQLResponse"        `shouldBe` True