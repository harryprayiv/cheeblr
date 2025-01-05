module Main where

import CreateItem (app)
import Prelude

import Effect (Effect)
import Effect.Class.Console (log)

main :: Effect Unit
main = do
  log "Starting main"
  app