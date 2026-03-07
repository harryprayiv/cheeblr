module GraphQL.Client
  ( AppClient
  , makeClientForUser
  ) where

import Prelude

import Affjax.RequestHeader (RequestHeader(..))
import Config.Network (currentConfig)
import Data.MediaType.Common (applicationJSON)
import GraphQL.Client.BaseClients.Affjax.Web (AffjaxWebClient(..))
import GraphQL.Client.Types (Client(..))
import GraphQL.Schema (AppSchema)
import Services.AuthService (UserId)

type AppClient = Client AffjaxWebClient AppSchema

makeClientForUser :: UserId -> AppClient
makeClientForUser userId =
  Client $ AffjaxWebClient
    (currentConfig.apiBaseUrl <> "/graphql")
    [ ContentType applicationJSON
    , Accept applicationJSON
    , RequestHeader "X-User-Id" userId
    ]