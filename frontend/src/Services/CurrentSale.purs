module Services.CurrentSale
  ( resumeOrStart
  , startNext
  ) where

import Prelude

import API.Request (ApiError)
import API.Sale as SaleApi
import API.SaleCommand as Command
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Types.Register (Register)
import Types.Session (SessionResponse)
import Types.Transaction.Sale as Sale
import Types.UUID (UUID, parseUUID)
import UI.Transaction.Model (canResume)
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage (getItem, setItem)

-- The sale this browser is working on. Its id is kept in localStorage so
-- that a reload or a second visit to the sale page continues the same sale.
-- Without this every visit started a new sale and left an empty sale row on
-- the backend.
--
-- The backend has no route that finds a user's open sale, so a sale opened
-- in another browser is not found here.

saleKey :: String
saleKey = "current_sale_id"

remembered :: Effect (Maybe UUID)
remembered = do
  storage <- window >>= localStorage
  stored <- getItem saleKey storage
  pure (stored >>= parseUUID)

remember :: UUID -> Effect Unit
remember saleId = do
  storage <- window >>= localStorage
  setItem saleKey (show saleId) storage

-- Starts a sale and remembers it. The backend records the session user as
-- the opener whatever employee id is sent.
start
  :: { employeeId :: UUID, registerId :: UUID, locationId :: UUID }
  -> Aff (Either ApiError Sale.SaleTransaction)
start params = do
  result <- Command.startSale
    { startSaleEmployeeId: params.employeeId
    , startSaleRegisterId: params.registerId
    , startSaleLocationId: params.locationId
    }
  case result of
    Right sale -> liftEffect (remember sale.saleId)
    Left _ -> pure unit
  pure result

-- Continues the remembered sale when UI.Transaction.Model.canResume allows
-- it. Otherwise starts a new one. A remembered sale that cannot be read (it
-- is gone, or the request failed) also leads to a new sale.
resumeOrStart
  :: SessionResponse
  -> Register
  -> Aff (Either ApiError Sale.SaleTransaction)
resumeOrStart user register = do
  mSaleId <- liftEffect remembered
  previous <- case mSaleId of
    Nothing -> pure Nothing
    Just saleId -> do
      result <- SaleApi.getSale saleId
      pure case result of
        Right sale | canResume user.sessionUserId register.registerId sale ->
          Just sale
        _ -> Nothing
  case previous of
    Just sale -> pure (Right sale)
    Nothing ->
      start
        { employeeId: user.sessionUserId
        , registerId: register.registerId
        , locationId: register.registerLocationId
        }

-- The next sale on the same register, after one has been completed.
startNext
  :: Sale.SaleTransaction
  -> Aff (Either ApiError Sale.SaleTransaction)
startNext previous =
  start
    { employeeId: previous.saleEmployeeId
    , registerId: previous.saleRegisterId
    , locationId: previous.saleLocationId
    }
