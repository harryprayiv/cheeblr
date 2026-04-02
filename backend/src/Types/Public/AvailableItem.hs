{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Public.AvailableItem
  ( AvailableItem (..)
  , PublicSku (..)
  , PublicLocationId (..)
  , mkAvailableItem
  ) where

import Data.Aeson    (FromJSON, ToJSON)
import Data.Text     (Text, pack)
import Data.Time     (UTCTime)
import Data.UUID     (UUID)
import qualified Data.UUID   as UUID
import qualified Data.Vector as V
import GHC.Generics  (Generic)

import Types.Inventory (MenuItem)
import qualified Types.Inventory as TI

newtype PublicSku = PublicSku Text
  deriving (Show, Eq, Ord, Generic)

instance ToJSON   PublicSku
instance FromJSON PublicSku

newtype PublicLocationId = PublicLocationId UUID
  deriving (Show, Eq, Ord, Generic)

instance ToJSON   PublicLocationId
instance FromJSON PublicLocationId

data AvailableItem = AvailableItem
  { aiPublicSku       :: PublicSku
  , aiName            :: Text
  , aiBrand           :: Text
  , aiCategory        :: Text
  , aiSubcategory     :: Text
  , aiMeasureUnit     :: Text
  , aiPerPackage      :: Text
  , aiThc             :: Text
  , aiCbg             :: Text
  , aiStrain          :: Text
  , aiSpecies         :: Text
  , aiDominantTerpene :: Text
  , aiTags            :: [Text]
  , aiEffects         :: [Text]
  , aiPricePerUnit    :: Int
  , aiAvailableQty    :: Int
  , aiInStock         :: Bool
  , aiLocationId      :: PublicLocationId
  , aiLocationName    :: Text
  , aiUpdatedAt       :: UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON   AvailableItem
instance FromJSON AvailableItem

mkAvailableItem
  :: MenuItem
  -> Int
  -> PublicLocationId
  -> Text
  -> UTCTime
  -> AvailableItem
mkAvailableItem item availQty locId locName ts =
  let sl = TI.strain_lineage item
  in AvailableItem
    { aiPublicSku       = PublicSku (UUID.toText (TI.sku item))
    , aiName            = TI.name item
    , aiBrand           = TI.brand item
    , aiCategory        = pack (show (TI.category item))
    , aiSubcategory     = TI.subcategory item
    , aiMeasureUnit     = TI.measure_unit item
    , aiPerPackage      = TI.per_package item
    , aiThc             = TI.thc sl
    , aiCbg             = TI.cbg sl
    , aiStrain          = TI.strain sl
    , aiSpecies         = pack (show (TI.species sl))
    , aiDominantTerpene = TI.dominant_terpene sl
    , aiTags            = V.toList (TI.tags item)
    , aiEffects         = V.toList (TI.effects item)
    , aiPricePerUnit    = TI.price item
    , aiAvailableQty    = max 0 availQty
    , aiInStock         = availQty > 0
    , aiLocationId      = locId
    , aiLocationName    = locName
    , aiUpdatedAt       = ts
    }