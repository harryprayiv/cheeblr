module Services.AuthService where

import Prelude

import Config.Auth (DevUser, allDevUsers, defaultDevUser, devUserCapabilities, toAuthenticatedUser, findDevUserById)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Types.Auth (AuthenticatedUser, UserCapabilities, UserRole)
import Types.UUID (UUID)

-- | Auth context containing current user state
type AuthContext =
  { currentUser :: DevUser
  , capabilities :: UserCapabilities
  }

-- | Create initial auth context with default dev user
mkInitialAuthContext :: AuthContext
mkInitialAuthContext =
  { currentUser: defaultDevUser
  , capabilities: devUserCapabilities defaultDevUser
  }

-- | Create a new auth state ref
newAuthRef :: Effect (Ref AuthContext)
newAuthRef = Ref.new mkInitialAuthContext

-- | Get current auth context
getAuthContext :: Ref AuthContext -> Effect AuthContext
getAuthContext = Ref.read

-- | Get current user
getCurrentUser :: Ref AuthContext -> Effect DevUser
getCurrentUser ref = do
  ctx <- Ref.read ref
  pure ctx.currentUser

-- | Get current user ID (for X-User-Id header)
getCurrentUserId :: Ref AuthContext -> Effect UUID
getCurrentUserId ref = do
  user <- getCurrentUser ref
  pure user.userId

-- | Get current capabilities
getCurrentCapabilities :: Ref AuthContext -> Effect UserCapabilities
getCurrentCapabilities ref = do
  ctx <- Ref.read ref
  pure ctx.capabilities

-- | Set current user by DevUser
setCurrentUser :: Ref AuthContext -> DevUser -> Effect Unit
setCurrentUser ref user = do
  Ref.write
    { currentUser: user
    , capabilities: devUserCapabilities user
    }
    ref

-- | Set current user by UUID (looks up from dev users)
setCurrentUserById :: Ref AuthContext -> UUID -> Effect Boolean
setCurrentUserById ref userId =
  case findDevUserById userId of
    Just user -> do
      setCurrentUser ref user
      pure true
    Nothing -> pure false

-- | Get authenticated user record (for display purposes)
getAuthenticatedUser :: Ref AuthContext -> Effect AuthenticatedUser
getAuthenticatedUser ref = do
  user <- getCurrentUser ref
  pure (toAuthenticatedUser user)

-- | Get current user's role
getCurrentRole :: Ref AuthContext -> Effect UserRole
getCurrentRole ref = do
  user <- getCurrentUser ref
  pure user.role

-- | Get all available dev users (for user selector UI)
getAvailableUsers :: Array DevUser
getAvailableUsers = allDevUsers

-- | Check if current user has a specific capability
checkCapability :: Ref AuthContext -> (UserCapabilities -> Boolean) -> Effect Boolean
checkCapability ref capFn = do
  caps <- getCurrentCapabilities ref
  pure (capFn caps)

-- | Capability check helpers
canViewInventory :: Ref AuthContext -> Effect Boolean
canViewInventory ref = checkCapability ref _.capCanViewInventory

canCreateItem :: Ref AuthContext -> Effect Boolean
canCreateItem ref = checkCapability ref _.capCanCreateItem

canEditItem :: Ref AuthContext -> Effect Boolean
canEditItem ref = checkCapability ref _.capCanEditItem

canDeleteItem :: Ref AuthContext -> Effect Boolean
canDeleteItem ref = checkCapability ref _.capCanDeleteItem

canProcessTransaction :: Ref AuthContext -> Effect Boolean
canProcessTransaction ref = checkCapability ref _.capCanProcessTransaction

canVoidTransaction :: Ref AuthContext -> Effect Boolean
canVoidTransaction ref = checkCapability ref _.capCanVoidTransaction

canRefundTransaction :: Ref AuthContext -> Effect Boolean
canRefundTransaction ref = checkCapability ref _.capCanRefundTransaction

canApplyDiscount :: Ref AuthContext -> Effect Boolean
canApplyDiscount ref = checkCapability ref _.capCanApplyDiscount

canManageRegisters :: Ref AuthContext -> Effect Boolean
canManageRegisters ref = checkCapability ref _.capCanManageRegisters

canOpenRegister :: Ref AuthContext -> Effect Boolean
canOpenRegister ref = checkCapability ref _.capCanOpenRegister

canCloseRegister :: Ref AuthContext -> Effect Boolean
canCloseRegister ref = checkCapability ref _.capCanCloseRegister

canViewReports :: Ref AuthContext -> Effect Boolean
canViewReports ref = checkCapability ref _.capCanViewReports

canViewAllLocations :: Ref AuthContext -> Effect Boolean
canViewAllLocations ref = checkCapability ref _.capCanViewAllLocations

canManageUsers :: Ref AuthContext -> Effect Boolean
canManageUsers ref = checkCapability ref _.capCanManageUsers

canViewCompliance :: Ref AuthContext -> Effect Boolean
canViewCompliance ref = checkCapability ref _.capCanViewCompliance