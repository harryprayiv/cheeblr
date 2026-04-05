module GraphQL.API.Inventory
  ( readInventoryGql
  , writeInventoryGql
  , updateInventoryGql
  , deleteInventoryGql
  ) where

import Prelude

import Data.Either (Either(..))
import Effect.Aff (Aff, attempt)
import Fetch (Method(..), RequestCredentials(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import Config.Network (currentConfig)
import Services.AuthService (UserId)
import Types.Inventory (Inventory, MenuItem, MutationResponse)
import Yoga.JSON (class ReadForeign, writeJSON)

type GqlResponse a = { data :: a }
type InventoryData = { inventory :: Inventory }
type MutationData  = { result :: MutationResponse }

gqlPost
  :: forall a
   . ReadForeign a
  => UserId
  -> String
  -> Aff (Either String a)
gqlPost userId query = do
  result <- attempt do
    response <- fetch (currentConfig.apiBaseUrl <> "/graphql/inventory")
      { method: POST
      , body: writeJSON { query }
      , headers:
          { "Content-Type":  "application/json"
          , "Accept":        "application/json"
          , "Authorization": "Bearer " <> userId
          }
      , credentials: Include
      }
    (r :: GqlResponse a) <- fromJSON response.json
    pure r.data
  pure $ case result of
    Left err -> Left $ show err
    Right v  -> Right v

inventoryQuery :: String
inventoryQuery = """
  { inventory {
      sort sku brand name price measure_unit per_package quantity
      category subcategory description tags effects
      strain_lineage {
        thc cbg strain creator species dominant_terpene
        terpenes lineage leafly_url img
      }
  } }
"""

readInventoryGql :: UserId -> Aff (Either String Inventory)
readInventoryGql userId = do
  result <- gqlPost userId inventoryQuery
  pure $ case result of
    Left err             -> Left err
    Right (d :: InventoryData) -> Right d.inventory

writeInventoryGql :: UserId -> MenuItem -> Aff (Either String MutationResponse)
writeInventoryGql userId item = do
  result <- gqlPost userId
    ("mutation { createMenuItem(input: " <> writeJSON item <> ") { success message } }")
  pure $ case result of
    Left err -> Left err
    Right (d :: { createMenuItem :: MutationResponse }) -> Right d.createMenuItem

updateInventoryGql :: UserId -> MenuItem -> Aff (Either String MutationResponse)
updateInventoryGql userId item = do
  result <- gqlPost userId
    ("mutation { updateMenuItem(input: " <> writeJSON item <> ") { success message } }")
  pure $ case result of
    Left err -> Left err
    Right (d :: { updateMenuItem :: MutationResponse }) -> Right d.updateMenuItem

deleteInventoryGql :: UserId -> String -> Aff (Either String MutationResponse)
deleteInventoryGql userId sku = do
  result <- gqlPost userId
    ("mutation { deleteMenuItem(sku: \"" <> sku <> "\") { success message } }")
  pure $ case result of
    Left err -> Left err
    Right (d :: { deleteMenuItem :: MutationResponse }) -> Right d.deleteMenuItem