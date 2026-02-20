module Cheeblr.Core.Tag where

import Prelude

import Data.Array (find, filter, sortBy, mapWithIndex)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype)
import Foreign (ForeignError(..), F, fail)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

-- | A phantom-typed string tag. The Symbol kind parameter prevents
-- | mixing tags from different domains (e.g. Category vs Species)
-- | while keeping serialization trivial.
newtype Tag (k :: Symbol) = Tag String

derive instance Newtype (Tag k) _
derive instance Eq (Tag k)
derive instance Ord (Tag k)

instance Show (Tag k) where
  show (Tag s) = s

-- | Permissive read — accepts any string.
-- | Validation against a registry is a separate step.
instance ReadForeign (Tag k) where
  readImpl f = Tag <$> readImpl f

instance WriteForeign (Tag k) where
  writeImpl (Tag s) = writeImpl s

-- | Unwrap a tag to its raw string value.
unTag :: forall k. Tag k -> String
unTag (Tag s) = s

-- | Directly construct a tag. Use `mkTag` for validated construction.
unsafeTag :: forall k. String -> Tag k
unsafeTag = Tag

-- | Registry entry: a valid tag value with display metadata.
type Entry (k :: Symbol) =
  { tag :: Tag k
  , label :: String
  , ordinal :: Int
  }

-- | A registry defines the valid values for a tag domain.
-- | Constructed from a simple array of {value, label} pairs;
-- | ordinals are assigned by position.
newtype Registry (k :: Symbol) = Registry (Array (Entry k))

-- | Build a registry from value/label pairs.
-- | Ordinals are assigned by array index.
mkRegistry :: forall k. Array { value :: String, label :: String } -> Registry k
mkRegistry pairs = Registry $
  mapWithIndex
    (\i { value, label: lbl } ->
      { tag: Tag value, label: lbl, ordinal: i })
    pairs

-- | Validated tag construction. Returns Nothing if the value
-- | is not in the registry.
mkTag :: forall k. Registry k -> String -> Maybe (Tag k)
mkTag (Registry es) str =
  case find (\e -> unTag e.tag == str) es of
    Just e -> Just e.tag
    Nothing -> Nothing

-- | Check membership without constructing.
member :: forall k. Registry k -> Tag k -> Boolean
member (Registry es) tag =
  case find (\e -> e.tag == tag) es of
    Just _ -> true
    Nothing -> false

-- | Check membership by raw string.
memberStr :: forall k. Registry k -> String -> Boolean
memberStr (Registry es) str =
  case find (\e -> unTag e.tag == str) es of
    Just _ -> true
    Nothing -> false

-- | All tags in registry order.
values :: forall k. Registry k -> Array (Tag k)
values (Registry es) = map _.tag (sortBy (comparing _.ordinal) es)

-- | All entries in registry order.
entries :: forall k. Registry k -> Array (Entry k)
entries (Registry es) = sortBy (comparing _.ordinal) es

-- | Get the display label for a tag. Falls back to the raw string.
label :: forall k. Registry k -> Tag k -> String
label (Registry es) tag =
  case find (\e -> e.tag == tag) es of
    Just e -> e.label
    Nothing -> unTag tag

-- | Get the ordinal for sorting/comparison by domain order
-- | (as opposed to lexicographic Ord).
ordinal :: forall k. Registry k -> Tag k -> Int
ordinal (Registry es) tag =
  case find (\e -> e.tag == tag) es of
    Just e -> e.ordinal
    Nothing -> 999999

-- | Compare two tags using registry ordering rather than string ordering.
compareByRegistry :: forall k. Registry k -> Tag k -> Tag k -> Ordering
compareByRegistry reg a b = compare (ordinal reg a) (ordinal reg b)

-- | Filter entries by a predicate on the tag.
filterRegistry :: forall k. (Tag k -> Boolean) -> Registry k -> Array (Entry k)
filterRegistry pred (Registry es) = filter (\e -> pred e.tag) es

-- | Generate dropdown-compatible options from a registry.
toOptions :: forall k. Registry k -> Array { value :: String, label :: String }
toOptions (Registry es) =
  sortBy (comparing _.ordinal) es
    <#> \e -> { value: unTag e.tag, label: e.label }

-- | Read a tag with registry validation (strict deserialization).
-- | Use this when you want to reject unknown values at parse time.
readTagStrict :: forall k. Registry k -> String -> String -> F (Tag k)
readTagStrict reg fieldName str =
  case mkTag reg str of
    Just tag -> pure tag
    Nothing -> fail (ForeignError $ "Invalid " <> fieldName <> ": " <> str)