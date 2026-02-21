module Cheeblr.UI.Register.RegisterService where

import Prelude

import Cheeblr.API.Auth (AuthContext, getCurrentUserId)
import Cheeblr.API.Register as API
import Cheeblr.Core.Register (Register, emptyRegister)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Effect.Ref as Ref
import Types.UUID (UUID, parseUUID, genUUID)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, setItem)

----------------------------------------------------------------------
-- Handle: mutable ref holding current register state
----------------------------------------------------------------------

type RegisterHandle = Ref (Maybe Register)

newRegisterHandle :: Effect RegisterHandle
newRegisterHandle = Ref.new Nothing

getRegister :: RegisterHandle -> Effect (Maybe Register)
getRegister = Ref.read

----------------------------------------------------------------------
-- localStorage-backed register ID
----------------------------------------------------------------------

getOrCreateLocalRegisterId :: Effect UUID
getOrCreateLocalRegisterId = do
  w <- window
  storage <- localStorage w
  stored <- getItem "register_id" storage
  case stored >>= parseUUID of
    Just id -> pure id
    Nothing -> do
      newId <- genUUID
      w' <- window
      storage' <- localStorage w'
      setItem "register_id" (show newId) storage'
      pure newId

----------------------------------------------------------------------
-- Init: fetch-or-create register, then open it
----------------------------------------------------------------------

initRegister
  :: Ref AuthContext
  -> RegisterHandle
  -> UUID
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
initRegister authRef handle locationId onSuccess onError = do
  registerId <- getOrCreateLocalRegisterId
  employeeId <- getCurrentUserId authRef

  launchAff_ do
    getResult <- API.getRegister authRef registerId

    case getResult of
      Right register -> do
        liftEffect do
          Ref.write (Just register) handle
          Console.log $ "Found register: " <> register.registerName
        -- If closed, open it
        if not register.registerIsOpen then
          openAndStore authRef handle register.registerId employeeId 0
            onSuccess onError
        else
          liftEffect $ onSuccess register

      Left _ -> do
        liftEffect $ Console.log $
          "Register not found, creating: " <> show registerId

        let newReg = emptyRegister registerId locationId
        createResult <- API.createRegister authRef newReg

        case createResult of
          Right created -> do
            liftEffect $ Ref.write (Just created) handle
            openAndStore authRef handle created.registerId employeeId 0
              onSuccess onError
          Left err ->
            liftEffect $ onError ("Failed to create register: " <> err)

----------------------------------------------------------------------
-- Open register
----------------------------------------------------------------------

openRegister
  :: Ref AuthContext
  -> RegisterHandle
  -> UUID
  -> Int
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
openRegister authRef handle registerId startingCash onSuccess onError = do
  employeeId <- getCurrentUserId authRef
  launchAff_ $
    openAndStore authRef handle registerId employeeId startingCash
      onSuccess onError

-- Internal: shared open logic used by init and openRegister
openAndStore
  :: Ref AuthContext
  -> RegisterHandle
  -> UUID
  -> UUID
  -> Int
  -> (Register -> Effect Unit)
  -> (String -> Effect Unit)
  -> Aff Unit
openAndStore authRef handle registerId employeeId startingCash onSuccess onError = do
  let
    req =
      { openRegisterEmployeeId: employeeId
      , openRegisterStartingCash: startingCash
      }
  result <- API.openRegister authRef req registerId
  liftEffect case result of
    Right opened -> do
      Ref.write (Just opened) handle
      Console.log $ "Register opened: " <> opened.registerName
      onSuccess opened
    Left err ->
      onError ("Failed to open register: " <> err)

----------------------------------------------------------------------
-- Close register
----------------------------------------------------------------------

closeRegister
  :: Ref AuthContext
  -> RegisterHandle
  -> UUID
  -> Int
  -> (String -> Effect Unit)
  -> Effect Unit
closeRegister authRef handle registerId countedCash onResult = do
  employeeId <- getCurrentUserId authRef

  launchAff_ do
    let
      req =
        { closeRegisterEmployeeId: employeeId
        , closeRegisterCountedCash: countedCash
        }
    result <- API.closeRegister authRef req registerId

    liftEffect case result of
      Right closeResult -> do
        -- Update handle to reflect closed state
        mReg <- Ref.read handle
        case mReg of
          Just reg -> Ref.write (Just (reg { registerIsOpen = false })) handle
          Nothing -> pure unit

        let variance = closeResult.closeRegisterResultVariance
        let
          msg =
            if variance /= 0 then "Register closed with variance of " <> show variance
            else "Register closed, no variance"
        Console.log $ "Register closed: " <> show registerId
        onResult msg

      Left err ->
        onResult $ "Failed to close register: " <> err