{-# LANGUAGE DeriveGeneric #-}

module Types.Location
  ( LocationId (..)
  , locationIdToUUID
  , uuidToLocationId
  ) where

import Data.Aeson   (FromJSON (..), ToJSON (..))
import Data.OpenApi (ToSchema)
import Data.UUID    (UUID)
import GHC.Generics (Generic)

newtype LocationId = LocationId UUID
  deriving (Show, Read, Eq, Ord, Generic)

instance ToJSON LocationId where
  toJSON (LocationId u) = toJSON u

instance FromJSON LocationId where
  parseJSON v = LocationId <$> parseJSON v

instance ToSchema LocationId

locationIdToUUID :: LocationId -> UUID
locationIdToUUID (LocationId u) = u

uuidToLocationId :: UUID -> LocationId
uuidToLocationId = LocationId