{-# LANGUAGE DeriveGeneric #-}
-- {-# LANGUAGE OverloadedStrings #-}
-- {-# LANGUAGE RecordWildCards #-}

module Types.Auth where

import Data.Aeson (ToJSON, FromJSON)
import Data.Text (Text)
import Data.UUID (UUID)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

-- | User roles in the dispensary system
data UserRole
  = Customer
  | Cashier
  | Manager
  | Admin
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON UserRole
instance FromJSON UserRole

-- | An authenticated user with their identity and role
data AuthenticatedUser = AuthenticatedUser
  { auUserId     :: UUID
  , auUserName   :: Text
  , auEmail      :: Maybe Text
  , auRole       :: UserRole
  , auLocationId :: Maybe UUID  -- Which location they're assigned to (Nothing = all locations for Admin)
  , auCreatedAt  :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON AuthenticatedUser
instance FromJSON AuthenticatedUser

data UserCapabilities = UserCapabilities
  { capCanViewInventory      :: Bool
  , capCanCreateItem         :: Bool
  , capCanEditItem           :: Bool
  , capCanDeleteItem         :: Bool
  , capCanProcessTransaction :: Bool
  , capCanVoidTransaction    :: Bool
  , capCanRefundTransaction  :: Bool
  , capCanApplyDiscount      :: Bool
  , capCanManageRegisters    :: Bool
  , capCanOpenRegister       :: Bool
  , capCanCloseRegister      :: Bool
  , capCanViewReports        :: Bool
  , capCanViewAllLocations   :: Bool
  , capCanManageUsers        :: Bool
  , capCanViewCompliance     :: Bool
  } deriving (Show, Eq, Generic)

instance ToJSON UserCapabilities
instance FromJSON UserCapabilities

capabilitiesForRole :: UserRole -> UserCapabilities
capabilitiesForRole Customer = UserCapabilities
  { capCanViewInventory      = True   -- Can browse menu
  , capCanCreateItem         = False
  , capCanEditItem           = False
  , capCanDeleteItem         = False
  , capCanProcessTransaction = False
  , capCanVoidTransaction    = False
  , capCanRefundTransaction  = False
  , capCanApplyDiscount      = False
  , capCanManageRegisters    = False
  , capCanOpenRegister       = False
  , capCanCloseRegister      = False
  , capCanViewReports        = False
  , capCanViewAllLocations   = False
  , capCanManageUsers        = False
  , capCanViewCompliance     = False
  }

capabilitiesForRole Cashier = UserCapabilities
  { capCanViewInventory      = True
  , capCanCreateItem         = False
  , capCanEditItem           = True   -- Can update quantities, etc.
  , capCanDeleteItem         = False
  , capCanProcessTransaction = True
  , capCanVoidTransaction    = False
  , capCanRefundTransaction  = False
  , capCanApplyDiscount      = False  -- Needs manager approval
  , capCanManageRegisters    = False
  , capCanOpenRegister       = True   -- Can open their assigned register
  , capCanCloseRegister      = True   -- Can close their register
  , capCanViewReports        = False
  , capCanViewAllLocations   = False
  , capCanManageUsers        = False
  , capCanViewCompliance     = True   -- Must verify IDs
  }

capabilitiesForRole Manager = UserCapabilities
  { capCanViewInventory      = True
  , capCanCreateItem         = True
  , capCanEditItem           = True
  , capCanDeleteItem         = True
  , capCanProcessTransaction = True
  , capCanVoidTransaction    = True
  , capCanRefundTransaction  = True
  , capCanApplyDiscount      = True
  , capCanManageRegisters    = True
  , capCanOpenRegister       = True
  , capCanCloseRegister      = True
  , capCanViewReports        = True
  , capCanViewAllLocations   = False  -- Only their location
  , capCanManageUsers        = False
  , capCanViewCompliance     = True
  }

capabilitiesForRole Admin = UserCapabilities
  { capCanViewInventory      = True
  , capCanCreateItem         = True
  , capCanEditItem           = True
  , capCanDeleteItem         = True
  , capCanProcessTransaction = True
  , capCanVoidTransaction    = True
  , capCanRefundTransaction  = True
  , capCanApplyDiscount      = True
  , capCanManageRegisters    = True
  , capCanOpenRegister       = True
  , capCanCloseRegister      = True
  , capCanViewReports        = True
  , capCanViewAllLocations   = True
  , capCanManageUsers        = True
  , capCanViewCompliance     = True
  }

hasCapability :: (UserCapabilities -> Bool) -> AuthenticatedUser -> Bool
hasCapability capFn user = capFn $ capabilitiesForRole (auRole user)

requireCapability :: (UserCapabilities -> Bool) -> String -> AuthenticatedUser -> Either String ()
requireCapability capFn errMsg user
  | hasCapability capFn user = Right ()
  | otherwise = Left errMsg