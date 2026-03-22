{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module API.OpenApi where

import Control.Lens ((&), (.~), (?~))
import Data.Morpheus.Types.IO (GQLRequest, GQLResponse)
import Data.OpenApi (NamedSchema (..), OpenApi, ToSchema (..))
import qualified Data.OpenApi as OpenApi
import Servant (Get, JSON, Proxy (..), (:<|>), (:>))
import Servant.OpenApi (toOpenApi)

import API.Auth     (AuthAPI)
import API.Inventory (InventoryAPI)
import API.Transaction (PosAPI)

instance ToSchema GQLRequest where
  declareNamedSchema _ = return $ NamedSchema (Just "GQLRequest") mempty

instance ToSchema GQLResponse where
  declareNamedSchema _ = return $ NamedSchema (Just "GQLResponse") mempty

instance ToSchema OpenApi where
  declareNamedSchema _ = return $ NamedSchema (Just "OpenApi") mempty

type CheeblrAPI =
       InventoryAPI
  :<|> PosAPI
  :<|> AuthAPI
  :<|> "openapi.json" :> Get '[JSON] OpenApi

cheeblrAPI :: Proxy CheeblrAPI
cheeblrAPI = Proxy

cheeblrOpenApi :: OpenApi
cheeblrOpenApi = toOpenApi cheeblrAPI
  & OpenApi.info . OpenApi.title       .~ "Cheeblr API"
  & OpenApi.info . OpenApi.version     .~ "1.0"
  & OpenApi.info . OpenApi.description ?~ "Cannabis dispensary POS and inventory management API"