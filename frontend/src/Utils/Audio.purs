module Utils.Audio where

import Prelude

import Data.Foldable (for_)
import Effect (Effect)
import Web.DOM.Document (createElement)
import Web.HTML (window)
import Web.HTML.HTMLAudioElement (fromElement, toHTMLMediaElement)
import Web.HTML.HTMLDocument (toDocument)
import Web.HTML.HTMLMediaElement (play, setSrc)
import Web.HTML.Window (document)

data AlertSound
  = SoundError
  | SoundInfo
  | SoundSuccess
  | SoundWarning

soundPath :: AlertSound -> String
soundPath SoundError   = "/assets/sounds/error.wav"
soundPath SoundInfo    = "/assets/sounds/info.wav"
soundPath SoundSuccess = "/assets/sounds/success.wav"
soundPath SoundWarning = "/assets/sounds/warning.wav"

-- | Play one of the four alert sounds using the browser's HTMLMediaElement API.
-- Creates a transient <audio> element, sets src, and calls play().
-- The element is not appended to the DOM — browsers do not require this.
-- play() returns a Promise which is discarded; we fire-and-forget.
playSound :: AlertSound -> Effect Unit
playSound sound = do
  w   <- window
  doc <- toDocument <$> document w
  el  <- createElement "audio" doc
  for_ (fromElement el) \audio -> do
    let media = toHTMLMediaElement audio
    setSrc (soundPath sound) media
    void (play media)