{-# LANGUAGE OverloadedStrings #-}

module Test.Types.Public.FeedFrameSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.UUID (UUID)
import qualified Data.Vector as V
import Test.Hspec

import Types.Events.Availability (AvailabilityUpdate (..))
import Types.Inventory
import Types.Public.AvailableItem
import Types.Public.FeedFrame

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2024 1 1) 0

testSku :: UUID
testSku = read "00000000-0000-0000-0000-000000000001"

testLocId :: PublicLocationId
testLocId = PublicLocationId (read "00000000-0000-0000-0000-000000000002")

testMenuItem :: MenuItem
testMenuItem =
  MenuItem
    { sort = 1
    , sku = testSku
    , brand = "Test Brand"
    , name = "Test Item"
    , price = 1000
    , measure_unit = "g"
    , per_package = "3.5"
    , quantity = 10
    , category = Flower
    , subcategory = "Indoor"
    , description = "Test"
    , tags = V.fromList ["test"]
    , effects = V.fromList ["relaxed"]
    , strain_lineage =
        StrainLineage
          { thc = "25%"
          , cbg = "1%"
          , strain = "Test Strain"
          , creator = "Test Creator"
          , species = Hybrid
          , dominant_terpene = "Myrcene"
          , terpenes = V.fromList ["Myrcene"]
          , lineage = V.fromList []
          , leafly_url = "https://leafly.com/test"
          , img = "https://example.com/img.jpg"
          }
    }

testAvailableItem :: AvailableItem
testAvailableItem =
  mkAvailableItem testMenuItem 5 testLocId "Test Location" testTime

testUpdate :: AvailabilityUpdate
testUpdate = AvailabilityUpdate testAvailableItem testTime

testFrame :: FeedFrame
testFrame = mkFeedFrame 1 testUpdate

spec :: Spec
spec = describe "FeedFrame" $ do
  describe "mkFeedFrame" $ do
    it "always produces the correct type constant" $
      ffType testFrame `shouldBe` "app.cheeblr.inventory.availableItem"

    it "carries the sequence number" $
      ffSeq testFrame `shouldBe` 1

    it "carries the update payload" $
      ffPayload testFrame `shouldBe` testAvailableItem

    it "carries the timestamp from the AvailabilityUpdate" $
      ffTimestamp testFrame `shouldBe` testTime

    it "seq is preserved across different values" $ do
      ffSeq (mkFeedFrame 0   testUpdate) `shouldBe` 0
      ffSeq (mkFeedFrame 42  testUpdate) `shouldBe` 42
      ffSeq (mkFeedFrame 999 testUpdate) `shouldBe` 999

  describe "JSON serialization" $ do
    it "produces 'seq' key" $ do
      let json = LBS.unpack (Aeson.encode testFrame)
      json `shouldContain` "\"seq\""

    it "produces 'type' key" $ do
      let json = LBS.unpack (Aeson.encode testFrame)
      json `shouldContain` "\"type\""

    it "produces 'payload' key" $ do
      let json = LBS.unpack (Aeson.encode testFrame)
      json `shouldContain` "\"payload\""

    it "produces 'timestamp' key" $ do
      let json = LBS.unpack (Aeson.encode testFrame)
      json `shouldContain` "\"timestamp\""

    it "type value is the lexicon NSID constant" $ do
      let json = LBS.unpack (Aeson.encode testFrame)
      json `shouldContain` "app.cheeblr.inventory.availableItem"

  describe "AvailableItem lexicon field names in payload" $ do
    it "uses 'publicSku' not 'aiPublicSku'" $ do
      let json = LBS.unpack (Aeson.encode (ffPayload testFrame))
      json `shouldContain` "\"publicSku\""
      json `shouldNotContain` "\"aiPublicSku\""

    it "uses 'name' not 'aiName'" $ do
      let json = LBS.unpack (Aeson.encode (ffPayload testFrame))
      json `shouldContain` "\"name\""
      json `shouldNotContain` "\"aiName\""

    it "uses 'inStock' not 'aiInStock'" $ do
      let json = LBS.unpack (Aeson.encode (ffPayload testFrame))
      json `shouldContain` "\"inStock\""
      json `shouldNotContain` "\"aiInStock\""

    it "uses 'pricePerUnit' not 'aiPricePerUnit'" $ do
      let json = LBS.unpack (Aeson.encode (ffPayload testFrame))
      json `shouldContain` "\"pricePerUnit\""
      json `shouldNotContain` "\"aiPricePerUnit\""

    it "uses 'locationId' not 'aiLocationId'" $ do
      let json = LBS.unpack (Aeson.encode (ffPayload testFrame))
      json `shouldContain` "\"locationId\""
      json `shouldNotContain` "\"aiLocationId\""