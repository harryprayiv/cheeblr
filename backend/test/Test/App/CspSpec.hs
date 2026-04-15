{-# LANGUAGE OverloadedStrings #-}

module Test.App.CspSpec (spec) where

import qualified Data.Text as T
import Test.Hspec

import App (buildCsp)

spec :: Spec
spec = describe "App.buildCsp" $ do
  describe "required directives are always present" $ do
    it "includes default-src 'self'" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "default-src 'self'"

    it "includes script-src 'self'" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "script-src 'self'"

    it "includes style-src 'self'" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "style-src 'self'"

    it "includes frame-ancestors 'none'" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "frame-ancestors 'none'"

    it "includes base-uri 'self'" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "base-uri 'self'"

    it "includes form-action 'self'" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "form-action 'self'"

  describe "no unsafe-inline anywhere" $ do
    it "does not include 'unsafe-inline' with no img domain" $
      buildCsp "https://api.example.com" Nothing
        `shouldNotSatisfy` T.isInfixOf "'unsafe-inline'"

    it "does not include 'unsafe-inline' with img domain set" $
      buildCsp "https://api.example.com" (Just "https://cdn.example.com")
        `shouldNotSatisfy` T.isInfixOf "'unsafe-inline'"

    it "does not include 'unsafe-eval'" $
      buildCsp "https://api.example.com" Nothing
        `shouldNotSatisfy` T.isInfixOf "'unsafe-eval'"

  describe "connect-src" $ do
    it "includes the HTTPS API URL" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "https://api.example.com"

    it "includes the WSS form of an HTTPS API URL" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "wss://api.example.com"

    it "converts http:// to ws:// for the websocket URL" $
      buildCsp "http://localhost:8080" Nothing
        `shouldSatisfy` T.isInfixOf "ws://localhost:8080"

    it "keeps http:// form in connect-src as well" $
      buildCsp "http://localhost:8080" Nothing
        `shouldSatisfy` T.isInfixOf "http://localhost:8080"

    it "handles localhost URLs" $ do
      let csp = buildCsp "https://localhost:8080" Nothing
      csp `shouldSatisfy` T.isInfixOf "https://localhost:8080"
      csp `shouldSatisfy` T.isInfixOf "wss://localhost:8080"

    it "non-http scheme is passed through unchanged" $
      buildCsp "localhost:8080" Nothing
        `shouldSatisfy` T.isInfixOf "localhost:8080"

  describe "img-src" $ do
    it "defaults to broad https: when no IMG_SRC_DOMAIN set" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "https:"

    it "uses the specific CDN domain when IMG_SRC_DOMAIN is set" $ do
      let csp = buildCsp "https://api.example.com" (Just "https://cdn.example.com")
      csp `shouldSatisfy` T.isInfixOf "https://cdn.example.com"

    it "always includes 'self' in img-src" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "img-src 'self'"

    it "always includes data: in img-src for inline images" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "data:"

  describe "directive format" $ do
    it "directives are separated by '; '" $
      buildCsp "https://api.example.com" Nothing
        `shouldSatisfy` T.isInfixOf "; "

    it "output is non-empty" $
      T.null (buildCsp "https://api.example.com" Nothing) `shouldBe` False

    it "output is consistent for the same inputs" $ do
      let csp1 = buildCsp "https://api.example.com" Nothing
          csp2 = buildCsp "https://api.example.com" Nothing
      csp1 `shouldBe` csp2

    it "different API URLs produce different CSPs" $
      buildCsp "https://api1.example.com" Nothing
        `shouldNotBe` buildCsp "https://api2.example.com" Nothing
