module Cheeblr.API.Register where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.AuthRequest as AR
import Cheeblr.Core.Register (Register, OpenRegisterRequest, CloseRegisterRequest, CloseRegisterResult)
import Data.Either (Either)
import Effect.Aff (Aff)
import Effect.Ref (Ref)
import Types.UUID (UUID)

getRegister :: Ref AuthContext -> UUID -> Aff (Either String Register)
getRegister ref registerId =
  AR.authGet ref ("register/" <> show registerId)

createRegister :: Ref AuthContext -> Register -> Aff (Either String Register)
createRegister ref register =
  AR.authPost ref "register" register

openRegister :: Ref AuthContext -> OpenRegisterRequest -> UUID -> Aff (Either String Register)
openRegister ref request registerId =
  AR.authPost ref ("register/" <> show registerId <> "/open") request

closeRegister :: Ref AuthContext -> CloseRegisterRequest -> UUID -> Aff (Either String CloseRegisterResult)
closeRegister ref request registerId =
  AR.authPost ref ("register/" <> show registerId <> "/close") request