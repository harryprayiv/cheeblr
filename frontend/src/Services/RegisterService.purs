module Services.RegisterService where

import Prelude

import API.Transaction as API
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Types.Register (Register)
import Types.UUID (UUID, parseUUID)
import Utils.UUIDGen (genUUID)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, setItem)

getOrInitLocalRegister :: UUID -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
getOrInitLocalRegister locationId employeeId setRegister setError = do
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
    -- Try to get existing register first
    getResult <- API.getRegister registerId

    case getResult of
      -- Register exists, use it
      Right register -> do
        liftEffect $ Console.log $ "Using existing register: " <>
          register.registerName
        liftEffect $ setRegister register

      -- Register doesn't exist, create a new one
      Left _ -> do
        liftEffect $ Console.log $
          "Register not found, creating a new one with ID: " <> show registerId

        -- locationId <- liftEffect genUUID
        -- employeeId <- liftEffect genUUID

        let
          newRegister =
            { registerId: registerId
            , registerName: "Register #" <> show registerId
            , registerLocationId: locationId
            , registerIsOpen: false
            , registerCurrentDrawerAmount: 0
            , registerExpectedDrawerAmount: 0
            , registerOpenedAt: Nothing
            , registerOpenedBy: Nothing
            , registerLastTransactionTime: Nothing
            }

        createResult <- API.createRegister newRegister

        case createResult of
          Right register -> do
            let
              openRequest =
                { openRegisterEmployeeId: employeeId
                , openRegisterStartingCash: 0
                }

            openResult <- API.openRegister openRequest register.registerId

            liftEffect $ case openResult of
              Right openedRegister -> do
                setRegister openedRegister
                Console.log $ "New register created and opened successfully: "
                  <> openedRegister.registerName
              Left openErr -> do
                setError ("Failed to open new register: " <> openErr)

          Left createErr -> do
            liftEffect $ setError ("Failed to create register: " <> createErr)

-- create a register if it doesn't exist
initLocalRegister :: UUID -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
initLocalRegister locationId employeeId setRegister setError = do

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
    -- locationId <- liftEffect genUUID
    -- employeeId <- liftEffect genUUID

    -- First try to get the register - if it exists, we'll open it
    getResult <- API.getRegister registerId

    case getResult of
      -- Register exists, open it
      Right register -> do
        let
          openRequest =
            { openRegisterEmployeeId: employeeId
            , openRegisterStartingCash: 0
            }

        openResult <- API.openRegister openRequest register.registerId

        liftEffect $ case openResult of
          Right openedRegister -> do
            setRegister openedRegister
            Console.log $ "Register opened successfully: " <>
              openedRegister.registerName
          Left err -> do
            setError ("Failed to open register: " <> err)

      -- Register doesn't exist, create it first
      Left _ -> do
        liftEffect $ Console.log $
          "Register not found, creating a new one with ID: " <> show registerId

        let
          newRegister =
            { registerId: registerId
            , registerName: "Register #" <> show registerId
            , registerLocationId: locationId
            , registerIsOpen: false
            , registerCurrentDrawerAmount: 0
            , registerExpectedDrawerAmount: 0
            , registerOpenedAt: Nothing
            , registerOpenedBy: Nothing
            , registerLastTransactionTime: Nothing
            }

        createResult <- API.createRegister newRegister

        case createResult of
          Right register -> do
            -- Now open the newly created register
            let
              openRequest =
                { openRegisterEmployeeId: employeeId
                , openRegisterStartingCash: 0
                }

            openResult <- API.openRegister openRequest register.registerId

            liftEffect $ case openResult of
              Right openedRegister -> do
                setRegister openedRegister
                Console.log $ "New register created and opened successfully: "
                  <> openedRegister.registerName
              Left openErr -> do
                setError ("Failed to open new register: " <> openErr)

          Left createErr -> do
            liftEffect $ setError ("Failed to create register: " <> createErr)


-- || local Register creation
createLocalRegister :: String -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
createLocalRegister name locationId setRegister setError = do
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

    result <- API.createRegister newRegister

    liftEffect case result of
      Right register -> do
        setRegister register
        Console.log $ "Register created successfully: " <> register.registerName
      Left err -> do
        setError ("Failed to create register: " <> err)

closeLocalRegister :: UUID -> UUID -> Int -> (String -> Effect Unit) -> Effect Unit
closeLocalRegister registerId employeeId countedCash setMessage = do
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