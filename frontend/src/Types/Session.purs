module Types.Session where

import Types.Auth (UserCapabilities, UserRole)
import Types.UUID (UUID)

type SessionResponse =
  { sessionUserId       :: UUID
  , sessionUserName     :: String
  , sessionRole         :: UserRole
  , sessionCapabilities :: UserCapabilities
  }