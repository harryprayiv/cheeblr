{-# LANGUAGE DeriveGeneric #-}

module Types.Trace (
  TraceId (..),
  newTraceId,
  traceIdToText,
  parseTraceId,
) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Data.UUID.V4 (nextRandom)
import GHC.Generics (Generic)

newtype TraceId = TraceId UUID
  deriving (Show, Eq, Ord, Generic)

instance ToJSON TraceId
instance FromJSON TraceId

newTraceId :: IO TraceId
newTraceId = TraceId <$> nextRandom

traceIdToText :: TraceId -> Text
traceIdToText (TraceId u) = UUID.toText u

parseTraceId :: Text -> Maybe TraceId
parseTraceId t = TraceId <$> UUID.fromText t
