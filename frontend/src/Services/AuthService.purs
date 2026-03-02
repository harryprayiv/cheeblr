module Services.AuthService where

import Prelude

import Config.Auth (DevUser, allDevUsers, defaultDevUser, devUserCapabilities, toAuthenticatedUser, findDevUserById)
import Data.Filterable (filterMap)
import Data.Maybe (Maybe(..))
import FRP.Poll (Poll)
import Types.Auth (AuthenticatedUser, UserCapabilities, UserRole, emptyCapabilities)
import Types.UUID (UUID)

-- | Core auth state ADT — mirrors the realworld pattern.
-- | Components receive `Poll AuthState` and react to changes.
data AuthState = SignedIn DevUser | SignedOut

derive instance eqAuthState :: Eq AuthState

-- | UserId type alias for API layer
type UserId = String

-- | Extract the current user from a poll (drops SignedOut events)
mostRecentUser :: Poll AuthState -> Poll DevUser
mostRecentUser = filterMap case _ of
  SignedIn user -> Just user
  SignedOut -> Nothing

-- | Extract userId string from AuthState (for API calls)
getUserId :: AuthState -> Maybe String
getUserId (SignedIn user) = Just (show user.userId)
getUserId SignedOut = Nothing

-- | Extract userId string, with fallback — used in Main for initial loads
userIdFromAuth :: AuthState -> String
userIdFromAuth (SignedIn user) = show user.userId
userIdFromAuth SignedOut = ""

-- | Get capabilities from auth state
getCapabilities :: AuthState -> Maybe UserCapabilities
getCapabilities (SignedIn user) = Just (devUserCapabilities user)
getCapabilities SignedOut = Nothing

-- | Get role from auth state
getRole :: AuthState -> Maybe UserRole
getRole (SignedIn user) = Just user.role
getRole SignedOut = Nothing

-- | Check a capability against auth state
checkCapability :: (UserCapabilities -> Boolean) -> AuthState -> Boolean
checkCapability capFn (SignedIn user) = capFn (devUserCapabilities user)
checkCapability _ SignedOut = false

-- | For use in components: run an action only when signed in
whenSignedIn :: forall m. Applicative m => AuthState -> (DevUser -> m Unit) -> m Unit
whenSignedIn (SignedIn user) f = f user
whenSignedIn SignedOut _ = pure unit

isSignedIn :: AuthState -> Boolean
isSignedIn (SignedIn _) = true
isSignedIn SignedOut = false

-- | Initial auth state for dev mode
defaultAuthState :: AuthState
defaultAuthState = SignedIn defaultDevUser

-- | Set user by ID (for dev user selector)
authStateForUserId :: UUID -> Maybe AuthState
authStateForUserId userId = SignedIn <$> findDevUserById userId

-- | All available dev users (for user selector UI)
getAvailableUsers :: Array DevUser
getAvailableUsers = allDevUsers

-- | Get AuthenticatedUser from state
getAuthenticatedUser :: AuthState -> Maybe AuthenticatedUser
getAuthenticatedUser (SignedIn user) = Just (toAuthenticatedUser user)
getAuthenticatedUser SignedOut = Nothing

-- Capability checks as predicates on AuthState
canViewInventory :: AuthState -> Boolean
canViewInventory = checkCapability _.capCanViewInventory

canCreateItem :: AuthState -> Boolean
canCreateItem = checkCapability _.capCanCreateItem

canEditItem :: AuthState -> Boolean
canEditItem = checkCapability _.capCanEditItem

canDeleteItem :: AuthState -> Boolean
canDeleteItem = checkCapability _.capCanDeleteItem

canProcessTransaction :: AuthState -> Boolean
canProcessTransaction = checkCapability _.capCanProcessTransaction

canVoidTransaction :: AuthState -> Boolean
canVoidTransaction = checkCapability _.capCanVoidTransaction

canRefundTransaction :: AuthState -> Boolean
canRefundTransaction = checkCapability _.capCanRefundTransaction

canApplyDiscount :: AuthState -> Boolean
canApplyDiscount = checkCapability _.capCanApplyDiscount

canManageRegisters :: AuthState -> Boolean
canManageRegisters = checkCapability _.capCanManageRegisters

canOpenRegister :: AuthState -> Boolean
canOpenRegister = checkCapability _.capCanOpenRegister

canCloseRegister :: AuthState -> Boolean
canCloseRegister = checkCapability _.capCanCloseRegister

canViewReports :: AuthState -> Boolean
canViewReports = checkCapability _.capCanViewReports

canViewAllLocations :: AuthState -> Boolean
canViewAllLocations = checkCapability _.capCanViewAllLocations

canManageUsers :: AuthState -> Boolean
canManageUsers = checkCapability _.capCanManageUsers

canViewCompliance :: AuthState -> Boolean
canViewCompliance = checkCapability _.capCanViewCompliance

resolveCapabilities :: Maybe UserCapabilities -> AuthState -> UserCapabilities
resolveCapabilities (Just backendCaps) _ = backendCaps
resolveCapabilities Nothing (SignedIn user) = devUserCapabilities user
resolveCapabilities Nothing SignedOut = emptyCapabilities