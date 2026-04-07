{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module DB.Reservation (
  getAllActiveReservations,
  createInventoryReservation,
  releaseInventoryReservation,
) where

import Data.Time (UTCTime)
import Data.UUID (UUID)
import qualified Hasql.Session as Session
import Rel8

import DB.Database (DBPool, runSession)
import DB.Schema
import Types.Transaction (InventoryReservation (..))

getAllActiveReservations :: DBPool -> IO [InventoryReservation]
getAllActiveReservations pool = do
  resRows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    res <- each reservationSchema
    where_ $ resStatus res ==. lit "Reserved"
    pure res
  pure $ map toReservation resRows
  where
    toReservation row =
      InventoryReservation
        { reservationItemSku       = resItemSku row
        , reservationTransactionId = resTransactionId row
        , reservationQuantity      = fromIntegral (resQuantity row)
        , reservationStatus        = resStatus row
        }

createInventoryReservation :: DBPool -> UUID -> UUID -> UUID -> Int -> UTCTime -> IO ()
createInventoryReservation pool reservationId itemSku trxId qty now =
  runSession pool $
    Session.statement () $
      run_ $
        Rel8.insert $
          Insert
            { into       = reservationSchema
            , rows       =
                values
                  [ ReservationRow
                      { resId            = lit reservationId
                      , resItemSku       = lit itemSku
                      , resTransactionId = lit trxId
                      , resQuantity      = lit (fromIntegral qty)
                      , resStatus        = lit "Reserved"
                      , resCreatedAt     = lit now
                      }
                  ]
            , onConflict = Abort
            , returning  = NoReturning
            }

releaseInventoryReservation :: DBPool -> UUID -> IO Bool
releaseInventoryReservation pool reservationId = do
  resRows <- runSession pool $ Session.statement () $ run $ Rel8.select $ do
    r <- each reservationSchema
    where_ $
      DB.Schema.resId r ==. lit reservationId
        &&. resStatus r ==. lit "Reserved"
    pure r
  case resRows of
    [] -> pure False
    _  -> do
      runSession pool $
        Session.statement () $
          run_ $
            Rel8.update $
              Update
                { target      = reservationSchema
                , from        = pure ()
                , set         = \() row -> row {resStatus = lit "Released"}
                , updateWhere = \() row -> DB.Schema.resId row ==. lit reservationId
                , returning   = NoReturning
                }
      pure True