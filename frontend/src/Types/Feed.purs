module Types.Feed where

-- | Public inventory item as received over the feed.
-- Field names match the app.cheeblr.inventory.availableItem lexicon exactly.
-- Note: the backend AvailableItem type uses "ai"-prefixed Haskell fields
-- but serializes to these exact JSON names.
type AvailableItem =
  { publicSku       :: String
  , name            :: String
  , brand           :: String
  , category        :: String
  , subcategory     :: String
  , measureUnit     :: String
  , perPackage      :: String
  , thc             :: String
  , cbg             :: String
  , strain          :: String
  , species         :: String
  , dominantTerpene :: String
  , tags            :: Array String
  , effects         :: Array String
  , pricePerUnit    :: Int
  , availableQty    :: Int
  , inStock         :: Boolean
  , locationId      :: String
  , locationName    :: String
  , updatedAt       :: String
  }

-- | A single WebSocket frame from app.cheeblr.feed.subscribe.
-- The "type" field is omitted since it is always the same constant
-- and "type" is a reserved keyword in PureScript.
type FeedFrame =
  { seq       :: Int
  , payload   :: AvailableItem
  , timestamp :: String
  }

-- | Response from GET /xrpc/app.cheeblr.feed.status.
type FeedStatus =
  { locationId   :: String
  , locationName :: String
  , currentSeq   :: Int
  , itemCount    :: Int
  , inStockCount :: Int
  }