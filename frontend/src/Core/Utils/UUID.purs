module Utils.UUID where

import Prelude

import Data.Int (hexadecimal, toStringAs)
import Data.Int.Bits ((.|.))
import Data.String (joinWith)
import Effect (Effect)
import Types.UUID (UUID(..))
import Utils.Formatting (padStart, randomInt)

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