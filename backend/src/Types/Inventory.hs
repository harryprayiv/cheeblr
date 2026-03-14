{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}

module Types.Inventory where

import Data.Aeson (ToJSON(toJSON), FromJSON(parseJSON))
import Data.OpenApi (ToSchema)
import Data.Text (Text)
import Data.UUID (UUID)
import qualified Data.Vector as V
import GHC.Generics (Generic)

data Species
  = Indica
  | IndicaDominantHybrid
  | Hybrid
  | SativaDominantHybrid
  | Sativa
  deriving (Show, Eq, Ord, Generic, FromJSON, ToJSON, ToSchema, Read)

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
  deriving (Show, Eq, Ord, Generic, FromJSON, ToJSON, ToSchema, Read)

data StrainLineage = StrainLineage
  { thc              :: Text
  , cbg              :: Text
  , strain           :: Text
  , creator          :: Text
  , species          :: Species
  , dominant_terpene :: Text
  , terpenes         :: V.Vector Text
  , lineage          :: V.Vector Text
  , leafly_url       :: Text
  , img              :: Text
  } deriving (Show, Eq, Generic, ToSchema)

instance ToJSON StrainLineage
instance FromJSON StrainLineage

data MenuItem = MenuItem
  { sort           :: Int
  , sku            :: UUID
  , brand          :: Text
  , name           :: Text
  , price          :: Int
  , measure_unit   :: Text
  , per_package    :: Text
  , quantity       :: Int
  , category       :: ItemCategory
  , subcategory    :: Text
  , description    :: Text
  , tags           :: V.Vector Text
  , effects        :: V.Vector Text
  , strain_lineage :: StrainLineage
  } deriving (Show, Eq, Generic, ToJSON, FromJSON, ToSchema)

newtype Inventory = Inventory
  { items :: V.Vector MenuItem
  } deriving (Show, Eq, Generic, ToSchema)

instance ToJSON Inventory where
  toJSON (Inventory inv) = toJSON inv

instance FromJSON Inventory where
  parseJSON v = Inventory <$> parseJSON v

data MutationResponse = MutationResponse
  { success :: Bool
  , message :: Text
  } deriving (Show, Eq, Generic, ToSchema)

instance ToJSON MutationResponse
instance FromJSON MutationResponse