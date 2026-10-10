module Services.RegisterService
  ( chosenRegisterId
  , chooseRegister
  , newRegister
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Types.Register (Register)
import Types.UUID (UUID, genUUID, parseUUID)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, setItem)

-- Which register this browser sells on. The choice is made on the registers
-- page and kept in localStorage under the key the app has always used, so a
-- browser that already has a register keeps it.
--
-- Nothing in this module creates or opens a register on the backend. Both
-- are deliberate actions on the registers page.

registerKey :: String
registerKey = "register_id"

chosenRegisterId :: Effect (Maybe UUID)
chosenRegisterId = do
  storage <- window >>= localStorage
  stored <- getItem registerKey storage
  pure (stored >>= parseUUID)

chooseRegister :: UUID -> Effect Unit
chooseRegister registerId = do
  storage <- window >>= localStorage
  setItem registerKey (show registerId) storage

-- A closed register with a fresh id, ready for API.Register.createRegister.
newRegister :: String -> UUID -> Effect Register
newRegister name locationId = do
  registerId <- genUUID
  pure
    { registerId
    , registerName: name
    , registerLocationId: locationId
    , registerIsOpen: false
    , registerCurrentDrawerAmount: 0
    , registerExpectedDrawerAmount: 0
    , registerOpenedAt: Nothing
    , registerOpenedBy: Nothing
    , registerLastTransactionTime: Nothing
    }
