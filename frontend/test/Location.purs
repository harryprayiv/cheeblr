module Test.Location where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Location (LocationId(..), locationIdToString, parseLocationId, unLocationId)
import Types.UUID (UUID(..))
import Yoga.JSON (readJSON_, writeJSON)

validUuidStr :: String
validUuidStr = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

anotherUuidStr :: String
anotherUuidStr = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

spec :: Spec Unit
spec = describe "Types.Location" do

  describe "parseLocationId" do
    it "accepts valid UUID string" $
      parseLocationId validUuidStr `shouldSatisfy` isJust

    it "returns Nothing for invalid string" $
      parseLocationId "not-a-uuid" `shouldEqual` Nothing

    it "returns Nothing for empty string" $
      parseLocationId "" `shouldEqual` Nothing

    it "returns Nothing for partial UUID" $
      parseLocationId "aaaaaaaa-aaaa-aaaa-aaaa" `shouldEqual` Nothing

    it "returns Nothing for uppercase UUID" $
      parseLocationId "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA" `shouldEqual` Nothing

    it "parses all-zero UUID" $
      parseLocationId "00000000-0000-0000-0000-000000000000" `shouldSatisfy` isJust

  describe "locationIdToString" do
    it "converts to the UUID string" do
      let lid = LocationId (UUID validUuidStr)
      locationIdToString lid `shouldEqual` validUuidStr

    it "roundtrips: parse → toString" do
      case parseLocationId validUuidStr of
        Just lid -> locationIdToString lid `shouldEqual` validUuidStr
        Nothing  -> false `shouldEqual` true

  describe "unLocationId" do
    it "extracts the inner UUID" do
      let uuid = UUID validUuidStr
      unLocationId (LocationId uuid) `shouldEqual` uuid

  describe "LocationId Show" do
    it "shows the UUID string (no wrapping)" do
      let lid = LocationId (UUID validUuidStr)
      show lid `shouldEqual` validUuidStr

  describe "LocationId Eq" do
    it "equal LocationIds are equal" do
      let lid = LocationId (UUID validUuidStr)
      (lid == lid) `shouldEqual` true

    it "different LocationIds are not equal" do
      let lid1 = LocationId (UUID validUuidStr)
      let lid2 = LocationId (UUID anotherUuidStr)
      (lid1 == lid2) `shouldEqual` false

  describe "LocationId Ord" do
    it "ordering is consistent with UUID string ordering" do
      let lid1 = LocationId (UUID validUuidStr)
      let lid2 = LocationId (UUID anotherUuidStr)
      (lid1 < lid2) `shouldEqual` true

  describe "LocationId JSON serialization" do
    it "serializes to quoted UUID string" do
      let lid = LocationId (UUID validUuidStr)
      writeJSON lid `shouldEqual` ("\"" <> validUuidStr <> "\"")

    it "deserializes from quoted UUID string" do
      let parsed = readJSON_ ("\"" <> validUuidStr <> "\"") :: Maybe LocationId
      parsed `shouldEqual` Just (LocationId (UUID validUuidStr))

    it "roundtrips through JSON" do
      let lid = LocationId (UUID validUuidStr)
      (readJSON_ (writeJSON lid) :: Maybe LocationId) `shouldEqual` Just lid

    it "fails to deserialize invalid UUID string" do
      (readJSON_ "\"not-a-uuid\"" :: Maybe LocationId) `shouldEqual` Nothing
