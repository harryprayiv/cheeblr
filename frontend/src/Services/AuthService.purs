module Services.AuthService where

import Prelude

import Config.Auth (DevUser, allDevUsers, defaultDevUser, devUserCapabilities,
                    toAuthenticatedUser, findDevUserById)
import Data.Filterable (filterMap)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import FRP.Poll (Poll)
import Types.Auth (AuthenticatedUser, UserCapabilities, UserRole, emptyCapabilities)
import Types.UUID (UUID)

-- | SignedIn DevUser String — the String is the user's UUID (ActorId),
-- | used for logging and capability resolution. It is NOT the session token.
-- | The session token lives exclusively in the HttpOnly cookie set by the
-- | server and is never accessible to JavaScript.
data AuthState = SignedIn DevUser String | SignedOut

instance showAuthState :: Show AuthState where
  show SignedOut           = "SignedOut"
  show (SignedIn _ actorId) = "SignedIn <user> " <> actorId

-- | ActorId is the UUID of the authenticated user, used for logging.
-- | Named UserId for backward compatibility with the API call-graph.
type UserId  = String
type ActorId = String

tokenKey :: String
tokenKey = "cheeblr_session_token"

-- | No-op. The session cookie is HttpOnly and cannot be written from JS.
-- | Retained so that call sites do not require changes.
persistToken :: String -> Effect Unit
persistToken _ = pure unit

-- | No-op. Always returns Nothing. Session validity is checked by calling
-- | GET /auth/me; the browser sends the HttpOnly cookie automatically.
loadToken :: Effect (Maybe String)
loadToken = pure Nothing

-- | No-op. The server clears the cookie on POST /auth/logout.
clearToken :: Effect Unit
clearToken = pure unit

mostRecentUser :: Poll AuthState -> Poll DevUser
mostRecentUser = filterMap case _ of
  SignedIn user _ -> Just user
  SignedOut       -> Nothing

getUserId :: AuthState -> Maybe ActorId
getUserId (SignedIn user _) = Just (show user.userId)
getUserId SignedOut           = Nothing

-- | Returns the user's UUID string for logging. NOT the session token.
userIdFromAuth :: AuthState -> ActorId
userIdFromAuth (SignedIn user _) = show user.userId
userIdFromAuth SignedOut           = ""

getCapabilities :: AuthState -> Maybe UserCapabilities
getCapabilities (SignedIn user _) = Just (devUserCapabilities user)
getCapabilities SignedOut          = Nothing

getRole :: AuthState -> Maybe UserRole
getRole (SignedIn user _) = Just user.role
getRole SignedOut           = Nothing

checkCapability :: (UserCapabilities -> Boolean) -> AuthState -> Boolean
checkCapability capFn (SignedIn user _) = capFn (devUserCapabilities user)
checkCapability _     SignedOut          = false

whenSignedIn :: forall m. Applicative m => AuthState -> (DevUser -> m Unit) -> m Unit
whenSignedIn (SignedIn user _) f = f user
whenSignedIn SignedOut          _ = pure unit

isSignedIn :: AuthState -> Boolean
isSignedIn (SignedIn _ _) = true
isSignedIn SignedOut       = false

defaultAuthState :: AuthState
defaultAuthState = SignedOut

-- | devModeAuthState stores the user's UUID as the ActorId slot.
-- | The Nix-based production guard is a follow-on task.
devModeAuthState :: AuthState
devModeAuthState = SignedIn defaultDevUser (show defaultDevUser.userId)

authStateForUserId :: UUID -> Maybe AuthState
authStateForUserId uuid =
  findDevUserById uuid <#> \u -> SignedIn u (show u.userId)

getAvailableUsers :: Array DevUser
getAvailableUsers = allDevUsers

getAuthenticatedUser :: AuthState -> Maybe AuthenticatedUser
getAuthenticatedUser (SignedIn user _) = Just (toAuthenticatedUser user)
getAuthenticatedUser SignedOut          = Nothing

resolveCapabilities :: Maybe UserCapabilities -> AuthState -> UserCapabilities
resolveCapabilities (Just backendCaps) _             = backendCaps
resolveCapabilities Nothing            (SignedIn u _) = devUserCapabilities u
resolveCapabilities Nothing            SignedOut       = emptyCapabilities

canViewInventory      :: AuthState -> Boolean
canViewInventory      = checkCapability _.capCanViewInventory

canCreateItem         :: AuthState -> Boolean
canCreateItem         = checkCapability _.capCanCreateItem

canEditItem           :: AuthState -> Boolean
canEditItem           = checkCapability _.capCanEditItem

canDeleteItem         :: AuthState -> Boolean
canDeleteItem         = checkCapability _.capCanDeleteItem

canProcessTransaction :: AuthState -> Boolean
canProcessTransaction = checkCapability _.capCanProcessTransaction

canVoidTransaction    :: AuthState -> Boolean
canVoidTransaction    = checkCapability _.capCanVoidTransaction

canRefundTransaction  :: AuthState -> Boolean
canRefundTransaction  = checkCapability _.capCanRefundTransaction

canApplyDiscount      :: AuthState -> Boolean
canApplyDiscount      = checkCapability _.capCanApplyDiscount

canManageRegisters    :: AuthState -> Boolean
canManageRegisters    = checkCapability _.capCanManageRegisters

canOpenRegister       :: AuthState -> Boolean
canOpenRegister       = checkCapability _.capCanOpenRegister

canCloseRegister      :: AuthState -> Boolean
canCloseRegister      = checkCapability _.capCanCloseRegister

canViewReports        :: AuthState -> Boolean
canViewReports        = checkCapability _.capCanViewReports

canViewAllLocations   :: AuthState -> Boolean
canViewAllLocations   = checkCapability _.capCanViewAllLocations

canManageUsers        :: AuthState -> Boolean
canManageUsers        = checkCapability _.capCanManageUsers

canViewCompliance     :: AuthState -> Boolean
canViewCompliance     = checkCapability _.capCanViewCompliance