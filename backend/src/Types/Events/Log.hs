{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Events.Log
  ( LogEvent (..)
  ) where

import Data.Aeson   (FromJSON, ToJSON, Value)
import Data.Text    (Text)
import Data.Time    (UTCTime)
import GHC.Generics (Generic)

data LogEvent = LogEvent
  { leTimestamp :: UTCTime
  , leComponent :: Text
  , leSeverity  :: Text
  , leMessage   :: Text
  , leContext   :: Value
  , leTraceId   :: Maybe Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON   LogEvent
instance FromJSON LogEvent