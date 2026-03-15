# Cheeblr Backend Documentation

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [State Machine Layer](#state-machine-layer)
- [Authentication and Authorization](#authentication-and-authorization)
- [API Reference](#api-reference)
- [Data Models](#data-models)
- [Database Schema](#database-schema)
- [Transaction Processing](#transaction-processing)
- [Inventory Reservation System](#inventory-reservation-system)
- [Security and Configuration](#security-and-configuration)
- [Development Guidelines](#development-guidelines)

## Overview

The Cheeblr backend is a Haskell-based API server built for inventory and transaction management in cannabis dispensary retail operations. It provides inventory tracking with reservation-based availability, point-of-sale transaction processing, cash register operations, compliance verification, financial reporting stubs, and a machine-readable OpenAPI3 schema.

The system uses a layered architecture with Servant for type-safe API definitions and PostgreSQL for persistence. The database layer uses **rel8** for type-safe query construction and **hasql** as the PostgreSQL driver, with **hasql-pool** for connection management. All table schemas are defined as `Rel8able` record types in `DB.Schema`. State machine transitions for transactions and registers are enforced at compile time via [crem](https://github.com/tweag/crem), a library that encodes state machine topologies as type-level constraints. All monetary values are stored as integer cents to avoid floating-point rounding.

For a detailed treatment of what crem adds to the codebase and how it compares to full dependent types, see [Crem.md](./Crem.md).

## Architecture

### Architectural Layers

1. **API Layer** (`API/`): Type-level API definitions using Servant's DSL. `API.Inventory` defines the inventory CRUD endpoints with auth headers. `API.Transaction` defines the POS, register, ledger, and compliance endpoints plus all request/response types that are not domain models. `API.OpenApi` composes the full `CheeblrAPI` type, derives the OpenAPI3 schema via `servant-openapi3`, and exposes the `/openapi.json` endpoint.

2. **Server Layer** (`Server.hs`, `Server/Transaction.hs`): Request handlers. `Server` handles inventory endpoints with capability checks. `Server.Transaction` implements all POS subsystem handlers (transactions, registers, ledger, compliance).

3. **Service Layer** (`Service/`): Business logic that sits between the server and database layers for state-machine-backed operations. `Service.Transaction` and `Service.Register` load domain state, run the relevant state machine transition to validate the command, and only proceed to the database if the transition is legal.

4. **State Machine Layer** (`State/`): Compile-time-enforced state machine definitions built on crem. `State.TransactionMachine` and `State.RegisterMachine` define the vertex types, GADT-indexed state types, topologies, commands, events, and transition functions. No IO. No database access. Pure transition logic only.

5. **Database Layer** (`DB/`): `DB.Schema` defines all `Rel8able` row types and `TableSchema` values. `DB.Database` handles inventory CRUD using rel8 queries executed inside hasql sessions via `runSession`. `DB.Transaction` handles all transaction, register, reservation, and payment database operations using the same pattern. Domain types carry no database instances; all serialization passes through the `Rel8able` row types in `DB.Schema` via explicit conversion functions.

6. **Auth Layer** (`Auth/Simple.hs`): Dev-mode authentication via `X-User-Id` header lookup against a fixed set of dev users, with role-based capability gating.

7. **Types Layer** (`Types/`): Domain models -- `Types.Inventory` (menu items, strain lineage, inventory response), `Types.Transaction` (transactions, payments, taxes, discounts, compliance, ledger), `Types.Auth` (roles, capabilities). These types carry only Aeson instances.

8. **Application Core** (`App.hs`): Server bootstrap, CORS configuration, TLS configuration, middleware setup.

### Key Technologies

| Concern | Library |
|---|---|
| API definition | **Servant** -- type-level web DSL |
| OpenAPI3 schema | **servant-openapi3** -- derives OpenAPI3 from the Servant API type at runtime |
| State machine enforcement | **crem** -- topology-indexed state machines |
| Singleton types | **singletons-base** -- bridges type-level and value-level universe |
| Database queries | **rel8** -- type-safe, composable Haskell-to-SQL query builder over `Rel8able` schemas |
| Database driver | **hasql** -- typed PostgreSQL sessions and statements |
| Connection pooling | **hasql-pool** -- connection pool; `DBPool` is an alias for `Hasql.Pool.Pool` |
| HTTP server | **Warp** / **warp-tls** |
| JSON | **Aeson** (derived + manual instances) |
| CORS | **wai-cors** with custom OPTIONS middleware |
| UUID generation | **uuid** + **uuid-v4** (`Data.UUID.V4.nextRandom`) |

### System Flow

**Inventory operations:**

1. Warp receives request; custom OPTIONS middleware handles preflight
2. `wai-cors` applies CORS headers
3. Servant routes to handler in `Server` (inventory) or `Server.Transaction` (POS subsystem)
4. Inventory handlers extract user from `X-User-Id` header via `Auth.Simple.lookupUser` and check capabilities
5. Handlers call `DB.Database` functions which build rel8 queries and execute them inside hasql sessions via `runSession`
6. Results serialized as JSON and returned

**State-machine-backed operations (transactions, registers):**

1. Steps 1-3 above
2. Server handler delegates to the appropriate `Service` function
3. Service layer loads the current entity from the database via `DB.Transaction`
4. `fromTransaction` or `fromRegister` promotes the domain record into a `SomeTxState` or `SomeRegState` existential
5. `runTxCommand` or `runRegCommand` runs the transition function, returning an event and a next state
6. If the event is `InvalidTxCommand` or `InvalidRegCommand`, the service throws `err409` immediately -- no database write occurs
7. If the transition is valid, the service calls the corresponding `DB.Transaction` function to persist the change
8. Result serialized as JSON and returned

## Core Components

### Main Application (`App.hs`)

Bootstraps the server: reads environment variables for DB and server config, initializes the hasql-pool connection pool, creates all tables, configures CORS, conditionally enables TLS, and starts Warp.

```haskell
data AppConfig = AppConfig
  { dbConfig    :: DBConfig
  , serverPort  :: Int
  , tlsCertFile :: Maybe FilePath
  , tlsKeyFile  :: Maybe FilePath
  }

data DBConfig = DBConfig
  { dbHost     :: ByteString
  , dbPort     :: Word
  , dbName     :: ByteString
  , dbUser     :: ByteString
  , dbPassword :: ByteString
  , poolSize   :: Int
  }
```

`DBConfig` fields use `ByteString` for host, name, user, and password, and `Word` for the port, matching the hasql connection parameter API. `initializeDB` builds a `hasql-pool` pool using `Hasql.Pool.Config` settings and runs a smoke-test statement on startup to verify connectivity. The resulting `DBPool` (an alias for `Hasql.Pool.Pool`) is threaded through all handlers and service functions.

Environment variables: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PORT`, `USE_TLS`, `TLS_CERT_FILE`, `TLS_KEY_FILE`. All have defaults. When `USE_TLS=true` and both cert/key files exist on disk, the server starts with `runTLS`; otherwise it falls back to plain HTTP.

CORS is configured to allow any origin (`corsOrigins = Nothing`) with all standard methods and custom headers (`x-requested-with`, `x-user-id`). A separate `handleOptionsMiddleware` intercepts `OPTIONS` requests directly to handle preflight before Servant routing.

### OpenAPI3 Schema (`API/OpenApi.hs`)

`API.OpenApi` composes `InventoryAPI` and `PosAPI` into `CheeblrAPI`, appends a `GET /openapi.json` endpoint, and derives the schema using `servant-openapi3`:

```haskell
type CheeblrAPI =
       InventoryAPI
  :<|> PosAPI
  :<|> "openapi.json" :> Get '[JSON] OpenApi

cheeblrOpenApi :: OpenApi
cheeblrOpenApi = toOpenApi cheeblrAPI
  & info . title       .~ "Cheeblr API"
  & info . version     .~ "1.0"
  & info . description ?~ "Cannabis dispensary POS and inventory management API"
```

Manual `ToSchema` instances are provided for `GQLRequest`, `GQLResponse`, and `OpenApi` itself (each returning an opaque named schema) so that `toOpenApi` can traverse the full API type without errors. All domain types in `Types.Inventory`, `Types.Transaction`, and `Types.Auth` derive `ToSchema` via `DeriveAnyClass`.

### Combined Server (`Server.hs`)

```haskell
combinedServer :: DBPool -> Server CheeblrAPI
combinedServer pool
  =    inventoryServer pool
  :<|> posServerImpl pool
  :<|> pure cheeblrOpenApi
```

`inventoryServer` handles the six inventory endpoints (four CRUD, `/session`, `/graphql/inventory`). Each handler extracts the user from the `X-User-Id` header via `lookupUser`, derives capabilities from the user's role, and gates write operations behind capability checks. Read (GET) is allowed for all authenticated users.

### Database Layer (`DB/Schema.hs`, `DB/Database.hs`, `DB/Transaction.hs`)

`DB.Schema` holds the full set of `Rel8able` row types and corresponding `TableSchema` values:

```haskell
data MenuItemRow f = MenuItemRow
  { menuSort        :: Column f Int32
  , menuSku         :: Column f UUID
  , menuBrand       :: Column f Text
  , ...
  } deriving stock Generic
    deriving anyclass Rel8able

menuItemSchema :: TableSchema (MenuItemRow Name)
menuItemSchema = TableSchema
  { name    = "menu_items"
  , columns = MenuItemRow { menuSort = "sort", menuSku = "sku", ... }
  }
```

`DB.Database` builds queries as rel8 `Query` values, executes them with `runSession`, and converts between row types and domain types via explicit functions (`rowsToMenuItem`, `menuItemToRow`, `strainLineageToRow`, etc.). There are no `FromRow` or `ToRow` instances on domain types.

`DB.Transaction` follows the same pattern for all transaction-related tables. Pure conversion functions (`txDomainToRow`, `txRowToDomain`, `paymentDomainToRow`, etc.) handle all mapping between the `Rel8able` row types and the domain types in `Types.Transaction`.

The three new helper functions added for the server layer are:

- `getInventoryAvailability :: DBPool -> UUID -> IO (Maybe (Int, Int))` -- returns total and reserved quantities for a SKU via rel8 aggregate queries
- `createInventoryReservation :: DBPool -> UUID -> UUID -> UUID -> Int -> UTCTime -> IO ()` -- inserts a reservation row
- `releaseInventoryReservation :: DBPool -> UUID -> IO Bool` -- sets a reservation to `Released`, returning whether a matching row was found

### POS Server (`Server/Transaction.hs`)

```haskell
posServerImpl :: DBPool -> Server PosAPI
posServerImpl pool =
  transactionServer pool
    :<|> registerServer pool
    :<|> ledgerServer pool
    :<|> complianceServer pool
```

All four sub-servers accept `DBPool` rather than `Pool Connection`. The inventory availability, reservation, and release handlers now call `DB.Transaction.getInventoryAvailability`, `DB.Transaction.createInventoryReservation`, and `DB.Transaction.releaseInventoryReservation` respectively, replacing the inline raw SQL that previously appeared in these handlers.

### Service Layer (`Service/Transaction.hs`, `Service/Register.hs`)

Both service modules accept `DBPool` throughout. The common pattern is unchanged:

```haskell
loadTx :: DBPool -> UUID -> Handler (Transaction, SomeTxState)
loadTx pool txId = do
  maybeTx <- liftIO $ DB.getTransactionById pool txId
  case maybeTx of
    Nothing -> throwError err404 { errBody = "Transaction not found" }
    Just tx -> pure (tx, fromTransaction tx)

guardEvent :: TxEvent -> Handler ()
guardEvent (InvalidTxCommand msg) =
  throwError err409 { errBody = LBS.fromStrict (TE.encodeUtf8 msg) }
guardEvent _ = pure ()
```

`loadTx` hydrates the `SomeTxState` from the database. `guardEvent` inspects the event emitted by the state machine and short-circuits with `409 Conflict` if the transition was rejected. Only after `guardEvent` passes does the service call the database write function.

## State Machine Layer

### Design Philosophy

The state machine layer promotes transaction and register lifecycle invariants into compile-time proof obligations. The topology of each machine is a type, not a comment, and every transition clause must satisfy it or the project will not build.

### Key Technologies Used

- **`DataKinds`**: Promotes value-level constructors to type-level inhabitants, allowing them to appear as type indices
- **`GADTs`**: Enables state types indexed by vertex, giving GHC local type equality witnesses at each pattern match branch
- **`TypeFamilies`** and **`singletons-base`**: Bridge the types-versus-values gap; the `singletons` machinery generates a parallel `SRegVertex` / `STxVertex` type whose constructors live at both levels simultaneously

### `State.RegisterMachine`

Manages the `Closed / Open` lifecycle of a cash register.

#### Topology

```haskell
$(singletons [d|
  data RegVertex = RegClosed | RegOpen deriving (Eq, Show)
  |])

type RegTopology = 'Topology
  '[ '( 'RegClosed, '[ 'RegClosed, 'RegOpen])
   , '( 'RegOpen,   '[ 'RegOpen,   'RegClosed])
   ]
```

`RegClosed` can transition to itself or to `RegOpen`. `RegOpen` can transition to itself or to `RegClosed`. Any `regAction` clause that attempts to return a state at a vertex not in the successor list will fail to compile.

#### State Type

```haskell
data RegState (v :: RegVertex) where
  ClosedState :: Register -> RegState 'RegClosed
  OpenState   :: Register -> RegState 'RegOpen
```

#### Existential Wrapper

```haskell
data SomeRegState = forall v. SomeRegState (SRegVertex v) (RegState v)
```

The existential is necessary because `fromRegister` determines the vertex at runtime by inspecting `registerIsOpen`. The singleton `SRegVertex v` travels alongside the state so that callers can recover vertex information by pattern-matching on it.

#### Commands and Events

```haskell
data RegCommand
  = OpenRegCmd  UUID Int
  | CloseRegCmd UUID Int

data RegEvent
  = RegOpened         Register
  | RegWasClosed      Register Int
  | InvalidRegCommand Text
```

#### Transition Function

```haskell
regAction :: RegState v -> RegCommand -> ActionResult Identity RegTopology RegState v RegEvent
```

Variance is computed purely inside `regAction`:

```haskell
regAction (OpenState reg) (CloseRegCmd _ countedCash) =
  let variance = registerExpectedDrawerAmount reg - countedCash
      closed   = reg { registerIsOpen = False, registerCurrentDrawerAmount = countedCash }
  in pureResult (RegWasClosed closed variance) (ClosedState closed)
```

#### Entry Point

```haskell
runRegCommand :: SomeRegState -> RegCommand -> (RegEvent, SomeRegState)
runRegCommand (SomeRegState _ st) cmd =
  case regAction st cmd of
    ActionResult m ->
      let (evt, nextSt) = runIdentity m
      in  (evt, toSomeRegState nextSt)
```

### `State.TransactionMachine`

Manages the full transaction lifecycle.

#### Topology

```haskell
$(singletons [d|
  data TxVertex
    = TxCreated | TxInProgress | TxCompleted | TxVoided | TxRefunded
    deriving (Eq, Show)
  |])

type TxTopology = 'Topology
  '[ '( 'TxCreated,    '[ 'TxCreated,    'TxInProgress, 'TxVoided])
   , '( 'TxInProgress, '[ 'TxInProgress, 'TxCompleted,  'TxVoided])
   , '( 'TxCompleted,  '[ 'TxCompleted,  'TxVoided,     'TxRefunded])
   , '( 'TxVoided,     '[ 'TxVoided])
   , '( 'TxRefunded,   '[ 'TxRefunded])
   ]
```

Terminal states (`TxVoided`, `TxRefunded`) only list themselves as successors. Any attempt to transition out of them produces a compile error.

#### State Type

```haskell
data TxState (v :: TxVertex) where
  CreatedState    :: T.Transaction -> TxState 'TxCreated
  InProgressState :: T.Transaction -> TxState 'TxInProgress
  CompletedState  :: T.Transaction -> TxState 'TxCompleted
  VoidedState     :: T.Transaction -> TxState 'TxVoided
  RefundedState   :: T.Transaction -> TxState 'TxRefunded
```

#### Commands and Events

```haskell
data TxCommand
  = AddItemCmd       T.TransactionItem
  | RemoveItemCmd    UUID
  | AddPaymentCmd    T.PaymentTransaction
  | RemovePaymentCmd UUID
  | FinalizeCmd
  | VoidCmd          Text
  | RefundCmd        Text UUID

data TxEvent
  = ItemAdded        T.TransactionItem
  | ItemRemoved      UUID
  | PaymentAdded     T.PaymentTransaction
  | PaymentRemoved   UUID
  | TxFinalized
  | TxWasVoided      Text
  | TxWasRefunded    Text UUID
  | InvalidTxCommand Text
```

#### Selected Transition Clauses

```haskell
txAction (CreatedState tx) (AddItemCmd item) =
  pureResult (ItemAdded item)
    (InProgressState tx { T.transactionStatus = T.InProgress })

txAction (InProgressState tx) FinalizeCmd =
  pureResult TxFinalized
    (CompletedState tx { T.transactionStatus = T.Completed })

txAction (CompletedState tx) (RefundCmd reason refundId) =
  pureResult (TxWasRefunded reason refundId)
    (RefundedState tx { T.transactionStatus = T.Refunded, ... })

txAction (VoidedState   tx) _ =
  pureResult (InvalidTxCommand "Transaction is voided")   (VoidedState   tx)
txAction (RefundedState tx) _ =
  pureResult (InvalidTxCommand "Transaction is refunded") (RefundedState tx)
```

### `fromTransaction` and `fromRegister`

These functions bridge the database layer into the state machine layer:

```haskell
fromTransaction :: T.Transaction -> SomeTxState
fromTransaction tx = case T.transactionStatus tx of
  T.Created    -> SomeTxState STxCreated    (CreatedState    tx)
  T.InProgress -> SomeTxState STxInProgress (InProgressState tx)
  T.Completed  -> SomeTxState STxCompleted  (CompletedState  tx)
  T.Voided     -> SomeTxState STxVoided     (VoidedState     tx)
  T.Refunded   -> SomeTxState STxRefunded   (RefundedState   tx)

fromRegister :: Register -> SomeRegState
fromRegister reg
  | registerIsOpen reg = SomeRegState SRegOpen   (OpenState   reg)
  | otherwise          = SomeRegState SRegClosed (ClosedState reg)
```

These are total functions. Every possible database state maps to exactly one vertex.

## Authentication and Authorization

### Dev Auth Model (`Auth/Simple.hs`)

Authentication uses a fixed map of dev users, looked up by the `X-User-Id` request header. The header is trusted without verification.

```haskell
lookupUser :: Maybe Text -> AuthenticatedUser
```

`lookupUser` tries two maps in sequence: by key name (`"cashier-1"`, etc., case-insensitive), then by UUID string. If no header is provided or no match is found, defaults to `cashier-1`.

### Dev Users

| Key | Role | UUID |
|---|---|---|
| `customer-1` | Customer | `8244082f-a6bc-4d6c-9427-64a0ecdc10db` |
| `cashier-1` | Cashier | `0a6f2deb-892b-4411-8025-08c1a4d61229` |
| `manager-1` | Manager | `8b75ea4a-00a4-4a2a-a5d5-a1bab8883802` |
| `admin-1` | Admin | `d3a1f4f0-c518-4db3-aa43-e80b428d6304` |

### Roles and Capabilities (`Types/Auth.hs`)

```haskell
data UserRole = Customer | Cashier | Manager | Admin
```

`capabilitiesForRole` maps each role to a `UserCapabilities` record with 15 boolean fields:

| Capability | Customer | Cashier | Manager | Admin |
|---|---|---|---|---|
| `capCanViewInventory` | Y | Y | Y | Y |
| `capCanCreateItem` | N | N | Y | Y |
| `capCanEditItem` | N | Y | Y | Y |
| `capCanDeleteItem` | N | N | Y | Y |
| `capCanProcessTransaction` | N | Y | Y | Y |
| `capCanVoidTransaction` | N | N | Y | Y |
| `capCanRefundTransaction` | N | N | Y | Y |
| `capCanApplyDiscount` | N | N | Y | Y |
| `capCanManageRegisters` | N | N | Y | Y |
| `capCanOpenRegister` | N | Y | Y | Y |
| `capCanCloseRegister` | N | Y | Y | Y |
| `capCanViewReports` | N | N | Y | Y |
| `capCanViewAllLocations` | N | N | N | Y |
| `capCanManageUsers` | N | N | N | Y |
| `capCanViewCompliance` | N | Y | Y | Y |

## API Reference

### Inventory Endpoints

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/inventory` | Any role | All inventory items with available quantities |
| POST | `/inventory` | `capCanCreateItem` | Add a new menu item |
| PUT | `/inventory` | `capCanEditItem` | Update an existing menu item |
| DELETE | `/inventory/:sku` | `capCanDeleteItem` | Delete a menu item by SKU UUID |
| GET | `/session` | Any role | Returns user role and capabilities |
| POST | `/graphql/inventory` | Any role | GraphQL endpoint for inventory queries and mutations |
| GET | `/openapi.json` | None | OpenAPI3 schema for the full API |

`GET /inventory` returns available quantity (stock minus active reservations) rather than raw quantity, via a rel8 left-join aggregate over `inventory_reservation`.

### Transaction Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/transaction` | List all transactions (newest first) |
| GET | `/transaction/:id` | Get transaction with items and payments |
| POST | `/transaction` | Create a new transaction |
| PUT | `/transaction/:id` | Update a transaction |
| POST | `/transaction/void/:id` | Void a transaction with reason |
| POST | `/transaction/refund/:id` | Create a refund (inverse transaction) |
| POST | `/transaction/item` | Add item to transaction (with inventory reservation) |
| DELETE | `/transaction/item/:id` | Remove item (releases reservation) |
| POST | `/transaction/payment` | Add payment to transaction |
| DELETE | `/transaction/payment/:id` | Remove payment |
| POST | `/transaction/finalize/:id` | Finalize transaction (commits reservations, decrements stock) |
| POST | `/transaction/clear/:id` | Clear all items/payments, release reservations, reset totals |

State machine validation applies to all item, payment, finalize, void, and refund operations. Illegal transitions return `409 Conflict`.

### Inventory Availability Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/inventory/available/:sku` | Get total, reserved, and available quantity for a SKU |
| POST | `/inventory/reserve` | Create an inventory reservation |
| DELETE | `/inventory/release/:id` | Release a reservation |

### Register Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/register` | List all registers |
| GET | `/register/:id` | Get register by ID |
| POST | `/register` | Create a register |
| PUT | `/register/:id` | Update a register |
| POST | `/register/open/:id` | Open register with starting cash |
| POST | `/register/close/:id` | Close register, report variance |

Open and close operations pass through `Service.Register`. Attempting to open an already-open register or close an already-closed register returns `409 Conflict`.

### Ledger Endpoints (stubs)

| Method | Endpoint | Status |
|---|---|---|
| GET | `/ledger/entry` | Returns `[]` |
| GET | `/ledger/entry/:id` | Returns `501` |
| GET | `/ledger/account` | Returns `[]` |
| GET | `/ledger/account/:id` | Returns `501` |
| POST | `/ledger/account` | Returns `501` |
| POST | `/ledger/report/daily` | Returns zeroed `DailyReportResult` |

### Compliance Endpoints (stubs)

| Method | Endpoint | Status |
|---|---|---|
| POST | `/compliance/verification` | Echoes back the input |
| GET | `/compliance/record/:transaction_id` | Returns `501` |
| POST | `/compliance/report` | Returns placeholder text |

## Data Models

### Inventory Models (`Types/Inventory.hs`)

Domain types carry only Aeson instances. All database mapping is handled by conversion functions in `DB.Database` operating on the `Rel8able` row types from `DB.Schema`.

#### MenuItem

```haskell
data MenuItem = MenuItem
  { sort :: Int, sku :: UUID, brand :: Text, name :: Text
  , price :: Int
  , measure_unit :: Text, per_package :: Text, quantity :: Int
  , category :: ItemCategory, subcategory :: Text
  , description :: Text
  , tags :: V.Vector Text, effects :: V.Vector Text
  , strain_lineage :: StrainLineage
  }
```

Enums (`category`, `species`) are stored as `TEXT` in the database and round-tripped via `show`/`read` inside the conversion functions.

#### StrainLineage

```haskell
data StrainLineage = StrainLineage
  { thc :: Text, cbg :: Text, strain :: Text, creator :: Text
  , species :: Species, dominant_terpene :: Text
  , terpenes :: V.Vector Text, lineage :: V.Vector Text
  , leafly_url :: Text, img :: Text
  }
```

#### Enums

- **Species**: `Indica | IndicaDominantHybrid | Hybrid | SativaDominantHybrid | Sativa` -- derived `FromJSON`/`ToJSON`/`ToSchema`
- **ItemCategory**: `Flower | PreRolls | Vaporizers | Edibles | Drinks | Concentrates | Topicals | Tinctures | Accessories` -- derived `FromJSON`/`ToJSON`/`ToSchema`

#### Inventory

```haskell
newtype Inventory = Inventory { items :: V.Vector MenuItem }
```

`Inventory` serializes as a bare JSON array (custom `ToJSON`/`FromJSON`).

### Transaction Models (`Types/Transaction.hs`)

#### Transaction

```haskell
data Transaction = Transaction
  { transactionId                     :: UUID
  , transactionStatus                 :: TransactionStatus
  , transactionCreated                :: UTCTime
  , transactionCompleted              :: Maybe UTCTime
  , transactionCustomerId             :: Maybe UUID
  , transactionEmployeeId             :: UUID
  , transactionRegisterId             :: UUID
  , transactionLocationId             :: UUID
  , transactionItems                  :: [TransactionItem]
  , transactionPayments               :: [PaymentTransaction]
  , transactionSubtotal               :: Int
  , transactionDiscountTotal          :: Int
  , transactionTaxTotal               :: Int
  , transactionTotal                  :: Int
  , transactionType                   :: TransactionType
  , transactionIsVoided               :: Bool
  , transactionVoidReason             :: Maybe Text
  , transactionIsRefunded             :: Bool
  , transactionRefundReason           :: Maybe Text
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes                  :: Maybe Text
  }
```

`transactionItems` and `transactionPayments` are populated by `getTransactionById` after the main query, via separate `hydrateTx`/`hydrateItem` passes.

#### Enums

| Type | Values | DB format |
|---|---|---|
| `TransactionStatus` | `Created | InProgress | Completed | Voided | Refunded` | SCREAMING_SNAKE (`CREATED`, `IN_PROGRESS`, etc.) |
| `TransactionType` | `Sale | Return | Exchange | InventoryAdjustment | ManagerComp | Administrative` | SCREAMING_SNAKE |
| `PaymentMethod` | `Cash | Debit | Credit | ACH | GiftCard | StoredValue | Mixed | Other Text` | SCREAMING_SNAKE |
| `TaxCategory` | `RegularSalesTax | ExciseTax | CannabisTax | LocalTax | MedicalTax | NoTax` | SCREAMING_SNAKE |
| `DiscountType` | `PercentOff Scientific | AmountOff Int | BuyOneGetOne | Custom Text Int` | String discriminator + nullable percent column |

JSON serialization uses PascalCase via Aeson's generic deriving. `FromJSON` instances accept both forms for interop with the frontend. DB parsing uses SCREAMING_SNAKE exclusively via the `show*` and `parse*` functions in `DB.Transaction`.

### Request/Response Types (`API/Transaction.hs`)

These types live in the API module and carry `ToJSON`/`FromJSON`/`ToSchema` instances:

```haskell
data Register = Register
  { registerId :: UUID, registerName :: Text, registerLocationId :: UUID
  , registerIsOpen :: Bool
  , registerCurrentDrawerAmount :: Int, registerExpectedDrawerAmount :: Int
  , registerOpenedAt :: Maybe UTCTime, registerOpenedBy :: Maybe UUID
  , registerLastTransactionTime :: Maybe UTCTime }

data AvailableInventory = AvailableInventory
  { availableTotal :: Int, availableReserved :: Int, availableActual :: Int }

data ReservationRequest = ReservationRequest
  { reserveItemSku :: UUID, reserveTransactionId :: UUID, reserveQuantity :: Int }

data OpenRegisterRequest  = OpenRegisterRequest  { openRegisterEmployeeId :: UUID, openRegisterStartingCash :: Int }
data CloseRegisterRequest = CloseRegisterRequest { closeRegisterEmployeeId :: UUID, closeRegisterCountedCash :: Int }
data CloseRegisterResult  = CloseRegisterResult  { closeRegisterResultRegister :: Register, closeRegisterResultVariance :: Int }

data DailyReportRequest = DailyReportRequest { dailyReportDate :: UTCTime, dailyReportLocationId :: UUID }
data DailyReportResult  = DailyReportResult  { dailyReportCash :: Int, dailyReportCard :: Int, dailyReportOther :: Int, dailyReportTotal :: Int, dailyReportTransactions :: Int }

data ComplianceReportRequest = ComplianceReportRequest
  { complianceReportStartDate :: UTCTime, complianceReportEndDate :: UTCTime, complianceReportLocationId :: UUID }

newtype ComplianceReportResult = ComplianceReportResult { complianceReportContent :: Text }
```

## Database Schema

### Inventory Tables

```sql
CREATE TABLE IF NOT EXISTS menu_items (
    sort INT NOT NULL,
    sku UUID PRIMARY KEY,
    brand TEXT NOT NULL,
    name TEXT NOT NULL,
    price INTEGER NOT NULL,
    measure_unit TEXT NOT NULL,
    per_package TEXT NOT NULL,
    quantity INT NOT NULL,
    category TEXT NOT NULL,
    subcategory TEXT NOT NULL,
    description TEXT NOT NULL,
    tags TEXT[] NOT NULL,
    effects TEXT[] NOT NULL
)
```

```sql
CREATE TABLE IF NOT EXISTS strain_lineage (
    sku UUID PRIMARY KEY REFERENCES menu_items(sku),
    thc TEXT NOT NULL,
    cbg TEXT NOT NULL,
    strain TEXT NOT NULL,
    creator TEXT NOT NULL,
    species TEXT NOT NULL,
    dominant_terpene TEXT NOT NULL,
    terpenes TEXT[] NOT NULL,
    lineage TEXT[] NOT NULL,
    leafly_url TEXT NOT NULL,
    img TEXT NOT NULL
)
```

### Transaction Tables

All transaction tables are created by `createTransactionTables` using `CREATE TABLE IF NOT EXISTS` DDL statements executed as hasql sessions.

```sql
CREATE TABLE IF NOT EXISTS transaction (
    id UUID PRIMARY KEY,
    status TEXT NOT NULL,
    created TIMESTAMP WITH TIME ZONE NOT NULL,
    completed TIMESTAMP WITH TIME ZONE,
    customer_id UUID,
    employee_id UUID NOT NULL,
    register_id UUID NOT NULL,
    location_id UUID NOT NULL,
    subtotal INTEGER NOT NULL,
    discount_total INTEGER NOT NULL,
    tax_total INTEGER NOT NULL,
    total INTEGER NOT NULL,
    transaction_type TEXT NOT NULL,
    is_voided BOOLEAN NOT NULL DEFAULT FALSE,
    void_reason TEXT,
    is_refunded BOOLEAN NOT NULL DEFAULT FALSE,
    refund_reason TEXT,
    reference_transaction_id UUID,
    notes TEXT
)
```

```sql
CREATE TABLE IF NOT EXISTS transaction_item (
    id UUID PRIMARY KEY,
    transaction_id UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,
    menu_item_sku UUID NOT NULL,
    quantity INTEGER NOT NULL,
    price_per_unit INTEGER NOT NULL,
    subtotal INTEGER NOT NULL,
    total INTEGER NOT NULL
)
```

```sql
CREATE TABLE IF NOT EXISTS transaction_tax (
    id UUID PRIMARY KEY,
    transaction_item_id UUID NOT NULL REFERENCES transaction_item(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    rate NUMERIC NOT NULL,
    amount INTEGER NOT NULL,
    description TEXT NOT NULL
)
```

```sql
CREATE TABLE IF NOT EXISTS discount (
    id UUID PRIMARY KEY,
    transaction_item_id UUID REFERENCES transaction_item(id) ON DELETE CASCADE,
    transaction_id UUID REFERENCES transaction(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    amount INTEGER NOT NULL,
    percent NUMERIC,
    reason TEXT NOT NULL,
    approved_by UUID
)
```

```sql
CREATE TABLE IF NOT EXISTS payment_transaction (
    id UUID PRIMARY KEY,
    transaction_id UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,
    method TEXT NOT NULL,
    amount INTEGER NOT NULL,
    tendered INTEGER NOT NULL,
    change_amount INTEGER NOT NULL,
    reference TEXT,
    approved BOOLEAN NOT NULL DEFAULT FALSE,
    authorization_code TEXT
)
```

```sql
CREATE TABLE IF NOT EXISTS register (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    location_id UUID NOT NULL,
    is_open BOOLEAN NOT NULL DEFAULT FALSE,
    current_drawer_amount INTEGER NOT NULL DEFAULT 0,
    expected_drawer_amount INTEGER NOT NULL DEFAULT 0,
    opened_at TIMESTAMP WITH TIME ZONE,
    opened_by UUID,
    last_transaction_time TIMESTAMP WITH TIME ZONE
)
```

```sql
CREATE TABLE IF NOT EXISTS inventory_reservation (
    id UUID PRIMARY KEY,
    item_sku UUID NOT NULL,
    transaction_id UUID NOT NULL,
    quantity INTEGER NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
)
```

## Transaction Processing

### Transaction Lifecycle

1. **Creation** (`POST /transaction`): Transaction inserted with status `CREATED` and zero totals.
2. **Item Addition** (`POST /transaction/item`): `Service.Transaction.addItem` loads the transaction, calls `runTxCommand` with `AddItemCmd`. The state machine validates the transition (only `Created` and `InProgress` states accept items). If valid, `DB.Transaction.addTransactionItem` checks availability via a rel8 aggregate query over `inventory_reservation`, creates a reservation row, and inserts the transaction item.
3. **Payment Addition** (`POST /transaction/payment`): `Service.Transaction.addPayment` validates via `AddPaymentCmd`, inserts the payment, and auto-updates transaction status -- if total payments >= transaction total, status becomes `COMPLETED`, otherwise `IN_PROGRESS`.
4. **Finalization** (`POST /transaction/finalize/:id`): `Service.Transaction.finalizeTx` validates via `FinalizeCmd` (only `InProgress` transactions can be finalized). Decrements `menu_items.quantity`, changes reservation status to `"Completed"`, sets transaction status to `COMPLETED`.

### Transaction Reversal Operations

**Void** (`POST /transaction/void/:id`): `Service.Transaction.voidTx` validates via `VoidCmd`. Permitted from `Created`, `InProgress`, and `Completed`. Terminal states reject the command at the machine level. Sets status to `VOIDED`, marks `is_voided = TRUE`, records reason. Does not reverse inventory.

**Refund** (`POST /transaction/refund/:id`): `Service.Transaction.refundTx` validates via `RefundCmd`. Only `Completed` transactions can be refunded -- the topology enforces this. Creates a new inverse transaction with negated monetary amounts, type `Return`, referencing the original. Marks the original as `is_refunded = TRUE`.

### Clear Transaction (`POST /transaction/clear/:id`)

Resets a transaction to empty state without passing through the state machine:

1. Releases all active reservations (status to `"Released"`)
2. Deletes payments and transaction items (taxes and discounts cascade)
3. Resets monetary totals to 0
4. Sets status back to `CREATED`

### Automatic Total Recalculation

`updateTransactionTotals` is called after item removal. It recalculates subtotal, discount total, tax total, and grand total from the database using rel8 aggregate queries. `updateTransactionPaymentStatus` checks if payments cover the total and updates status accordingly.

### Data Assembly Pattern

`hydrateTx` fetches the base transaction row then separately fetches items (which themselves fetch their discounts and taxes via `hydrateItem`) and payments. This multi-query assembly pattern matches the rel8 style where each query is a typed `Session` value executed independently.

## Inventory Reservation System

The reservation system prevents overselling by tracking inventory commitments before finalization.

### Flow

1. **Check availability**: `addTransactionItem` runs a rel8 aggregate query for `menu_items.quantity` minus `SUM(inventory_reservation.quantity)` where status is `"Reserved"`
2. **Reserve**: Creates a reservation row with status `"Reserved"`
3. **On item removal**: Reservation status set to `"Released"`
4. **On finalization**: Actual `menu_items.quantity` decremented, reservation status set to `"Completed"`
5. **On clear**: All reservations for the transaction set to `"Released"`

### Error Handling

Custom exceptions for inventory operations:

```haskell
data InventoryException
  = ItemNotFound UUID
  | InsufficientInventory UUID Int Int
```

`addTransactionItemHandler` catches these and returns structured JSON error responses with `err400`.

## Security and Configuration

### CORS Configuration

Two layers:

1. **`handleOptionsMiddleware`**: Intercepts all `OPTIONS` requests before Servant, returning `200` with permissive CORS headers.
2. **`wai-cors` middleware**: Applied to all other requests with `corsOrigins = Nothing` (any origin), all standard methods, and custom headers (`x-requested-with`, `x-user-id`). `corsMaxAge = 86400`. `corsIgnoreFailures = True`.

### TLS Configuration

When `USE_TLS=true` and `TLS_CERT_FILE`/`TLS_KEY_FILE` point to existing files, the server starts with `warp-tls`. If files are missing, it logs a warning and falls back to plain HTTP. The `onException` handler suppresses `TLSException` noise from client disconnects.

### Server Configuration

| Setting | Value |
|---|---|
| Port | `PORT` env var, default 8080 |
| DB host | `PGHOST` env var, default `localhost` |
| DB port | `PGPORT` env var, default 5432 |
| DB name | `PGDATABASE` env var, default `cheeblr` |
| DB user | `PGUSER` env var, default current system user |
| DB password | `PGPASSWORD` env var, default bootstrap fallback string |
| Pool size | 10 |
| Pool acquisition timeout | 30 seconds |

## Development Guidelines

### Project Structure Convention

- `API/` -- Servant type definitions and request/response types. No business logic. `API.OpenApi` owns the combined type and schema.
- `Auth/` -- Authentication/authorization. Currently dev-only.
- `State/` -- State machine definitions. Pure functions only. No IO, no database access, no Servant.
- `Service/` -- Business logic combining state machine validation with database effects. No SQL lives here.
- `Server/` and `Server.hs` -- Request handlers. Inventory handlers in `Server.hs`, POS handlers in `Server/Transaction.hs`. State-machine-backed operations delegate to `Service/`.
- `DB/Schema.hs` -- The single source of truth for table structure. Adding or modifying a table means updating the `Rel8able` row type and `TableSchema` here first.
- `DB/Database.hs` and `DB/Transaction.hs` -- Database operations. All rel8 queries and hasql sessions live here. All domain-to-row and row-to-domain conversion functions live here.
- `Types/` -- Domain models with Aeson and `ToSchema` instances. No effects. No database instances.

### Database Patterns

- **Pool access**: All database operations call `runSession pool session` where `session` is a hasql `Session` value built from rel8 `select`, `insert`, `update`, or `delete` expressions
- **DDL**: `createTables` and `createTransactionTables` execute raw DDL as `Statement () ()` values via the `ddl` helper in `DB.Database`
- **Aggregates**: Reservation counts use rel8's `aggregate`/`sumOn`/`groupByOn` combinators
- **Returning counts**: Delete operations that need row counts use `runN` (returns `Int64`) rather than `run_`

### Enum Serialization Convention

Enums are stored as SCREAMING_SNAKE_CASE text in the database via explicit `show*` functions in `DB.Transaction` (`showStatus`, `showTransactionType`, `showPaymentMethod`, etc.). JSON serialization uses PascalCase via Aeson's generic deriving. `FromJSON` instances accept both forms. `parse*` functions in `DB.Transaction` and `Types.Transaction` handle SCREAMING_SNAKE on read.

### Error Handling

- Database operations use `try @SomeException` with descriptive error messages
- State machine validation uses `guardEvent` in service functions, returning `err409` with the rejection message
- Transaction item addition uses custom `InventoryException` types caught and converted to `err400` with JSON error bodies
- Missing resources return `err404`
- Unimplemented endpoints return `err501`
- Capability violations return `err403`
- Server logging goes to stdout (handler activity) and stderr (database operations, table creation)

### Known Issues and Tech Debt

- **No real authentication**: `X-User-Id` header is trusted without verification. Default user is cashier, not admin.
- **Capability enforcement incomplete**: Only inventory write endpoints check capabilities. Transaction and register endpoints do not enforce role-based access.
- **Ledger and compliance are stubs**: Endpoints exist and types are defined, but no database tables or real logic back them.
- **`PaymentMethod.Other` text dropped on DB write**: `showPaymentMethod (Other text) = "OTHER"` -- the custom text payload is lost in the database.
- **`DiscountType` round-trip lossy**: `parseDiscountType` reconstructs from a `(Text, Maybe Int)` tuple; `PercentOff` stores `Scientific` in Haskell while the DB stores a nullable `NUMERIC`.
- **No inventory reservation expiry**: Reservations with status `"Reserved"` persist indefinitely if a transaction is abandoned.
- **`error` calls in DB layer**: Several functions use `error` for "impossible" post-write states, which would crash the server thread rather than returning an HTTP error.
- **State machine and DB status can diverge**: `fromTransaction` trusts `transactionStatus` as stored. If a DB write partially fails after a state machine transition was validated, the two can fall out of sync.
- **`clear` bypasses the state machine**: `clearTransaction` resets a transaction to `CREATED` directly in the database without going through `runTxCommand`. This is intentional as an operational escape hatch.

---

For a deeper look at the design tradeoffs in the state machine layer, including why singletons exist, what the GHC warnings mean, and how dependent types would change the picture, see [Crem.md](./Crem.md).