module Types.RemoteData
  ( RemoteData(..)
  , fromEither
  ) where

import Prelude

import Data.Either (Either(..))

-- The state of a value fetched from the backend. One type replaces the
-- per-page Loading / Loaded / Error ADTs.
data RemoteData a
  = NotAsked
  | Loading
  | Failure String
  | Success a

derive instance Eq a => Eq (RemoteData a)
derive instance Functor RemoteData

fromEither :: forall a. Either String a -> RemoteData a
fromEither = case _ of
  Left err -> Failure err
  Right a -> Success a
