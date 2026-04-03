module Infrastructure.AvailabilityState (
  AvailabilityState (..),
  availableQty,
  toAvailableItem,
  allAvailableItems,
) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.UUID (UUID)

import Types.Inventory (MenuItem)
import qualified Types.Inventory as TI
import Types.Public.AvailableItem (
  AvailableItem,
  PublicLocationId,
  mkAvailableItem,
 )

data AvailabilityState = AvailabilityState
  { asItems :: Map UUID MenuItem
  , asReserved :: Map UUID Int
  , asPublicLocId :: PublicLocationId
  , asLocName :: Text
  }

availableQty :: AvailabilityState -> UUID -> Int
availableQty st sku' =
  let
    total = maybe 0 TI.quantity (Map.lookup sku' (asItems st))
    reserved = fromMaybe 0 (Map.lookup sku' (asReserved st))
   in
    max 0 (total - reserved)

toAvailableItem :: AvailabilityState -> UUID -> UTCTime -> Maybe AvailableItem
toAvailableItem st sku' ts = do
  item <- Map.lookup sku' (asItems st)
  pure $
    mkAvailableItem
      item
      (availableQty st sku')
      (asPublicLocId st)
      (asLocName st)
      ts

allAvailableItems :: AvailabilityState -> UTCTime -> [AvailableItem]
allAvailableItems st ts =
  mapMaybe (\sku' -> toAvailableItem st sku' ts) (Map.keys (asItems st))
