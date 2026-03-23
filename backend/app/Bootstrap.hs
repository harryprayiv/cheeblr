{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE TypeApplications   #-}

module Main where

import           Control.Exception          (SomeException, try)
import           Data.ByteArray.Encoding    (Base (Base64), convertToBase)
import           Data.ByteString            (ByteString)
import qualified Data.ByteString.Char8      as B8
import           Data.Maybe                 (fromMaybe)
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import qualified Data.Text.Encoding         as TE
import qualified Hasql.Pool                 as Pool
import qualified Hasql.Session              as Session
import           Rel8
import           System.Entropy             (getEntropy)
import           System.Environment         (lookupEnv)
import           System.Exit                (exitFailure, exitSuccess)
import           System.IO                  (hPutStrLn, stderr)
import           System.Posix.User          (getEffectiveUserName)

import           DB.Auth
import           DB.Database                (DBConfig (..), initializeDB)
import           DB.Schema                  (userSchema, isActive)
import           Types.Auth                 (UserRole (..))

------------------------------------------------------------------------
-- Check whether the users table is empty
------------------------------------------------------------------------

anyUserExists :: Pool.Pool -> IO Bool
anyUserExists pool = do
  result <- Pool.use pool $ Session.statement () $ run $ Rel8.select $ do
    u <- each userSchema
    where_ $ isActive u
    pure u
  case result of
    Left _  -> pure False
    Right r -> pure (not (Prelude.null r))

------------------------------------------------------------------------
-- Generate a random URL-safe password (no padding, 24 printable chars)
------------------------------------------------------------------------

generatePassword :: IO Text
generatePassword = do
  raw <- getEntropy 18  -- 18 bytes -> 24 base64url chars
  let encoded = convertToBase Base64 (raw :: ByteString)
  -- Drop any padding and replace + / with - _ for URL safety.
  let clean = T.map sanitize
            . T.dropWhileEnd (== '=')
            . TE.decodeUtf8
            $ encoded
  pure clean
  where
    sanitize '+' = '-'
    sanitize '/' = '_'
    sanitize c   = c

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------

main :: IO ()
main = do
  currentUser <- getEffectiveUserName

  envHost <- fromMaybe "localhost" <$> lookupEnv "PGHOST"
  envPort <- maybe (5432 :: Int) read <$> lookupEnv "PGPORT"
  envDb   <- fromMaybe "cheeblr"  <$> lookupEnv "PGDATABASE"
  envUser <- fromMaybe currentUser <$> lookupEnv "PGUSER"
  envPass <- fromMaybe ""          <$> lookupEnv "PGPASSWORD"

  let cfg = DBConfig
        { dbHost     = B8.pack envHost
        , dbPort     = fromIntegral envPort
        , dbName     = B8.pack envDb
        , dbUser     = B8.pack envUser
        , dbPassword = B8.pack envPass
        , poolSize   = 2
        }

  pool <- initializeDB cfg
  createAuthTables pool

  hasUsers <- anyUserExists pool
  if hasUsers
    then do
      hPutStrLn stderr
        "bootstrap-admin: users table already has rows — skipping."
      hPutStrLn stderr
        "  To re-bootstrap, delete all rows from the users table first."
      exitSuccess
    else do
      pwd <- generatePassword
      let nu = NewUser
                 { newUserName    = "admin"
                 , newDisplayName = "Administrator"
                 , newEmail       = Nothing
                 , newRole        = Admin
                 , newLocationId  = Nothing
                 , newPassword    = pwd
                 }
      result <- try @SomeException $ createUser pool nu
      case result of
        Left err -> do
          hPutStrLn stderr $
            "bootstrap-admin: failed to create admin user: " <> show err
          exitFailure
        Right uid -> do
          -- Credentials printed once to stdout so the shell wrapper can
          -- capture and store them via sops --set.
          putStrLn "===== Cheeblr Admin Bootstrap ====="
          putStrLn $ "username : admin"
          putStrLn $ "password : " <> T.unpack pwd
          putStrLn $ "uuid     : " <> show uid
          putStrLn "===================================="
          putStrLn "Store this password now — it will not be shown again."
          exitSuccess