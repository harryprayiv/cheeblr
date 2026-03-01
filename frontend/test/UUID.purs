module Test.UUID where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Data.String as String
import Effect.Class (liftEffect)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.UUID (UUID(..), parseUUID, emptyUUID, genUUID, uuidToString, validateUUID)
import Data.Validation.Semigroup (toEither)
import Data.Either (isRight, isLeft)
import Yoga.JSON (writeJSON, readJSON_)

spec :: Spec Unit
spec = describe "Types.UUID" do

  describe "parseUUID" do
    it "parses valid v4 UUID" do
      parseUUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c" `shouldSatisfy` isJust

    it "parses all-zero UUID" do
      parseUUID "00000000-0000-0000-0000-000000000000" `shouldSatisfy` isJust

    it "rejects empty string" do
      parseUUID "" `shouldEqual` Nothing

    it "rejects malformed UUID" do
      parseUUID "not-a-uuid" `shouldEqual` Nothing

    it "rejects UUID with wrong length" do
      parseUUID "4e58b3e6-3fd4-425c-b6a3" `shouldEqual` Nothing

    it "rejects UUID with uppercase (lowercase only)" do
      parseUUID "4E58B3E6-3FD4-425C-B6A3-4F033A76859C" `shouldEqual` Nothing

    it "rejects UUID without dashes" do
      parseUUID "4e58b3e63fd4425cb6a34f033a76859c" `shouldEqual` Nothing

    it "rejects UUID with extra characters" do
      parseUUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c-extra" `shouldEqual` Nothing

  describe "emptyUUID" do
    it "is all zeros" do
      show emptyUUID `shouldEqual` "00000000-0000-0000-0000-000000000000"

    it "parses back to itself" do
      parseUUID (show emptyUUID) `shouldEqual` Just emptyUUID

  describe "UUID Show instance" do
    it "shows the raw string" do
      show (UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c")
        `shouldEqual` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

  describe "UUID Eq" do
    it "equal UUIDs are equal" do
      let uuid = UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
      (uuid == uuid) `shouldEqual` true

    it "different UUIDs are not equal" do
      let a = UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
      let b = UUID "00000000-0000-0000-0000-000000000000"
      (a == b) `shouldEqual` false

  describe "uuidToString" do
    it "extracts the string" do
      uuidToString (UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c")
        `shouldEqual` "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

  describe "genUUID" do
    it "generates a valid UUID" do
      uuid <- liftEffect genUUID
      parseUUID (show uuid) `shouldSatisfy` isJust

    it "generates unique UUIDs" do
      uuid1 <- liftEffect genUUID
      uuid2 <- liftEffect genUUID
      (uuid1 /= uuid2) `shouldEqual` true

    it "generates v4 UUID (version nibble = 4)" do
      uuid <- liftEffect genUUID
      let str = show uuid
      -- v4 UUID format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      -- The '4' is at character index 14
      let versionSection = String.take 1 (String.drop 14 str)
      versionSection `shouldEqual` "4"

  describe "validateUUID" do
    it "validates correct UUID" do
      toEither (validateUUID "SKU" "4e58b3e6-3fd4-425c-b6a3-4f033a76859c")
        `shouldSatisfy` isRight

    it "rejects invalid UUID with field name in error" do
      toEither (validateUUID "SKU" "invalid")
        `shouldSatisfy` isLeft

  describe "UUID JSON serialization" do
    it "serializes UUID to string" do
      let uuid = UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
      let json = writeJSON uuid
      -- Should be a JSON string
      json `shouldEqual` "\"4e58b3e6-3fd4-425c-b6a3-4f033a76859c\""

    it "deserializes UUID from string" do
      let parsed = readJSON_ "\"4e58b3e6-3fd4-425c-b6a3-4f033a76859c\"" :: Maybe UUID
      parsed `shouldEqual` Just (UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c")

    it "roundtrips through JSON" do
      let uuid = UUID "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"
      let parsed = readJSON_ (writeJSON uuid) :: Maybe UUID
      parsed `shouldEqual` Just uuid