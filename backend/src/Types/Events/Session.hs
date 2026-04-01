{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Types.Events.Session
  ( SessionEvent (..)
  ) where

import Data.Aeson   (FromJSON, ToJSON)
import Data.Time    (UTCTime)
import Data.UUID    (UUID)
import GHC.Generics (Generic)
import Types.Auth   (UserRole)

data SessionEvent
  = SessionCreated
      { sesUserId    :: UUID
      , sesRole      :: UserRole
      , sesTimestamp :: UTCTime
      }
  | SessionExpired
      { sesUserId    :: UUID
      , sesTimestamp :: UTCTime
      }
  | SessionRevoked
      { sesUserId    :: UUID
      , sesActorId   :: UUID
      , sesTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON   SessionEvent
instance FromJSON SessionEvent