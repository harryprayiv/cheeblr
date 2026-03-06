## Fix 1: `loadTxPageData` sequential fallback

The core issue is that `TxPageError` is a single failure channel, so an inventory fetch failure prevents the transaction UI from loading at all — even though the register/transaction are independent and fully usable without inventory (you just can't select items yet).

**`Pages/CreateTransaction.purs`** — add a degraded state:

```purescript
data TxPageStatus
  = TxPageLoading
  | TxPageReady Inventory Register Transaction
  | TxPageDegraded String Register Transaction  -- inventory failed, tx still usable
  | TxPageError String                          -- register/tx failed, fatal
```

Update the page renderer to handle the new case:

```purescript
page :: Poll AuthState -> UserId -> Poll TxPageStatus -> Nut
page _authPoll userId statusPoll =
  statusPoll <#~> case _ of
    TxPageLoading ->
      D.div [ DA.klass_ "loading-indicator" ]
        [ text_ "Initializing transaction..." ]
    TxPageError err ->
      renderError err
    TxPageReady inventory register transaction ->
      TransactionUI.createTransaction userId
        (pure inventory)
        (pure transaction)
        register
    TxPageDegraded inventoryErr register transaction ->
      D.div_
        [ D.div [ DA.klass_ "warning-banner" ]
            [ text_ $ "Inventory unavailable: " <> inventoryErr ]
        , TransactionUI.createTransaction userId
            (pure (Inventory []))   -- empty but valid
            (pure transaction)
            register
        ]
```

**`Main.purs`** — restructure `loadTxPageData` to treat the two loads as truly independent:

```purescript
loadTxPageData :: String -> Aff Pages.CreateTransaction.TxPageStatus
loadTxPageData userId = do
  Tuple invResult regTxResult <- sequential $
    Tuple
      <$> parallel (loadInventoryResult userId)
      <*> parallel (loadRegisterAndStartTx userId)
  -- Register/transaction failure is fatal — you can't process a transaction
  -- without them. Inventory failure is degraded — UI still works, just empty.
  pure $ case regTxResult of
    Left err ->
      Pages.CreateTransaction.TxPageError err
    Right { register, transaction } ->
      case invResult of
        Right inv ->
          Pages.CreateTransaction.TxPageReady inv register transaction
        Left err ->
          Pages.CreateTransaction.TxPageDegraded err register transaction
  where
  loadInventoryResult :: String -> Aff (Either String Inventory)
  loadInventoryResult uid = do
    result <- fetchInventory uid defaultViewConfig.fetchConfig defaultViewConfig.mode
    pure $ case result of
      Right (InventoryData inv _) -> Right inv
      Right (Message msg)         -> Left msg
      Left err                    -> Left err

  loadRegisterAndStartTx
    :: String
    -> Aff (Either String { register :: Register, transaction :: Transaction })
  loadRegisterAndStartTx uid = do
    regResult <- getOrInitRegisterAff uid dummyLocationId dummyEmployeeId
    case regResult of
      Left err -> pure $ Left err
      Right register -> do
        txResult <- TransactionService.startTransaction uid
          { employeeId: fromMaybe register.registerId register.registerOpenedBy
          , registerId: register.registerId
          , locationId: register.registerLocationId
          }
        pure $ case txResult of
          Right transaction -> Right { register, transaction }
          Left err          -> Left ("Failed to create transaction: " <> err)
```

The key shift is: the `case invResult, regTxResult of` pattern was a symmetric product match that hid the asymmetry in the domain. Inventory and register/transaction don't have equal standing — one is recoverable, one isn't.

---

## Fix 2: `InventoryResponse` with `Maybe UserCapabilities`

The awkwardness has two roots: capabilities are bundled into a data-fetch response when they belong to a session/auth concern, and `Message` is doing double duty as both a mutation acknowledgement and an error carrier.

**Haskell — `Types/Inventory.hs`**

Separate the concerns cleanly. Inventory returns inventory. Mutations return a dedicated type. Capabilities travel on their own endpoint.

```haskell
-- Clean inventory response — just data
newtype InventoryResponse = InventoryResponse
  { inventoryItems :: Inventory
  } deriving (Show, Eq, Generic)

instance ToJSON InventoryResponse where
  toJSON (InventoryResponse inv) = toJSON (items inv)

instance FromJSON InventoryResponse where
  parseJSON v = InventoryResponse . Inventory <$> parseJSON v

-- Mutation responses are their own thing
data MutationResponse = MutationResponse
  { mutationSuccess :: Bool
  , mutationMessage :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON MutationResponse
instance FromJSON MutationResponse
```

**Haskell — new `Types/Auth.hs` response type and endpoint**

```haskell
-- In Types/Auth.hs
data SessionResponse = SessionResponse
  { sessionUserId       :: UUID
  , sessionUserName     :: Text
  , sessionRole         :: UserRole
  , sessionCapabilities :: UserCapabilities
  } deriving (Show, Eq, Generic)

instance ToJSON SessionResponse
instance FromJSON SessionResponse
```

**Haskell — `API/Inventory.hs`** — add the session endpoint, clean up return types:

```haskell
type InventoryAPI =
       "inventory"   :> AuthHeader :> Get    '[JSON] InventoryResponse
  :<|> "inventory"   :> AuthHeader :> ReqBody '[JSON] MenuItem :> Post '[JSON] MutationResponse
  :<|> "inventory"   :> AuthHeader :> ReqBody '[JSON] MenuItem :> Put  '[JSON] MutationResponse
  :<|> "inventory"   :> AuthHeader :> Capture "sku" UUID :> Delete '[JSON] MutationResponse
  :<|> "session"     :> AuthHeader :> Get    '[JSON] SessionResponse
```

**Haskell — `Server.hs`** — implement the session handler and fix inventory server:

```haskell
inventoryServer :: Pool.Pool Connection -> Server InventoryAPI
inventoryServer pool =
  getInventory :<|> addMenuItem :<|> updateMenuItem :<|> deleteInventoryItem :<|> getSession
  where
    getInventory :: Maybe Text -> Handler InventoryResponse
    getInventory mUserId = do
      let user = lookupUser mUserId
      liftIO $ putStrLn $ "GET /inventory - User: " ++ show (auRole user)
      inventory <- liftIO $ getAllMenuItems pool
      return $ InventoryResponse inventory

    addMenuItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    addMenuItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      if not (capCanCreateItem caps)
        then throwError err403 { errBody = "Permission denied" }
        else do
          result <- liftIO $ try $ insertMenuItem pool item
          pure $ case result of
            Right _             -> MutationResponse True "Item added successfully"
            Left (e :: SomeException) ->
              MutationResponse False (pack $ "Error inserting item: " <> show e)

    updateMenuItem :: Maybe Text -> MenuItem -> Handler MutationResponse
    updateMenuItem mUserId item = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      if not (capCanEditItem caps)
        then throwError err403 { errBody = "Permission denied" }
        else do
          result <- liftIO $ try $ updateExistingMenuItem pool item
          pure $ case result of
            Right _             -> MutationResponse True "Item updated successfully"
            Left (e :: SomeException) ->
              MutationResponse False (pack $ "Error updating item: " <> show e)

    deleteInventoryItem :: Maybe Text -> UUID -> Handler MutationResponse
    deleteInventoryItem mUserId uuid = do
      let user = lookupUser mUserId
          caps = capabilitiesForRole (auRole user)
      if not (capCanDeleteItem caps)
        then throwError err403 { errBody = "Permission denied" }
        else do
          result <- liftIO $ try $ DB.deleteMenuItem pool uuid
          pure $ case result of
            Right _ -> MutationResponse True "Item deleted successfully"
            Left (e :: SomeException) ->
              MutationResponse False (pack $ "Error deleting item: " <> show e)

    getSession :: Maybe Text -> Handler SessionResponse
    getSession mUserId = do
      let user = lookupUser mUserId
      pure $ SessionResponse
        { sessionUserId       = auUserId user
        , sessionUserName     = auUserName user
        , sessionRole         = auRole user
        , sessionCapabilities = capabilitiesForRole (auRole user)
        }
```

**PureScript — `Types/Inventory.purs`** — remove the `Maybe UserCapabilities` from the sum type entirely:

```purescript
-- InventoryResponse is now just Inventory
newtype InventoryResponse = InventoryResponse Inventory

instance readForeignInventoryResponse :: ReadForeign InventoryResponse where
  readImpl f = InventoryResponse <$> readImpl f

-- Mutation responses are their own type
type MutationResponse =
  { success :: Boolean
  , message :: String
  }
```

**PureScript — new `Types/Session.purs`**:

```purescript
module Types.Session where

import Types.Auth (UserCapabilities, UserRole)
import Types.UUID (UUID)
import Yoga.JSON (class ReadForeign)

type SessionResponse =
  { sessionUserId       :: UUID
  , sessionUserName     :: String
  , sessionRole         :: UserRole
  , sessionCapabilities :: UserCapabilities
  }
```

**PureScript — `API/Inventory.purs`** — updated signatures:

```purescript
module API.Inventory where

import Types.Inventory (Inventory, InventoryResponse(..), MenuItem, MutationResponse)
import Types.Session (SessionResponse)

writeInventory :: UserId -> MenuItem -> Aff (Either String MutationResponse)
writeInventory userId menuItem =
  Request.authPost userId "/inventory" menuItem

readInventory :: UserId -> Aff (Either String Inventory)
readInventory userId = do
  result <- Request.authGet userId "/inventory"
  pure $ map (\(InventoryResponse inv) -> inv) result

updateInventory :: UserId -> MenuItem -> Aff (Either String MutationResponse)
updateInventory userId menuItem =
  Request.authPut userId "/inventory" menuItem

deleteInventory :: UserId -> String -> Aff (Either String MutationResponse)
deleteInventory userId itemId =
  Request.authDelete userId ("/inventory/" <> itemId)

fetchSession :: UserId -> Aff (Either String SessionResponse)
fetchSession userId =
  Request.authGet userId "/session"
```

**`Main.purs`** — capabilities now come from a dedicated session fetch, not piggy-backed on inventory:

```purescript
-- Replace loadInventoryStatus with two focused loaders
loadInventory :: String -> Aff Pages.LiveView.InventoryLoadStatus
loadInventory userId = do
  result <- fetchInventory userId defaultViewConfig.fetchConfig defaultViewConfig.mode
  pure $ case result of
    Right (InventoryResponse inv) -> Pages.LiveView.InventoryLoaded inv
    Left err                      -> Pages.LiveView.InventoryError err

loadSession :: String -> Aff (Maybe UserCapabilities)
loadSession userId = do
  result <- API.Inventory.fetchSession userId
  pure $ case result of
    Right session -> Just session.sessionCapabilities
    Left _        -> Nothing  -- fall back to local role derivation

-- In the matcher for LiveView:
LiveView ->
  [ do
      result <- loadInventory userId
      liftEffect $ inventory.push result
  , do
      caps <- loadSession userId
      liftEffect $ for_ caps backendCaps.push
  ]
```

The net result: `InventoryResponse` is now honest about what it is (a list of items), mutations have a typed acknowledgement instead of a stringly-typed `Message` fallback, and capabilities travel on their own route where they semantically belong. The `Maybe` disappears because the absence of capabilities is now expressed by the session endpoint failing rather than by poisoning the inventory type.