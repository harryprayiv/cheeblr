module Main where

import Prelude

import API.Auth as Auth
import API.Request as Request
import Control.Alt ((<|>))
import Control.Monad.ST.Class (liftST)
import Data.Either (Either(..))
import Data.Tuple (Tuple(..), fst, snd)
import Deku.Core (Nut, fixed)
import Deku.DOM as D
import Deku.Hooks (cycle)
import Deku.Toplevel (runInBody)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref as Ref
import FRP.Poll as Poll
import Pages.Admin.Dashboard as Pages.Admin.Dashboard
import Pages.CreateItem as Pages.CreateItem
import Pages.CreateTransaction as Pages.CreateTransaction
import Pages.DeleteItem as Pages.DeleteItem
import Pages.EditItem as Pages.EditItem
import Pages.Feed.Monitor as Pages.Feed.Monitor
import Pages.LiveView as Pages.LiveView
import Pages.Login as Pages.Login
import Pages.Manager.Dashboard as Pages.Manager.Dashboard
import Pages.Registers as Pages.Registers
import Pages.Stock.Interface as Pages.Stock.Interface
import Pages.TransactionHistory as Pages.TransactionHistory
import Route (Route(..), nav, route)
import Routing.Duplex (parse)
import Routing.Hash (matchesWith, setHash)
import Services.AuthService (AuthState(..))
import Types.Session (SessionResponse)
import Types.UUID (genUUID)

-- How the app decides what to show.
--
-- The session is asked for once at boot (GET /auth/me). Until the answer
-- arrives nothing is rendered. After that every render reads the auth
-- state first:
--   signed out: the login page, whatever the route says;
--   signed in:  the page for the route. Each page reads its own data when
--               it is mounted.
-- Signing in or out renders the current route again, so the page changes
-- without a navigation.
--
-- A session that cannot be read (no cookie, an expired cookie, a response
-- that does not decode, an unknown role) is signed out.
main :: Effect Unit
main = do
  authState <- liftST Poll.create
  currentRoute <- liftST Poll.create

  authRef <- Ref.new SignedOut
  routeRef <- Ref.new LiveView
  readyRef <- Ref.new false
  leaveRef <- Ref.new (pure unit)

  let
    authPoll = pure SignedOut <|> authState.poll

    onLeave :: Effect Unit -> Effect Unit
    onLeave cleanup = Ref.modify_ (_ *> cleanup) leaveRef

    -- Runs what the page being left registered through onLeave.
    leave :: Effect Unit
    leave = do
      cleanup <- Ref.read leaveRef
      Ref.write (pure unit) leaveRef
      cleanup

    pageFor :: SessionResponse -> Route -> Effect Nut
    pageFor user = case _ of
      Login -> pure Pages.LiveView.page
      LiveView -> pure Pages.LiveView.page
      Create -> Pages.CreateItem.page <<< show <$> genUUID
      Edit sku -> pure $ Pages.EditItem.page sku
      Delete sku -> pure $ Pages.DeleteItem.page sku
      CreateTransaction -> pure $ Pages.CreateTransaction.page user
      TransactionHistory -> pure $ Pages.TransactionHistory.page user
      Registers -> pure $ Pages.Registers.page user
      Admin -> pure $ Pages.Admin.Dashboard.page onLeave
      Manager -> pure Pages.Manager.Dashboard.page
      Stock -> pure $ Pages.Stock.Interface.page onLeave
      Feed -> pure $ Pages.Feed.Monitor.page onLeave

    render :: Route -> Effect Unit
    render r = do
      leave
      auth <- Ref.read authRef
      case auth of
        SignedOut ->
          currentRoute.push (Tuple Login (Pages.Login.page signIn))
        SignedIn user -> do
          nut <- pageFor user r
          currentRoute.push (Tuple r nut)

    -- The auth push comes before the render. The nav bar is rebuilt on an
    -- auth change, and its links learn the current route from the route
    -- push that follows.
    setAuth :: AuthState -> Effect Unit
    setAuth auth = do
      Ref.write auth authRef
      authState.push auth

    signIn :: SessionResponse -> Effect Unit
    signIn user = do
      setAuth (SignedIn user)
      r <- Ref.read routeRef
      if r == Login then setHash "/" else render r

    signOut :: Effect Unit
    signOut = launchAff_ do
      void Auth.logout
      liftEffect do
        setAuth SignedOut
        Ref.read routeRef >>= render

  void $ matchesWith (parse route) \_ r -> do
    Ref.write r routeRef
    ready <- Ref.read readyRef
    when ready (render r)

  void $ runInBody
    ( fixed
        [ nav (fst <$> currentRoute.poll) authPoll signOut
        , D.div_ [ cycle (snd <$> currentRoute.poll) ]
        ]
    )

  launchAff_ do
    result <- Auth.validateSession
    liftEffect do
      case result of
        Right user -> do
          Console.log $ "Session restored for " <> user.sessionUserName
          setAuth (SignedIn user)
        Left err -> do
          Console.log $ "No session: " <> Request.describe err
          setAuth SignedOut
      Ref.write true readyRef
      Ref.read routeRef >>= render
