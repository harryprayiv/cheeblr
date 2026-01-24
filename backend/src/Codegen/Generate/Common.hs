{-# LANGUAGE OverloadedStrings #-}

module Codegen.Generate.Common
  ( GeneratedModule(..)
  , moduleNameToPath
  , toSnakeCase
  , toCamelCase
  , toPascalCase
  , indent
  , quoted
  , toTableName
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Char (toLower, toUpper, isUpper)

-- | A generated module with its file path and content
data GeneratedModule = GeneratedModule
  { modulePath :: FilePath
  , moduleContent :: Text
  } deriving (Show, Eq)

-- | Convert a module name to a file path
-- e.g., "Generated.Types.Inventory" -> "src/Generated/Types/Inventory.hs"
moduleNameToPath :: Text -> FilePath
moduleNameToPath modName =
  "src/" <> T.unpack (T.replace "." "/" modName) <> ".hs"

-- | Convert PascalCase or camelCase to snake_case
toSnakeCase :: Text -> Text
toSnakeCase = T.pack . go False . T.unpack
  where
    go _ [] = []
    go isFirst (c:cs)
      | isUpper c = (if isFirst then [] else "_") ++ [toLower c] ++ go False cs
      | otherwise = c : go False cs

-- | Convert snake_case to camelCase
toCamelCase :: Text -> Text
toCamelCase txt =
  let parts = T.split (== '_') txt
  in case parts of
    [] -> txt
    (first:rest) -> T.concat (T.toLower first : map capitalize rest)
  where
    capitalize t = case T.uncons t of
      Nothing -> t
      Just (c, cs) -> T.cons (toUpper c) cs

-- | Convert snake_case to PascalCase
toPascalCase :: Text -> Text
toPascalCase txt =
  let parts = T.split (== '_') txt
  in T.concat (map capitalize parts)
  where
    capitalize t = case T.uncons t of
      Nothing -> t
      Just (c, cs) -> T.cons (toUpper c) cs

-- | Indent text by n spaces
indent :: Int -> Text -> Text
indent n txt = T.replicate n " " <> txt

-- | Wrap text in quotes
quoted :: Text -> Text
quoted txt = "\"" <> txt <> "\""

-- | Convert a type name to a table name (lowercase + 's')
toTableName :: Text -> Text
toTableName name = T.toLower name <> "s"