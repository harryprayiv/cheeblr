module Utils.Formatting where

import Prelude

import Config.LiveView (LiveViewConfig, SortField(..), SortOrder(..))
import Data.Array (length, uncons) as Array
import Data.Either (Either(..))
import Data.Enum (class BoundedEnum, fromEnum, toEnum)
import Data.Int (fromString, toNumber) as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Number (fromString) as Number
import Data.String (Pattern(..), split, take, trim)
import Data.String as String
import Data.String.Regex (regex, replace) as Regex
import Data.String.Regex.Flags (global) as Regex
import Data.Tuple (Tuple)
import Data.Tuple.Nested ((/\))
import Partial.Unsafe (unsafePartial)
import Types.Inventory (MenuItem(..), StrainLineage(..))
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
    Nothing -> centsStr -- If not a valid number, return as is

formatCentsToDollars :: Int -> String
formatCentsToDollars cents =
  let
    dollars = cents / 100
    centsRemaining = cents `mod` 100
    centsStr =
      if centsRemaining < 10 then "0" <> show centsRemaining
      else show centsRemaining
  in
    show dollars <> "." <> centsStr

-- Converts Int cents to a dollar amount (for form fields)
formatCentsToDecimal :: Int -> String
formatCentsToDecimal cents =
  let
    dollars = Int.toNumber cents / 100.0
  in
    show dollars

getAllEnumValues :: ∀ a. BoundedEnum a => Bounded a => Array a
getAllEnumValues = catMaybes $ map toEnum $ range 0 (fromEnum (top :: a))

compareMenuItems :: LiveViewConfig -> MenuItem -> MenuItem -> Ordering
compareMenuItems config (MenuItem item1) (MenuItem item2) =
  let
    StrainLineage meta1 = item1.strain_lineage
    StrainLineage meta2 = item2.strain_lineage

    compareByField :: Tuple SortField SortOrder -> Ordering
    compareByField (sortField /\ sortOrder) =
      let
        fieldComparison = case sortField of
          SortByOrder -> compare item1.sort item2.sort
          SortByName -> compare item1.name item2.name
          SortByCategory -> compare item1.category item2.category
          SortBySubCategory -> compare item1.subcategory item2.subcategory
          SortBySpecies -> compare meta1.species meta2.species
          SortBySKU -> compare item1.sku item2.sku
          SortByPrice -> compare item1.price item2.price
          SortByQuantity -> compare item1.quantity item2.quantity
      in
        case sortOrder of
          Ascending -> fieldComparison
          Descending -> invertOrdering fieldComparison

    compareWithPriority :: Array (Tuple SortField SortOrder) -> Ordering
    compareWithPriority priorities = case Array.uncons priorities of
      Nothing -> EQ
      Just { head: priority, tail: rest } ->
        case compareByField priority of
          EQ -> compareWithPriority rest
          result -> result
  in
    compareWithPriority config.sortFields

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
