-- FILE: ./backend/src/Types/Inventory.hs
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Types.Inventory where

import Data.Aeson
    ( ToJSON(toJSON), FromJSON(parseJSON), object, KeyValue((.=)), (.:), withObject )
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID ( UUID )
import qualified Data.Vector as V
import Database.PostgreSQL.Simple.FromRow (FromRow (..), field)
import Database.PostgreSQL.Simple.ToField (ToField (..))
import Database.PostgreSQL.Simple.ToRow (ToRow (..))
import Database.PostgreSQL.Simple.Types (PGArray (..))
import GHC.Generics ( Generic )
import Types.Auth (UserCapabilities, AuthenticatedUser, capabilitiesForRole, auRole)

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
  { thc :: Text
  , cbg :: Text
  , strain :: Text
  , creator :: Text
  , species :: Species
  , dominant_terpene :: Text
  , terpenes :: V.Vector Text
  , lineage :: V.Vector Text
  , leafly_url :: Text
  , img :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON StrainLineage
instance FromJSON StrainLineage

data MenuItem = MenuItem
  { sort :: Int
  , sku :: UUID
  , brand :: Text
  , name :: Text
  , price :: Int
  , measure_unit :: Text
  , per_package :: Text
  , quantity :: Int
  , category :: ItemCategory
  , subcategory :: Text
  , description :: Text
  , tags :: V.Vector Text
  , effects :: V.Vector Text
  , strain_lineage :: StrainLineage
  }
  deriving (Show, Eq, Generic)

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

newtype Inventory = Inventory
  { items :: V.Vector MenuItem
  }
  deriving (Show, Eq, Generic)

instance ToJSON Inventory where
  toJSON (Inventory {items = items}) = toJSON items

instance FromJSON Inventory where
  parseJSON v = Inventory <$> parseJSON v

-- | Response that includes both data and user capabilities
data InventoryResponse
  = InventoryData 
      { inventoryItems :: Inventory
      , inventoryCapabilities :: UserCapabilities
      }
  | Message Text
  deriving (Show, Eq, Generic)

instance ToJSON InventoryResponse where
  toJSON (InventoryData inv caps) =
    object
      [ "type" .= T.pack "data"
      , "value" .= toJSON inv
      , "capabilities" .= toJSON caps
      ]
  toJSON (Message msg) =
    object
      [ "type" .= T.pack "message"
      , "value" .= msg
      ]

instance FromJSON InventoryResponse where
  parseJSON = withObject "InventoryResponse" $ \v -> do
    typ <- v .: "type"
    case (typ :: Text) of
      "data" -> InventoryData 
        <$> v .: "value"
        <*> v .: "capabilities"
      "message" -> Message <$> v .: "value"
      _ -> fail "Unknown InventoryResponse type"

-- | For backwards compatibility / simple messages that don't need capabilities
simpleMessage :: Text -> InventoryResponse
simpleMessage = Message

-- | Create an inventory response with capabilities
inventoryWithCapabilities :: Inventory -> AuthenticatedUser -> InventoryResponse
inventoryWithCapabilities inv user = 
  InventoryData inv (Types.Auth.capabilitiesForRole $ Types.Auth.auRole user)