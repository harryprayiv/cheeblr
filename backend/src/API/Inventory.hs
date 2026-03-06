{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Inventory where

import Data.UUID
import Servant
import Types.Inventory
import Types.Auth (SessionResponse)
import API.Transaction (PosAPI)
import Data.Text (Text)

type AuthHeader = Header "X-User-Id" Text

type InventoryAPI =
  -- GET /inventory  → plain array of menu items
  "inventory" :> AuthHeader :> Get  '[JSON] Inventory

  -- POST /inventory  → create
  :<|> "inventory" :> AuthHeader :> ReqBody '[JSON] MenuItem :> Post   '[JSON] MutationResponse

  -- PUT /inventory  → update
  :<|> "inventory" :> AuthHeader :> ReqBody '[JSON] MenuItem :> Put    '[JSON] MutationResponse

  -- DELETE /inventory/:sku  → delete
  :<|> "inventory" :> AuthHeader :> Capture "sku" UUID      :> Delete '[JSON] MutationResponse

  -- GET /session  → capabilities for the authenticated user
  :<|> "session"   :> AuthHeader :> Get '[JSON] SessionResponse

inventoryAPI :: Proxy InventoryAPI
inventoryAPI = Proxy

type API =
  InventoryAPI
    :<|> PosAPI

api :: Proxy API
api = Proxy