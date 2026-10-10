module GraphQL.API.Inventory
  ( readInventoryGql
  , writeInventoryGql
  , updateInventoryGql
  , deleteInventoryGql
  ) where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Data.Either (Either)
import Effect.Aff (Aff)
import Types.Inventory (Inventory, MenuItem, MutationResponse)
import Yoga.JSON (class ReadForeign, writeJSON)

type GqlResponse a = { data :: a }

gqlPost :: forall a. ReadForeign a => String -> Aff (Either ApiError a)
gqlPost query = do
  result <- Request.post "/graphql/inventory" { query }
  pure (result <#> \(r :: GqlResponse a) -> r.data)

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

readInventoryGql :: Aff (Either ApiError Inventory)
readInventoryGql = do
  result <- gqlPost inventoryQuery
  pure (result <#> \(d :: { inventory :: Inventory }) -> d.inventory)

writeInventoryGql :: MenuItem -> Aff (Either ApiError MutationResponse)
writeInventoryGql item = do
  result <- gqlPost
    ("mutation { createMenuItem(input: " <> writeJSON item <> ") { success message } }")
  pure (result <#> \(d :: { createMenuItem :: MutationResponse }) -> d.createMenuItem)

updateInventoryGql :: MenuItem -> Aff (Either ApiError MutationResponse)
updateInventoryGql item = do
  result <- gqlPost
    ("mutation { updateMenuItem(input: " <> writeJSON item <> ") { success message } }")
  pure (result <#> \(d :: { updateMenuItem :: MutationResponse }) -> d.updateMenuItem)

deleteInventoryGql :: String -> Aff (Either ApiError MutationResponse)
deleteInventoryGql sku = do
  result <- gqlPost
    ("mutation { deleteMenuItem(sku: \"" <> sku <> "\") { success message } }")
  pure (result <#> \(d :: { deleteMenuItem :: MutationResponse }) -> d.deleteMenuItem)
