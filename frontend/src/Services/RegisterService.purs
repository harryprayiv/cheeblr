module Services.RegisterService where

import Prelude

import API.Transaction as API
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Types.System (Register)
import Types.UUID (UUID, parseUUID)
import Utils.UUIDGen (genUUID)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, setItem)

initializeRegister
  :: (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
initializeRegister setRegister setError = do

  w <- window
  storage <- localStorage w
  storedRegId <- getItem "register_id" storage


  registerId <- case storedRegId >>= parseUUID of
    Just id -> pure id
    Nothing -> do

      newId <- genUUID
      w' <- window
      storage' <- localStorage w'
      setItem "register_id" (show newId) storage'
      pure newId


  launchAff_ do
    employeeId <- liftEffect genUUID


    let
      openRequest =
        { openRegisterEmployeeId: employeeId
        , openRegisterStartingCash: 0
        }

    result <- API.openRegister openRequest registerId

    liftEffect case result of
      Right register -> do
        setRegister register
        Console.log $ "Register opened successfully: " <> register.registerName
      Left err -> do
        setError ("Failed to open register: " <> err)

createRegister
  :: String
  -> UUID
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
createRegister name locationId setRegister setError = do
  launchAff_ do
    -- Fixed warning: Using "_" to ignore the unused employeeId
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

    result <- API.createRegister newRegister

    liftEffect case result of
      Right register -> do
        setRegister register
        Console.log $ "Register created successfully: " <> register.registerName
      Left err -> do
        setError ("Failed to create register: " <> err)

closeRegister :: UUID -> UUID -> Int -> (String -> Effect Unit) -> Effect Unit
closeRegister registerId employeeId countedCash setMessage = do
  launchAff_ do
    let
      closeRequest =
        { closeRegisterEmployeeId: employeeId
        , closeRegisterCountedCash: countedCash
        }

    result <- API.closeRegister closeRequest registerId

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