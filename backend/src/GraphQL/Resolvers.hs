{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-star-is-type #-}

module GraphQL.Resolvers
  ( rootResolver
  , Query (..)
  , Mutation (..)
  , menuItemToGql
  , strainLineageToGql
  , gqlInputToMenuItem
  , gqlInputToStrainLineage
  ) where

import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Data.Typeable (Typeable)
import Data.Morpheus.Types
import Data.Text (Text, pack)
import qualified Data.UUID as UUID
import qualified Data.Vector as V
import GHC.Generics (Generic)
import Servant.Server (runHandler)

import Auth.Simple (lookupUser)
import qualified DB.Database as DB
import DB.Database (DBPool)
import GraphQL.Schema
import qualified Types.Inventory as TI
import Types.Auth (capabilitiesForRole, auRole, UserCapabilities(..))

data Query (m :: * -> *) = Query
  { inventory :: m [MenuItemGql]
  , menuItem  :: MenuItemArgs -> m (Maybe MenuItemGql)
  } deriving Generic

instance Typeable m => GQLType (Query m)

data Mutation (m :: * -> *) = Mutation
  { createMenuItem :: CreateMenuItemArgs -> m MutationResponseGql
  , updateMenuItem :: UpdateMenuItemArgs -> m MutationResponseGql
  , deleteMenuItem :: DeleteMenuItemArgs -> m MutationResponseGql
  } deriving Generic

instance Typeable m => GQLType (Mutation m)

menuItemToGql :: TI.MenuItem -> MenuItemGql
menuItemToGql TI.MenuItem
  { TI.sort = s, TI.sku = u, TI.brand = b, TI.name = n, TI.price = p
  , TI.measure_unit = mu, TI.per_package = pp, TI.quantity = q
  , TI.category = cat, TI.subcategory = sub, TI.description = desc
  , TI.tags = ts, TI.effects = effs, TI.strain_lineage = sl
  } = MenuItemGql
  { sort           = s
  , sku            = pack $ UUID.toString u
  , brand          = b
  , name           = n
  , price          = p
  , measure_unit   = mu
  , per_package    = pp
  , quantity       = q
  , category       = pack $ show cat
  , subcategory    = sub
  , description    = desc
  , tags           = V.toList ts
  , effects        = V.toList effs
  , strain_lineage = strainLineageToGql sl
  }

strainLineageToGql :: TI.StrainLineage -> StrainLineageGql
strainLineageToGql TI.StrainLineage
  { TI.thc = a, TI.cbg = b, TI.strain = st, TI.creator = cr
  , TI.species = sp, TI.dominant_terpene = dt, TI.terpenes = tp
  , TI.lineage = ln, TI.leafly_url = lu, TI.img = im
  } = StrainLineageGql
  { thc              = a
  , cbg              = b
  , strain           = st
  , creator          = cr
  , species          = pack $ show sp
  , dominant_terpene = dt
  , terpenes         = V.toList tp
  , lineage          = V.toList ln
  , leafly_url       = lu
  , img              = im
  }

gqlInputToMenuItem :: MenuItemInputGql -> Either Text TI.MenuItem
gqlInputToMenuItem MenuItemInputGql
  { sku = skuTxt, sort = srt, brand = br, name = nm, price = pr
  , measure_unit = mu, per_package = pp, quantity = qty
  , category = cat, subcategory = sub, description = desc
  , tags = ts, effects = effs, strain_lineage = sl
  } =
  case UUID.fromText skuTxt of
    Nothing   -> Left $ "Invalid UUID: " <> skuTxt
    Just uuid -> Right $ TI.MenuItem
      { TI.sort           = srt
      , TI.sku            = uuid
      , TI.brand          = br
      , TI.name           = nm
      , TI.price          = pr
      , TI.measure_unit   = mu
      , TI.per_package    = pp
      , TI.quantity       = qty
      , TI.category       = read $ show cat
      , TI.subcategory    = sub
      , TI.description    = desc
      , TI.tags           = V.fromList ts
      , TI.effects        = V.fromList effs
      , TI.strain_lineage = gqlInputToStrainLineage sl
      }

gqlInputToStrainLineage :: StrainLineageInputGql -> TI.StrainLineage
gqlInputToStrainLineage StrainLineageInputGql
  { thc = a, cbg = b, strain = st, creator = cr, species = sp
  , dominant_terpene = dt, terpenes = tp, lineage = ln
  , leafly_url = lu, img = im
  } = TI.StrainLineage
  { TI.thc              = a
  , TI.cbg              = b
  , TI.strain           = st
  , TI.creator          = cr
  , TI.species          = read $ show sp
  , TI.dominant_terpene = dt
  , TI.terpenes         = V.fromList tp
  , TI.lineage          = V.fromList ln
  , TI.leafly_url       = lu
  , TI.img              = im
  }

resolveInventory :: DBPool -> Maybe Text -> ResolverQ () IO [MenuItemGql]
resolveInventory pool _userId = do
  TI.Inventory items <- liftIO $ DB.getAllMenuItems pool
  pure $ map menuItemToGql (V.toList items)

resolveMenuItem :: DBPool -> Maybe Text -> MenuItemArgs -> ResolverQ () IO (Maybe MenuItemGql)
resolveMenuItem pool _userId MenuItemArgs { sku = skuTxt } = do
  TI.Inventory items <- liftIO $ DB.getAllMenuItems pool
  pure $ case UUID.fromText skuTxt of
    Nothing -> Nothing
    Just u  -> menuItemToGql <$> V.find (\m -> TI.sku m == u) items

resolveCreateMenuItem :: DBPool -> Maybe Text -> CreateMenuItemArgs -> ResolverM () IO MutationResponseGql
resolveCreateMenuItem pool userId CreateMenuItemArgs { input = inp } = do
  let user = lookupUser userId
      caps = capabilitiesForRole (auRole user)
  if not (capCanCreateItem caps)
    then pure $ MutationResponseGql False "Forbidden: cannot create items"
    else case gqlInputToMenuItem inp of
      Left err   -> pure $ MutationResponseGql False err
      Right item -> do
        result <- liftIO (try (DB.insertMenuItem pool item) :: IO (Either SomeException ()))
        pure $ case result of
          Right _ -> MutationResponseGql True "Item created successfully"
          Left e  -> MutationResponseGql False (pack $ show e)

resolveUpdateMenuItem :: DBPool -> Maybe Text -> UpdateMenuItemArgs -> ResolverM () IO MutationResponseGql
resolveUpdateMenuItem pool userId UpdateMenuItemArgs { input = inp } = do
  let user = lookupUser userId
      caps = capabilitiesForRole (auRole user)
  if not (capCanEditItem caps)
    then pure $ MutationResponseGql False "Forbidden: cannot edit items"
    else case gqlInputToMenuItem inp of
      Left err   -> pure $ MutationResponseGql False err
      Right item -> do
        result <- liftIO (try (DB.updateExistingMenuItem pool item) :: IO (Either SomeException ()))
        pure $ case result of
          Right _ -> MutationResponseGql True "Item updated successfully"
          Left e  -> MutationResponseGql False (pack $ show e)

resolveDeleteMenuItem :: DBPool -> Maybe Text -> DeleteMenuItemArgs -> ResolverM () IO MutationResponseGql
resolveDeleteMenuItem pool userId DeleteMenuItemArgs { sku = skuTxt } = do
  let user = lookupUser userId
      caps = capabilitiesForRole (auRole user)
  if not (capCanDeleteItem caps)
    then pure $ MutationResponseGql False "Forbidden: cannot delete items"
    else case UUID.fromText skuTxt of
      Nothing   -> pure $ MutationResponseGql False "Invalid UUID"
      Just uuid -> do
        result <- liftIO $ try (DB.deleteMenuItem pool uuid)
        pure $ case (result :: Either SomeException TI.MutationResponse) of
          Right mr -> MutationResponseGql (TI.success mr) (TI.message mr)
          Left e   -> MutationResponseGql False (pack $ show e)

rootResolver :: DBPool -> Maybe Text -> RootResolver IO () Query Mutation Undefined
rootResolver pool userId = RootResolver
  { queryResolver = Query
      { inventory = resolveInventory pool userId
      , menuItem  = resolveMenuItem pool userId
      }
  , mutationResolver = Mutation
      { createMenuItem = resolveCreateMenuItem pool userId
      , updateMenuItem = resolveUpdateMenuItem pool userId
      , deleteMenuItem = resolveDeleteMenuItem pool userId
      }
  , subscriptionResolver = undefined
  }