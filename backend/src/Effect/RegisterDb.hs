{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Effect.RegisterDb (
  RegisterDb (..),
  getAllRegisters,
  getRegistersByLocation,
  getRegisterById,
  createRegister,
  updateRegister,
  openRegisterDb,
  closeRegisterDb,
  runRegisterDbIO,
  RegStore (..),
  emptyRegStore,
  runRegisterDbPure,
) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.UUID (UUID)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.Error.Static (Error, throwError)
import Effectful.State.Static.Local
import Servant (ServerError, err404)

import API.Transaction (
  CloseRegisterRequest (..),
  CloseRegisterResult (..),
  OpenRegisterRequest (..),
  Register (..),
 )
import DB.Database (DBPool)
import qualified DB.Register as DBR
import Types.Location (LocationId)

data RegisterDb :: Effect where
  GetAllRegisters        :: RegisterDb m [Register]
  GetRegistersByLocation :: LocationId -> RegisterDb m [Register]
  GetRegisterById        :: UUID -> RegisterDb m (Maybe Register)
  CreateRegister         :: Register -> RegisterDb m Register
  UpdateRegister         :: UUID -> Register -> RegisterDb m Register
  OpenRegisterDb         :: UUID -> OpenRegisterRequest -> RegisterDb m Register
  CloseRegisterDb        :: UUID -> CloseRegisterRequest -> RegisterDb m CloseRegisterResult

type instance DispatchOf RegisterDb = Dynamic

getAllRegisters :: (RegisterDb :> es) => Eff es [Register]
getAllRegisters = send GetAllRegisters

getRegistersByLocation :: (RegisterDb :> es) => LocationId -> Eff es [Register]
getRegistersByLocation = send . GetRegistersByLocation

getRegisterById :: (RegisterDb :> es) => UUID -> Eff es (Maybe Register)
getRegisterById = send . GetRegisterById

createRegister :: (RegisterDb :> es) => Register -> Eff es Register
createRegister = send . CreateRegister

updateRegister :: (RegisterDb :> es) => UUID -> Register -> Eff es Register
updateRegister regId reg = send (UpdateRegister regId reg)

openRegisterDb :: (RegisterDb :> es) => UUID -> OpenRegisterRequest -> Eff es Register
openRegisterDb regId req = send (OpenRegisterDb regId req)

closeRegisterDb :: (RegisterDb :> es) => UUID -> CloseRegisterRequest -> Eff es CloseRegisterResult
closeRegisterDb regId req = send (CloseRegisterDb regId req)

runRegisterDbIO :: (IOE :> es) => DBPool -> Eff (RegisterDb : es) a -> Eff es a
runRegisterDbIO pool = interpret $ \_ -> \case
  GetAllRegisters             -> liftIO $ DBR.getAllRegisters pool
  GetRegistersByLocation locId -> liftIO $ do
    regs <- DBR.getAllRegisters pool
    pure (filter (\r -> registerLocationId r == locId) regs)
  GetRegisterById u      -> liftIO $ DBR.getRegisterById pool u
  CreateRegister r       -> liftIO $ DBR.createRegister pool r
  UpdateRegister u r     -> liftIO $ DBR.updateRegister pool u r
  OpenRegisterDb u req   -> liftIO $ DBR.openRegister pool u req
  CloseRegisterDb u req  -> liftIO $ DBR.closeRegister pool u req

newtype RegStore = RegStore
  { rsRegisters :: Map UUID Register
  }
  deriving (Show, Eq)

emptyRegStore :: RegStore
emptyRegStore = RegStore Map.empty

-- | Pure interpreter for tests.
-- Previously used `error` on missing register IDs; now uses `throwError err404`
-- so test stacks can handle the failure without crashing the process.
runRegisterDbPure ::
  (Error ServerError :> es) =>
  RegStore ->
  Eff (RegisterDb : es) a ->
  Eff es (a, RegStore)
runRegisterDbPure initial = reinterpret (runState initial) $ \_ -> \case
  GetAllRegisters ->
    gets @RegStore (Map.elems . rsRegisters)
  GetRegistersByLocation locId ->
    gets @RegStore (filter (\r -> registerLocationId r == locId) . Map.elems . rsRegisters)
  GetRegisterById regId ->
    gets @RegStore (Map.lookup regId . rsRegisters)
  CreateRegister reg -> do
    modify @RegStore $ \st ->
      st {rsRegisters = Map.insert (registerId reg) reg (rsRegisters st)}
    pure reg
  UpdateRegister regId reg -> do
    modify @RegStore $ \st ->
      st {rsRegisters = Map.insert regId reg (rsRegisters st)}
    pure reg
  OpenRegisterDb regId req -> do
    st <- get @RegStore
    case Map.lookup regId (rsRegisters st) of
      Nothing  -> throwError err404
      Just reg -> do
        let opened =
              reg
                { registerIsOpen               = True
                , registerCurrentDrawerAmount  = openRegisterStartingCash req
                , registerExpectedDrawerAmount = openRegisterStartingCash req
                , registerOpenedBy             = Just (openRegisterEmployeeId req)
                }
        put @RegStore st {rsRegisters = Map.insert regId opened (rsRegisters st)}
        pure opened
  CloseRegisterDb regId req -> do
    st <- get @RegStore
    case Map.lookup regId (rsRegisters st) of
      Nothing  -> throwError err404
      Just reg -> do
        let
          counted  = closeRegisterCountedCash req
          variance = registerExpectedDrawerAmount reg - counted
          closed   = reg {registerIsOpen = False, registerCurrentDrawerAmount = counted}
        put @RegStore st {rsRegisters = Map.insert regId closed (rsRegisters st)}
        pure
          CloseRegisterResult
            { closeRegisterResultRegister = closed
            , closeRegisterResultVariance = variance
            }