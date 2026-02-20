module Cheeblr.API.AuthRequest where

import Prelude

import Cheeblr.API.Auth (AuthContext, getUserIdStr)
import Cheeblr.API.Request as R
import Data.Either (Either)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Effect.Ref (Ref)
import Yoga.JSON (class ReadForeign, class WriteForeign)

-- | All functions here just extract the userId from the AuthRef
-- | and delegate to the stateless Request module.
-- | This is the only module that knows about both Auth and Request.

authGet :: forall a. ReadForeign a
        => Ref AuthContext -> R.URL -> Aff (Either String a)
authGet ref url = do
  userId <- liftEffect $ getUserIdStr ref
  R.get userId url

authGetFullUrl :: forall a. ReadForeign a
               => Ref AuthContext -> String -> Aff (Either String a)
authGetFullUrl ref fullUrl = do
  userId <- liftEffect $ getUserIdStr ref
  R.getFullUrl userId fullUrl

authPost :: forall req res. WriteForeign req => ReadForeign res
         => Ref AuthContext -> R.URL -> req -> Aff (Either String res)
authPost ref url body = do
  userId <- liftEffect $ getUserIdStr ref
  R.post userId url body

authPostEmpty :: forall a. ReadForeign a
              => Ref AuthContext -> R.URL -> Aff (Either String a)
authPostEmpty ref url = do
  userId <- liftEffect $ getUserIdStr ref
  R.postEmpty userId url

authPostUnit :: Ref AuthContext -> R.URL -> Aff (Either String Unit)
authPostUnit ref url = do
  userId <- liftEffect $ getUserIdStr ref
  R.postUnit userId url

authPostChecked :: forall req res. WriteForeign req => ReadForeign res
               => Ref AuthContext -> R.URL -> req -> Aff (Either String res)
authPostChecked ref url body = do
  userId <- liftEffect $ getUserIdStr ref
  R.postChecked userId url body

authPut :: forall req res. WriteForeign req => ReadForeign res
        => Ref AuthContext -> R.URL -> req -> Aff (Either String res)
authPut ref url body = do
  userId <- liftEffect $ getUserIdStr ref
  R.put userId url body

authDelete :: forall a. ReadForeign a
           => Ref AuthContext -> R.URL -> Aff (Either String a)
authDelete ref url = do
  userId <- liftEffect $ getUserIdStr ref
  R.delete userId url

authDeleteUnit :: Ref AuthContext -> R.URL -> Aff (Either String Unit)
authDeleteUnit ref url = do
  userId <- liftEffect $ getUserIdStr ref
  R.deleteUnit userId url