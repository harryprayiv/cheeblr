module Config.Auth where

import Prelude

import Data.Array (filter)
import Data.DateTime (DateTime)
import Data.DateTime.Instant (instant, toDateTime)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Types.Auth (AuthenticatedUser, UserCapabilities, UserRole(..), capabilitiesForRole)
import Types.UUID (UUID(..))

-- | Dev user configuration matching backend Auth/Simple.hs hardcoded users
type DevUser =
  { userId :: UUID
  , userName :: String
  , email :: Maybe String
  , role :: UserRole
  , locationId :: Maybe UUID
  }

-- | Helper to create a default DateTime (epoch)
defaultDateTime :: DateTime
defaultDateTime = 
  toDateTime $ fromMaybe bottom (instant (Milliseconds 0.0))

-- | Dev user: customer-1 (UUID: 8244082f-a6bc-4d6c-9427-64a0ecdc10db)
devCustomer :: DevUser
devCustomer =
  { userId: UUID("8244082f-a6bc-4d6c-9427-64a0ecdc10db")
  , userName: "customer-1"
  , email: Just "customer@example.com"
  , role: Customer
  , locationId: Nothing
  }

-- | Dev user: Cashier-1 (UUID: 0a6f2deb-892b-4411-8025-08c1a4d61229)
-- | This is the default user in the backend
devCashier :: DevUser
devCashier =
  { userId: UUID("0a6f2deb-892b-4411-8025-08c1a4d61229")
  , userName: "cashier-1"
  , email: Just "cashier@example.com"
  , role: Cashier
  , locationId: Nothing
  }

-- | Dev user: manager-1 (UUID: 8b75ea4a-00a4-4a2a-a5d5-a1bab8883802)
devManager :: DevUser
devManager =
  { userId: UUID("8b75ea4a-00a4-4a2a-a5d5-a1bab8883802")
  , userName: "manager-1"
  , email: Just "manager@example.com"
  , role: Manager
  , locationId: Nothing
  }

-- | Dev user: admin-1 (UUID: d3a1f4f0-c518-4db3-aa43-e80b428d6304)
devAdmin :: DevUser
devAdmin =
  { userId: UUID("d3a1f4f0-c518-4db3-aa43-e80b428d6304")
  , userName: "admin-1"
  , email: Just "admin@example.com"
  , role: Admin
  , locationId: Nothing
  }

-- | All available dev users
allDevUsers :: Array DevUser
allDevUsers = [devCustomer, devCashier, devManager, devAdmin]

-- | Default dev user (Cashier-1, matching backend default)
defaultDevUser :: DevUser
defaultDevUser = devAdmin

-- | Convert DevUser to AuthenticatedUser
toAuthenticatedUser :: DevUser -> AuthenticatedUser
toAuthenticatedUser dev =
  { auUserId: dev.userId
  , auUserName: dev.userName
  , auEmail: dev.email
  , auRole: dev.role
  , auLocationId: dev.locationId
  , auCreatedAt: defaultDateTime
  }

-- | Get capabilities for a DevUser
devUserCapabilities :: DevUser -> UserCapabilities
devUserCapabilities dev = capabilitiesForRole dev.role

-- | Find dev user by UUID
findDevUserById :: UUID -> Maybe DevUser
findDevUserById targetId = 
  case filter (\u -> u.userId == targetId) allDevUsers of
    [user] -> Just user
    _ -> Nothing

-- | Find dev user by role
findDevUserByRole :: UserRole -> Maybe DevUser
findDevUserByRole targetRole =
  case filter (\u -> u.role == targetRole) allDevUsers of
    [user] -> Just user
    _ -> Nothing