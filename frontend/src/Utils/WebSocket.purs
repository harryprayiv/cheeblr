module Utils.WebSocket where

import Prelude

import Data.String (take, drop) as S
import Effect (Effect)

foreign import data WSConnection :: Type

foreign import _openWebSocket
  :: String                  -- URL
  -> (String -> Effect Unit) -- onMessage
  -> Effect Unit             -- onOpen
  -> Effect Unit             -- onClose
  -> Effect Unit             -- onError
  -> Effect WSConnection

foreign import _closeWebSocket :: WSConnection -> Effect Unit

type WSCallbacks =
  { onMessage :: String -> Effect Unit
  , onOpen    :: Effect Unit
  , onClose   :: Effect Unit
  , onError   :: Effect Unit
  }

openWebSocket :: String -> WSCallbacks -> Effect WSConnection
openWebSocket url cbs =
  _openWebSocket url cbs.onMessage cbs.onOpen cbs.onClose cbs.onError

closeWebSocket :: WSConnection -> Effect Unit
closeWebSocket = _closeWebSocket

-- | Convert an HTTP(S) base URL to a WebSocket URL.
-- "https://host" -> "wss://host"
-- "http://host"  -> "ws://host"
toWsUrl :: String -> String
toWsUrl url
  | S.take 8 url == "https://" = "wss://" <> S.drop 8 url
  | S.take 7 url == "http://"  = "ws://"  <> S.drop 7 url
  | otherwise                   = url