{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Stock where

import Data.Text (Text)
import Data.UUID (UUID)
import Servant

import Types.Inventory (MutationResponse)
import Types.Location (LocationId)
import Types.Stock

type AuthHeader = Header "Authorization" Text

type StockAPI =
  "stock"
    :> ( "queue"
           :> AuthHeader
           :> QueryParam "locationId" LocationId
           :> Get '[JSON] [PullRequest]
           :<|> "queue"
             :> "stream"
             :> AuthHeader
             :> QueryParam "locationId" LocationId
             :> QueryParam "cursor" Int
             :> Raw
           :<|> "pull"
             :> Capture "id" UUID
             :> AuthHeader
             :> Get '[JSON] PullRequestDetail
           :<|> "pull"
             :> Capture "id" UUID
             :> "accept"
             :> AuthHeader
             :> Post '[JSON] MutationResponse
           :<|> "pull"
             :> Capture "id" UUID
             :> "start"
             :> AuthHeader
             :> Post '[JSON] MutationResponse
           :<|> "pull"
             :> Capture "id" UUID
             :> "fulfill"
             :> AuthHeader
             :> Post '[JSON] MutationResponse
           :<|> "pull"
             :> Capture "id" UUID
             :> "issue"
             :> AuthHeader
             :> ReqBody '[JSON] IssueReport
             :> Post '[JSON] MutationResponse
           :<|> "pull"
             :> Capture "id" UUID
             :> "retry"
             :> AuthHeader
             :> Post '[JSON] MutationResponse
           :<|> "pull"
             :> Capture "id" UUID
             :> "message"
             :> AuthHeader
             :> ReqBody '[JSON] NewMessage
             :> Post '[JSON] MutationResponse
           :<|> "pull"
             :> Capture "id" UUID
             :> "messages"
             :> AuthHeader
             :> Get '[JSON] [PullMessage]
       )

stockAPI :: Proxy StockAPI
stockAPI = Proxy
