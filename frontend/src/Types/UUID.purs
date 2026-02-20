module Types.UUID where

import Prelude

import Data.Array (replicate)
import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.Int (floor, toNumber) as Int
import Data.Int (hexadecimal, toStringAs)
import Data.Int.Bits ((.|.))
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype)
import Data.String (joinWith)
import Data.String as String
import Data.String.Regex (regex, test)
import Data.String.Regex.Flags (noFlags)
import Effect (Effect)
import Effect.Random (random)
import Foreign (ForeignError(..), fail)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

newtype UUID = UUID String

derive instance genericUUID :: Generic UUID _
derive instance newtypeUUID :: Newtype UUID _
derive instance eqUUID :: Eq UUID
derive instance ordUUID :: Ord UUID

instance showUUID :: Show UUID where
  show (UUID uuid) = uuid

instance writeForeignUUID :: WriteForeign UUID where
  writeImpl (UUID str) = writeImpl str

instance readForeignUUID :: ReadForeign UUID where
  readImpl f = do
    str <- readImpl f
    case parseUUID str of
      Just uuid -> pure uuid
      Nothing -> fail (ForeignError $ "Invalid UUID format: " <> str)

-- | Generate a random integer in a given range (inclusive)
randomInt :: Int -> Int -> Effect Int
randomInt min max = do
  r <- random
  pure $ Int.floor $ r * Int.toNumber (max - min + 1) + Int.toNumber min

padStart :: Int -> String -> String
padStart targetLength str =
  let
    paddingLength = max 0 (targetLength - String.length str) -- Ensure no negative padding
    padding = replicate paddingLength "0" -- Create an Array String
  in
    joinWith "" padding <> str

parseUUID :: String -> Maybe UUID
parseUUID str =
  case
    regex "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
      noFlags
    of
    Left _ -> Nothing
    Right r ->
      if test r str then Just $ UUID str
      else Nothing

emptyUUID :: UUID
emptyUUID = UUID "00000000-0000-0000-0000-000000000000"

-- | Generate a UUID v4
genUUID :: Effect UUID
genUUID = do
  -- Generate random 16-bit integers for smaller chunks
  r1 <- randomInt 0 0xFFFF -- First half of time_low
  r2 <- randomInt 0 0xFFFF -- Second half of time_low
  r3 <- randomInt 0 0xFFFF -- time_mid
  r4 <- randomInt 0 0x0FFF -- time_hi (12 bits for randomness)
  r5 <- randomInt 0 0x3FFF -- clock_seq (14 bits for randomness)
  r6 <- randomInt 0 0xFFFF -- First part of node
  r7 <- randomInt 0 0xFFFF -- Second part of node
  r8 <- randomInt 0 0xFFFF -- Third part of node

  -- Set the version (4) and variant (10)
  let
    versioned = r4 .|. 0x4000 -- Set version to 4 (binary OR with 0100 0000 0000 0000)
    variant = r5 .|. 0x8000 -- Set variant to 10xx (binary OR with 1000 0000 0000 0000)

  -- Convert to hex and pad as needed
  let
    hex1 = padStart 4 (toHex r1) <> padStart 4 (toHex r2) -- time_low
    hex2 = padStart 4 (toHex r3) -- time_mid
    hex3 = padStart 4 (toHex versioned) -- time_hi_and_version
    hex4 = padStart 4 (toHex variant) -- clock_seq
    hex5 = padStart 4 (toHex r6) <> padStart 4 (toHex r7) <> padStart 4
      (toHex r8) -- node
    uuid = joinWith "-" [ hex1, hex2, hex3, hex4, hex5 ]

  pure $ UUID uuid
  where
  toHex = toStringAs hexadecimal