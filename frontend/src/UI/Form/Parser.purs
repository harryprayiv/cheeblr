module UI.Form.Parser
  ( Parser
  , anyText
  , trimmed
  , required
  , optional
  , alphanumeric
  , extendedAlphanumeric
  , maxLen
  , nonNegativeInt
  , positiveInt
  , cents
  , percentage
  , measurementUnit
  , url
  , uuid
  , commaList
  ) where

import Prelude

import Data.Array (elem, filter)
import Data.Either (Either(..), note)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), length, split, take, toLower, trim)
import Data.String.Regex (Regex, test)
import Data.String.Regex.Flags (noFlags)
import Data.String.Regex.Unsafe (unsafeRegex)
import Data.Number as Number
import Types.UUID (UUID, parseUUID)

-- A field parser turns the raw text of an input into a typed value or a
-- message for the hint next to the field. Parsers that return String can be
-- chained with (>=>), for example: required >=> alphanumeric >=> maxLen 50.
type Parser a = String -> Either String a

anyText :: Parser String
anyText = Right

trimmed :: Parser String
trimmed = Right <<< trim

required :: Parser String
required raw =
  let
    s = trim raw
  in
    if s == "" then Left "Required" else Right s

-- Blank input parses to Nothing. Anything else must satisfy the inner parser.
optional :: forall a. Parser a -> Parser (Maybe a)
optional p raw =
  if trim raw == "" then Right Nothing else Just <$> p raw

alphanumericRe :: Regex
alphanumericRe = unsafeRegex "^[A-Za-z0-9-\\s]+$" noFlags

alphanumeric :: Parser String
alphanumeric s =
  if test alphanumericRe s then Right s
  else Left "Letters, digits, spaces and hyphens only"

extendedAlphanumericRe :: Regex
extendedAlphanumericRe = unsafeRegex "^[A-Za-z0-9\\s\\-_&+',\\.\\(\\)]+$" noFlags

extendedAlphanumeric :: Parser String
extendedAlphanumeric s =
  if test extendedAlphanumericRe s then Right s
  else Left "Contains characters that are not allowed"

maxLen :: Int -> Parser String
maxLen n s =
  if length s <= n then Right s
  else Left ("Must be " <> show n <> " characters or fewer")

nonNegativeInt :: Parser Int
nonNegativeInt raw = case Int.fromString (trim raw) of
  Just n | n >= 0 -> Right n
  _ -> Left "Whole number, zero or greater"

positiveInt :: Parser Int
positiveInt raw = case Int.fromString (trim raw) of
  Just n | n > 0 -> Right n
  _ -> Left "Whole number greater than zero"

centsRe :: Regex
centsRe = unsafeRegex "^\\d+(\\.\\d{1,2})?$" noFlags

-- Parses a dollar amount into integer cents using digit arithmetic only.
-- The previous path multiplied a Number by 100.0 and floored it, which turns
-- 19.99 into 1998 cents because 19.99 * 100.0 is 1998.9999999999998.
cents :: Parser Int
cents raw =
  let
    s = trim raw
  in
    if not (test centsRe s) then Left "Dollar amount such as 12.99"
    else case split (Pattern ".") s of
      [ w ] -> scale w "0"
      [ w, f ] -> scale w (if length f == 1 then f <> "0" else f)
      _ -> Left "Dollar amount such as 12.99"
  where
  scale w f = note "Amount is too large" do
    whole <- Int.fromString w
    frac <- Int.fromString f
    if whole > 21474835 then Nothing else Just (whole * 100 + frac)

percentageRe :: Regex
percentageRe = unsafeRegex "^\\d{1,3}(\\.\\d{1,2})?%$" noFlags

-- Kept as text because StrainLineage stores thc and cbg as strings that
-- include the percent sign.
percentage :: Parser String
percentage raw =
  let
    s = trim raw
  in
    if not (test percentageRe s) then Left "Format: 25.5%"
    else case Number.fromString (take (length s - 1) s) of
      Just n | n >= 0.0 && n <= 100.0 -> Right s
      _ -> Left "Must be between 0% and 100%"

measurementUnits :: Array String
measurementUnits =
  [ "g", "mg", "kg", "oz", "lb", "ml", "l", "ea", "unit", "units", "pack"
  , "packs", "eighth", "quarter", "half", "1/8", "1/4", "1/2"
  ]

measurementUnit :: Parser String
measurementUnit raw =
  let
    s = trim raw
  in
    if elem (toLower s) measurementUnits then Right s
    else Left "Unit such as g, mg, oz, ml, ea"

urlRe :: Regex
urlRe = unsafeRegex
  "^https?:\\/\\/(www\\.)?[a-zA-Z0-9][a-zA-Z0-9-]*(\\.[a-zA-Z0-9][a-zA-Z0-9-]*)+(\\/[\\w\\-\\.~:\\/?#[\\]@!$&'()*+,;=]*)*$"
  noFlags

url :: Parser String
url raw =
  let
    s = trim raw
  in
    if test urlRe s then Right s
    else Left "URL starting with http:// or https://"

uuid :: Parser UUID
uuid raw = note "Not a valid UUID" (parseUUID (trim raw))

-- Never fails. Blank entries are dropped.
commaList :: Parser (Array String)
commaList raw = Right (filter (_ /= "") (map trim (split (Pattern ",") raw)))
