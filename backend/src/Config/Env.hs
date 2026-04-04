{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Config.Env (
  envInt,
  envText,
  envSecs,
  envPath,
  envList,
  envEnum,
  envBool,
  envUUID,
  envMaybe,
  envRequired,
) where

import Control.Exception (throwIO)
import qualified Data.Maybe
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

envInt :: String -> Int -> IO Int
envInt name def = do
  mv <- lookupEnv name
  pure $ Data.Maybe.fromMaybe def (mv >>= readMaybe)

envText :: String -> Text -> IO Text
envText name def = do
  mv <- lookupEnv name
  pure $ maybe def T.pack mv

envSecs :: String -> Int -> IO NominalDiffTime
envSecs name defSecs = fromIntegral <$> envInt name defSecs

envPath :: String -> FilePath -> IO FilePath
envPath name def = do
  mv <- lookupEnv name
  pure $ Data.Maybe.fromMaybe def mv

envList :: String -> [Text] -> IO [Text]
envList name def = do
  mv <- lookupEnv name
  pure $ case mv of
    Nothing -> def
    Just v ->
      filter (not . T.null) $
        map T.strip (T.splitOn "," (T.pack v))

envEnum :: forall a. (Read a) => String -> a -> IO a
envEnum name def = do
  mv <- lookupEnv name
  pure $ Data.Maybe.fromMaybe def (mv >>= readMaybe)

envBool :: String -> Bool -> IO Bool
envBool name def = do
  mv <- lookupEnv name
  pure $ case fmap (T.toLower . T.pack) mv of
    Just "true" -> True
    Just "1" -> True
    Just "yes" -> True
    Just "false" -> False
    Just "0" -> False
    Just "no" -> False
    _ -> def

envUUID :: String -> UUID -> IO UUID
envUUID name def = do
  mv <- lookupEnv name
  pure $ Data.Maybe.fromMaybe def (mv >>= UUID.fromString)

envMaybe :: String -> IO (Maybe Text)
envMaybe name = do
  mv <- lookupEnv name
  pure $ case mv of
    Nothing -> Nothing
    Just "" -> Nothing
    Just v -> Just (T.pack v)

envRequired :: String -> IO Text
envRequired name = do
  mv <- lookupEnv name
  case mv of
    Just v -> pure (T.pack v)
    Nothing -> throwIO (userError ("Required environment variable not set: " <> name))
