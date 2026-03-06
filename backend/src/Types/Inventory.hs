{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Types.Inventory where

import Data.Aeson (ToJSON(toJSON), FromJSON(parseJSON))
import Data.Text (Text)
import Data.UUID (UUID)
import qualified Data.Vector as V
import Database.PostgreSQL.Simple.FromRow (FromRow (..), field)
import Database.PostgreSQL.Simple.ToField (ToField (..))
import Database.PostgreSQL.Simple.ToRow (ToRow (..))
import Database.PostgreSQL.Simple.Types (PGArray (..))
import GHC.Generics (Generic)

data Species
  = Indica
  | IndicaDominantHybrid
  | Hybrid
  | SativaDominantHybrid
  | Sativa
  deriving (Show, Eq, Ord, Generic, FromJSON, ToJSON, Read)

data ItemCategory
  = Flower
  | PreRolls
  | Vaporizers
  | Edibles
  | Drinks
  | Concentrates
  | Topicals
  | Tinctures
  | Accessories
  deriving (Show, Eq, Ord, Generic, FromJSON, ToJSON, Read)

data StrainLineage = StrainLineage
  { thc             :: Text
  , cbg             :: Text
  , strain          :: Text
  , creator         :: Text
  , species         :: Species
  , dominant_terpene :: Text
  , terpenes        :: V.Vector Text
  , lineage         :: V.Vector Text
  , leafly_url      :: Text
  , img             :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON StrainLineage
instance FromJSON StrainLineage

data MenuItem = MenuItem
  { sort         :: Int
  , sku          :: UUID
  , brand        :: Text
  , name         :: Text
  , price        :: Int
  , measure_unit :: Text
  , per_package  :: Text
  , quantity     :: Int
  , category     :: ItemCategory
  , subcategory  :: Text
  , description  :: Text
  , tags         :: V.Vector Text
  , effects      :: V.Vector Text
  , strain_lineage :: StrainLineage
  } deriving (Show, Eq, Generic)

instance ToJSON MenuItem
instance FromJSON MenuItem

instance ToRow MenuItem where
  toRow MenuItem {..} =
    [ toField sort
    , toField sku
    , toField brand
    , toField name
    , toField price
    , toField measure_unit
    , toField per_package
    , toField quantity
    , toField (show category)
    , toField subcategory
    , toField description
    , toField (PGArray $ V.toList tags)
    , toField (PGArray $ V.toList effects)
    ]

instance FromRow MenuItem where
  fromRow =
    MenuItem
      <$> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> (read <$> field)
      <*> field
      <*> field
      <*> (V.fromList . fromPGArray <$> field)
      <*> (V.fromList . fromPGArray <$> field)
      <*> ( StrainLineage
              <$> field
              <*> field
              <*> field
              <*> field
              <*> (read <$> field)
              <*> field
              <*> (V.fromList . fromPGArray <$> field)
              <*> (V.fromList . fromPGArray <$> field)
              <*> field
              <*> field
          )

-- | GET /inventory — serialises as a plain JSON array.
newtype Inventory = Inventory
  { items :: V.Vector MenuItem
  } deriving (Show, Eq, Generic)

instance ToJSON Inventory where
  toJSON (Inventory inv) = toJSON inv

instance FromJSON Inventory where
  parseJSON v = Inventory <$> parseJSON v

-- | Returned by POST / PUT / DELETE /inventory.
data MutationResponse = MutationResponse
  { success :: Bool
  , message :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON MutationResponse
instance FromJSON MutationResponse