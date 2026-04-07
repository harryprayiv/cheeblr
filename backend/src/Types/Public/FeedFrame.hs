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
import Data.OpenApi (NamedSchema (..), ToSchema (..))
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import Types.Events.Availability (AvailabilityUpdate (..))
import Types.Public.AvailableItem (AvailableItem, PublicLocationId)

data FeedFrame = FeedFrame
  { ffSeq       :: Int64
  , ffType      :: Text
  , ffPayload   :: AvailableItem
  , ffTimestamp :: UTCTime
  }
  deriving (Show, Eq, Generic)

$( deriveToJSON
     ( defaultOptions
         { fieldLabelModifier = \label -> case drop 2 label of
             []       -> label
             (c : cs) -> toLower c : cs
         }
     )
     ''FeedFrame
 )

-- Manual stub: custom fieldLabelModifier means the generic schema would use
-- the wrong field names.
instance ToSchema FeedFrame where
  declareNamedSchema _ = return $ NamedSchema (Just "FeedFrame") mempty

data FeedStatus = FeedStatus
  { fsLocationId   :: PublicLocationId
  , fsLocationName :: Text
  , fsCurrentSeq   :: Int64
  , fsItemCount    :: Int
  , fsInStockCount :: Int
  , fsOldestSeq    :: Maybe Int64
  }
  deriving (Show, Eq, Generic)

$( deriveToJSON
     ( defaultOptions
         { fieldLabelModifier = \label -> case drop 2 label of
             []       -> label
             (c : cs) -> toLower c : cs
         }
     )
     ''FeedStatus
 )

-- Manual stub: custom fieldLabelModifier.
instance ToSchema FeedStatus where
  declareNamedSchema _ = return $ NamedSchema (Just "FeedStatus") mempty

mkFeedFrame :: Int64 -> AvailabilityUpdate -> FeedFrame
mkFeedFrame seq' upd =
  FeedFrame
    { ffSeq       = seq'
    , ffType      = "app.cheeblr.inventory.availableItem"
    , ffPayload   = auItem upd
    , ffTimestamp = auTimestamp upd
    }