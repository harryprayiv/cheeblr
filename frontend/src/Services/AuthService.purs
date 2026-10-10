module Services.AuthService
  ( AuthState(..)
  , isSignedIn
  , session
  , capabilities
  , can
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Types.Auth (UserCapabilities, emptyCapabilities)
import Types.Session (SessionResponse)

-- Who the browser is signed in as. The session comes from the backend
-- (POST /auth/login or GET /auth/me) and is held as it arrived. The user
-- id, the role and the capabilities are the backend's. Nothing here is
-- derived from a role on the client.
--
-- The session itself is an HttpOnly cookie. This value decides only what
-- the screens show. The backend decides every request.
data AuthState
  = SignedIn SessionResponse
  | SignedOut

instance showAuthState :: Show AuthState where
  show SignedOut = "SignedOut"
  show (SignedIn s) =
    "SignedIn " <> s.sessionUserName <> " (" <> show s.sessionRole <> ")"

isSignedIn :: AuthState -> Boolean
isSignedIn = case _ of
  SignedIn _ -> true
  SignedOut -> false

session :: AuthState -> Maybe SessionResponse
session = case _ of
  SignedIn s -> Just s
  SignedOut -> Nothing

-- A signed-out browser has no capabilities.
capabilities :: AuthState -> UserCapabilities
capabilities = case _ of
  SignedIn s -> s.sessionCapabilities
  SignedOut -> emptyCapabilities

can :: (UserCapabilities -> Boolean) -> AuthState -> Boolean
can capability = capability <<< capabilities
