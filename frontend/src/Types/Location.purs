module Types.Location where

import Prelude

import Data.Maybe (Maybe)
import Types.UUID (UUID, parseUUID)
import Yoga.JSON (class ReadForeign, class WriteForeign, readImpl, writeImpl)

newtype LocationId = LocationId UUID

derive instance eqLocationId :: Eq LocationId
derive instance ordLocationId :: Ord LocationId

instance showLocationId :: Show LocationId where
  show (LocationId uid) = show uid

instance readForeignLocationId :: ReadForeign LocationId where
  readImpl f = LocationId <$> readImpl f

instance writeForeignLocationId :: WriteForeign LocationId where
  writeImpl (LocationId uid) = writeImpl uid

locationIdToString :: LocationId -> String
locationIdToString (LocationId uid) = show uid

parseLocationId :: String -> Maybe LocationId
parseLocationId s = LocationId <$> parseUUID s

unLocationId :: LocationId -> UUID
unLocationId (LocationId uid) = uid