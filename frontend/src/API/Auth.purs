module API.Auth where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Data.Either (Either)
import Data.Maybe (Maybe)
import Effect.Aff (Aff)
import Types.Session (SessionResponse)
import Types.UUID (UUID)

type LoginRequest =
  { loginUsername :: String
  , loginPassword :: String
  , loginRegisterId :: Maybe UUID
  }

type LoginResponse =
  { loginExpiresAt :: String
  , loginUser :: SessionResponse
  }

-- A successful login sets the HttpOnly session cookie. The page never sees
-- the token.
login :: LoginRequest -> Aff (Either ApiError LoginResponse)
login req = Request.post "/auth/login" req

logout :: Aff (Either ApiError Unit)
logout = Request.postUnit "/auth/logout"

-- Answers 401 when the browser holds no valid session cookie.
validateSession :: Aff (Either ApiError SessionResponse)
validateSession = Request.get "/auth/me"
