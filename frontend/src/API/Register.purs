module API.Register where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Types.Register (CloseRegisterRequest, CloseRegisterResult, OpenRegisterRequest, Register)
import Types.UUID (UUID)

getRegisters :: Aff (Either ApiError (Array Register))
getRegisters = Request.get "/register"

-- Answers 404 "Register not found" for an unknown id.
getRegister :: UUID -> Aff (Either ApiError Register)
getRegister registerId = Request.get ("/register/" <> show registerId)

-- Owner decision: only a manager or an admin may create a register. The
-- backend does not enforce that yet. The only caller is the create form on
-- Pages.Registers, which is shown with capCanManageRegisters only.
createRegister :: Register -> Aff (Either ApiError Register)
createRegister register = Request.post "/register" register

-- Needs capCanOpenRegister (403). Answers 409 when the register is already
-- open.
openRegister :: UUID -> OpenRegisterRequest -> Aff (Either ApiError Register)
openRegister registerId req =
  Request.post ("/register/open/" <> show registerId) req

-- Needs capCanCloseRegister (403). Answers 409 when the register is already
-- closed. The result carries the variance: expected drawer amount minus the
-- counted cash.
closeRegister
  :: UUID -> CloseRegisterRequest -> Aff (Either ApiError CloseRegisterResult)
closeRegister registerId req =
  Request.post ("/register/close/" <> show registerId) req
