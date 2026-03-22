module Services.AuthService where

import Prelude

import Config.Auth (DevUser, allDevUsers, defaultDevUser, devUserCapabilities,
                    toAuthenticatedUser, findDevUserById)
import Data.Filterable (filterMap)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff)
import FRP.Poll (Poll)
import Types.Auth (AuthenticatedUser, UserCapabilities, UserRole, emptyCapabilities)
import Types.UUID (UUID)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, removeItem, setItem)

------------------------------------------------------------------------
-- Core auth state
------------------------------------------------------------------------

data AuthState = SignedIn DevUser | SignedOut

derive instance eqAuthState :: Eq AuthState

-- In real-auth mode this carries the opaque Bearer token.
-- In dev mode it carries the dev user UUID string (legacy behaviour).
type UserId = String

------------------------------------------------------------------------
-- Session token persistence (localStorage)
--
-- The token is the raw base64url string returned by POST /auth/login.
-- Storing it in localStorage is appropriate for a dedicated POS terminal
-- where HttpOnly cookies are impractical across different origins.
------------------------------------------------------------------------

tokenKey :: String
tokenKey = "cheeblr_session_token"

persistToken :: String -> Effect Unit
persistToken token = do
  w <- window
  storage <- localStorage w
  setItem tokenKey token storage

loadToken :: Effect (Maybe String)
loadToken = do
  w <- window
  storage <- localStorage w
  getItem tokenKey storage

clearToken :: Effect Unit
clearToken = do
  w <- window
  storage <- localStorage w
  removeItem tokenKey storage

------------------------------------------------------------------------
-- Poll / state helpers (unchanged from dev version)
------------------------------------------------------------------------

mostRecentUser :: Poll AuthState -> Poll DevUser
mostRecentUser = filterMap case _ of
  SignedIn user -> Just user
  SignedOut     -> Nothing

getUserId :: AuthState -> Maybe String
getUserId (SignedIn user) = Just (show user.userId)
getUserId SignedOut       = Nothing

userIdFromAuth :: AuthState -> String
userIdFromAuth (SignedIn user) = show user.userId
userIdFromAuth SignedOut       = ""

getCapabilities :: AuthState -> Maybe UserCapabilities
getCapabilities (SignedIn user) = Just (devUserCapabilities user)
getCapabilities SignedOut       = Nothing

getRole :: AuthState -> Maybe UserRole
getRole (SignedIn user) = Just user.role
getRole SignedOut       = Nothing

checkCapability :: (UserCapabilities -> Boolean) -> AuthState -> Boolean
checkCapability capFn (SignedIn user) = capFn (devUserCapabilities user)
checkCapability _     SignedOut       = false

whenSignedIn :: forall m. Applicative m => AuthState -> (DevUser -> m Unit) -> m Unit
whenSignedIn (SignedIn user) f = f user
whenSignedIn SignedOut       _ = pure unit

isSignedIn :: AuthState -> Boolean
isSignedIn (SignedIn _) = true
isSignedIn SignedOut    = false

-- Default to SignedOut in production; Main.purs will restore from
-- localStorage on startup when USE_REAL_AUTH is true on the backend.
-- Dev builds keep SignedIn defaultDevUser by calling devModeAuthState.
defaultAuthState :: AuthState
defaultAuthState = SignedOut

devModeAuthState :: AuthState
devModeAuthState = SignedIn defaultDevUser

authStateForUserId :: UUID -> Maybe AuthState
authStateForUserId userId = SignedIn <$> findDevUserById userId

getAvailableUsers :: Array DevUser
getAvailableUsers = allDevUsers

getAuthenticatedUser :: AuthState -> Maybe AuthenticatedUser
getAuthenticatedUser (SignedIn user) = Just (toAuthenticatedUser user)
getAuthenticatedUser SignedOut       = Nothing

------------------------------------------------------------------------
-- Capability shortcuts (unchanged)
------------------------------------------------------------------------

resolveCapabilities :: Maybe UserCapabilities -> AuthState -> UserCapabilities
resolveCapabilities (Just backendCaps) _            = backendCaps
resolveCapabilities Nothing            (SignedIn u)  = devUserCapabilities u
resolveCapabilities Nothing            SignedOut      = emptyCapabilities

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