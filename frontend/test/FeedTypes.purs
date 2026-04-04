module Test.FeedTypes where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Feed (FeedFrame, AvailableItem, FeedStatus)
import Yoga.JSON (readJSON_)

inStockFrameJson :: String
inStockFrameJson =
  """{"seq":42,"payload":{"publicSku":"4e58b3e6-3fd4-425c-b6a3-4f033a76859c","name":"OG Kush","brand":"TestBrand","category":"Flower","subcategory":"Indoor","measureUnit":"g","perPackage":"3.5","thc":"25%","cbg":"0.5%","strain":"OG Kush","species":"Indica","dominantTerpene":"Myrcene","tags":["indica","classic"],"effects":["relaxed","sleepy"],"pricePerUnit":2999,"availableQty":10,"inStock":true,"locationId":"loc-1","locationName":"Main Store","updatedAt":"2024-06-15T10:30:00Z"},"timestamp":"2024-06-15T10:30:00Z"}"""

outOfStockFrameJson :: String
outOfStockFrameJson =
  """{"seq":1,"payload":{"publicSku":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"Edible","brand":"BrandX","category":"Edibles","subcategory":"Gummies","measureUnit":"mg","perPackage":"100mg","thc":"10%","cbg":"0%","strain":"None","species":"Hybrid","dominantTerpene":"None","tags":[],"effects":[],"pricePerUnit":500,"availableQty":0,"inStock":false,"locationId":"loc-1","locationName":"Main Store","updatedAt":"2024-06-15T10:30:00Z"},"timestamp":"2024-06-15T10:30:00Z"}"""

spec :: Spec Unit
spec = describe "Types.Feed JSON" do

  describe "FeedFrame — in-stock item" do
    it "parses" $
      (readJSON_ inStockFrameJson :: Maybe FeedFrame) `shouldSatisfy` isJust

    it "preserves seq number" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.seq `shouldEqual` 42
        Nothing -> false `shouldEqual` true

    it "preserves timestamp" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.timestamp `shouldEqual` "2024-06-15T10:30:00Z"
        Nothing -> false `shouldEqual` true

    it "preserves payload.name" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.name `shouldEqual` "OG Kush"
        Nothing -> false `shouldEqual` true

    it "preserves payload.brand" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.brand `shouldEqual` "TestBrand"
        Nothing -> false `shouldEqual` true

    it "preserves payload.category" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.category `shouldEqual` "Flower"
        Nothing -> false `shouldEqual` true

    it "preserves payload.pricePerUnit" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.pricePerUnit `shouldEqual` 2999
        Nothing -> false `shouldEqual` true

    it "preserves payload.availableQty" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.availableQty `shouldEqual` 10
        Nothing -> false `shouldEqual` true

    it "preserves payload.inStock = true" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.inStock `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves payload.thc" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.thc `shouldEqual` "25%"
        Nothing -> false `shouldEqual` true

    it "preserves payload.cbg" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.cbg `shouldEqual` "0.5%"
        Nothing -> false `shouldEqual` true

    it "preserves payload.tags array" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.tags `shouldEqual` [ "indica", "classic" ]
        Nothing -> false `shouldEqual` true

    it "preserves payload.effects array" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.effects `shouldEqual` [ "relaxed", "sleepy" ]
        Nothing -> false `shouldEqual` true

    it "preserves payload.strain" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.strain `shouldEqual` "OG Kush"
        Nothing -> false `shouldEqual` true

    it "preserves payload.species" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.species `shouldEqual` "Indica"
        Nothing -> false `shouldEqual` true

    it "preserves payload.dominantTerpene" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.dominantTerpene `shouldEqual` "Myrcene"
        Nothing -> false `shouldEqual` true

    it "preserves payload.locationName" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.locationName `shouldEqual` "Main Store"
        Nothing -> false `shouldEqual` true

    it "preserves payload.locationId" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.locationId `shouldEqual` "loc-1"
        Nothing -> false `shouldEqual` true

    it "preserves payload.measureUnit" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.measureUnit `shouldEqual` "g"
        Nothing -> false `shouldEqual` true

    it "preserves payload.perPackage" $
      case readJSON_ inStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.perPackage `shouldEqual` "3.5"
        Nothing -> false `shouldEqual` true

  describe "FeedFrame — out-of-stock item" do
    it "parses" $
      (readJSON_ outOfStockFrameJson :: Maybe FeedFrame) `shouldSatisfy` isJust

    it "inStock is false" $
      case readJSON_ outOfStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.inStock `shouldEqual` false
        Nothing -> false `shouldEqual` true

    it "availableQty is 0" $
      case readJSON_ outOfStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.availableQty `shouldEqual` 0
        Nothing -> false `shouldEqual` true

    it "empty tags array" $
      case readJSON_ outOfStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.tags `shouldEqual` []
        Nothing -> false `shouldEqual` true

    it "empty effects array" $
      case readJSON_ outOfStockFrameJson :: Maybe FeedFrame of
        Just f  -> f.payload.effects `shouldEqual` []
        Nothing -> false `shouldEqual` true

  describe "AvailableItem JSON" do
    let json =
          """{"publicSku":"4e58b3e6-3fd4-425c-b6a3-4f033a76859c","name":"OG Kush","brand":"TestBrand","category":"Flower","subcategory":"Indoor","measureUnit":"g","perPackage":"3.5","thc":"25%","cbg":"0.5%","strain":"OG Kush","species":"Indica","dominantTerpene":"Myrcene","tags":["indica"],"effects":["relaxed"],"pricePerUnit":2999,"availableQty":10,"inStock":true,"locationId":"loc-1","locationName":"Main Store","updatedAt":"2024-06-15T10:30:00Z"}"""

    it "parses AvailableItem directly" $
      (readJSON_ json :: Maybe AvailableItem) `shouldSatisfy` isJust

    it "publicSku is preserved" $
      case readJSON_ json :: Maybe AvailableItem of
        Just i  -> i.publicSku `shouldEqual` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
        Nothing -> false `shouldEqual` true

  describe "FeedStatus JSON" do
    let json =
          """{"locationId":"loc-1","locationName":"Main Store","currentSeq":42,"itemCount":25,"inStockCount":22}"""

    it "parses FeedStatus" $
      (readJSON_ json :: Maybe FeedStatus) `shouldSatisfy` isJust

    it "preserves locationName" $
      case readJSON_ json :: Maybe FeedStatus of
        Just s  -> s.locationName `shouldEqual` "Main Store"
        Nothing -> false `shouldEqual` true

    it "preserves itemCount" $
      case readJSON_ json :: Maybe FeedStatus of
        Just s  -> s.itemCount `shouldEqual` 25
        Nothing -> false `shouldEqual` true

    it "preserves inStockCount" $
      case readJSON_ json :: Maybe FeedStatus of
        Just s  -> s.inStockCount `shouldEqual` 22
        Nothing -> false `shouldEqual` true

    it "preserves currentSeq" $
      case readJSON_ json :: Maybe FeedStatus of
        Just s  -> s.currentSeq `shouldEqual` 42
        Nothing -> false `shouldEqual` true
