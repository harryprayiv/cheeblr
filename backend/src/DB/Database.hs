-- {-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module DB.Database where

import Control.Exception (SomeException, throwIO, try)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.Functor.Contravariant (contramap)
import Data.Int (Int32)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (pack, unpack)
import Data.UUID (UUID)
import qualified Data.Vector as V
import qualified Hasql.Pool as Pool
import qualified Hasql.Session as Session
import qualified Hasql.Statement as Statement
import qualified Hasql.Decoders as Decoders
import qualified Hasql.Encoders as Encoders
import qualified Hasql.Pool.Config as PoolConfig
import qualified Hasql.Connection.Setting as ConnSetting
import qualified Hasql.Connection.Setting.Connection as ConnSetting.Conn
import qualified Hasql.Connection.Setting.Connection.Param as ConnSetting.Param
import qualified Data.Text.Encoding as TE
import Rel8
import Servant (Handler, throwError, err404)

import DB.Schema
import qualified Types.Inventory as TI
import Types.Inventory (MenuItem (..), StrainLineage (..), Inventory (..), MutationResponse (..))

data DBConfig = DBConfig
  { dbHost     :: ByteString
  , dbPort     :: Word
  , dbName     :: ByteString
  , dbUser     :: ByteString
  , dbPassword :: ByteString
  , poolSize   :: Int
  }

type DBPool = Pool.Pool

initializeDB :: DBConfig -> IO DBPool
initializeDB DBConfig{..} = do
  let connSettings =
        [ ConnSetting.connection $ ConnSetting.Conn.params
            [ ConnSetting.Param.host     (TE.decodeUtf8 dbHost)
            , ConnSetting.Param.port     (fromIntegral dbPort)
            , ConnSetting.Param.user     (TE.decodeUtf8 dbUser)
            , ConnSetting.Param.password (TE.decodeUtf8 dbPassword)
            , ConnSetting.Param.dbname   (TE.decodeUtf8 dbName)
            ]
        ]
      cfg = PoolConfig.settings
              [ PoolConfig.size (fromIntegral poolSize)
              , PoolConfig.acquisitionTimeout 30
              , PoolConfig.staticConnectionSettings connSettings
              ]
  pool <- Pool.acquire cfg
  result <- Pool.use pool (Session.statement () smokeTestStmt)
  case result of
    Left err -> throwIO $ userError $ "DB connection failed: " <> show err
    Right _  -> pure pool
  where
    smokeTestStmt :: Statement.Statement () ()
    smokeTestStmt = Statement.Statement "SELECT 1" Encoders.noParams Decoders.noResult False

runSession :: DBPool -> Session.Session a -> IO a
runSession pool session = do
  result <- Pool.use pool session
  case result of
    Left err  -> throwIO $ userError $ show err
    Right val -> pure val

ddl :: ByteString -> Statement.Statement () ()
ddl sql = Statement.Statement sql Encoders.noParams Decoders.noResult False

createTables :: DBPool -> IO ()
createTables pool = runSession pool $ do
  Session.statement () $ ddl
    "CREATE TABLE IF NOT EXISTS menu_items (\
    \  sort          INT NOT NULL,\
    \  sku           UUID PRIMARY KEY,\
    \  brand         TEXT NOT NULL,\
    \  name          TEXT NOT NULL,\
    \  price         INTEGER NOT NULL,\
    \  measure_unit  TEXT NOT NULL,\
    \  per_package   TEXT NOT NULL,\
    \  quantity      INT NOT NULL,\
    \  category      TEXT NOT NULL,\
    \  subcategory   TEXT NOT NULL,\
    \  description   TEXT NOT NULL,\
    \  tags          TEXT[] NOT NULL,\
    \  effects       TEXT[] NOT NULL\
    \)"
  Session.statement () $ ddl
    "CREATE TABLE IF NOT EXISTS strain_lineage (\
    \  sku               UUID PRIMARY KEY REFERENCES menu_items(sku),\
    \  thc               TEXT NOT NULL,\
    \  cbg               TEXT NOT NULL,\
    \  strain            TEXT NOT NULL,\
    \  creator           TEXT NOT NULL,\
    \  species           TEXT NOT NULL,\
    \  dominant_terpene  TEXT NOT NULL,\
    \  terpenes          TEXT[] NOT NULL,\
    \  lineage           TEXT[] NOT NULL,\
    \  leafly_url        TEXT NOT NULL,\
    \  img               TEXT NOT NULL\
    \)"

-- asc :: DBOrd a => Order (Expr a) — a value, not a function.
-- Use contramap to produce an Order over a larger type.
menuItemsQuery :: Query (MenuItemRow Expr, StrainLineageRow Expr)
menuItemsQuery =
  orderBy (contramap (\(mi, _) -> menuSort mi) asc) $ do
    mi <- each menuItemSchema
    sl <- each strainLineageSchema
    where_ $ menuSku mi ==. slSku sl
    pure (mi, sl)

-- aggregate1 :: Aggregator' fold i a -> Query i -> Query a
-- groupByOn / sumOn are Aggregator values; combine with Applicative.
reservedBySkuQuery :: Query (Expr UUID, Expr Int32)
reservedBySkuQuery =
  aggregate1
    ((,) <$> groupByOn resItemSku <*> sumOn resQuantity)
    ( do
        res <- each reservationSchema
        where_ $ resStatus res ==. lit "Reserved"
        pure res
    )

getAllMenuItems :: DBPool -> IO Inventory
getAllMenuItems pool = do
  -- Rel8.select :: Query a -> Statement (Query a)
  -- run :: Statement (Query exprs) -> Hasql.Statement () [a]
  rows     <- runSession pool $ Session.statement () $ run $ Rel8.select menuItemsQuery
  reserved <- runSession pool $ Session.statement () $ run $ Rel8.select reservedBySkuQuery
  let reservedMap :: Map UUID Int32 =
        Map.fromList [ (sku, qty) | (sku, qty) <- reserved ]
  let toMenuItem (mi, sl) =
        let qty = fromIntegral (menuQuantity mi)
                - fromIntegral (Map.findWithDefault 0 (menuSku mi) reservedMap)
        in rowsToMenuItem mi sl qty
  pure $ Inventory $ V.fromList $ map toMenuItem rows

insertMenuItem :: DBPool -> MenuItem -> IO ()
insertMenuItem pool item = runSession pool $ do
  Session.statement () $ run_ $ Rel8.insert $ Insert
    { into       = menuItemSchema
    , rows       = values [menuItemToRow item]
    , onConflict = Abort
    , returning  = NoReturning
    }
  Session.statement () $ run_ $ Rel8.insert $ Insert
    { into       = strainLineageSchema
    , rows       = values [strainLineageToRow (TI.sku item) (TI.strain_lineage item)]
    , onConflict = Abort
    , returning  = NoReturning
    }

updateExistingMenuItem :: DBPool -> MenuItem -> IO ()
updateExistingMenuItem pool item = runSession pool $ do
  Session.statement () $ run_ $ Rel8.update $ Update
    { target      = menuItemSchema
    , from        = pure ()
    , set         = \() row -> row
        { menuSort        = lit $ fromIntegral (TI.sort item)
        , menuBrand       = lit (TI.brand item)
        , menuName        = lit (TI.name item)
        , menuPrice       = lit $ fromIntegral (TI.price item)
        , menuMeasureUnit = lit (TI.measure_unit item)
        , menuPerPackage  = lit (TI.per_package item)
        , menuQuantity    = lit $ fromIntegral (TI.quantity item)
        , menuCategory    = lit $ pack $ show (TI.category item)
        , menuSubcategory = lit (TI.subcategory item)
        , menuDescription = lit (TI.description item)
        , menuTags        = lit $ V.toList (TI.tags item)
        , menuEffects     = lit $ V.toList (TI.effects item)
        }
    , updateWhere = \() row -> menuSku row ==. lit (TI.sku item)
    , returning   = NoReturning
    }
  let sl = TI.strain_lineage item
  Session.statement () $ run_ $ Rel8.update $ Update
    { target      = strainLineageSchema
    , from        = pure ()
    , set         = \() row -> row
        { slThc             = lit (TI.thc sl)
        , slCbg             = lit (TI.cbg sl)
        , slStrain          = lit (TI.strain sl)
        , slCreator         = lit (TI.creator sl)
        , slSpecies         = lit $ pack $ show (TI.species sl)
        , slDominantTerpene = lit (TI.dominant_terpene sl)
        , slTerpenes        = lit $ V.toList (TI.terpenes sl)
        , slLineage         = lit $ V.toList (TI.lineage sl)
        , slLeaflyUrl       = lit (TI.leafly_url sl)
        , slImg             = lit (TI.img sl)
        }
    , updateWhere = \() row -> slSku row ==. lit (TI.sku item)
    , returning   = NoReturning
    }

deleteMenuItem :: DBPool -> UUID -> Handler MutationResponse
deleteMenuItem pool uuid = do
  result <- liftIO $ try @SomeException $ runSession pool $ do
    Session.statement () $ run_ $ Rel8.delete $ Delete
      { from        = strainLineageSchema
      , using       = pure ()
      , deleteWhere = \() row -> slSku row ==. lit uuid
      , returning   = NoReturning
      }
    -- runN :: Statement () -> Hasql.Statement () Int64
    Session.statement () $ runN $ Rel8.delete $ Delete
      { from        = menuItemSchema
      , using       = pure ()
      , deleteWhere = \() row -> menuSku row ==. lit uuid
      , returning   = NoReturning
      }
  case result of
    Left e ->
      pure $ MutationResponse False (pack $ "Error deleting item: " <> show e)
    Right n ->
      if n > 0
        then pure $ MutationResponse True "Item deleted successfully"
        else throwError err404

withConnection :: DBPool -> (DBPool -> IO a) -> IO a
withConnection pool f = f pool

menuItemToRow :: MenuItem -> MenuItemRow Expr
menuItemToRow mi = MenuItemRow
  { menuSort        = lit $ fromIntegral (TI.sort mi)
  , menuSku         = lit (TI.sku mi)
  , menuBrand       = lit (TI.brand mi)
  , menuName        = lit (TI.name mi)
  , menuPrice       = lit $ fromIntegral (TI.price mi)
  , menuMeasureUnit = lit (TI.measure_unit mi)
  , menuPerPackage  = lit (TI.per_package mi)
  , menuQuantity    = lit $ fromIntegral (TI.quantity mi)
  , menuCategory    = lit $ pack $ show (TI.category mi)
  , menuSubcategory = lit (TI.subcategory mi)
  , menuDescription = lit (TI.description mi)
  , menuTags        = lit $ V.toList (TI.tags mi)
  , menuEffects     = lit $ V.toList (TI.effects mi)
  }

strainLineageToRow :: UUID -> StrainLineage -> StrainLineageRow Expr
strainLineageToRow u sl = StrainLineageRow
  { slSku             = lit u
  , slThc             = lit (TI.thc sl)
  , slCbg             = lit (TI.cbg sl)
  , slStrain          = lit (TI.strain sl)
  , slCreator         = lit (TI.creator sl)
  , slSpecies         = lit $ pack $ show (TI.species sl)
  , slDominantTerpene = lit (TI.dominant_terpene sl)
  , slTerpenes        = lit $ V.toList (TI.terpenes sl)
  , slLineage         = lit $ V.toList (TI.lineage sl)
  , slLeaflyUrl       = lit (TI.leafly_url sl)
  , slImg             = lit (TI.img sl)
  }

rowsToMenuItem :: MenuItemRow Result -> StrainLineageRow Result -> Int -> MenuItem
rowsToMenuItem mi sl availQty = MenuItem
  { TI.sort           = fromIntegral (menuSort mi)
  , TI.sku            = menuSku mi
  , TI.brand          = menuBrand mi
  , TI.name           = menuName mi
  , TI.price          = fromIntegral (menuPrice mi)
  , TI.measure_unit   = menuMeasureUnit mi
  , TI.per_package    = menuPerPackage mi
  , TI.quantity       = availQty
  , TI.category       = read $ unpack (menuCategory mi)
  , TI.subcategory    = menuSubcategory mi
  , TI.description    = menuDescription mi
  , TI.tags           = V.fromList (menuTags mi)
  , TI.effects        = V.fromList (menuEffects mi)
  , TI.strain_lineage = rowToStrainLineage sl
  }

rowToStrainLineage :: StrainLineageRow Result -> StrainLineage
rowToStrainLineage sl = StrainLineage
  { TI.thc              = slThc sl
  , TI.cbg              = slCbg sl
  , TI.strain           = slStrain sl
  , TI.creator          = slCreator sl
  , TI.species          = read $ unpack (slSpecies sl)
  , TI.dominant_terpene = slDominantTerpene sl
  , TI.terpenes         = V.fromList (slTerpenes sl)
  , TI.lineage          = V.fromList (slLineage sl)
  , TI.leafly_url       = slLeaflyUrl sl
  , TI.img              = slImg sl
  }