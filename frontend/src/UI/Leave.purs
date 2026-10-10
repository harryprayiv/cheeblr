module UI.Leave
  ( OnLeave
  ) where

import Prelude

import Effect (Effect)

-- A page that opens something long lived (an event stream, a socket) hands
-- its close action to this. Main runs every registered action when the
-- route changes or the user signs out, so the connection does not outlive
-- the page.
type OnLeave = Effect Unit -> Effect Unit
