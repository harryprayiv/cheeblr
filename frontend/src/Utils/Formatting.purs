module Utils.Formatting where

import Prelude

import Data.Array (length) as Array
import Data.Either (Either(..))
import Data.Enum (class BoundedEnum, fromEnum, toEnum)
import Data.Ord (abs)
import Data.DateTime (DateTime, date, day, hour, minute, month, time, year)
import Data.Int (fromString, quot, rem, toNumber) as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Number (fromString) as Number
import Data.String (Pattern(..), split, take, trim)
import Data.String as String
import Data.String.Regex (regex, replace) as Regex
import Data.String.Regex.Flags (global) as Regex
import Partial.Unsafe (unsafePartial)
import Data.Array (catMaybes, filter, range, (!!))

ensureNumber :: String -> String
ensureNumber str = fromMaybe "0.0" $ map show $ Number.fromString $ trim str

ensureInt :: String -> String
ensureInt str = fromMaybe "0" $ map show $ Int.fromString $ trim str

parseCommaList :: String -> Array String
parseCommaList str =
  if str == "" then []
  else
    str
      # split (Pattern ",")
      # map trim
      # filter (_ /= "")

formatDollarAmount :: String -> String
formatDollarAmount str =
  if str == "" then ""
  else case Number.fromString str of
    Just n ->
      let
        fixed = show n
        parts = split (Pattern ".") fixed
      in
        case Array.length parts of
          1 -> fixed <> ".00"
          2 ->
            let
              decimals = fromMaybe "" $ parts !! 1
            in
              if String.length decimals >= 2 then fromMaybe "" (parts !! 0)
                <> "."
                <> take 2 decimals
              else fromMaybe "" (parts !! 0) <> "." <> decimals <> "0"
          _ -> str
    Nothing -> str

formatCentsToDisplayDollars :: String -> String
formatCentsToDisplayDollars centsStr =
  case Int.fromString centsStr of
    Just cents ->
      let
        dollars = Int.toNumber cents / 100.0
      in
        show dollars
    Nothing -> centsStr

-- Cents as dollars with two decimals. A negative amount keeps its sign:
-- -250 gives "-2.50" and -5 gives "-0.05".
formatCentsToDollars :: Int -> String
formatCentsToDollars cents =
  let
    dollars = Int.quot cents 100
    centsRemaining = abs (Int.rem cents 100)
    centsStr =
      if centsRemaining < 10 then "0" <> show centsRemaining
      else show centsRemaining
    sign = if cents < 0 && dollars == 0 then "-" else ""
  in
    sign <> show dollars <> "." <> centsStr

formatCentsToDecimal :: Int -> String
formatCentsToDecimal cents =
  let
    dollars = Int.toNumber cents / 100.0
  in
    show dollars

getAllEnumValues :: ∀ a. BoundedEnum a => Bounded a => Array a
getAllEnumValues = catMaybes $ map toEnum $ range 0 (fromEnum (top :: a))

invertOrdering :: Ordering -> Ordering
invertOrdering LT = GT
invertOrdering EQ = EQ
invertOrdering GT = LT

summarizeLongText :: String -> String
summarizeLongText desc =
  let
    noLinebreaks = String.replace (String.Pattern "\n") (String.Replacement " ")
      desc

    condensedSpaces = unsafePartial case Regex.regex "\\s+" Regex.global of
      Right r -> Regex.replace r " " noLinebreaks

    maxLength = 100
    truncated =
      if String.length condensedSpaces > maxLength then
        String.take maxLength condensedSpaces <> "..."
      else condensedSpaces
  in
    truncated

-- A UTC time as "2026-10-10 15:04 UTC". Times from the backend are UTC.
formatDateTime :: DateTime -> String
formatDateTime dt =
  let
    d = date dt
    t = time dt
    two n = if n < 10 then "0" <> show n else show n
  in
    show (fromEnum (year d))
      <> "-"
      <> two (fromEnum (month d))
      <> "-"
      <> two (fromEnum (day d))
      <> " "
      <> two (fromEnum (hour t))
      <> ":"
      <> two (fromEnum (minute t))
      <> " UTC"
