module Main where

import Prelude

import Config.Entity (dummyEmployeeId, dummyLocationId)
import Control.Monad.ST.Class (liftST)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Deku.Core (fixed)
import Deku.DOM as D
import Deku.Hooks (cycle)
import Deku.Toplevel (runInBody)
import Effect (Effect)
import Effect.Class.Console as Console
import FRP.Poll as Poll
import Pages.CreateItem as Pages.CreateItem
import Pages.CreateTransaction as Pages.CreateTransaction
import Pages.DeleteItem as Pages.DeleteItem
import Pages.EditItem as Pages.EditItem
import Pages.LiveView as Pages.LiveView
import Pages.TransactionHistory as Pages.TransactionHistory
import Route (Route(..), nav, route)
import Routing.Duplex (parse)
import Routing.Hash (matchesWith)
import Services.AuthService (newAuthRef)
import Services.RegisterService as RegisterService
import Types.UUID (genUUID)

main :: Effect Unit
main = do
  authRef <- newAuthRef
  currentRoute <- liftST Poll.create

  RegisterService.initLocalRegister
    authRef
    dummyLocationId
    dummyEmployeeId
    (\register -> Console.log $ "Register pre-initialized: " <> register.registerName)
    (\err -> Console.error $ "Register pre-init failed: " <> err)

  let
    matcher _ r = do
      Console.log $ "Route changed to: " <> show r

      nut <- case r of
        LiveView ->
          Pages.LiveView.page authRef

        Create -> do
          uuid <- genUUID
          Console.log $ "Generated UUID for new item: " <> show uuid
          Pages.CreateItem.page authRef (show uuid)

        Edit uuid ->
          Pages.EditItem.page authRef uuid

        Delete uuid ->
          Pages.DeleteItem.page authRef uuid

        CreateTransaction ->
          Pages.CreateTransaction.page authRef

        TransactionHistory ->
          Pages.TransactionHistory.page

      currentRoute.push (Tuple r nut)

  void $ matchesWith (parse route) matcher

  void $ runInBody
    ( fixed
        [ nav (fst <$> currentRoute.poll)
        , D.div_ [ cycle (snd <$> currentRoute.poll) ]
        ]
    )

  matcher Nothing LiveView