{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Service.Register
  ( openRegister
  , closeRegister
  ) where

import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import Effectful
import Effectful.Error.Static
import Servant (ServerError(..), err404, err409)

import API.Transaction
  ( CloseRegisterRequest (..)
  , CloseRegisterResult
  , OpenRegisterRequest (..)
  , Register
  )
import Effect.RegisterDb
import State.RegisterMachine

loadReg
  :: (RegisterDb :> es, Error ServerError :> es)
  => UUID
  -> Eff es (Register, SomeRegState)
loadReg regId = do
  maybeReg <- getRegisterById regId
  case maybeReg of
    Nothing  -> throwError err404 { errBody = "Register not found" }
    Just reg -> pure (reg, fromRegister reg)

guardRegEvent :: Error ServerError :> es => RegEvent -> Eff es ()
guardRegEvent (InvalidRegCommand msg) =
  throwError err409 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
guardRegEvent _ = pure ()

openRegister
  :: (RegisterDb :> es, Error ServerError :> es)
  => UUID
  -> OpenRegisterRequest
  -> Eff es Register
openRegister regId req = do
  (_, someState) <- loadReg regId
  let cmd      = OpenRegCmd (openRegisterEmployeeId req) (openRegisterStartingCash req)
      (evt, _) = runRegCommand someState cmd
  guardRegEvent evt
  openRegisterDb regId req

closeRegister
  :: (RegisterDb :> es, Error ServerError :> es)
  => UUID
  -> CloseRegisterRequest
  -> Eff es CloseRegisterResult
closeRegister regId req = do
  (_, someState) <- loadReg regId
  let cmd      = CloseRegCmd (closeRegisterEmployeeId req) (closeRegisterCountedCash req)
      (evt, _) = runRegCommand someState cmd
  guardRegEvent evt
  closeRegisterDb regId req