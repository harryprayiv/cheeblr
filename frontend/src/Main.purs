module Main where

import Prelude

import API.Auth (validateSession)
import API.Inventory (fetchInventory, fetchSession, readInventory)
import GraphQL.API.Inventory (readInventoryGql)
import Config.Auth (defaultDevUser, findDevUserByRole)
import Config.Entity (dummyEmployeeId, dummyLocationId)
import Config.LiveView (defaultViewConfig)
import Control.Alt ((<|>))
import Control.Monad.ST.Class (liftST)
import Control.Parallel (parSequence_, parallel, sequential)
import Data.Array (find)
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), fromMaybe, isNothing)
import Data.Tuple (Tuple(..), fst, snd)
import Deku.Core (fixed)
import Deku.DOM as D
import Deku.Hooks (cycle)
import Deku.Toplevel (runInBody)
import Effect (Effect)
import Effect.Aff (Aff, killFiber, launchAff, launchAff_, makeAff, nonCanceler)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Exception (error)
import Effect.Ref as Ref
import FRP.Poll as Poll
import Pages.CreateItem as Pages.CreateItem
import Pages.CreateTransaction as Pages.CreateTransaction
import Pages.DeleteItem as Pages.DeleteItem
import Pages.EditItem as Pages.EditItem
import Pages.LiveView as Pages.LiveView
import Pages.Login as Pages.Login
import Pages.TransactionHistory as Pages.TransactionHistory
import Route (Route(..), nav, route)
import Routing.Duplex (parse)
import Routing.Hash (matchesWith)
import Services.AuthService (AuthState(..), clearToken, defaultAuthState, devModeAuthState, loadToken, userIdFromAuth)
import Services.RegisterService as RegisterService
import Services.TransactionService as TransactionService
import Types.Auth (UserCapabilities)
import Types.Inventory (Inventory(..), MenuItem(..))
import Types.Register (Register)
import Types.Transaction (Transaction)
import Types.UUID (UUID, genUUID)

devMode :: Boolean
devMode = false

run :: forall a r. Aff a -> { push :: a -> Effect Unit | r } -> Aff Unit
run aff { push } = aff >>= liftEffect <<< push

getOrInitRegisterAff :: String -> UUID -> UUID -> Aff (Either String Register)
getOrInitRegisterAff userId locationId employeeId =
  makeAff \cb -> do
    RegisterService.getOrInitLocalRegister userId locationId employeeId
      (\register -> cb (Right (Right register)))
      (\err      -> cb (Right (Left err)))
    pure nonCanceler

testItemUUID :: String
testItemUUID = "4e58b3e6-3fd4-425c-b6a3-4f033a76859c"

loadInventory :: String -> Aff Pages.LiveView.InventoryLoadStatus
loadInventory userId = do
  result <- readInventoryGql userId
  pure $ case result of
    Right inv -> Pages.LiveView.InventoryLoaded inv
    Left err  -> Pages.LiveView.InventoryError err

loadSession :: String -> Aff (Maybe UserCapabilities)
loadSession userId = do
  result <- fetchSession userId
  pure $ case result of
    Right session -> Just session.sessionCapabilities
    Left _        -> Nothing

loadEditItem :: String -> String -> Aff Pages.EditItem.EditItemStatus
loadEditItem userId rawUuid = do
  let uuid = if rawUuid == "test" then testItemUUID else rawUuid
  result <- readInventory userId
  pure $ case result of
    Right (Inventory items) ->
      case find (\(MenuItem item) -> show item.sku == uuid) items of
        Just menuItem -> Pages.EditItem.EditReady menuItem
        Nothing       -> Pages.EditItem.EditNotFound uuid
    Left err ->
      Pages.EditItem.EditError ("Failed to fetch inventory: " <> err)

loadDeleteItem :: String -> String -> Aff Pages.DeleteItem.DeleteItemStatus
loadDeleteItem userId rawUuid = do
  let uuid = if rawUuid == "test" then testItemUUID else rawUuid
  result <- readInventory userId
  pure $ case result of
    Right (Inventory items) ->
      case find (\(MenuItem item) -> show item.sku == uuid) items of
        Just (MenuItem item) -> Pages.DeleteItem.DeleteReady uuid item.name
        Nothing              -> Pages.DeleteItem.DeleteNotFound uuid
    Left err ->
      Pages.DeleteItem.DeleteError ("Failed to fetch inventory: " <> err)

loadTxPageData :: String -> Aff Pages.CreateTransaction.TxPageStatus
loadTxPageData userId = do
  Tuple invResult regTxResult <- sequential $
    Tuple
      <$> parallel (loadInventoryResult userId)
      <*> parallel (loadRegisterAndStartTx userId)
  pure $ case regTxResult of
    Left err ->
      Pages.CreateTransaction.TxPageError err
    Right { register, transaction } ->
      case invResult of
        Right inv -> Pages.CreateTransaction.TxPageReady inv register transaction
        Left err  -> Pages.CreateTransaction.TxPageDegraded err register transaction
  where
  loadInventoryResult :: String -> Aff (Either String Inventory)
  loadInventoryResult uid = do
    result <- fetchInventory uid defaultViewConfig.fetchConfig defaultViewConfig.mode
    pure $ case result of
      Right inv -> Right inv
      Left err  -> Left err

  loadRegisterAndStartTx
    :: String
    -> Aff (Either String { register :: Register, transaction :: Transaction })
  loadRegisterAndStartTx uid = do
    regResult <- getOrInitRegisterAff uid dummyLocationId dummyEmployeeId
    case regResult of
      Left err     -> pure $ Left err
      Right register -> do
        txResult <- TransactionService.startTransaction uid
          { employeeId: fromMaybe register.registerId register.registerOpenedBy
          , registerId: register.registerId
          , locationId: register.registerLocationId
          }
        pure $ case txResult of
          Right transaction -> Right { register, transaction }
          Left err          -> Left ("Failed to create transaction: " <> err)

