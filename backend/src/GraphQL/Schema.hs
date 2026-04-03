{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GADTs #-}

{- | morpheus-graphql type definitions for the inventory GraphQL layer.
| These mirror Types.Inventory but use plain Haskell lists (not V.Vector)
| and Text UUIDs — conversion happens in GraphQL.Resolvers.
-}
module GraphQL.Schema where

import Data.Morpheus.Types (GQLType)
import Data.Text (Text)
import GHC.Generics (Generic)

-- ---------------------------------------------------------------------------
-- Output types (what the server returns)
-- ---------------------------------------------------------------------------

data StrainLineageGql = StrainLineageGql
  { thc :: Text
  , cbg :: Text
  , strain :: Text
  , creator :: Text
  , species :: Text
  , dominant_terpene :: Text
  , terpenes :: [Text]
  , lineage :: [Text]
  , leafly_url :: Text
  , img :: Text
  }
  deriving (Generic, Show)

instance GQLType StrainLineageGql

data MenuItemGql = MenuItemGql
  { sort :: Int
  , sku :: Text
  , brand :: Text
  , name :: Text
  , price :: Int -- cents
  , measure_unit :: Text
  , per_package :: Text
  , quantity :: Int
  , category :: Text
  , subcategory :: Text
  , description :: Text
  , tags :: [Text]
  , effects :: [Text]
  , strain_lineage :: StrainLineageGql
  }
  deriving (Generic, Show)

instance GQLType MenuItemGql

data MutationResponseGql = MutationResponseGql
  { success :: Bool
  , message :: Text
  }
  deriving (Generic, Show)

instance GQLType MutationResponseGql

-- ---------------------------------------------------------------------------
-- Input types (mutation arguments)
-- ---------------------------------------------------------------------------

data StrainLineageInputGql = StrainLineageInputGql
  { thc :: Text
  , cbg :: Text
  , strain :: Text
  , creator :: Text
  , species :: Text
  , dominant_terpene :: Text
  , terpenes :: [Text]
  , lineage :: [Text]
  , leafly_url :: Text
  , img :: Text
  }
  deriving (Generic, Show)

instance GQLType StrainLineageInputGql

data MenuItemInputGql = MenuItemInputGql
  { sort :: Int
  , sku :: Text
  , brand :: Text
  , name :: Text
  , price :: Int
  , measure_unit :: Text
  , per_package :: Text
  , quantity :: Int
  , category :: Text
  , subcategory :: Text
  , description :: Text
  , tags :: [Text]
  , effects :: [Text]
  , strain_lineage :: StrainLineageInputGql
  }
  deriving (Generic, Show)

instance GQLType MenuItemInputGql

-- ---------------------------------------------------------------------------
-- Argument wrappers (one per field that takes args)
-- ---------------------------------------------------------------------------

data MenuItemArgs where
  MenuItemArgs :: {sku :: Text} -> MenuItemArgs
  deriving (Generic, Show)

instance GQLType MenuItemArgs

data CreateMenuItemArgs where
  CreateMenuItemArgs ::
    {input :: MenuItemInputGql} ->
    CreateMenuItemArgs
  deriving (Generic, Show)

instance GQLType CreateMenuItemArgs

data UpdateMenuItemArgs where
  UpdateMenuItemArgs ::
    {input :: MenuItemInputGql} ->
    UpdateMenuItemArgs
  deriving (Generic, Show)

instance GQLType UpdateMenuItemArgs

data DeleteMenuItemArgs where
  DeleteMenuItemArgs :: {sku :: Text} -> DeleteMenuItemArgs
  deriving (Generic, Show)

instance GQLType DeleteMenuItemArgs
