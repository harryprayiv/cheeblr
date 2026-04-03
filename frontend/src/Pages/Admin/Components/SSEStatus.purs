module Pages.Admin.Components.SSEStatus where

import Prelude

import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.Hooks ((<#~>))
import FRP.Poll (Poll)
import Utils.SSE (SSEStatus(..))

sseStatus :: Poll SSEStatus -> Nut
sseStatus statusPoll =
  statusPoll <#~> \status ->
    D.span
      [ DA.klass_ ("sse-status " <> statusClass status) ]
      [ text_ (statusLabel status) ]
  where
  statusClass SSEConnecting   = "sse-connecting"
  statusClass SSEConnected    = "sse-connected"
  statusClass SSEReconnecting = "sse-reconnecting"
  statusClass SSEClosed       = "sse-closed"

  statusLabel SSEConnecting   = "⟳ Connecting"
  statusLabel SSEConnected    = "● Live"
  statusLabel SSEReconnecting = "⟳ Reconnecting"
  statusLabel SSEClosed       = "○ Closed"