{-# LANGUAGE OverloadedStrings #-}

module Test.Types.TraceSpec (spec) where

import Data.Maybe  (isJust)
import Data.Text   (Text)
import qualified Data.Text as T
import Test.Hspec

import Types.Trace

spec :: Spec
spec = describe "Types.Trace" $ do

  describe "newTraceId" $ do
    it "generates a TraceId" $ do
      tid <- newTraceId
      T.null (traceIdToText tid) `shouldBe` False

    it "generates unique IDs" $ do
      t1 <- newTraceId
      t2 <- newTraceId
      t1 `shouldNotBe` t2

  describe "traceIdToText / parseTraceId" $ do
    it "roundtrips through text" $ do
      tid <- newTraceId
      parseTraceId (traceIdToText tid) `shouldBe` Just tid

    it "produces a 36-character UUID string" $ do
      tid <- newTraceId
      T.length (traceIdToText tid) `shouldBe` 36

    it "returns Nothing for invalid text" $
      parseTraceId ("not-a-uuid" :: Text) `shouldBe` Nothing

    it "returns Nothing for empty string" $
      parseTraceId ("" :: Text) `shouldBe` Nothing

    it "returns Just for valid UUID text" $ do
      let validUUID = "11111111-1111-1111-1111-111111111111" :: Text
      parseTraceId validUUID `shouldSatisfy` isJust