{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

-- | The register's sale commands. Every command answers with the whole
-- sale. Request bodies carry no money the backend can compute itself.
module API.SaleCommand (SaleCommandAPI) where

import Data.UUID (UUID)
import Servant

import API.Transaction (AuthHeader)
import Types.Transaction.Request
import qualified Types.Transaction.Sale as Sale

type SaleCommandAPI =
  "pos" :> "sale" :> AuthHeader :> ReqBody '[JSON] StartSaleRequest :> Post '[JSON] Sale.SaleTransaction
    :<|> "pos" :> "sale" :> "item" :> AuthHeader :> ReqBody '[JSON] AddItemRequest :> Post '[JSON] Sale.SaleTransaction
    :<|> "pos" :> "sale" :> "item" :> AuthHeader :> Capture "id" UUID :> Delete '[JSON] Sale.SaleTransaction
    :<|> "pos" :> "sale" :> "payment" :> AuthHeader :> ReqBody '[JSON] AddPaymentRequest :> Post '[JSON] Sale.SaleTransaction
    :<|> "pos" :> "sale" :> "payment" :> AuthHeader :> Capture "id" UUID :> Delete '[JSON] Sale.SaleTransaction
    :<|> "pos" :> "sale" :> "clear" :> AuthHeader :> Capture "id" UUID :> Post '[JSON] Sale.SaleTransaction
    :<|> "pos" :> "sale" :> "finalize" :> AuthHeader :> Capture "id" UUID :> Post '[JSON] Sale.SaleTransaction
