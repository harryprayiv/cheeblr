module Services.CurrentSale
  ( resume
  , startOn
  , startNext
  ) where

import Prelude

import API.Request (ApiError)
import API.Request as Request
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
import Web.Storage.Storage (getItem, removeItem, setItem)

-- The sale a user is working on in this browser. Its id is kept in
-- localStorage under a key that contains the user's id, so that a reload or
-- a later sign-in by the same user continues the same sale. A second user
-- of the same browser has their own key and never reads the first user's
-- sale.
--
-- Nothing in this module starts a sale on its own. A sale is started only
-- by startOn and startNext, and the pages call those from a button. Loading
-- the sale page creates no sale row on the backend.
--
-- The backend has no route that finds a user's open sale, so a sale opened
-- in another browser is not found here.

saleKey :: UUID -> String
saleKey userId = "current_sale_id:" <> show userId

remembered :: UUID -> Effect (Maybe UUID)
remembered userId = do
  storage <- window >>= localStorage
  stored <- getItem (saleKey userId) storage
  pure (stored >>= parseUUID)

remember :: UUID -> UUID -> Effect Unit
remember userId saleId = do
  storage <- window >>= localStorage
  setItem (saleKey userId) (show saleId) storage

forget :: UUID -> Effect Unit
forget userId = do
  storage <- window >>= localStorage
  removeItem (saleKey userId) storage

-- Starts a sale and remembers it under the employee the backend recorded as
-- its opener, which is the session user.
start
  :: { registerId :: UUID, locationId :: UUID }
  -> Aff (Either ApiError Sale.SaleTransaction)
start params = do
  result <- Command.startSale
    { startSaleRegisterId: params.registerId
    , startSaleLocationId: params.locationId
    }
  case result of
    Right sale -> liftEffect (remember sale.saleEmployeeId sale.saleId)
    Left _ -> pure unit
  pure result

-- The sale this user left open on this register, if there is one.
--
--   Right (Just sale)  the remembered sale passes UI.Transaction.Model.canResume
--   Right Nothing      nothing is remembered, or the remembered sale is gone
--                      (404) or can no longer be resumed; the remembered id
--                      is removed in the last two cases
--   Left err           the remembered sale could not be read for another
--                      reason; the id is kept, because the sale may still be
--                      open
resume
  :: SessionResponse
  -> Register
  -> Aff (Either ApiError (Maybe Sale.SaleTransaction))
resume user register = do
  mSaleId <- liftEffect (remembered user.sessionUserId)
  case mSaleId of
    Nothing -> pure (Right Nothing)
    Just saleId -> do
      result <- SaleApi.getSale saleId
      case result of
        Right sale
          | canResume user.sessionUserId register.registerId sale ->
              pure (Right (Just sale))
          | otherwise -> do
              liftEffect (forget user.sessionUserId)
              pure (Right Nothing)
        Left err
          | Request.isRefusal 404 err -> do
              liftEffect (forget user.sessionUserId)
              pure (Right Nothing)
          | otherwise -> pure (Left err)

-- A new sale on the given register.
startOn :: Register -> Aff (Either ApiError Sale.SaleTransaction)
startOn register =
  start
    { registerId: register.registerId
    , locationId: register.registerLocationId
    }

-- The next sale on the same register, after one has been completed.
startNext
  :: Sale.SaleTransaction
  -> Aff (Either ApiError Sale.SaleTransaction)
startNext previous =
  start
    { registerId: previous.saleRegisterId
    , locationId: previous.saleLocationId
    }