main :: Effect Unit
main = do
  authState <- liftST Poll.create

  let initialAuth = if devMode then devModeAuthState else defaultAuthState

  tokenRef <- Ref.new (userIdFromAuth initialAuth)

  let
    pushAuth :: AuthState -> Effect Unit
    pushAuth st = do
      Ref.write (userIdFromAuth st) tokenRef
      authState.push st

  pushAuth initialAuth
  let authPoll = pure initialAuth <|> authState.poll

  currentRoute <- liftST Poll.create
  backendCaps  <- liftST Poll.create

  inventory  <- liftST Poll.create
  editItem   <- liftST Poll.create
  deleteItem <- liftST Poll.create
  txPage     <- liftST Poll.create

  prevAction <- Ref.new (pure unit)

  -- In real-auth mode matchesWith fires the initial route synchronously before
  -- the async session restore has written the token into tokenRef. readyRef
  -- suppresses that first automatic fire so the route only runs once the real
  -- token is available. Subsequent hash-change fires (prev == Just _) always
  -- pass through regardless of the flag.
  readyRef <- Ref.new devMode

  let
    matcher prev r = do
      ready <- Ref.read readyRef
      if not ready && isNothing prev
        then pure unit
        else do
          Console.log $ "Route changed to: " <> show r

          userId <- Ref.read tokenRef

          pa <- Ref.read prevAction
          newAction <- launchAff $ killFiber (error "route changed") pa *>
            parSequence_ case r of
              LiveView ->
                [ do
                    result <- loadInventory userId
                    liftEffect $ inventory.push result
                , do
                    mcaps <- loadSession userId
                    liftEffect $ for_ mcaps backendCaps.push
                ]
              Edit uuid ->
                [ run (loadEditItem userId uuid) editItem ]
              Delete uuid ->
                [ run (loadDeleteItem userId uuid) deleteItem ]
              CreateTransaction ->
                [ run (loadTxPageData userId) txPage ]
              _ -> []

          Ref.write newAction prevAction

          nut <- case r of
            Login ->
              pure $ Pages.Login.page pushAuth (pure unit)

            LiveView ->
              pure $ Pages.LiveView.page authPoll
                (pure Pages.LiveView.InventoryLoading <|> inventory.poll)

            Create -> do
              uuid <- genUUID
              Console.log $ "Generated UUID for new item: " <> show uuid
              pure $ Pages.CreateItem.page authPoll userId (show uuid)

            Edit _ ->
              pure $ Pages.EditItem.page authPoll userId
                (pure Pages.EditItem.EditLoading <|> editItem.poll)

            Delete _ ->
              pure $ Pages.DeleteItem.page authPoll userId
                (pure Pages.DeleteItem.DeleteLoading <|> deleteItem.poll)

            CreateTransaction ->
              pure $ Pages.CreateTransaction.page authPoll userId
                (pure Pages.CreateTransaction.TxPageLoading <|> txPage.poll)

            TransactionHistory ->
              pure Pages.TransactionHistory.page

          currentRoute.push (Tuple r nut)

  void $ matchesWith (parse route) matcher

  void $ runInBody
    ( fixed
        [ nav (fst <$> currentRoute.poll) authPoll pushAuth
        , D.div_ [ cycle (snd <$> currentRoute.poll) ]
        ]
    )

  -- Restore session, then mark ready and fire the initial route.
  -- This ensures tokenRef holds the real token before loadInventory runs.
  launchAff_ do
    initialRoute <- if devMode
      then pure LiveView
      else do
        mToken <- liftEffect loadToken
        case mToken of
          Nothing -> pure Login
          Just token -> do
            result <- validateSession token
            liftEffect $ case result of
              Left err -> do
                Console.warn $ "Session restore failed: " <> err
                clearToken
                pure Login
              Right sessionResp -> do
                let devUser = case findDevUserByRole sessionResp.sessionRole of
                      Just u  -> u
                      Nothing -> defaultDevUser
                pushAuth (SignedIn devUser token)
                Console.log $ "Session restored for " <> sessionResp.sessionUserName
                pure LiveView
    liftEffect do
      userId <- Ref.read tokenRef
      RegisterService.initLocalRegister
        userId
        dummyLocationId
        dummyEmployeeId
        (\register -> Console.log $ "Register pre-initialized: " <> register.registerName)
        (\err      -> Console.error $ "Register pre-init failed: " <> err)
      Ref.write true readyRef
      matcher Nothing initialRoute