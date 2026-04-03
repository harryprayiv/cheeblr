{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Types.Events.Register (
  RegisterEvent (..),
) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import GHC.Generics (Generic)

data RegisterEvent
  = RegisterOpened
      { reRegId :: UUID
      , reEmpId :: UUID
      , reStartingCash :: Int
      , reTimestamp :: UTCTime
      }
  | RegisterClosed
      { reRegId :: UUID
      , reEmpId :: UUID
      , reCountedCash :: Int
      , reVariance :: Int
      , reTimestamp :: UTCTime
      }
  deriving (Show, Eq, Generic)

instance ToJSON RegisterEvent
instance FromJSON RegisterEvent
