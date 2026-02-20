module Utils.Storage where

import Prelude

import Data.Maybe (Maybe)
import Effect (Effect)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage as Storage

-- Store a key-value pair in local storage
storeItem :: String -> String -> Effect Unit
storeItem key value = do
  w <- window
  storage <- localStorage w
  Storage.setItem key value storage

-- Retrieve a value from local storage
retrieveItem :: String -> Effect (Maybe String)
retrieveItem key = do
  w <- window
  storage <- localStorage w
  Storage.getItem key storage

-- Remove a value from local storage
removeItem :: String -> Effect Unit
removeItem key = do
  w <- window
  storage <- localStorage w
  Storage.removeItem key storage

-- Clear all items from local storage
clearStorage :: Effect Unit
clearStorage = do
  w <- window
  storage <- localStorage w
  Storage.clear storage