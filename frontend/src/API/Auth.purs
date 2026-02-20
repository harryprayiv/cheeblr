module Cheeblr.API.Auth where

import Prelude

import Cheeblr.Core.Auth (Role(..), Capabilities, capabilitiesFor)
import Data.Array as Data.Array
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Types.UUID (UUID(..))

----------------------------------------------------------------------
-- Dev Users (will be replaced by real auth)
----------------------------------------------------------------------

type DevUser =
  { userId :: UUID
  , userName :: String
  , email :: Maybe String
  , role :: Role
  , locationId :: Maybe UUID
  }

devCustomer :: DevUser
devCustomer =
  { userId: UUID "8244082f-a6bc-4d6c-9427-64a0ecdc10db"
  , userName: "customer-1"
  , email: Just "customer@example.com"
  , role: Customer
  , locationId: Nothing
  }

devCashier :: DevUser
devCashier =
  { userId: UUID "0a6f2deb-892b-4411-8025-08c1a4d61229"
  , userName: "cashier-1"
  , email: Just "cashier@example.com"
  , role: Cashier
  , locationId: Nothing
  }

devManager :: DevUser
devManager =
  { userId: UUID "8b75ea4a-00a4-4a2a-a5d5-a1bab8883802"
  , userName: "manager-1"
  , email: Just "manager@example.com"
  , role: Manager
  , locationId: Nothing
  }

devAdmin :: DevUser
devAdmin =
  { userId: UUID "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
  , userName: "admin-1"
  , email: Just "admin@example.com"
  , role: Admin
  , locationId: Nothing
  }

allDevUsers :: Array DevUser
allDevUsers = [ devCustomer, devCashier, devManager, devAdmin ]

defaultDevUser :: DevUser
defaultDevUser = devAdmin

findDevUserById :: UUID -> Maybe DevUser
findDevUserById targetId =
  case Data.Array.filter (\u -> u.userId == targetId) allDevUsers of
    [ user ] -> Just user
    _ -> Nothing

----------------------------------------------------------------------
-- Auth Context (mutable ref holding current user + capabilities)
----------------------------------------------------------------------

type AuthContext =
  { currentUser :: DevUser
  , capabilities :: Capabilities
  }

mkAuthContext :: DevUser -> AuthContext
mkAuthContext user =
  { currentUser: user
  , capabilities: capabilitiesFor user.role
  }

newAuthRef :: Effect (Ref AuthContext)
newAuthRef = Ref.new (mkAuthContext defaultDevUser)

----------------------------------------------------------------------
-- Accessors
----------------------------------------------------------------------

getAuthContext :: Ref AuthContext -> Effect AuthContext
getAuthContext = Ref.read

getCurrentUser :: Ref AuthContext -> Effect DevUser
getCurrentUser ref = _.currentUser <$> Ref.read ref

getCurrentUserId :: Ref AuthContext -> Effect UUID
getCurrentUserId ref = _.userId <$> getCurrentUser ref

-- | Get the userId as a String, ready for request headers.
getUserIdStr :: Ref AuthContext -> Effect String
getUserIdStr ref = show <$> getCurrentUserId ref

getCurrentCapabilities :: Ref AuthContext -> Effect Capabilities
getCurrentCapabilities ref = _.capabilities <$> Ref.read ref

getCurrentRole :: Ref AuthContext -> Effect Role
getCurrentRole ref = _.role <$> getCurrentUser ref

----------------------------------------------------------------------
-- Mutation
----------------------------------------------------------------------

setCurrentUser :: Ref AuthContext -> DevUser -> Effect Unit
setCurrentUser ref user =
  Ref.write (mkAuthContext user) ref

setCurrentUserById :: Ref AuthContext -> UUID -> Effect Boolean
setCurrentUserById ref userId =
  case findDevUserById userId of
    Just user -> do
      setCurrentUser ref user
      pure true
    Nothing ->
      pure false

----------------------------------------------------------------------
-- Capability checks
----------------------------------------------------------------------

checkCapability :: Ref AuthContext -> (Capabilities -> Boolean) -> Effect Boolean
checkCapability ref capFn =
  capFn <$> getCurrentCapabilities ref

canViewInventory :: Ref AuthContext -> Effect Boolean
canViewInventory ref = checkCapability ref _.canViewInventory

canCreateItem :: Ref AuthContext -> Effect Boolean
canCreateItem ref = checkCapability ref _.canCreateItem

canEditItem :: Ref AuthContext -> Effect Boolean
canEditItem ref = checkCapability ref _.canEditItem

canDeleteItem :: Ref AuthContext -> Effect Boolean
canDeleteItem ref = checkCapability ref _.canDeleteItem

canProcessTransaction :: Ref AuthContext -> Effect Boolean
canProcessTransaction ref = checkCapability ref _.canProcessTransaction

canVoidTransaction :: Ref AuthContext -> Effect Boolean
canVoidTransaction ref = checkCapability ref _.canVoidTransaction

canManageRegisters :: Ref AuthContext -> Effect Boolean
canManageRegisters ref = checkCapability ref _.canManageRegisters

canOpenRegister :: Ref AuthContext -> Effect Boolean
canOpenRegister ref = checkCapability ref _.canOpenRegister

canCloseRegister :: Ref AuthContext -> Effect Boolean
canCloseRegister ref = checkCapability ref _.canCloseRegister

canViewReports :: Ref AuthContext -> Effect Boolean
canViewReports ref = checkCapability ref _.canViewReports