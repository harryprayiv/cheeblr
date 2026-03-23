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
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, removeItem, setItem)

-- | The session token carried inside SignedIn is what gets sent as the
-- | Authorization: Bearer header. In dev mode it is the UUID string of the
-- | selected dev user. In real-auth mode it is the opaque token returned by
-- | POST /auth/login.
data AuthState = SignedIn DevUser String | SignedOut

derive instance eqAuthState :: Eq AuthState

type UserId = String

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

mostRecentUser :: Poll AuthState -> Poll DevUser
mostRecentUser = filterMap case _ of
  SignedIn user _ -> Just user
  SignedOut       -> Nothing

getUserId :: AuthState -> Maybe String
getUserId (SignedIn _ token) = Just token
getUserId SignedOut           = Nothing

-- | Returns the token/userId to use in Authorization: Bearer headers.
-- | Dev mode: UUID string. Real mode: opaque session token.
userIdFromAuth :: AuthState -> String
userIdFromAuth (SignedIn _ token) = token
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

-- | In dev mode the "token" is the UUID string of the default dev user.
-- | The backend's Auth.Simple.lookupUser accepts UUIDs as auth values, so
-- | this round-trips correctly when USE_REAL_AUTH=false.
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