module Utils.SSE where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Ref as Ref
import FRP.Poll (Poll)
import FRP.Poll as Poll
import Control.Alt ((<|>))
import Control.Monad.ST.Class (liftST)

data SSEStatus
  = SSEConnecting
  | SSEConnected
  | SSEReconnecting
  | SSEClosed

derive instance eqSSEStatus :: Eq SSEStatus

instance showSSEStatus :: Show SSEStatus where
  show SSEConnecting   = "Connecting"
  show SSEConnected    = "Connected"
  show SSEReconnecting = "Reconnecting"
  show SSEClosed       = "Closed"

type SSEConnection =
  { status  :: Poll SSEStatus
  , close   :: Effect Unit
  }

foreign import openSSEImpl
  :: String
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect (Effect Unit)

openSSE
  :: String
  -> (String -> Effect Unit)
  -> Effect SSEConnection
openSSE url onMessage = do
  statusRef <- liftST Poll.create
  closeRef  <- Ref.new (pure unit)

  let onStatus s = statusRef.push case s of
        "connected"    -> SSEConnected
        "reconnecting" -> SSEReconnecting
        "closed"       -> SSEClosed
        _              -> SSEConnecting

  closeFn <- openSSEImpl url onMessage onStatus
  Ref.write closeFn closeRef

  pure
    { status : pure SSEConnecting <|> statusRef.poll
    , close  : do
        fn <- Ref.read closeRef
        fn
    }