{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Inventory where

import Data.UUID
import Servant
import Types.Inventory
import API.Transaction (PosAPI)
import Data.Text (Text)

-- | Auth header for identifying the user
type AuthHeader = Header "X-User-Id" Text

-- | Inventory API with auth
type InventoryAPI =
  -- GET inventory - returns data + capabilities based on user
  "inventory" :> AuthHeader :> Get '[JSON] InventoryResponse
  
  -- POST new item - requires create permission
  :<|> "inventory" :> AuthHeader :> ReqBody '[JSON] MenuItem :> Post '[JSON] InventoryResponse
  
  -- PUT update item - requires edit permission  
  :<|> "inventory" :> AuthHeader :> ReqBody '[JSON] MenuItem :> Put '[JSON] InventoryResponse
  
  -- DELETE item - requires delete permission
  :<|> "inventory" :> AuthHeader :> Capture "sku" UUID :> Delete '[JSON] InventoryResponse

inventoryAPI :: Proxy InventoryAPI
inventoryAPI = Proxy

type API =
  InventoryAPI
    :<|> PosAPI

api :: Proxy API
api = Proxy