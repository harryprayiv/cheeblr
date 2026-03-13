# Cheeblr Backend Documentation

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [State Machine Layer](#state-machine-layer)
- [Authentication & Authorization](#authentication--authorization)
- [API Reference](#api-reference)
- [Data Models](#data-models)
- [Database Schema](#database-schema)
- [Transaction Processing](#transaction-processing)
- [Inventory Reservation System](#inventory-reservation-system)
- [Security and Configuration](#security-and-configuration)
- [Development Guidelines](#development-guidelines)

## Overview

The Cheeblr backend is a Haskell-based API server built for inventory and transaction management in cannabis dispensary retail operations. It provides inventory tracking with reservation-based availability, point-of-sale transaction processing, cash register operations, compliance verification, and financial reporting stubs.

The system uses a layered architecture with Servant for type-safe API definitions and PostgreSQL for persistence. State machine transitions for transactions and registers are enforced at compile time via [crem](https://github.com/tweag/crem), a library that encodes state machine topologies as type-level constraints. All monetary values are stored as integer cents to avoid floating-point rounding.

For a detailed treatment of what crem adds to the codebase and how it compares to full dependent types, see [Crem.md](./Crem.md).

## Architecture

### Architectural Layers

1. **API Layer** (`API/`): Type-level API definitions using Servant's DSL. `API.Inventory` defines the inventory CRUD endpoints with auth headers. `API.Transaction` defines the POS, register, ledger, and compliance endpoints plus all request/response types that are not domain models.
2. **Server Layer** (`Server.hs`, `Server/Transaction.hs`): Request handlers. `Server` handles inventory endpoints with capability checks. `Server.Transaction` implements all POS subsystem handlers (transactions, registers, ledger, compliance).
3. **Service Layer** (`Service/`): Business logic that sits between the server and database layers for state-machine-backed operations. `Service.Transaction` and `Service.Register` load domain state, run the relevant state machine transition to validate the command, and only proceed to the database if the transition is legal.
4. **State Machine Layer** (`State/`): Compile-time-enforced state machine definitions built on crem. `State.TransactionMachine` and `State.RegisterMachine` define the vertex types, GADT-indexed state types, topologies, commands, events, and transition functions. No IO. No database access. Pure transition logic only.
5. **Database Layer** (`DB/`): `DB.Database` handles inventory CRUD and connection pooling. `DB.Transaction` handles all transaction, register, reservation, and payment database operations.
6. **Auth Layer** (`Auth/Simple.hs`): Dev-mode authentication via `X-User-Id` header lookup against a fixed set of dev users, with role-based capability gating.
7. **Types Layer** (`Types/`): Domain models — `Types.Inventory` (menu items, strain lineage, inventory response), `Types.Transaction` (transactions, payments, taxes, discounts, compliance, ledger), `Types.Auth` (roles, capabilities).
8. **Application Core** (`App.hs`): Server bootstrap, CORS configuration, TLS configuration, middleware setup.

### Key Technologies

| Concern | Library |
|---|---|
| API definition | **Servant** — type-level web DSL |
| State machine enforcement | **crem** — topology-indexed state machines |
| Singleton types | **singletons-base** — bridges type-level and value-level universe |
| Database | **postgresql-simple** with `sql` quasiquoter |
| Connection pooling | **resource-pool** (`Data.Pool`) |
| HTTP server | **Warp** / **warp-tls** |
| JSON | **Aeson** (derived + manual instances) |
| CORS | **wai-cors** with custom OPTIONS middleware |
| UUID generation | **uuid** + **uuid-v4** (`Data.UUID.V4.nextRandom`) |

### System Flow

**Inventory operations:**

1. Warp receives request, custom OPTIONS middleware handles preflight
2. `wai-cors` applies CORS headers
3. Servant routes to handler in `Server` (inventory) or `Server.Transaction` (POS subsystem)
4. Inventory handlers extract user from `X-User-Id` header via `Auth.Simple.lookupUser`, check capabilities
5. Handlers interact with `DB.Database`
6. Results serialized as JSON and returned

**State-machine-backed operations (transactions, registers):**

1. Steps 1-3 above
2. Server handler delegates to the appropriate `Service` function
3. Service layer loads the current entity from the database
4. `fromTransaction` or `fromRegister` promotes the DB row into a `SomeTxState` or `SomeRegState` existential
5. `runTxCommand` or `runRegCommand` runs the transition function against the promoted state, returning an event and a next state
6. If the event is `InvalidTxCommand` or `InvalidRegCommand`, the service throws `err409` immediately — no database write occurs
7. If the transition is valid, the service calls the corresponding `DB.Transaction` function to persist the change
8. Result serialized as JSON and returned

## Core Components

### Main Application (`App.hs`)

Bootstraps the server: reads environment variables for DB and server config, initializes the connection pool, creates all tables, configures CORS, conditionally enables TLS, and starts Warp.

```haskell
data AppConfig = AppConfig
  { dbConfig    :: DBConfig
  , serverPort  :: Int
  , tlsCertFile :: Maybe FilePath
  , tlsKeyFile  :: Maybe FilePath
  }
```

Environment variables: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PORT`, `USE_TLS`, `TLS_CERT_FILE`, `TLS_KEY_FILE`. All have defaults. When `USE_TLS=true` and both cert/key files exist on disk, the server starts with `runTLS`; otherwise it falls back to plain HTTP.

CORS is configured to allow any origin (`corsOrigins = Nothing`) with all standard methods and custom headers (`x-requested-with`, `x-user-id`). A separate `handleOptionsMiddleware` intercepts `OPTIONS` requests directly to handle preflight before Servant routing.

### Combined Server (`Server.hs`)

```haskell
type API = InventoryAPI :<|> PosAPI

combinedServer :: Pool Connection -> Server API
combinedServer pool = inventoryServer pool :<|> posServerImpl pool
```

`inventoryServer` handles the five inventory endpoints (four CRUD plus `/session`). Each handler extracts the user from the `X-User-Id` header via `lookupUser`, derives capabilities from the user's role, and gates write operations behind capability checks (`capCanCreateItem`, `capCanEditItem`, `capCanDeleteItem`). Read (GET) is allowed for all authenticated users.

### POS Server (`Server/Transaction.hs`)

```haskell
posServerImpl :: Pool Connection -> Server PosAPI
posServerImpl pool =
  transactionServer pool
    :<|> registerServer pool
    :<|> ledgerServer pool
    :<|> complianceServer pool
```

Four sub-servers compose the POS API:
- **transactionServer**: Full transaction CRUD, item management, payment management, finalization, clearing, plus inventory availability/reservation/release endpoints
- **registerServer**: Register CRUD, open/close operations
- **ledgerServer**: Stub implementations — returns empty lists or `501 Not Implemented`
- **complianceServer**: Stub implementations — echoes verification, returns `501` for record lookup, returns placeholder report

### Service Layer (`Service/Transaction.hs`, `Service/Register.hs`)

The service layer is the integration point between the server handlers and the state machines. Its responsibilities are narrow: load state, validate the transition, delegate to the database.

```haskell
-- Service.Transaction
addItem    :: Pool Connection -> TransactionItem    -> Handler TransactionItem
removeItem :: Pool Connection -> UUID               -> Handler NoContent
addPayment :: Pool Connection -> PaymentTransaction -> Handler PaymentTransaction
removePayment :: Pool Connection -> UUID            -> Handler NoContent
finalizeTx :: Pool Connection -> UUID              -> Handler Transaction
voidTx     :: Pool Connection -> UUID -> Text      -> Handler Transaction
refundTx   :: Pool Connection -> UUID -> Text      -> Handler Transaction
```

```haskell
-- Service.Register
openRegister  :: Pool Connection -> UUID -> OpenRegisterRequest  -> Handler Register
closeRegister :: Pool Connection -> UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
```

The common pattern throughout both modules is:

```haskell
loadTx :: Pool Connection -> UUID -> Handler (Transaction, SomeTxState)
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

`loadTx` hydrates the `SomeTxState` from the database row. `guardEvent` inspects the event that the state machine emitted and short-circuits with `409 Conflict` if the transition was rejected. Only after `guardEvent` passes does the service call the database write function. The state machine never touches IO; all effects are the service layer's responsibility.

## State Machine Layer

### Design Philosophy

Before crem, transaction and register state transitions were enforced entirely by convention and tests. A handler could attempt to finalize a voided transaction and the type system would not object. The state machine layer promotes those invariants into compile-time proof obligations. The topology of each machine is a type, not a comment, and every transition clause must satisfy it or the project will not build.

### Key Technologies Used

crem uses several GHC extensions to achieve this:

- **`DataKinds`**: Promotes value-level constructors (e.g. `RegClosed`) to type-level inhabitants (e.g. `'RegClosed :: RegVertex`), allowing them to appear as type indices
- **`GADTs`**: Enables state types indexed by vertex, giving GHC local type equality witnesses at each pattern match branch
- **`TypeFamilies`** and **`singletons-base`**: Bridge the types-versus-values gap. Since GHC erases types at runtime, a promoted type like `'RegClosed` cannot be inspected at runtime. The `singletons` machinery generates a parallel `SRegVertex` type whose constructors (`SRegClosed`, `SRegOpen`) live at both levels simultaneously

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

`RegClosed` can transition to itself or to `RegOpen`. `RegOpen` can transition to itself or to `RegClosed`. Any `regAction` clause that attempts to return a state at a vertex not in the successor list for the current vertex will fail to compile.

#### State Type

```haskell
data RegState (v :: RegVertex) where
  ClosedState :: Register -> RegState 'RegClosed
  OpenState   :: Register -> RegState 'RegOpen
```

The GADT index `v` is a phantom at runtime but a hard constraint at compile time. `regAction (ClosedState reg) cmd` can only return states whose vertex type is in `successors 'RegClosed`.

#### Existential Wrapper

```haskell
data SomeRegState = forall v. SomeRegState (SRegVertex v) (RegState v)
```

The existential is necessary because `fromRegister` determines the vertex at runtime by inspecting `registerIsOpen`. The singleton `SRegVertex v` travels alongside the state so that callers can recover vertex information by pattern-matching on it without losing the type-index connection to the state.

#### Commands and Events

```haskell
data RegCommand
  = OpenRegCmd  UUID Int   -- employee id, starting cash
  | CloseRegCmd UUID Int   -- employee id, counted cash

data RegEvent
  = RegOpened         Register
  | RegWasClosed      Register Int   -- register, variance
  | InvalidRegCommand Text
```

#### Transition Function

```haskell
regAction :: RegState v -> RegCommand -> ActionResult Identity RegTopology RegState v RegEvent
```

`ActionResult` is a crem type that wraps the next state in a way that lets the library verify, at the type level, that the next-state vertex is reachable from `v` in `RegTopology`. Attempting to return an `OpenState` from a `(ClosedState reg, CloseRegCmd _ _)` branch produces a compile error.

Variance is computed purely inside `regAction`:

```haskell
regAction (OpenState reg) (CloseRegCmd _ countedCash) =
  let variance = registerExpectedDrawerAmount reg - countedCash
      closed   = reg { registerIsOpen = False, registerCurrentDrawerAmount = countedCash }
  in pureResult (RegWasClosed closed variance) (ClosedState closed)
```

Invalid commands (e.g. opening an already-open register) produce `InvalidRegCommand` and leave the state unchanged, which is legal since both vertices include themselves in their successor lists.

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

Terminal states (`TxVoided`, `TxRefunded`) only list themselves as successors. Any attempt to transition out of them produces a compile error. `TxCreated` can only reach `TxInProgress` via `AddItemCmd`, not directly reach `TxCompleted` — the type system enforces that finalization requires passing through `InProgress`.

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
-- First item addition transitions Created -> InProgress
txAction (CreatedState tx) (AddItemCmd item) =
  pureResult (ItemAdded item)
    (InProgressState tx { T.transactionStatus = T.InProgress })

-- Finalization transitions InProgress -> Completed
txAction (InProgressState tx) FinalizeCmd =
  pureResult TxFinalized
    (CompletedState tx { T.transactionStatus = T.Completed })

-- Refund only available from Completed
txAction (CompletedState tx) (RefundCmd reason refundId) =
  pureResult (TxWasRefunded reason refundId)
    (RefundedState tx { T.transactionStatus = T.Refunded, ... })

-- Terminal states reject everything
txAction (VoidedState   tx) _ =
  pureResult (InvalidTxCommand "Transaction is voided")   (VoidedState   tx)
txAction (RefundedState tx) _ =
  pureResult (InvalidTxCommand "Transaction is refunded") (RefundedState tx)
```

The `cmdLabel` helper produces readable error messages for the catch-all invalid-command clauses at each non-terminal vertex.

### `fromTransaction` and `fromRegister`

These functions are the bridge from the database layer into the state machine layer:

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

These are total functions. Every possible database state maps to exactly one vertex. The singleton constructor (`STxCreated`, `SRegOpen`, etc.) carried in the existential is what allows downstream code to recover the vertex without losing the type index.

## Authentication & Authorization

### Dev Auth Model (`Auth/Simple.hs`)

Authentication uses a fixed map of dev users, looked up by the `X-User-Id` request header. There is no real authentication — the header is trusted.

```haskell
type AuthHeader = Header "X-User-Id" Text

lookupUser :: Maybe Text -> AuthenticatedUser
```

`lookupUser` tries two maps in sequence:
1. **By key name**: `"customer-1"`, `"cashier-1"`, `"manager-1"`, `"admin-1"` (case-insensitive)
2. **By UUID string**: The actual UUID values for each dev user

If no header is provided or no match is found, defaults to `cashier-1`.

### Dev Users

| Key | Role | UUID |
|---|---|---|
| `customer-1` | Customer | `8244082f-a6bc-4d6c-9427-64a0ecdc10db` |
| `cashier-1` | Cashier | `0a6f2deb-892b-4411-8025-08c1a4d61229` |
| `manager-1` | Manager | `8b75ea4a-00a4-4a2a-a5d5-a1bab8883802` |
| `admin-1` | Admin | `d3a1f4f0-c518-4db3-aa43-e80b428d6304` |

All dev users have `auLocationId = Just "b2bd4b3a-..."` except Customer and Admin (which have `Nothing`).

### Roles & Capabilities (`Types/Auth.hs`)

```haskell
data UserRole = Customer | Cashier | Manager | Admin
```

`capabilitiesForRole` maps each role to a `UserCapabilities` record with 15 boolean fields:

| Capability | Customer | Cashier | Manager | Admin |
|---|---|---|---|---|
| `capCanViewInventory` | ✓ | ✓ | ✓ | ✓ |
| `capCanCreateItem` | ✗ | ✗ | ✓ | ✓ |
| `capCanEditItem` | ✗ | ✓ | ✓ | ✓ |
| `capCanDeleteItem` | ✗ | ✗ | ✓ | ✓ |
| `capCanProcessTransaction` | ✗ | ✓ | ✓ | ✓ |
| `capCanVoidTransaction` | ✗ | ✗ | ✓ | ✓ |
| `capCanRefundTransaction` | ✗ | ✗ | ✓ | ✓ |
| `capCanApplyDiscount` | ✗ | ✗ | ✓ | ✓ |
| `capCanManageRegisters` | ✗ | ✗ | ✓ | ✓ |
| `capCanOpenRegister` | ✗ | ✓ | ✓ | ✓ |
| `capCanCloseRegister` | ✗ | ✓ | ✓ | ✓ |
| `capCanViewReports` | ✗ | ✗ | ✓ | ✓ |
| `capCanViewAllLocations` | ✗ | ✗ | ✗ | ✓ |
| `capCanManageUsers` | ✗ | ✗ | ✗ | ✓ |
| `capCanViewCompliance` | ✗ | ✓ | ✓ | ✓ |

### Capability Enforcement

`requireAuth` is a reusable handler combinator:

```haskell
requireAuth :: Maybe Text -> (UserCapabilities -> Bool) -> Text -> Handler AuthenticatedUser
```

It looks up the user, checks the capability predicate, and either returns the user or throws `err403`. Currently, only inventory write endpoints use explicit capability checks (directly in handlers rather than via `requireAuth`). Transaction and register endpoints do not yet enforce capabilities — the state machine layer validates transition legality but not caller authorization.

## API Reference

### Inventory Endpoints

All inventory endpoints require the `X-User-Id` header.

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/inventory` | Any role | Returns all inventory items |
| POST | `/inventory` | `capCanCreateItem` | Add a new menu item |
| PUT | `/inventory` | `capCanEditItem` | Update an existing menu item |
| DELETE | `/inventory/:sku` | `capCanDeleteItem` | Delete a menu item by SKU UUID |
| GET | `/session` | Any role | Returns user role and capabilities |
| POST | `/graphql/inventory` | Any role | GraphQL endpoint for inventory queries and mutations |

**Note**: `GET /inventory` returns `available_quantity` (stock minus active reservations) rather than raw `quantity`, via a LEFT JOIN on `inventory_reservation`.

### Transaction Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/transaction` | List all transactions (newest first) |
| GET | `/transaction/:id` | Get transaction by ID with items and payments |
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

State machine validation applies to all item, payment, finalize, void, and refund operations. Illegal transitions return `409 Conflict` with the rejection message as the response body.

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

Open and close operations pass through `Service.Register`, which validates the transition via `State.RegisterMachine` before writing. Attempting to open an already-open register or close an already-closed register returns `409 Conflict`.

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

#### MenuItem

```haskell
data MenuItem = MenuItem
  { sort :: Int, sku :: UUID, brand :: Text, name :: Text
  , price :: Int              -- cents
  , measure_unit :: Text, per_package :: Text, quantity :: Int
  , category :: ItemCategory, subcategory :: Text
  , description :: Text
  , tags :: V.Vector Text, effects :: V.Vector Text
  , strain_lineage :: StrainLineage
  }
```

Has manual `ToRow`/`FromRow` instances. `FromRow` reads 23 columns (13 from `menu_items` + 10 from `strain_lineage` via JOIN). Enums (`category`, `species`) are stored as `TEXT` and round-tripped via `show`/`read`.

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

- **Species**: `Indica | IndicaDominantHybrid | Hybrid | SativaDominantHybrid | Sativa` — derived `FromJSON`/`ToJSON`
- **ItemCategory**: `Flower | PreRolls | Vaporizers | Edibles | Drinks | Concentrates | Topicals | Tinctures | Accessories` — derived `FromJSON`/`ToJSON`

#### Inventory

```haskell
newtype Inventory = Inventory { items :: V.Vector MenuItem }
```

`Inventory` serializes as a bare JSON array (custom `ToJSON`/`FromJSON`).

### Transaction Models (`Types/Transaction.hs`)

#### Transaction

```haskell
data Transaction = Transaction
  { transactionId :: UUID
  , transactionStatus :: TransactionStatus
  , transactionCreated :: UTCTime
  , transactionCompleted :: Maybe UTCTime
  , transactionCustomerId :: Maybe UUID
  , transactionEmployeeId :: UUID
  , transactionRegisterId :: UUID
  , transactionLocationId :: UUID
  , transactionItems :: [TransactionItem]
  , transactionPayments :: [PaymentTransaction]
  , transactionSubtotal :: Int          -- cents
  , transactionDiscountTotal :: Int     -- cents
  , transactionTaxTotal :: Int          -- cents
  , transactionTotal :: Int             -- cents
  , transactionType :: TransactionType
  , transactionIsVoided :: Bool
  , transactionVoidReason :: Maybe Text
  , transactionIsRefunded :: Bool
  , transactionRefundReason :: Maybe Text
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes :: Maybe Text
  }
```

Has a custom `FromJSON` instance using `.:?` for optional fields. `FromRow` reads 19 columns from the `transaction` table and initializes `transactionItems`/`transactionPayments` as `[]` (populated separately by `getTransactionById`).

#### TransactionItem

```haskell
data TransactionItem = TransactionItem
  { transactionItemId :: UUID
  , transactionItemTransactionId :: UUID
  , transactionItemMenuItemSku :: UUID
  , transactionItemQuantity :: Int
  , transactionItemPricePerUnit :: Int  -- cents
  , transactionItemDiscounts :: [DiscountRecord]
  , transactionItemTaxes :: [TaxRecord]
  , transactionItemSubtotal :: Int      -- cents
  , transactionItemTotal :: Int         -- cents
  }
```

`FromRow` reads 7 columns; `transactionItemDiscounts` and `transactionItemTaxes` are populated separately.

#### PaymentTransaction

```haskell
data PaymentTransaction = PaymentTransaction
  { paymentId :: UUID
  , paymentTransactionId :: UUID
  , paymentMethod :: PaymentMethod
  , paymentAmount :: Int          -- cents
  , paymentTendered :: Int        -- cents
  , paymentChange :: Int          -- cents
  , paymentReference :: Maybe Text
  , paymentApproved :: Bool
  , paymentAuthorizationCode :: Maybe Text
  }
```

#### InventoryReservation

```haskell
data InventoryReservation = InventoryReservation
  { reservationItemSku :: UUID
  , reservationTransactionId :: UUID
  , reservationQuantity :: Int
  , reservationStatus :: Text     -- "Reserved" | "Released" | "Completed"
  }
```

#### Enums

| Type | Values | DB format |
|---|---|---|
| `TransactionStatus` | `Created \| InProgress \| Completed \| Voided \| Refunded` | SCREAMING_SNAKE (`CREATED`, `IN_PROGRESS`, etc.) |
| `TransactionType` | `Sale \| Return \| Exchange \| InventoryAdjustment \| ManagerComp \| Administrative` | SCREAMING_SNAKE |
| `PaymentMethod` | `Cash \| Debit \| Credit \| ACH \| GiftCard \| StoredValue \| Mixed \| Other Text` | SCREAMING_SNAKE; `Other` stored as `"OTHER"` (text payload dropped on DB write) |
| `TaxCategory` | `RegularSalesTax \| ExciseTax \| CannabisTax \| LocalTax \| MedicalTax \| NoTax` | SCREAMING_SNAKE |
| `DiscountType` | `PercentOff Scientific \| AmountOff Int \| BuyOneGetOne \| Custom Text Int` | String discriminator + nullable percent column |

**JSON parsing**: `PaymentMethod` and `TransactionStatus`/`TransactionType` accept both PascalCase and SCREAMING_SNAKE on read. DB parsing (`FromRow`) uses SCREAMING_SNAKE exclusively.

#### Supporting Types

```haskell
data TaxRecord = TaxRecord
  { taxCategory :: TaxCategory, taxRate :: Scientific
  , taxAmount :: Int, taxDescription :: Text }

data DiscountRecord = DiscountRecord
  { discountType :: DiscountType, discountAmount :: Int
  , discountReason :: Text, discountApprovedBy :: Maybe UUID }
```

#### Compliance Types

```haskell
data VerificationType = AgeVerification | MedicalCardVerification | IDScan
  | VisualInspection | PatientRegistration | PurchaseLimitCheck

data VerificationStatus = VerifiedStatus | FailedStatus | ExpiredStatus | NotRequiredStatus

data CustomerVerification = CustomerVerification
  { customerVerificationId :: UUID, customerVerificationCustomerId :: UUID
  , customerVerificationType :: VerificationType
  , customerVerificationStatus :: VerificationStatus
  , customerVerificationVerifiedBy :: UUID, customerVerificationVerifiedAt :: UTCTime
  , customerVerificationExpiresAt :: Maybe UTCTime
  , customerVerificationNotes :: Maybe Text
  , customerVerificationDocumentId :: Maybe Text }

data ReportingStatus = NotRequired | Pending | Submitted | Acknowledged | Failed

data ComplianceRecord = ComplianceRecord
  { complianceRecordId :: UUID, complianceRecordTransactionId :: UUID
  , complianceRecordVerifications :: [CustomerVerification]
  , complianceRecordIsCompliant :: Bool
  , complianceRecordRequiresStateReporting :: Bool
  , complianceRecordReportingStatus :: ReportingStatus
  , complianceRecordReportedAt :: Maybe UTCTime
  , complianceRecordReferenceId :: Maybe Text
  , complianceRecordNotes :: Maybe Text }

data InventoryStatus = Available | OnHold | Reserved | Sold | Damaged
  | Expired | InTransit | UnderReview | Recalled
```

These types have `ToJSON`/`FromJSON` instances but are only used by the stub compliance endpoints currently.

#### Ledger Types

```haskell
data LedgerEntryType = SaleEntry | Tax | Discount | Payment | Refund | Void | Adjustment | Fee
data AccountType = Asset | Liability | Equity | Revenue | Expense

data Account = Account
  { accountId :: UUID, accountCode :: Text, accountName :: Text
  , accountIsDebitNormal :: Bool, accountParentAccountId :: Maybe UUID
  , accountType :: AccountType }

data LedgerEntry = LedgerEntry
  { ledgerEntryId :: UUID, ledgerEntryTransactionId :: UUID
  , ledgerEntryAccountId :: UUID, ledgerEntryAmount :: Int
  , ledgerEntryIsDebit :: Bool, ledgerEntryTimestamp :: UTCTime
  , ledgerEntryType :: LedgerEntryType, ledgerEntryDescription :: Text }
```

Defined with JSON instances but not yet backed by database operations.

### Request/Response Types (`API/Transaction.hs`)

These types live in the API module rather than Types:

```haskell
data Register = Register
  { registerId :: UUID, registerName :: Text, registerLocationId :: UUID
  , registerIsOpen :: Bool
  , registerCurrentDrawerAmount :: Int, registerExpectedDrawerAmount :: Int
  , registerOpenedAt :: Maybe UTCTime, registerOpenedBy :: Maybe UUID
  , registerLastTransactionTime :: Maybe UTCTime }

data OpenRegisterRequest = OpenRegisterRequest
  { openRegisterEmployeeId :: UUID, openRegisterStartingCash :: Int }

data CloseRegisterRequest = CloseRegisterRequest
  { closeRegisterEmployeeId :: UUID, closeRegisterCountedCash :: Int }

data CloseRegisterResult = CloseRegisterResult
  { closeRegisterResultRegister :: Register, closeRegisterResultVariance :: Int }

data AvailableInventory = AvailableInventory
  { availableTotal :: Int, availableReserved :: Int, availableActual :: Int }

data ReservationRequest = ReservationRequest
  { reserveItemSku :: UUID, reserveTransactionId :: UUID, reserveQuantity :: Int }

data DailyReportRequest = DailyReportRequest
  { dailyReportDate :: UTCTime, dailyReportLocationId :: UUID }

data DailyReportResult = DailyReportResult
  { dailyReportCash :: Int, dailyReportCard :: Int, dailyReportOther :: Int
  , dailyReportTotal :: Int, dailyReportTransactions :: Int }

data ComplianceReportRequest = ComplianceReportRequest
  { complianceReportStartDate :: UTCTime, complianceReportEndDate :: UTCTime
  , complianceReportLocationId :: UUID }

newtype ComplianceReportResult = ComplianceReportResult
  { complianceReportContent :: Text }
```

## Database Schema

### Inventory Tables

#### `menu_items`

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

#### `strain_lineage`

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

All transaction tables are created by `createTransactionTables` which checks for table existence before creating (using `information_schema.tables` queries rather than `CREATE TABLE IF NOT EXISTS` for the conditional logic).

#### `transaction`

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

#### `transaction_item`

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

#### `transaction_tax`

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

#### `discount`

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

#### `payment_transaction`

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

#### `register`

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

#### `inventory_reservation`

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

1. **Creation** (`POST /transaction`): Transaction created with status `CREATED`, zero totals, empty items/payments. Checks for duplicate transaction IDs.
2. **Item Addition** (`POST /transaction/item`): `Service.Transaction.addItem` loads the transaction, calls `runTxCommand` with `AddItemCmd`. The state machine validates the transition (only `Created` and `InProgress` states accept items). If valid, validates inventory availability (stock minus active reservations), creates an `inventory_reservation` with status `"Reserved"`, inserts the transaction item with associated taxes and discounts.
3. **Payment Addition** (`POST /transaction/payment`): `Service.Transaction.addPayment` validates the transition via `AddPaymentCmd`, then inserts the payment and auto-updates transaction status — if total payments >= transaction total, status becomes `COMPLETED`, otherwise `IN_PROGRESS`.
4. **Finalization** (`POST /transaction/finalize/:id`): `Service.Transaction.finalizeTx` validates via `FinalizeCmd` (only `InProgress` transactions can be finalized). Decrements actual `menu_items.quantity` by reserved amounts, changes reservation status from `"Reserved"` to `"Completed"`, sets transaction status to `COMPLETED` with completion timestamp.

### Transaction Reversal Operations

**Void** (`POST /transaction/void/:id`): `Service.Transaction.voidTx` validates via `VoidCmd`. The state machine permits voiding from `Created`, `InProgress`, and `Completed`. Terminal states (`Voided`, `Refunded`) reject the command at the machine level. Sets status to `VOIDED`, marks `is_voided = TRUE`, records reason. Does not create a new transaction or reverse inventory.

**Refund** (`POST /transaction/refund/:id`): `Service.Transaction.refundTx` validates via `RefundCmd`. Only `Completed` transactions can be refunded — the topology enforces this. Creates a new inverse transaction with negated monetary amounts, type `Return`, referencing the original transaction. Marks the original as `is_refunded = TRUE`.

### Clear Transaction (`POST /transaction/clear/:id`)

Resets a transaction to empty state without passing through the state machine (clear is an operational reset, not a domain transition):

1. Releases all active reservations (status to `"Released"`)
2. Deletes all taxes, discounts, transaction items, and payments
3. Resets monetary totals to 0
4. Sets status back to `CREATED`

### Automatic Total Recalculation

`updateTransactionTotals` is called after item removal. It recalculates subtotal, discount total, tax total, and total from the database using `COALESCE(SUM(...), 0)` queries. Similarly, `updateTransactionPaymentStatus` checks if payments cover the total and updates status accordingly.

### Data Assembly Pattern

`getTransactionById` fetches the base transaction row, then separately fetches:
- Transaction items (which themselves fetch their discounts and taxes)
- Payments

This multi-query assembly pattern means `transactionItems` and `transactionPayments` in the `FromRow` instance are initialized as `pure []` and populated after the main query.

## Inventory Reservation System

The reservation system prevents overselling by tracking inventory commitments before finalization.

### Flow

1. **Check availability**: `addTransactionItem` queries `menu_items.quantity` minus `SUM(inventory_reservation.quantity)` where status is `"Reserved"`
2. **Reserve**: If sufficient, creates a reservation row with status `"Reserved"`
3. **On item removal**: Reservation status set to `"Released"`
4. **On finalization**: Actual `menu_items.quantity` decremented, reservation status set to `"Completed"`
5. **On clear**: All reservations for the transaction set to `"Released"`

### Inventory Query with Reservations

`getAllMenuItems` returns `available_quantity` rather than raw `quantity`:

```sql
SELECT m.*, m.quantity - COALESCE(r.reserved_qty, 0) as available_quantity
FROM menu_items m
LEFT JOIN (
    SELECT item_sku, SUM(quantity) as reserved_qty
    FROM inventory_reservation
    WHERE status = 'Reserved'
    GROUP BY item_sku
) r ON r.item_sku = m.sku
```

### Error Handling

Custom exceptions for inventory operations:

```haskell
data InventoryException
  = ItemNotFound UUID
  | InsufficientInventory UUID Int Int  -- sku, requested, available
```

The `addTransactionItemHandler` catches these and returns structured JSON error responses with `err400`.

## Security and Configuration

### CORS Configuration

Two layers of CORS handling:

1. **`handleOptionsMiddleware`**: Intercepts all `OPTIONS` requests before Servant, returning `200` with permissive CORS headers. This prevents Servant from returning `405 Method Not Allowed` for preflight requests.

2. **`wai-cors` middleware**: Applied to all other requests with:
   - `corsOrigins = Nothing` (any origin)
   - Methods: GET, POST, PUT, DELETE, OPTIONS
   - Request headers: `Content-Type`, `Accept`, `Authorization`, `Origin`, `Content-Length`, `x-requested-with`, `x-user-id`
   - `corsMaxAge = 86400` (24 hours)
   - `corsIgnoreFailures = True`

### TLS Configuration

When `USE_TLS=true` and `TLS_CERT_FILE`/`TLS_KEY_FILE` point to existing files, the server starts with `warp-tls`. If the files are missing, it logs a warning and falls back to plain HTTP. The `onException` handler suppresses `TLSException` noise from client disconnects. Intended for use with mkcert-generated local certificates.

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
| Pool idle timeout | 0.5 seconds |
| Pool max connections | 10 |

## Development Guidelines

### Project Structure Convention

- `API/` — Servant type definitions and request/response types. No business logic.
- `Auth/` — Authentication/authorization. Currently dev-only with fixed users.
- `State/` — State machine definitions. Pure functions only. No IO, no database access, no Servant. `State.TransactionMachine` and `State.RegisterMachine` each define a vertex type, a GADT-indexed state type, a promoted topology, commands, events, and a transition function. Adding a new state machine means adding a new module here.
- `Service/` — Business logic combining state machine validation with database effects. Each function follows the pattern: load entity, call `fromX` to promote to state machine type, call `runXCommand`, call `guardEvent`, call database function. No SQL lives here.
- `Server/` and `Server.hs` — Request handlers. Inventory handlers in `Server.hs`, POS handlers in `Server/Transaction.hs`. Handlers should delegate state-machine-backed operations to `Service/` rather than calling the database directly.
- `DB/` — Database operations. Parameterized queries, connection pooling, all SQL lives here.
- `Types/` — Domain models with serialization instances. No effects.

### State Machine Patterns

**Adding a new vertex**: Add the constructor to the `TxVertex` or `RegVertex` data type inside the `$(singletons [d| ... |])` splice. Update the `Topology` type to include the new vertex with its successor list. Add a new `TxState` or `RegState` GADT constructor. Add a `toSomeTxState` / `fromTransaction` clause. GHC will then enumerate every `txAction` clause that needs a new branch.

**Adding a new command**: Add to `TxCommand` or `RegCommand`. Add the corresponding event to `TxEvent` or `RegEvent`. Add `txAction` / `regAction` clauses for every vertex that should accept the command. The `cmdLabel` catch-all clauses will handle rejection at vertices that do not.

**Recovering the vertex at runtime**: Pattern-match on the singleton carried in the `SomeRegState` or `SomeTxState` existential:

```haskell
vertexOf :: SomeTxState -> TxVertex
vertexOf (SomeTxState sv _) = case sv of
  STxCreated    -> TxCreated
  STxInProgress -> TxInProgress
  ...
```

The `{-# LANGUAGE GADTs #-}` pragma is required in any module that does this, because each case branch refines the type index and `GADTs` implies `MonoLocalBinds`, which ensures that refinement does not escape its scope unsoundly.

**Testing transitions**: Test files should use `case` expressions with explicit `expectationFailure` fallbacks rather than irrefutable `let` bindings, since `TxEvent` and `RegEvent` have multiple constructors and GHC cannot statically verify which one `runTxCommand` produces in a given test scenario.

### Database Patterns

- **Connection pooling**: All database operations use `withConnection pool $ \conn -> ...`
- **Retry logic**: `connectWithRetry` attempts 5 connections with 5-second delays
- **Table creation**: `createTables` (inventory) uses `CREATE TABLE IF NOT EXISTS`; `createTransactionTables` checks `information_schema.tables` first
- **Parameterized queries**: All queries use `?` placeholders via `postgresql-simple`
- **RETURNING clauses**: Insert operations use `RETURNING` to get the inserted row back
- **Cascade deletes**: `transaction_item`, `transaction_tax`, `discount`, `payment_transaction` all cascade on parent deletion

### Enum Serialization Convention

Enums are stored in the database as SCREAMING_SNAKE_CASE text (`"CREATED"`, `"IN_PROGRESS"`, `"CANNABIS_TAX"`, etc.) via explicit `show*` functions in `DB.Transaction`. JSON serialization uses PascalCase via Aeson's generic deriving, but `FromJSON` instances accept both forms for interop with the frontend.

### Error Handling

- Database operations use `try @SomeException` with descriptive error messages
- State machine validation uses `guardEvent` in service functions, returning `err409` with the rejection message
- Transaction item addition uses custom `InventoryException` types caught and converted to `err400` with JSON error bodies
- Missing resources return `err404`
- Unimplemented endpoints return `err501`
- Capability violations return `err403`
- Server logging goes to both stdout (handler activity) and stderr (database operations, table creation)

### Known Issues / Tech Debt

- **No real authentication**: `X-User-Id` header is trusted without verification. Default user is cashier, not admin.
- **Backend default vs frontend default**: Backend defaults to `cashier-1` when no header provided; frontend sends admin UUID. This mismatch is harmless in dev but worth noting.
- **Capability enforcement incomplete**: Only inventory write endpoints check capabilities. Transaction, register, and other endpoints do not enforce role-based access. The state machine layer validates transition legality but is orthogonal to authorization — a cashier could currently void a transaction.
- **Ledger and compliance are stubs**: Endpoints exist and types are defined, but no database tables or real logic back them.
- **`PaymentMethod.Other` text dropped on DB write**: `showPaymentMethod (Other text) = "OTHER"` — the custom text payload is lost in the database.
- **`DiscountType` round-trip lossy**: `parseDiscountType` reconstructs from a `(Text, Maybe Int)` tuple, but `PercentOff` stores the percent as `Scientific` in Haskell while the DB stores it as a nullable `NUMERIC` on the discount row.
- **No inventory reservation expiry**: Reservations with status `"Reserved"` persist indefinitely if a transaction is abandoned without being cleared or finalized.
- **`error` calls in DB layer**: Several functions (e.g., `finalizeTransaction`, `refundTransaction`) use `error` for "impossible" states (record not found after insert/update), which would crash the server thread rather than returning an HTTP error.
- **State machine and DB status can diverge**: `fromTransaction` trusts `transactionStatus` as stored in the database. If a DB write partially fails after a state machine transition was validated, the two can fall out of sync. There is no transaction-level rollback coordinating the state machine output with the DB write.
- **`clear` bypasses the state machine**: `clearTransaction` resets a transaction to `CREATED` directly in the database without going through `runTxCommand`. This is intentional as an operational escape hatch, but it means the state machine topology does not govern the clear operation.

---

For a deeper look at the design tradeoffs in the state machine layer, including why singletons exist, what the GHC warnings mean, and how dependent types would change the picture, see [Crem.md](./Crem.md).