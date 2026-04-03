{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Location (
  LocationId (..),
  locationIdToUUID,
  uuidToLocationId,
) where

import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.OpenApi (ToSchema)
import Data.UUID (UUID, fromText, toText)
import GHC.Generics (Generic)
import Web.HttpApiData (FromHttpApiData (..), ToHttpApiData (..))

newtype LocationId = LocationId UUID
  deriving (Show, Read, Eq, Ord, Generic)

instance ToJSON LocationId where
  toJSON (LocationId u) = toJSON u

instance FromJSON LocationId where
  parseJSON v = LocationId <$> parseJSON v

instance ToSchema LocationId

instance FromHttpApiData LocationId where
  parseUrlPiece t = case fromText t of
    Nothing -> Left "Invalid UUID for LocationId"
    Just uid -> Right (LocationId uid)

instance ToHttpApiData LocationId where
  toUrlPiece (LocationId uid) = toText uid

locationIdToUUID :: LocationId -> UUID
locationIdToUUID (LocationId u) = u

uuidToLocationId :: UUID -> LocationId
uuidToLocationId = LocationId
