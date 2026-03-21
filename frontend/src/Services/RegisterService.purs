module Services.RegisterService where

import Prelude

import API.Transaction as API
import Data.DateTime (DateTime)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Services.AuthService (UserId)
import Types.Register (Register)
import Types.UUID (UUID, parseUUID, genUUID)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, setItem)

getOrCreateRegisterId :: Effect UUID
getOrCreateRegisterId = do
  w <- window
  storage <- localStorage w
  storedRegId <- getItem "register_id" storage
  case storedRegId >>= parseUUID of
    Just id -> pure id
    Nothing -> do
      newId <- genUUID
      setItem "register_id" (show newId) storage
      pure newId

createAndOpenRegister
  :: UserId
  -> UUID
  -> UUID
  -> UUID
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
createAndOpenRegister userId registerId locationId employeeId onSuccess onError = do
  launchAff_ do
    let
      newRegister =
        { registerId
        , registerName: "Register ID: " <> show registerId
        , registerLocationId: locationId
        , registerIsOpen: false
        , registerCurrentDrawerAmount: 0
        , registerExpectedDrawerAmount: 0
        , registerOpenedAt: Nothing
        , registerOpenedBy: Nothing
        , registerLastTransactionTime: Nothing
        }

    createResult <- API.createRegister userId newRegister
    case createResult of
      Right register -> do
        openResult <- API.openRegister userId
          { openRegisterEmployeeId: employeeId
          , openRegisterStartingCash: 0
          }
          register.registerId
        liftEffect $ case openResult of
          Right opened -> do
            onSuccess opened
            Console.log $ "Register created and opened: " <> opened.registerName
          Left err -> onError ("Failed to open register: " <> err)
      Left err ->
        liftEffect $ onError ("Failed to create register: " <> err)

openExistingRegister
  :: UserId
  -> UUID
  -> Register
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
openExistingRegister userId employeeId register onSuccess onError = do
  launchAff_ do
    openResult <- API.openRegister userId
      { openRegisterEmployeeId: employeeId
      , openRegisterStartingCash: 0
      }
      register.registerId
    liftEffect $ case openResult of
      Right opened -> do
        onSuccess opened
        Console.log $ "Register opened: " <> opened.registerName
      Left err -> onError ("Failed to open register: " <> err)

getOrInitLocalRegister
  :: UserId
  -> UUID
  -> UUID
  -> ({ registerCurrentDrawerAmount :: Int
     , registerExpectedDrawerAmount :: Int
     , registerId :: UUID
     , registerIsOpen :: Boolean
     , registerLastTransactionTime :: Maybe DateTime
     , registerLocationId :: UUID
     , registerName :: String
     , registerOpenedAt :: Maybe DateTime
     , registerOpenedBy :: Maybe UUID
     }
     -> Effect Unit
    )
  -> (String -> Effect Unit)
  -> Effect Unit
getOrInitLocalRegister userId locationId employeeId onSuccess onError = do
  registerId <- getOrCreateRegisterId
  launchAff_ do
    getResult <- API.getRegister userId registerId
    case getResult of
      Right register ->
        liftEffect $ do
          Console.log $ "Using existing register: " <> register.registerName
          onSuccess register
      Left _ ->
        liftEffect $ createAndOpenRegister userId registerId locationId employeeId onSuccess onError

initLocalRegister :: UserId -> UUID -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
initLocalRegister userId locationId employeeId onSuccess onError = do
  registerId <- getOrCreateRegisterId
  launchAff_ do
    getResult <- API.getRegister userId registerId
    case getResult of
      Right register ->
        liftEffect $
          if register.registerIsOpen
            then do
              Console.log $ "Register already open: " <> register.registerName
              onSuccess register
            else openExistingRegister userId employeeId register onSuccess onError
      Left _ ->
        liftEffect $ createAndOpenRegister userId registerId locationId employeeId onSuccess onError

createLocalRegister :: UserId -> String -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
createLocalRegister userId name locationId setRegister setError = do
  launchAff_ do

    _ <- liftEffect genUUID
    registerId <- liftEffect genUUID

    let
      newRegister =
        { registerId: registerId
        , registerName: name
        , registerLocationId: locationId
        , registerIsOpen: false
        , registerCurrentDrawerAmount: 0
        , registerExpectedDrawerAmount: 0
        , registerOpenedAt: Nothing
        , registerOpenedBy: Nothing
        , registerLastTransactionTime: Nothing
        }

    result <- API.createRegister userId newRegister

    liftEffect case result of
      Right register -> do
        setRegister register
        Console.log $ "Register created successfully: " <> register.registerName
      Left err -> do
        setError ("Failed to create register: " <> err)

closeLocalRegister :: UserId -> UUID -> UUID -> Int -> (String -> Effect Unit) -> Effect Unit
closeLocalRegister userId registerId employeeId countedCash setMessage = do
  launchAff_ do
    let
      closeRequest =
        { closeRegisterEmployeeId: employeeId
        , closeRegisterCountedCash: countedCash
        }

    result <- API.closeRegister userId closeRequest registerId

    liftEffect case result of
      Right closeResult -> do
        let variance = closeResult.closeRegisterResultVariance
        let
          varMsg =
            if variance /= 0 then " with variance of " <> show variance
            else " with no variance"
        setMessage $ "Register closed successfully" <> varMsg
        Console.log $ "Register closed: " <> show registerId

      Left err -> do
        setMessage $ "Failed to close register: " <> err