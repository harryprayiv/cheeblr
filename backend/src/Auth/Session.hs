{-# LANGUAGE OverloadedStrings #-}

-- Auth.Session: session-based authentication resolver.
-- Replaces Auth.Simple.lookupUser for the real-auth path.
-- Step 3 will wire resolveSession into existing handlers behind
-- the USE_REAL_AUTH flag; for now it is used only by Server.Auth.
module Auth.Session
  ( SessionContext (..)
  , resolveSession
  , extractBearer
  ) where

import qualified Data.ByteString.Lazy.Char8 as LBS
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import           Data.UUID                  (UUID)
import           Control.Monad.IO.Class     (liftIO)
import           Servant                    (Handler, ServerError (..), err401,
                                             throwError)

import           DB.Auth                    (lookupSession, userRowToAuthUser)
import           DB.Database                (DBPool)
import           DB.Schema                  (sessId)
import           Types.Auth                 (AuthenticatedUser)

data SessionContext = SessionContext
  { scUser      :: AuthenticatedUser
  , scSessionId :: UUID
  }

-- Strip "Bearer " prefix and return the raw token string.
extractBearer :: Maybe Text -> Maybe Text
extractBearer (Just h)
  | "Bearer " `T.isPrefixOf` h = Just (T.drop 7 h)
extractBearer _ = Nothing

-- Validate the Authorization header, return a SessionContext,
-- or throw 401 for any missing / invalid / expired token.
resolveSession :: DBPool -> Maybe Text -> Handler SessionContext
resolveSession pool mHeader = do
  token <- case extractBearer mHeader of
    Nothing -> throwError err401
      { errBody = LBS.pack "Missing or malformed Authorization header" }
    Just t  -> pure t
  mResult <- liftIO $ lookupSession pool token
  case mResult of
    Nothing ->
      throwError err401 { errBody = LBS.pack "Invalid or expired session" }
    Just (sessRow, userRow) ->
      pure SessionContext
        { scUser      = userRowToAuthUser userRow
        , scSessionId = sessId sessRow
        }