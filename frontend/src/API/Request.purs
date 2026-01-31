module API.Request where

import Prelude

import Affjax (Error, Request, Response, URL, defaultRequest, printError)
import Affjax.RequestBody as RequestBody
import Affjax.RequestHeader (RequestHeader(..))
import Affjax.ResponseFormat as ResponseFormat
import Affjax.Web as AW
import Data.Either (Either(..))
import Data.HTTP.Method (Method(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Ref (Ref)
import Services.AuthService (AuthContext, getCurrentUserId)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, readJSON_, writeJSON)

-- | API base URL (configurable for different environments)
apiBaseUrl :: String
apiBaseUrl = "http://localhost:8080"

-- | Build a request with authentication header (returns string for Yoga.JSON parsing)
mkAuthenticatedRequest
  :: URL
  -> Method
  -> Maybe String
  -> UUID
  -> Request String
mkAuthenticatedRequest url method body userId =
  defaultRequest
    { url = apiBaseUrl <> url
    , method = Left method
    , headers = 
        [ RequestHeader "X-User-Id" (show userId)
        , RequestHeader "Content-Type" "application/json"
        ]
    , content = RequestBody.string <$> body
    , responseFormat = ResponseFormat.string
    }

-- | Perform an authenticated GET request
authGet
  :: forall a
   . ReadForeign a
  => Ref AuthContext
  -> URL
  -> Aff (Either String a)
authGet authRef url = do
  userId <- liftEffect $ getCurrentUserId authRef
  response <- AW.request (mkAuthenticatedRequest url GET Nothing userId)
  pure $ parseResponse response

-- | Perform an authenticated POST request
authPost
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => Ref AuthContext
  -> URL
  -> req
  -> Aff (Either String res)
authPost authRef url body = do
  userId <- liftEffect $ getCurrentUserId authRef
  let jsonBody = writeJSON body
  response <- AW.request (mkAuthenticatedRequest url POST (Just jsonBody) userId)
  pure $ parseResponse response

-- | Perform an authenticated PUT request
authPut
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => Ref AuthContext
  -> URL
  -> req
  -> Aff (Either String res)
authPut authRef url body = do
  userId <- liftEffect $ getCurrentUserId authRef
  let jsonBody = writeJSON body
  response <- AW.request (mkAuthenticatedRequest url PUT (Just jsonBody) userId)
  pure $ parseResponse response

-- | Perform an authenticated DELETE request
authDelete
  :: forall a
   . ReadForeign a
  => Ref AuthContext
  -> URL
  -> Aff (Either String a)
authDelete authRef url = do
  userId <- liftEffect $ getCurrentUserId authRef
  response <- AW.request (mkAuthenticatedRequest url DELETE Nothing userId)
  pure $ parseResponse response

-- | Perform an authenticated PATCH request
authPatch
  :: forall req res
   . WriteForeign req
  => ReadForeign res
  => Ref AuthContext
  -> URL
  -> req
  -> Aff (Either String res)
authPatch authRef url body = do
  userId <- liftEffect $ getCurrentUserId authRef
  let jsonBody = writeJSON body
  response <- AW.request (mkAuthenticatedRequest url PATCH (Just jsonBody) userId)
  pure $ parseResponse response

-- | Parse JSON response
parseResponse
  :: forall a
   . ReadForeign a
  => Either Error (Response String)
  -> Either String a
parseResponse (Left err) = Left (printError err)
parseResponse (Right res) =
  case readJSON_ res.body of
    Nothing -> Left "JSON parse error"
    Just a -> Right a

-- | Helper for endpoints that return Unit/void
authPostUnit
  :: forall req
   . WriteForeign req
  => Ref AuthContext
  -> URL
  -> req
  -> Aff (Either String Unit)
authPostUnit authRef url body = do
  userId <- liftEffect $ getCurrentUserId authRef
  let jsonBody = writeJSON body
  response <- AW.request (mkAuthenticatedRequest url POST (Just jsonBody) userId)
  pure $ case response of
    Left err -> Left (printError err)
    Right _ -> Right unit

-- | Helper for endpoints that return Unit/void
authDeleteUnit
  :: Ref AuthContext
  -> URL
  -> Aff (Either String Unit)
authDeleteUnit authRef url = do
  userId <- liftEffect $ getCurrentUserId authRef
  response <- AW.request (mkAuthenticatedRequest url DELETE Nothing userId)
  pure $ case response of
    Left err -> Left (printError err)
    Right _ -> Right unit