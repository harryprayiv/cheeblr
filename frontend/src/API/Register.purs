module API.Register where

import Prelude

import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Services.AuthService (UserId)
import Types.Register
  ( CloseRegisterRequest
  , CloseRegisterResult
  , OpenRegisterRequest
  , Register
  )
import Types.UUID (UUID)

getRegister :: UserId -> UUID -> Aff (Either String Register)
getRegister userId registerId =
  Request.authGet userId ("/register/" <> show registerId)

createRegister :: UserId -> Register -> Aff (Either String Register)
createRegister userId register =
  Request.authPost userId "/register" register

openRegister
  :: UserId -> OpenRegisterRequest -> UUID -> Aff (Either String Register)
openRegister userId request registerId =
  Request.authPost userId ("/register/open/" <> show registerId) request

closeRegister
  :: UserId
  -> CloseRegisterRequest
  -> UUID
  -> Aff (Either String CloseRegisterResult)
closeRegister userId request registerId =
  Request.authPost userId ("/register/close/" <> show registerId) request