{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}

module API.Auth where

import Data.Aeson (FromJSON, ToJSON)
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Servant

import Types.Auth (SessionResponse, UserRole)
import Types.Location (LocationId)

-- The Authorization header used by all session-protected endpoints.
-- Format: "Bearer <token>"
type SessionHeader = Header "Authorization" Text

------------------------------------------------------------------------
-- Request / response types
------------------------------------------------------------------------

data LoginRequest = LoginRequest
  { loginUsername :: Text
  , loginPassword :: Text
  , loginRegisterId :: Maybe UUID
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

data LoginResponse = LoginResponse
  { loginToken :: Text
  , loginExpiresAt :: UTCTime
  , loginUser :: SessionResponse
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

-- Outward-facing user summary (no password hash, no internal fields).
data UserSummary = UserSummary
  { summaryId :: UUID
  , summaryUsername :: Text
  , summaryDisplayName :: Text
  , summaryEmail :: Maybe Text
  , summaryRole :: UserRole
  , summaryIsActive :: Bool
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

-- API request for creating a new user (admin only).
data NewUserRequest = NewUserRequest
  { newReqUsername :: Text
  , newReqDisplayName :: Text
  , newReqEmail :: Maybe Text
  , newReqRole :: UserRole
  , newReqLocationId :: Maybe LocationId
  , newReqPassword :: Text
  }
  deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

------------------------------------------------------------------------
-- API type
------------------------------------------------------------------------

type AuthAPI =
  "auth"
    :> "login"
    :> Header "User-Agent" Text
    :> Header "X-Real-IP" Text
    :> ReqBody '[JSON] LoginRequest
    :> Post '[JSON] LoginResponse
    :<|> "auth"
      :> "logout"
      :> SessionHeader
      :> Post '[JSON] NoContent
    :<|> "auth"
      :> "me"
      :> SessionHeader
      :> Get '[JSON] SessionResponse
    :<|> "auth"
      :> "users"
      :> SessionHeader
      :> Get '[JSON] [UserSummary]
    :<|> "auth"
      :> "users"
      :> SessionHeader
      :> ReqBody '[JSON] NewUserRequest
      :> Post '[JSON] UserSummary

authAPI :: Proxy AuthAPI
authAPI = Proxy
