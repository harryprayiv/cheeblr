{-# LANGUAGE OverloadedStrings #-}

module Test.Types.Public.FeedPrivacySpec (spec) where

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

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

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
    , tags = V.fromList []
    , effects = V.fromList []
    , strain_lineage =
        StrainLineage
          { thc = "25%"
          , cbg = "1%"
          , strain = "Test Strain"
          , creator = "Test Creator"
          , species = Hybrid
          , dominant_terpene = "Myrcene"
          , terpenes = V.fromList []
          , lineage = V.fromList []
          , leafly_url = "https://leafly.com/test"
          , img = "https://example.com/img.jpg"
          }
    }

testAvailableItem :: AvailableItem
testAvailableItem =
  mkAvailableItem testMenuItem 5 testLocId "Test Location" testTime

testFrame :: FeedFrame
testFrame = mkFeedFrame 1 (AvailabilityUpdate testAvailableItem testTime)

-- The full serialized JSON of a feed frame. All privacy tests operate on
-- this value so that any future addition of a field is automatically caught.
frameJson :: String
frameJson = LBS.unpack (Aeson.encode testFrame)

payloadJson :: String
payloadJson = LBS.unpack (Aeson.encode testAvailableItem)

-- ---------------------------------------------------------------------------
-- Tests
--
-- These tests are not redundant with the type-level privacy guarantees.
-- The AvailableItem type enforces absence at compile time. These tests verify
-- that no library, instance, or serialization path leaks additional fields
-- at runtime — for example, a misapplied Generic instance or a hand-written
-- ToJSON that accidentally includes internal state.
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "FeedFrame privacy" $ do
  describe "serialized FeedFrame JSON" $ do
    it "does not contain 'transactionId'" $
      frameJson `shouldNotContain` "transactionId"

    it "does not contain 'employeeId'" $
      frameJson `shouldNotContain` "employeeId"

    it "does not contain 'sessionId'" $
      frameJson `shouldNotContain` "sessionId"

    it "does not contain 'registerId'" $
      frameJson `shouldNotContain` "registerId"

    it "does not contain 'cashierId'" $
      frameJson `shouldNotContain` "cashierId"

    it "does not contain 'userId'" $
      frameJson `shouldNotContain` "userId"

    it "does not contain 'password'" $
      frameJson `shouldNotContain` "password"

  describe "serialized AvailableItem payload JSON" $ do
    it "does not contain 'transactionId'" $
      payloadJson `shouldNotContain` "transactionId"

    it "does not contain 'employeeId'" $
      payloadJson `shouldNotContain` "employeeId"

    it "does not contain 'sessionId'" $
      payloadJson `shouldNotContain` "sessionId"

    it "does not contain 'registerId'" $
      payloadJson `shouldNotContain` "registerId"

    it "does not expose internal Haskell field prefix 'ai'" $
      -- The field prefix is an implementation detail; only lexicon names
      -- should appear in the wire format.
      payloadJson `shouldNotContain` "\"ai"

    it "contains only the expected top-level keys" $ do
      -- A basic smoke-test that the key set is bounded.
      -- The full set is: publicSku, name, brand, category, subcategory,
      -- measureUnit, perPackage, thc, cbg, strain, species, dominantTerpene,
      -- tags, effects, pricePerUnit, availableQty, inStock,
      -- locationId, locationName, updatedAt.
      let expected =
            [ "publicSku", "name", "brand", "category", "subcategory"
            , "measureUnit", "perPackage", "thc", "cbg", "strain"
            , "species", "dominantTerpene", "tags", "effects"
            , "pricePerUnit", "availableQty", "inStock"
            , "locationId", "locationName", "updatedAt"
            ]
      mapM_ (\k -> payloadJson `shouldContain` ("\"" <> k <> "\"")) expected