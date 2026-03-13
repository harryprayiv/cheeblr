{-# LANGUAGE OverloadedStrings #-}

module Service.Register
  ( openRegister
  , closeRegister
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Pool (Pool)
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import qualified Data.ByteString.Lazy as LBS
import Database.PostgreSQL.Simple (Connection)
import Servant

import qualified DB.Transaction as DB
import State.RegisterMachine
import API.Transaction
  ( Register (..)
  , OpenRegisterRequest (..)
  , CloseRegisterRequest (..)
  , CloseRegisterResult (..)
  )

-- ── Helpers ──────────────────────────────────────────────────────────────────

loadReg :: Pool Connection -> UUID -> Handler (Register, SomeRegState)
loadReg pool regId = do
  maybeReg <- liftIO $ DB.getRegisterById pool regId
  case maybeReg of
    Nothing  -> throwError err404 { errBody = "Register not found" }
    Just reg -> pure (reg, fromRegister reg)

guardRegEvent :: RegEvent -> Handler ()
guardRegEvent (InvalidRegCommand msg) =
  throwError err409 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
guardRegEvent _ = pure ()

-- ── Handlers ─────────────────────────────────────────────────────────────────

openRegister :: Pool Connection -> UUID -> OpenRegisterRequest -> Handler Register
openRegister pool regId req = do
  (_, someState) <- loadReg pool regId
  let cmd = OpenRegCmd (openRegisterEmployeeId req) (openRegisterStartingCash req)
  let (evt, _) = runRegCommand someState cmd
  guardRegEvent evt
  liftIO $ DB.openRegister pool regId req

closeRegister :: Pool Connection -> UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
closeRegister pool regId req = do
  (_, someState) <- loadReg pool regId
  let cmd = CloseRegCmd (closeRegisterEmployeeId req) (closeRegisterCountedCash req)
  let (evt, _) = runRegCommand someState cmd
  guardRegEvent evt
  liftIO $ DB.closeRegister pool regId req