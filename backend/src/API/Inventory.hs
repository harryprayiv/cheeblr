{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Inventory where

import API.Transaction (PosAPI)
import Data.Morpheus.Types (GQLRequest, GQLResponse)
import Data.Text (Text)
import Data.UUID
import Servant
import Types.Auth (SessionResponse)
import Types.Inventory

-- Changed from "X-User-Id" to "Authorization" for the Bearer token path.
-- In dev mode (USE_REAL_AUTH=false) the header is optional and ignored by
-- lookupUser, which returns the default dev user for Nothing.
type AuthHeader = Header "Authorization" Text

type InventoryAPI =
  "inventory" :> AuthHeader :> Get '[JSON] Inventory
    :<|> "inventory" :> AuthHeader :> ReqBody '[JSON] MenuItem :> Post '[JSON] MutationResponse
    :<|> "inventory" :> AuthHeader :> ReqBody '[JSON] MenuItem :> Put '[JSON] MutationResponse
    :<|> "inventory" :> AuthHeader :> Capture "sku" UUID :> Delete '[JSON] MutationResponse
    :<|> "session" :> AuthHeader :> Get '[JSON] SessionResponse
    :<|> "graphql"
      :> "inventory"
      :> AuthHeader
      :> ReqBody '[JSON] GQLRequest
      :> Post '[JSON] GQLResponse

inventoryAPI :: Proxy InventoryAPI
inventoryAPI = Proxy

type API =
  InventoryAPI
    :<|> PosAPI

api :: Proxy API
api = Proxy
