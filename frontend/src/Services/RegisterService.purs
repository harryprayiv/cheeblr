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
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import Types.Auth (UserRole)
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
  :: Ref AuthContext
  -> UUID  -- registerId
  -> UUID  -- locationId
  -> UUID  -- employeeId
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
createAndOpenRegister authRef registerId locationId employeeId onSuccess onError = do
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

    createResult <- API.createRegister authRef newRegister
    case createResult of
      Right register -> do
        openResult <- API.openRegister authRef
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
  :: Ref AuthContext
  -> UUID
  -> Register
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
openExistingRegister authRef employeeId register onSuccess onError = do
  launchAff_ do
    openResult <- API.openRegister authRef
      { openRegisterEmployeeId: employeeId
      , openRegisterStartingCash: 0
      }
      register.registerId
    liftEffect $ case openResult of
      Right opened -> do
        onSuccess opened
        Console.log $ "Register opened: " <> opened.registerName
      Left err -> onError ("Failed to open register: " <> err)

getOrInitLocalRegister ∷ Ref { capabilities ∷ { capCanApplyDiscount :: Boolean , capCanCloseRegister :: Boolean , capCanCreateItem :: Boolean , capCanDeleteItem :: Boolean , capCanEditItem :: Boolean , capCanManageRegisters :: Boolean , capCanManageUsers :: Boolean , capCanOpenRegister :: Boolean , capCanProcessTransaction :: Boolean , capCanRefundTransaction :: Boolean , capCanViewAllLocations :: Boolean , capCanViewCompliance :: Boolean , capCanViewInventory :: Boolean , capCanViewReports :: Boolean , capCanVoidTransaction :: Boolean } , currentUser ∷ { email :: Maybe String , locationId :: Maybe UUID , role :: UserRole , userId :: UUID , userName :: String } } → UUID → UUID → ({ registerCurrentDrawerAmount ∷ Int , registerExpectedDrawerAmount ∷ Int , registerId ∷ UUID , registerIsOpen ∷ Boolean , registerLastTransactionTime ∷ Maybe DateTime , registerLocationId ∷ UUID , registerName ∷ String , registerOpenedAt ∷ Maybe DateTime , registerOpenedBy ∷ Maybe UUID } → Effect Unit ) → (String → Effect Unit) → Effect Unit
getOrInitLocalRegister authRef locationId employeeId onSuccess onError = do
  registerId <- getOrCreateRegisterId
  launchAff_ do
    getResult <- API.getRegister authRef registerId
    case getResult of
      Right register ->
        liftEffect $ do
          Console.log $ "Using existing register: " <> register.registerName
          onSuccess register
      Left _ ->
        liftEffect $ createAndOpenRegister authRef registerId locationId employeeId onSuccess onError

initLocalRegister ∷ Ref AuthContext → UUID → UUID → (Register → Effect Unit) → (String → Effect Unit) → Effect Unit
initLocalRegister authRef locationId employeeId onSuccess onError = do
  registerId <- getOrCreateRegisterId
  launchAff_ do
    getResult <- API.getRegister authRef registerId
    case getResult of
      Right register ->
        liftEffect $ openExistingRegister authRef employeeId register onSuccess onError
      Left _ ->
        liftEffect $ createAndOpenRegister authRef registerId locationId employeeId onSuccess onError

createLocalRegister :: Ref AuthContext -> String -> UUID -> (Register -> Effect Unit) -> (String -> Effect Unit) -> Effect Unit
createLocalRegister authRef name locationId setRegister setError = do
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

    result <- API.createRegister authRef newRegister

    liftEffect case result of
      Right register -> do
        setRegister register
        Console.log $ "Register created successfully: " <> register.registerName
      Left err -> do
        setError ("Failed to create register: " <> err)

closeLocalRegister :: Ref AuthContext -> UUID -> UUID -> Int -> (String -> Effect Unit) -> Effect Unit
closeLocalRegister authRef registerId employeeId countedCash setMessage = do
  launchAff_ do
    let
      closeRequest =
        { closeRegisterEmployeeId: employeeId
        , closeRegisterCountedCash: countedCash
        }

    result <- API.closeRegister authRef closeRequest registerId

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