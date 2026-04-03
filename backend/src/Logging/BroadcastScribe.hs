{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module Logging.BroadcastScribe (
  mkBroadcastScribe,
) where

import Data.Aeson (Value (..))
import Data.Text (Text)
import qualified Data.Text as T
import Katip (
  Item (
    _itemMessage,
    _itemNamespace,
    _itemPayload,
    _itemSeverity,
    _itemTime
  ),
  LogItem,
  LogStr (unLogStr),
  Namespace (Namespace),
  PermitFunc,
  Scribe (..),
  Severity (..),
  ToObject (toObject),
 )

import Control.Monad (when)
import Infrastructure.Broadcast (Broadcaster, publish)
import Types.Events.Log (LogEvent (..))

mkBroadcastScribe :: Broadcaster LogEvent -> PermitFunc -> IO Scribe
mkBroadcastScribe broadcaster permit =
  pure $
    Scribe
      { liPush = \item -> do
          allowed <- permit item
          when allowed $ publish broadcaster (toLogEvent item)
      , scribeFinalizer = pure ()
      , scribePermitItem = permit
      }

toLogEvent :: (LogItem a) => Item a -> LogEvent
toLogEvent item =
  LogEvent
    { leTimestamp = _itemTime item
    , leComponent = renderNS (_itemNamespace item)
    , leSeverity = renderSev (_itemSeverity item)
    , leMessage = renderMsg (_itemMessage item)
    , leContext = Data.Aeson.Object (toObject (_itemPayload item))
    , leTraceId = Nothing
    }

renderNS :: Namespace -> Text
renderNS (Namespace parts) = T.intercalate "." parts

renderSev :: Severity -> Text
renderSev DebugS = "debug"
renderSev InfoS = "info"
renderSev NoticeS = "notice"
renderSev WarningS = "warning"
renderSev ErrorS = "error"
renderSev CriticalS = "critical"
renderSev AlertS = "alert"
renderSev EmergencyS = "emergency"

renderMsg :: LogStr -> Text
renderMsg = T.pack . show . unLogStr
