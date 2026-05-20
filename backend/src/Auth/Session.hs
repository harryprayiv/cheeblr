{-# LANGUAGE OverloadedStrings #-}

module Auth.Session (
  SessionContext (..),
  resolveSession,
  extractBearer,
) where

import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID (UUID)
import Servant (
  Handler,
  ServerError (..),
  err401,
  throwError,
 )

import DB.Auth (lookupSession, userRowToAuthUser)
import DB.Database (DBPool)
import DB.Schema (sessId)
import Types.Auth (AuthenticatedUser)
import Types.Primitives.Token (mkSessionToken)

data SessionContext = SessionContext
  { scUser :: AuthenticatedUser
  , scSessionId :: UUID
  }

-- | Strip the "Bearer " prefix from an Authorization header value.
-- Does not validate the token format; that happens in 'resolveSession'.
extractBearer :: Maybe Text -> Maybe Text
extractBearer (Just h)
  | "Bearer " `T.isPrefixOf` h = Just (T.drop 7 h)
extractBearer _ = Nothing

resolveSession :: DBPool -> Maybe Text -> Handler SessionContext
resolveSession pool mHeader = do
  rawText <- case extractBearer mHeader of
    Nothing ->
      throwError
        err401
          { errBody = LBS.pack "Missing or malformed Authorization header"
          }
    Just t -> pure t
  token <- case mkSessionToken rawText of
    Nothing ->
      throwError
        err401
          { errBody = LBS.pack "Invalid or expired session"
          }
    Just t -> pure t
  mResult <- liftIO $ lookupSession pool token
  case mResult of
    Nothing ->
      throwError err401 {errBody = LBS.pack "Invalid or expired session"}
    Just (sessRow, userRow) ->
      pure
        SessionContext
          { scUser = userRowToAuthUser userRow
          , scSessionId = sessId sessRow
          }