-- FILE: ./frontend/src/Main.purs
module Main where

import Prelude

import Cheeblr.API.Auth (newAuthRef)
import Cheeblr.UI.Route (appShell)
import Deku.Toplevel (runInBody)
import Effect (Effect)

main :: Effect Unit
main = do
  authRef <- newAuthRef
  void $ runInBody (appShell authRef)