module GraphQL.Schema where

import Data.Maybe (Maybe)
import GraphQL.Client.Args (NotNull)
import Type.Data.List (Nil', List')
import Type.Proxy (Proxy)

type UUIDString = String

type StrainLineageGql =
  { thc              :: String
  , cbg              :: String
  , strain           :: String
  , creator          :: String
  , species          :: String
  , dominant_terpene :: String
  , terpenes         :: Array String
  , lineage          :: Array String
  , leafly_url       :: String
  , img              :: String
  }

type MenuItemGql =
  { sort           :: Int
  , sku            :: UUIDString
  , brand          :: String
  , name           :: String
  , price          :: Int
  , measure_unit   :: String
  , per_package    :: String
  , quantity       :: Int
  , category       :: String
  , subcategory    :: String
  , description    :: String
  , tags           :: Array String
  , effects        :: Array String
  , strain_lineage :: StrainLineageGql
  }

type MutationResponseGql =
  { success :: Boolean
  , message :: String
  }

type StrainLineageInputGql =
  { thc              :: String
  , cbg              :: String
  , strain           :: String
  , creator          :: String
  , species          :: String
  , dominant_terpene :: String
  , terpenes         :: Array String
  , lineage          :: Array String
  , leafly_url       :: String
  , img              :: String
  }

type MenuItemInputGql =
  { sort           :: Int
  , sku            :: UUIDString
  , brand          :: String
  , name           :: String
  , price          :: Int
  , measure_unit   :: String
  , per_package    :: String
  , quantity       :: Int
  , category       :: String
  , subcategory    :: String
  , description    :: String
  , tags           :: Array String
  , effects        :: Array String
  , strain_lineage :: StrainLineageInputGql
  }

type QuerySchema =
  { inventory :: Array MenuItemGql
  , menuItem  :: { sku :: NotNull UUIDString } -> Maybe MenuItemGql
  }

type MutationSchema =
  { createMenuItem :: { input :: NotNull MenuItemInputGql } -> MutationResponseGql
  , updateMenuItem :: { input :: NotNull MenuItemInputGql } -> MutationResponseGql
  , deleteMenuItem :: { sku   :: NotNull UUIDString       } -> MutationResponseGql
  }

type AppSchema =
  { directives :: Proxy (Nil' :: List' Type)
  , query      :: QuerySchema
  , mutation   :: MutationSchema
  }