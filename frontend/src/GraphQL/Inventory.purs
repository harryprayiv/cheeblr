module GraphQL.API.Inventory
  ( readInventoryGql
  , writeInventoryGql
  , updateInventoryGql
  , deleteInventoryGql
  ) where

import Prelude

import Data.Array (uncons)
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff, attempt)
import GraphQL.Client (makeClientForUser)
import GraphQL.Client.Args (Args(..))
import GraphQL.Client.Query (mutation, query)
import GraphQL.Schema (MenuItemGql, MenuItemInputGql, StrainLineageGql, StrainLineageInputGql)
import Services.AuthService (UserId)
import Types.Inventory (Inventory(..), ItemCategory(..), MenuItem(..), Species(..), StrainLineage(..))
import Types.UUID (parseUUID)

-- ---------------------------------------------------------------------------
-- Conversion: GQL → domain
-- ---------------------------------------------------------------------------

gqlToStrainLineage :: StrainLineageGql -> StrainLineage
gqlToStrainLineage g = StrainLineage
  { thc:              g.thc
  , cbg:              g.cbg
  , strain:           g.strain
  , creator:          g.creator
  , species:          parseSpecies g.species
  , dominant_terpene: g.dominant_terpene
  , terpenes:         g.terpenes
  , lineage:          g.lineage
  , leafly_url:       g.leafly_url
  , img:              g.img
  }

parseSpecies :: String -> Species
parseSpecies = case _ of
  "Indica"               -> Indica
  "IndicaDominantHybrid" -> IndicaDominantHybrid
  "Hybrid"               -> Hybrid
  "SativaDominantHybrid" -> SativaDominantHybrid
  _                      -> Sativa

parseCategory :: String -> ItemCategory
parseCategory = case _ of
  "Flower"       -> Flower
  "PreRolls"     -> PreRolls
  "Vaporizers"   -> Vaporizers
  "Edibles"      -> Edibles
  "Drinks"       -> Drinks
  "Concentrates" -> Concentrates
  "Topicals"     -> Topicals
  "Tinctures"    -> Tinctures
  _              -> Accessories

gqlToMenuItem :: MenuItemGql -> Either String MenuItem
gqlToMenuItem g = case parseUUID g.sku of
  Nothing  -> Left $ "Invalid UUID in GraphQL response: " <> g.sku
  Just sku -> Right $ MenuItem
    { sort:           g.sort
    , sku
    , brand:          g.brand
    , name:           g.name
    , price:          Discrete g.price
    , measure_unit:   g.measure_unit
    , per_package:    g.per_package
    , quantity:       g.quantity
    , category:       parseCategory g.category
    , subcategory:    g.subcategory
    , description:    g.description
    , tags:           g.tags
    , effects:        g.effects
    , strain_lineage: gqlToStrainLineage g.strain_lineage
    }

gqlToInventory :: Array MenuItemGql -> Either String Inventory
gqlToInventory = go []
  where
  go acc xs = case uncons xs of
    Nothing          -> Right (Inventory (acc))
    Just { head, tail } -> case gqlToMenuItem head of
      Left e    -> Left e
      Right item -> go (acc <> [item]) tail

-- ---------------------------------------------------------------------------
-- Conversion: domain → GQL input
-- ---------------------------------------------------------------------------

menuItemToInput :: MenuItem -> MenuItemInputGql
menuItemToInput (MenuItem i) =
  { sort:           i.sort
  , sku:            show i.sku
  , brand:          i.brand
  , name:           i.name
  , price:          unwrapDiscrete i.price
  , measure_unit:   i.measure_unit
  , per_package:    i.per_package
  , quantity:       i.quantity
  , category:       show i.category
  , subcategory:    i.subcategory
  , description:    i.description
  , tags:           i.tags
  , effects:        i.effects
  , strain_lineage: strainLineageToInput i.strain_lineage
  }
  where
  unwrapDiscrete (Discrete n) = n

strainLineageToInput :: StrainLineage -> StrainLineageInputGql
strainLineageToInput (StrainLineage sl) =
  { thc:              sl.thc
  , cbg:              sl.cbg
  , strain:           sl.strain
  , creator:          sl.creator
  , species:          show sl.species
  , dominant_terpene: sl.dominant_terpene
  , terpenes:         sl.terpenes
  , lineage:          sl.lineage
  , leafly_url:       sl.leafly_url
  , img:              sl.img
  }

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

readInventoryGql :: UserId -> Aff (Either String Inventory)
readInventoryGql userId = do
  result <- attempt $
    query (makeClientForUser userId) "readInventory"
      { inventory:
          { sort: unit, sku: unit, brand: unit, name: unit, price: unit
          , measure_unit: unit, per_package: unit, quantity: unit
          , category: unit, subcategory: unit, description: unit
          , tags: unit, effects: unit
          , strain_lineage:
              { thc: unit, cbg: unit, strain: unit, creator: unit
              , species: unit, dominant_terpene: unit
              , terpenes: unit, lineage: unit, leafly_url: unit, img: unit
              }
          }
      }
  case result of
    Left err   -> pure $ Left $ show err
    Right resp -> pure $ gqlToInventory resp.inventory

writeInventoryGql :: UserId -> MenuItem -> Aff (Either String { success :: Boolean, message :: String })
writeInventoryGql userId item = do
  result <- attempt $
    mutation (makeClientForUser userId) "writeInventory"
      { createMenuItem: { input: menuItemToInput item } `Args` { success: unit, message: unit } }
  pure $ case result of
    Left err -> Left $ show err
    Right r  -> Right r.createMenuItem

updateInventoryGql :: UserId -> MenuItem -> Aff (Either String { success :: Boolean, message :: String })
updateInventoryGql userId item = do
  result <- attempt $
    mutation (makeClientForUser userId) "updateInventory"
      { updateMenuItem: { input: menuItemToInput item } `Args` { success: unit, message: unit } }
  pure $ case result of
    Left err -> Left $ show err
    Right r  -> Right r.updateMenuItem

deleteInventoryGql :: UserId -> String -> Aff (Either String { success :: Boolean, message :: String })
deleteInventoryGql userId skuStr = do
  result <- attempt $
    mutation (makeClientForUser userId) "deleteInventory"
      { deleteMenuItem: { sku: skuStr } `Args` { success: unit, message: unit } }
  pure $ case result of
    Left err -> Left $ show err
    Right r  -> Right r.deleteMenuItem