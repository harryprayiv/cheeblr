{-# LANGUAGE OverloadedStrings #-}

module Codegen.Generate.Common
  ( GeneratedModule(..)
  , moduleNameToPath
  , toSnakeCase
  , toCamelCase
  , toPascalCase
  , indent
  , quoted
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Char (toLower, toUpper, isUpper)

-- | Represents a generated module with its file path and content
data GeneratedModule = GeneratedModule
  { modulePath :: FilePath
  , moduleContent :: Text
  } deriving (Show, Eq)

-- | Convert a module name like "Types.Inventory" to a file path like "src/Types/Inventory.hs"
moduleNameToPath :: Text -> FilePath
moduleNameToPath modName =
  "src/" <> T.unpack (T.replace "." "/" modName) <> ".hs"

-- | Convert PascalCase or camelCase to snake_case
-- e.g., "menuItem" -> "menu_item", "MenuItem" -> "menu_item"
toSnakeCase :: Text -> Text
toSnakeCase = T.pack . go . T.unpack
  where
    go [] = []
    go (c:cs)
      | isUpper c = '_' : toLower c : go cs
      | otherwise = c : go cs

-- | Convert snake_case to camelCase
-- e.g., "menu_item" -> "menuItem"
toCamelCase :: Text -> Text
toCamelCase txt =
  let parts = T.split (== '_') txt
  in case parts of
    [] -> txt
    (first:rest) -> T.concat (first : map capitalize rest)
  where
    capitalize t = case T.uncons t of
      Nothing -> t
      Just (c, cs) -> T.cons (toUpper c) cs

-- | Convert snake_case to PascalCase
-- e.g., "menu_item" -> "MenuItem"
toPascalCase :: Text -> Text
toPascalCase txt =
  let parts = T.split (== '_') txt
  in T.concat (map capitalize parts)
  where
    capitalize t = case T.uncons t of
      Nothing -> t
      Just (c, cs) -> T.cons (toUpper c) cs

-- | Indent text by a given number of spaces
indent :: Int -> Text -> Text
indent n txt = T.replicate n " " <> txt

-- | Wrap text in double quotes
quoted :: Text -> Text
quoted txt = "\"" <> txt <> "\""