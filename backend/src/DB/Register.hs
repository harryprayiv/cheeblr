{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module DB.Register (
  getAllRegisters,
  getRegisterById,
  createRegister,
  updateRegister,
  openRegister,
  closeRegister,
) where

import Control.Exception (throwIO)
import Data.Functor.Contravariant (contramap)
import Data.Time (getCurrentTime)
import Data.UUID (UUID)
import qualified Hasql.Session as Session
import Rel8

import API.Transaction (
  CloseRegisterRequest (..),
  CloseRegisterResult (..),
  OpenRegisterRequest (..),
  Register (..),
 )
import DB.Database (DBPool, runSession)
import DB.Schema
import Types.Location (LocationId (..), locationIdToUUID)

getAllRegisters :: DBPool -> IO [Register]
getAllRegisters pool = do
  rows <-
    runSession pool $
      Session.statement () $
        run $
          Rel8.select $
            orderBy (contramap regName asc) (each registerSchema)
  pure $ map regRowToDomain rows

getRegisterById :: DBPool -> UUID -> IO (Maybe Register)
getRegisterById pool regId = do
  rows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    r <- each registerSchema
    where_ $ DB.Schema.regId r ==. lit regId
    pure r
  case rows of
    [row] -> pure $ Just $ regRowToDomain row
    _     -> pure Nothing

createRegister :: DBPool -> Register -> IO Register
createRegister pool reg = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into       = registerSchema
            , rows       = values [regDomainToRow reg]
            , onConflict = Abort
            , returning  = NoReturning
            }
  mReg <- getRegisterById pool (registerId reg)
  case mReg of
    Just r  -> pure r
    Nothing -> throwIO $ userError "INSERT RETURNING produced no rows"

updateRegister :: DBPool -> UUID -> Register -> IO Register
updateRegister pool regId reg = do
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target      = registerSchema
            , from        = pure ()
            , set         = \() _ -> regDomainToRow reg
            , updateWhere = \() row -> DB.Schema.regId row ==. lit regId
            , returning   = NoReturning
            }
  mReg <- getRegisterById pool regId
  case mReg of
    Just r  -> pure r
    Nothing -> throwIO $ userError $ "Register not found after update: " <> show regId

openRegister :: DBPool -> UUID -> OpenRegisterRequest -> IO Register
openRegister pool regId req = do
  now <- getCurrentTime
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.update $
          Update
            { target      = registerSchema
            , from        = pure ()
            , set         = \() row ->
                row
                  { regIsOpen               = lit True
                  , regCurrentDrawerAmount  = lit $ fromIntegral (openRegisterStartingCash req)
                  , regExpectedDrawerAmount = lit $ fromIntegral (openRegisterStartingCash req)
                  , regOpenedAt             = lit (Just now)
                  , regOpenedBy             = lit (Just (openRegisterEmployeeId req))
                  }
            , updateWhere = \() row -> DB.Schema.regId row ==. lit regId
            , returning   = NoReturning
            }
  mReg <- getRegisterById pool regId
  case mReg of
    Just r  -> pure r
    Nothing -> throwIO $ userError $ "Register not found after opening: " <> show regId

closeRegister :: DBPool -> UUID -> CloseRegisterRequest -> IO CloseRegisterResult
closeRegister pool regId req = do
  mReg <- getRegisterById pool regId
  case mReg of
    Nothing  -> throwIO $ userError $ "Register not found: " <> show regId
    Just reg -> do
      now <- getCurrentTime
      let variance = registerExpectedDrawerAmount reg - closeRegisterCountedCash req
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.update $
              Update
                { target      = registerSchema
                , from        = pure ()
                , set         = \() row ->
                    row
                      { regIsOpen              = lit False
                      , regCurrentDrawerAmount = lit $ fromIntegral (closeRegisterCountedCash req)
                      , regLastTransactionTime = lit (Just now)
                      }
                , updateWhere = \() row -> DB.Schema.regId row ==. lit regId
                , returning   = NoReturning
                }
      mUpdated <- getRegisterById pool regId
      case mUpdated of
        Nothing      -> throwIO $ userError $ "Register not found after closing: " <> show regId
        Just updated ->
          pure
            CloseRegisterResult
              { closeRegisterResultRegister = updated
              , closeRegisterResultVariance = variance
              }

regDomainToRow :: Register -> RegisterRow Expr
regDomainToRow r =
  RegisterRow
    { regId                   = lit (registerId r)
    , regName                 = lit (registerName r)
    , regLocationId           = lit (locationIdToUUID (registerLocationId r))
    , regIsOpen               = lit (registerIsOpen r)
    , regCurrentDrawerAmount  = lit $ fromIntegral (registerCurrentDrawerAmount r)
    , regExpectedDrawerAmount = lit $ fromIntegral (registerExpectedDrawerAmount r)
    , regOpenedAt             = lit (registerOpenedAt r)
    , regOpenedBy             = lit (registerOpenedBy r)
    , regLastTransactionTime  = lit (registerLastTransactionTime r)
    }

regRowToDomain :: RegisterRow Result -> Register
regRowToDomain row =
  Register
    { registerId                   = DB.Schema.regId row
    , registerName                 = regName row
    , registerLocationId           = LocationId (regLocationId row)
    , registerIsOpen               = regIsOpen row
    , registerCurrentDrawerAmount  = fromIntegral (regCurrentDrawerAmount row)
    , registerExpectedDrawerAmount = fromIntegral (regExpectedDrawerAmount row)
    , registerOpenedAt             = regOpenedAt row
    , registerOpenedBy             = regOpenedBy row
    , registerLastTransactionTime  = regLastTransactionTime row
    }