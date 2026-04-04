{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Types.Public.FeedFrame (
  FeedFrame (..),
  FeedStatus (..),
  mkFeedFrame,
) where

import Data.Aeson (defaultOptions)
import Data.Aeson.TH (deriveToJSON)
import Data.Aeson.Types (Options (..))
import Data.Char (toLower)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import Types.Events.Availability (AvailabilityUpdate (..))
import Types.Public.AvailableItem (AvailableItem, PublicLocationId)

-- Strip the two-character prefix (ff / fs) and lowercase the first remaining
-- character, matching the instance derivation in AvailableItem.hs.
-- e.g. ffSeq -> seq, ffType -> type, fsCurrentSeq -> currentSeq
--
-- Note: feedOptions cannot be used in the splice below (GHC stage restriction
-- prohibits using locally-defined values in top-level splices). The lambda is
-- inlined directly. Both use the identical transformation.

-- | A single frame sent over the WebSocket feed.
-- JSON fields: seq, type, payload, timestamp.
-- Maps to the app.cheeblr.feed.subscribe#frame lexicon definition.
data FeedFrame = FeedFrame
  { ffSeq :: Int64
  , ffType :: Text -- always "app.cheeblr.inventory.availableItem"
  , ffPayload :: AvailableItem
  , ffTimestamp :: UTCTime
  }
  deriving (Show, Eq, Generic)

$(deriveToJSON
    ( defaultOptions
        { fieldLabelModifier = \label -> case drop 2 label of
            [] -> label
            (c : cs) -> toLower c : cs
        }
    )
    ''FeedFrame)

-- | Response from GET /xrpc/app.cheeblr.feed.status.
-- JSON fields: locationId, locationName, currentSeq, itemCount,
--              inStockCount, oldestSeq.
data FeedStatus = FeedStatus
  { fsLocationId :: PublicLocationId
  , fsLocationName :: Text
  , fsCurrentSeq :: Int64
  , fsItemCount :: Int
  , fsInStockCount :: Int
  , fsOldestSeq :: Maybe Int64
  }
  deriving (Show, Eq, Generic)

$(deriveToJSON
    ( defaultOptions
        { fieldLabelModifier = \label -> case drop 2 label of
            [] -> label
            (c : cs) -> toLower c : cs
        }
    )
    ''FeedStatus)

mkFeedFrame :: Int64 -> AvailabilityUpdate -> FeedFrame
mkFeedFrame seq' upd =
  FeedFrame
    { ffSeq = seq'
    , ffType = "app.cheeblr.inventory.availableItem"
    , ffPayload = auItem upd
    , ffTimestamp = auTimestamp upd
    }