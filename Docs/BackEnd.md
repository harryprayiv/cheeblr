# Cheeblr Backend Documentation

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Effect Layer](#effect-layer)
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

The system uses a layered architecture with Servant for type-safe API definitions and PostgreSQL for persistence. The database layer uses **rel8** for type-safe query construction and **hasql** as the PostgreSQL driver, with **hasql-pool** for connection management. All table schemas are defined as `Rel8able` record types in `DB.Schema`. Side effects are mediated through **effectful** algebraic effect types defined in the `Effect/` hierarchy, which decouples the service and server layers from IO and enables pure in-memory interpreters for unit testing. State machine transitions for transactions and registers are enforced at compile time via [crem](https://github.com/tweag/crem), a library that encodes state machine topologies as type-level constraints. All monetary values are stored as integer cents to avoid floating-point rounding.

## Architecture

### Architectural Layers

1. **API Layer** (`API/`): Type-level API definitions using Servant's DSL. `API.Inventory` defines the inventory CRUD endpoints with auth headers. `API.Transaction` defines the POS, register, ledger, and compliance endpoints plus all request/response types that are not domain models. `API.Auth` defines the login, logout, me, and user management endpoints. `API.OpenApi` composes the full `CheeblrAPI` type, derives the OpenAPI3 schema via `servant-openapi3`, and exposes the `/openapi.json` endpoint.

2. **Server Layer** (`Server.hs`, `Server/Transaction.hs`, `Server/Auth.hs`): Request handlers. `Server` handles inventory endpoints with capability checks, running effectful stacks via `runInvEff`. `Server.Transaction` implements all POS subsystem handlers. `Server.Auth` implements the login, logout, me, and user management handlers including rate limit enforcement.

3. **Service Layer** (`Service/`): Business logic combining state machine validation with effectful database operations. `Service.Transaction` and `Service.Register` load domain state via the `TransactionDb` and `RegisterDb` effects, run the relevant state machine transition to validate the command, and only proceed to the database effect if the transition is legal. No `DBPool` references appear here.

4. **Effect Layer** (`Effect/`): Algebraic effect definitions and their interpreters. Each effect (`InventoryDb`, `TransactionDb`, `RegisterDb`, `GenUUID`, `Clock`) has an IO interpreter that delegates to the corresponding `DB.*` module, and a pure in-memory interpreter backed by `runState` for unit testing. This layer is the boundary between service logic and IO.

5. **State Machine Layer** (`State/`): Compile-time-enforced state machine definitions built on crem. `State.TransactionMachine` and `State.RegisterMachine` define the vertex types, GADT-indexed state types, topologies, commands, events, and transition functions. No IO. No effects. Pure transition logic only.

6. **Database Layer** (`DB/`): `DB.Schema` defines all `Rel8able` row types and `TableSchema` values. `DB.Database` handles inventory CRUD. `DB.Transaction` handles all transaction, register, reservation, and payment operations. `DB.Auth` handles all auth operations: user creation, password hashing/verification, session lifecycle, and login attempt recording. All use rel8 queries executed inside hasql sessions via `runSession`. Domain types carry no database instances; all serialization passes through the `Rel8able` row types in `DB.Schema`.

7. **Auth Layer** (`Auth/Session.hs`): Production session authentication. `resolveSession` extracts the `Bearer` token from the `Authorization` header, hashes it with SHA-256, looks up the matching non-revoked non-expired session row joined to the user row, updates `last_seen_at`, and returns a `SessionContext` or throws `err401`. All endpoints call this. There is no dev-mode bypass.

8. **Types Layer** (`Types/`): Domain models -- `Types.Inventory`, `Types.Transaction`, `Types.Auth`. These types carry only Aeson instances.

9. **Application Core** (`App.hs`): Server bootstrap, CORS configuration, security headers middleware, TLS configuration, Warp startup.

### Key Technologies

| Concern | Library |
|---|---|
| API definition | **Servant** -- type-level web DSL |
| OpenAPI3 schema | **servant-openapi3** -- derives OpenAPI3 from the Servant API type at runtime |
| Effects | **effectful** -- algebraic effects with IO and pure interpreters |
| State machine enforcement | **crem** -- topology-indexed state machines |
| Singleton types | **singletons-base** -- bridges type-level and value-level universe |
| Database queries | **rel8** -- type-safe, composable Haskell-to-SQL query builder over `Rel8able` schemas |
| Database driver | **hasql** -- typed PostgreSQL sessions and statements |
| Connection pooling | **hasql-pool** -- connection pool; `DBPool` is an alias for `Hasql.Pool.Pool` |
| HTTP server | **Warp** / **warp-tls** |
| JSON | **Aeson** (derived + manual instances) |
| CORS | **wai-cors** with custom OPTIONS middleware |
| UUID generation | **uuid** + **uuid-v4** (`Data.UUID.V4.nextRandom`), also abstracted as a `GenUUID` effect |
| Logging | **katip** -- structured JSON log output with namespaces and severity |
| Password hashing | **argon2** -- Argon2id with 3 iterations, 64 MB memory, 4 parallelism |
| Cryptography | **crypton** -- SHA-256 for token hashing; **entropy** -- CSPRNG for token generation |

### System Flow

**Inventory operations:**

1. Warp receives request; `securityHeadersMiddleware` appends security headers to the response
2. Custom OPTIONS middleware handles preflight
3. `wai-cors` applies CORS headers
4. Servant routes to handler in `Server`
5. Inventory handlers call `resolveSession pool mAuthHeader` which extracts the Bearer token, hashes it, and looks up the session; returns `SessionContext { scUser, scSessionId }` or throws `err401`
6. Capability check on `scUser`
7. `runInvEff` runs the `[InventoryDb, Error ServerError, IOE]` stack, delegating `InventoryDb` operations to `DB.Database` via `runInventoryDbIO`
8. Results serialized as JSON and returned

**Auth operations:**

1. Steps 1-3 above
2. Servant routes to `Server.Auth`
3. `loginHandler` checks per-credential and per-IP rate limits via `DB.Auth.recentFailedAttempts` and `recentFailedAttemptsByIp`
4. Looks up user by username, verifies Argon2id hash
5. On success: generates 32-byte CSPRNG token, stores SHA-256 hash in `sessions`, returns raw token
6. Records outcome in `login_attempts`

**State-machine-backed operations (transactions, registers):**

1. Steps 1-4 above
2. Server handler runs the appropriate effect stack via `runTxEff` or `runRegEff`
3. Service function loads the current entity via the `TransactionDb` or `RegisterDb` effect
4. `fromTransaction` or `fromRegister` promotes the domain record into a `SomeTxState` or `SomeRegState` existential
5. `runTxCommand` or `runRegCommand` runs the transition function, returning an event and a next state
6. If the event is `InvalidTxCommand` or `InvalidRegCommand`, the service throws `err409` -- no database write occurs
7. If the transition is valid, the service calls the corresponding database effect operation to persist the change
8. Result serialized as JSON and returned

## Core Components

### Main Application (`App.hs`)

Bootstraps the server: reads environment variables, initializes the connection pool, creates all tables, applies middleware, conditionally enables TLS, and starts Warp.

```haskell
data AppConfig = AppConfig
  { dbConfig    :: DBConfig
  , serverPort  :: Int
  , tlsCertFile :: Maybe FilePath
  , tlsKeyFile  :: Maybe FilePath
  }
```

Environment variables: `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PORT`, `USE_TLS`, `TLS_CERT_FILE`, `TLS_KEY_FILE`, `ALLOWED_ORIGIN`. All have defaults. `ALLOWED_ORIGIN` controls the CORS policy -- empty or absent means all origins accepted (dev), non-empty locks CORS to that single origin (production).

#### Middleware Stack

Middleware is composed in order, outermost first:

1. **`securityHeadersMiddleware`** -- appends HSTS, CSP, X-Frame-Options, X-Content-Type-Options, and Referrer-Policy to every response
2. **`handleOptionsMiddleware`** -- intercepts `OPTIONS` requests before Servant routing
3. **`wai-cors`** -- applies CORS headers based on `ALLOWED_ORIGIN`

```haskell
app = securityHeadersMiddleware
    . handleOptionsMiddleware
    $ cors (const $ Just corsPolicy) (serve cheeblrAPI (combinedServer pool logEnv))
```

### OpenAPI3 Schema (`API/OpenApi.hs`)

`CheeblrAPI` composes `InventoryAPI`, `PosAPI`, and `AuthAPI`, appends `GET /openapi.json`, and derives the schema via `servant-openapi3`. Manual `ToSchema` instances are provided for `GQLRequest`, `GQLResponse`, and `OpenApi` itself.

### Combined Server (`Server.hs`)

```haskell
combinedServer :: DBPool -> LogEnv -> Server CheeblrAPI
combinedServer pool logEnv =
  inventoryServer pool logEnv
    :<|> posServerImpl pool logEnv
    :<|> authServerImpl pool logEnv
    :<|> pure cheeblrOpenApi
```

All inventory handlers resolve the session unconditionally:

```haskell
auth :: Maybe Text -> Handler AuthenticatedUser
auth mHeader = scUser <$> resolveSession pool mHeader
```

`resolveSession` is the single authentication entry point for all non-auth endpoints.

### Auth Server (`Server/Auth.hs`)

`authServerImpl` wires the five auth handlers:

```haskell
authServerImpl :: DBPool -> LogEnv -> Server AuthAPI
authServerImpl pool logEnv =
       loginHandler    pool logEnv
  :<|> logoutHandler   pool logEnv
  :<|> meHandler       pool
  :<|> listUsersHandler pool logEnv
  :<|> createUserHandler pool logEnv
```

`checkLoginRateLimit` runs two independent checks before any password work:

```haskell
perCredentialLimit = 5   -- failures per username+IP in 10 minutes
perIpLimit         = 20  -- failures per IP across all usernames in 10 minutes
```

Both return `429 Too Many Requests` with `Retry-After: 600`.

### Effect Stacks (`Server/Transaction.hs`)

```haskell
type TxEffs  = '[GenUUID, Clock, TransactionDb, Error ServerError, IOE]
type RegEffs = '[GenUUID, Clock, RegisterDb,    Error ServerError, IOE]
```

These are the only points where `DBPool` enters the effect stack. Everything above -- service functions, state machine code -- is pool-free.

### Database Layer (`DB/Schema.hs`, `DB/Database.hs`, `DB/Transaction.hs`, `DB/Auth.hs`)

`DB.Schema` holds the full set of `Rel8able` row types including the auth tables:

```haskell
data UserRow f = UserRow
  { userId :: Column f UUID, userName :: Column f Text
  , displayName :: Column f Text, email :: Column f (Maybe Text)
  , userRole :: Column f Text, userLocationId :: Column f (Maybe UUID)
  , passwordHash :: Column f Text, isActive :: Column f Bool
  , userCreatedAt :: Column f UTCTime, userUpdatedAt :: Column f UTCTime
  } deriving stock Generic deriving anyclass Rel8able

data SessionRow f = SessionRow
  { sessId :: Column f UUID, sessUserId :: Column f UUID
  , sessTokenHash :: Column f Text  -- SHA-256(raw_token), hex-encoded
  , sessRegisterId :: Column f (Maybe UUID)
  , sessCreatedAt :: Column f UTCTime, sessLastSeenAt :: Column f UTCTime
  , sessExpiresAt :: Column f UTCTime, sessRevoked :: Column f Bool
  , sessRevokedAt :: Column f (Maybe UTCTime), sessRevokedBy :: Column f (Maybe UUID)
  , sessUserAgent :: Column f (Maybe Text), sessIpAddress :: Column f (Maybe Text)
  } deriving stock Generic deriving anyclass Rel8able
```

`DB.Auth` provides:

- `hashPassword :: Text -> IO Text` -- Argon2id PHC string (includes salt, parameters, hash)
- `verifyPassword :: Text -> Text -> Bool` -- constant-time comparison via Argon2id
- `createUser :: DBPool -> NewUser -> IO UUID`
- `lookupUserByUsername :: DBPool -> Text -> IO (Maybe (UserRow Result))`
- `createSession :: DBPool -> UUID -> Maybe UUID -> Text -> Text -> IO (SessionToken, UTCTime)` -- generates 32-byte raw token, stores SHA-256 hash
- `lookupSession :: DBPool -> Text -> IO (Maybe (SessionRow Result, UserRow Result))` -- hashes incoming token, queries, updates `last_seen_at`
- `revokeSession :: DBPool -> UUID -> Maybe UUID -> IO ()`
- `revokeAllUserSessions :: DBPool -> UUID -> IO ()`
- `recordLoginAttempt :: DBPool -> Text -> Text -> Bool -> IO ()`
- `recentFailedAttempts :: DBPool -> Text -> Text -> NominalDiffTime -> IO Int` -- per credential
- `recentFailedAttemptsByIp :: DBPool -> Text -> NominalDiffTime -> IO Int` -- per IP across all usernames

## Effect Layer

The `Effect/` modules define algebraic effects used throughout the service and server layers. Each module exports the effect GADT, smart constructors, an IO interpreter delegating to the corresponding `DB.*` module, and a pure in-memory interpreter for testing.

### `Effect.Clock`

`currentTime :: Clock :> es => Eff es UTCTime`. Interpreters: `runClockIO`, `runClockPure t`, `runClockPureSequence ts`.

### `Effect.GenUUID`

`nextUUID :: GenUUID :> es => Eff es UUID`. Interpreters: `runGenUUIDIO`, `runGenUUIDPure supply`.

### `Effect.InventoryDb`

Operations: `getAllMenuItems`, `insertMenuItem`, `updateMenuItem`, `deleteMenuItem`. Interpreters: `runInventoryDbIO pool`, `runInventoryDbPure initial`.

### `Effect.RegisterDb`

Operations: `getAllRegisters`, `getRegisterById`, `createRegister`, `updateRegister`, `openRegisterDb`, `closeRegisterDb`. Interpreters: `runRegisterDbIO pool`, `runRegisterDbPure initial`.

### `Effect.TransactionDb`

Full transaction lifecycle operations. The pure interpreter `runTransactionDbPure` is backed by `TxStore`:

```haskell
data TxStore = TxStore
  { tsTxs          :: Map UUID Transaction
  , tsItemToTx     :: Map UUID UUID
  , tsPaymentToTx  :: Map UUID UUID
  , tsReservations :: Map UUID ReservationEntry
  , tsInventory    :: Map UUID Int
  }
```

Requires `GenUUID :> es` and `Clock :> es` because the pure refund implementation needs fresh UUIDs and timestamps.

### Testing with Pure Interpreters

```haskell
type TestEffs = '[TransactionDb, Clock, GenUUID, Error ServerError, IOE]

runTest :: TxStore -> Eff TestEffs a -> IO (Either ServerError a)
runTest store action =
  fmap (fmap (fst . fst)) $
  runEff
  . runErrorNoCallStack @ServerError
  . runGenUUIDPure uuidSupply
  . runClockPure testTime
  . runTransactionDbPure store
  $ action
```

State machine invariants, HTTP error codes, and inventory accounting are all verified without a running database. `Test.Integration` provides serialization boundary and real database coverage.

## State Machine Layer

### Design Philosophy

The state machine layer promotes transaction and register lifecycle invariants into compile-time proof obligations. The topology is a type, not a comment. Every transition clause must satisfy it or the project will not build.

### `State.RegisterMachine`

```haskell
$(singletons [d|
  data RegVertex = RegClosed | RegOpen deriving (Eq, Show)
  |])

type RegTopology = 'Topology
  '[ '( 'RegClosed, '[ 'RegClosed, 'RegOpen])
   , '( 'RegOpen,   '[ 'RegOpen,   'RegClosed])
   ]
```

### `State.TransactionMachine`

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

Terminal states only list themselves as successors. Any attempt to transition out of them produces a compile error.

`someTxStatus` extracts the domain `TransactionStatus` from a `SomeTxState` by casing on the singleton, allowing the service layer to persist status changes without pattern-matching on the full existential.

`fromTransaction` and `fromRegister` are total functions that bridge the database layer into the state machine layer.

## Authentication and Authorization

### Session Authentication (`Auth/Session.hs`)

All non-auth endpoints resolve identity through `resolveSession`:

```haskell
data SessionContext = SessionContext
  { scUser      :: AuthenticatedUser
  , scSessionId :: UUID
  }

resolveSession :: DBPool -> Maybe Text -> Handler SessionContext
```

`resolveSession` extracts `Bearer <token>` from the header, base64url-decodes the raw token, hashes it with SHA-256, and queries `sessions JOIN users` with conditions `NOT revoked AND expires_at > NOW() AND is_active`. On a hit, it updates `last_seen_at` and returns the `SessionContext`. Any miss throws `err401`.

### Token Design

- 32 bytes from `System.Entropy.getEntropy` (reads `/dev/urandom`)
- base64url-encoded without padding as the client-facing token
- SHA-256 of the raw bytes stored in `sessions.token_hash` as lowercase hex
- The database never holds anything usable if breached

### Password Hashing (`DB/Auth.hs`)

Argon2id with parameters matching OWASP minimum recommendations:

```haskell
argonOpts = Argon2.Options
  { iterations  = 3
  , memory      = 65536   -- 64 MB
  , parallelism = 4
  , variant     = Argon2.Argon2id
  , version     = Argon2.Version13
  }
```

`hashPassword` generates a fresh 16-byte salt per call and returns a PHC-format string (includes parameters and salt). `verifyPassword` re-derives and compares; constant-time by construction.

### Rate Limiting (`Server/Auth.hs`)

Two independent checks on every login attempt, using the `login_attempts` table (DB-backed, survives restarts):

| Check | Threshold | Window |
|---|---|---|
| Per credential (username + IP) | 5 failures | 10 minutes |
| Per IP (all usernames) | 20 failures | 10 minutes |

The per-IP check catches credential-stuffing attacks that rotate across multiple usernames to evade the per-credential limit.

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

### Admin Bootstrap

The `bootstrap-admin` devshell command connects to the DB, checks whether any users exist, and if not generates a random password and creates an admin user. The password is printed once to stdout and stored encrypted in sops. It is a no-op if any users already exist.

## API Reference

### Auth Endpoints

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/auth/login` | None | Username/password -> session token |
| POST | `/auth/logout` | Bearer token | Revoke current session |
| GET | `/auth/me` | Bearer token | Current user role and capabilities |
| GET | `/auth/users` | Admin only | List all users |
| POST | `/auth/users` | Admin only | Create a new user |

`POST /auth/login` accepts `{ loginUsername, loginPassword, loginRegisterId? }` and returns `{ loginToken, loginExpiresAt, loginUser }`. The token is an opaque base64url string. All subsequent requests send it as `Authorization: Bearer <token>`.

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

### Transaction Endpoints

All transaction endpoints require a valid `Authorization: Bearer <token>` header.

| Method | Endpoint | Description |
|---|---|---|
| GET | `/transaction` | List all transactions |
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

### Register Endpoints

All register endpoints require a valid `Authorization: Bearer <token>` header.

| Method | Endpoint | Description |
|---|---|---|
| GET | `/register` | List all registers |
| GET | `/register/:id` | Get register by ID |
| POST | `/register` | Create a register |
| PUT | `/register/:id` | Update a register |
| POST | `/register/open/:id` | Open register with starting cash |
| POST | `/register/close/:id` | Close register, report variance |

### Inventory Availability Endpoints

All availability endpoints require a valid `Authorization: Bearer <token>` header.

| Method | Endpoint | Description |
|---|---|---|
| GET | `/inventory/available/:sku` | Total, reserved, and available quantity for a SKU |
| POST | `/inventory/reserve` | Create an inventory reservation |
| DELETE | `/inventory/release/:id` | Release a reservation |

### Ledger and Compliance Endpoints (stubs)

All ledger and compliance endpoints require a valid `Authorization: Bearer <token>` header. Ledger endpoints return `[]` or `501`. Compliance endpoints echo input or return placeholder text.

## Data Models

### Auth Tables (`DB/Schema.hs`)

Three tables managed by `createAuthTables` in `DB.Auth`:

- `users` -- credentials, role, active flag
- `sessions` -- token hashes, register binding, expiry, revocation
- `login_attempts` -- audit trail for rate limiting and compliance

See [Database Schema](#database-schema) for full DDL.

### Inventory Models (`Types/Inventory.hs`)

`MenuItem`, `StrainLineage`, `Inventory`, `MutationResponse`. Domain types carry only Aeson instances. All database mapping is handled by conversion functions in `DB.Database`.

### Transaction Models (`Types/Transaction.hs`)

`Transaction`, `TransactionItem`, `PaymentTransaction`, `TaxRecord`, `DiscountRecord` and associated enums. `transactionItems` and `transactionPayments` are populated by `hydrateTx`/`hydrateItem` passes after the main query.

### Enum Serialization Convention

Enums are stored as SCREAMING_SNAKE_CASE in the database. JSON uses PascalCase via Aeson's generic deriving. `FromJSON` instances accept both forms for frontend interop.

## Database Schema

### Auth Tables

```sql
CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY,
    username      TEXT NOT NULL UNIQUE,
    display_name  TEXT NOT NULL,
    email         TEXT,
    role          TEXT NOT NULL,
    location_id   UUID,
    password_hash TEXT NOT NULL,    -- Argon2id PHC string, includes salt
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

CREATE TABLE IF NOT EXISTS sessions (
    id            UUID PRIMARY KEY,
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash    TEXT NOT NULL UNIQUE,  -- SHA-256(raw_token), hex
    register_id   UUID,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ NOT NULL,
    revoked       BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at    TIMESTAMPTZ,
    revoked_by    UUID REFERENCES users(id),
    user_agent    TEXT,
    ip_address    TEXT
)

CREATE INDEX sessions_token_hash_idx ON sessions (token_hash) WHERE NOT revoked

CREATE TABLE IF NOT EXISTS login_attempts (
    id           UUID PRIMARY KEY,
    username     TEXT NOT NULL,
    ip_address   TEXT NOT NULL,
    success      BOOLEAN NOT NULL,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

CREATE INDEX login_attempts_ip_idx ON login_attempts (ip_address, attempted_at DESC)
CREATE INDEX login_attempts_username_idx ON login_attempts (username, attempted_at DESC)
```

### Inventory Tables

```sql
CREATE TABLE IF NOT EXISTS menu_items (
    sort INT NOT NULL, sku UUID PRIMARY KEY, brand TEXT NOT NULL,
    name TEXT NOT NULL, price INTEGER NOT NULL, measure_unit TEXT NOT NULL,
    per_package TEXT NOT NULL, quantity INT NOT NULL, category TEXT NOT NULL,
    subcategory TEXT NOT NULL, description TEXT NOT NULL,
    tags TEXT[] NOT NULL, effects TEXT[] NOT NULL
)

CREATE TABLE IF NOT EXISTS strain_lineage (
    sku UUID PRIMARY KEY REFERENCES menu_items(sku),
    thc TEXT NOT NULL, cbg TEXT NOT NULL, strain TEXT NOT NULL,
    creator TEXT NOT NULL, species TEXT NOT NULL,
    dominant_terpene TEXT NOT NULL, terpenes TEXT[] NOT NULL,
    lineage TEXT[] NOT NULL, leafly_url TEXT NOT NULL, img TEXT NOT NULL
)
```

### Transaction Tables

```sql
CREATE TABLE IF NOT EXISTS transaction (
    id UUID PRIMARY KEY, status TEXT NOT NULL,
    created TIMESTAMPTZ NOT NULL, completed TIMESTAMPTZ,
    customer_id UUID, employee_id UUID NOT NULL,
    register_id UUID NOT NULL, location_id UUID NOT NULL,
    subtotal INTEGER NOT NULL, discount_total INTEGER NOT NULL,
    tax_total INTEGER NOT NULL, total INTEGER NOT NULL,
    transaction_type TEXT NOT NULL,
    is_voided BOOLEAN NOT NULL DEFAULT FALSE, void_reason TEXT,
    is_refunded BOOLEAN NOT NULL DEFAULT FALSE, refund_reason TEXT,
    reference_transaction_id UUID, notes TEXT
)

CREATE TABLE IF NOT EXISTS transaction_item (
    id UUID PRIMARY KEY,
    transaction_id UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,
    menu_item_sku UUID NOT NULL, quantity INTEGER NOT NULL,
    price_per_unit INTEGER NOT NULL, subtotal INTEGER NOT NULL, total INTEGER NOT NULL
)

CREATE TABLE IF NOT EXISTS transaction_tax (
    id UUID PRIMARY KEY,
    transaction_item_id UUID NOT NULL REFERENCES transaction_item(id) ON DELETE CASCADE,
    category TEXT NOT NULL, rate NUMERIC NOT NULL,
    amount INTEGER NOT NULL, description TEXT NOT NULL
)

CREATE TABLE IF NOT EXISTS discount (
    id UUID PRIMARY KEY,
    transaction_item_id UUID REFERENCES transaction_item(id) ON DELETE CASCADE,
    transaction_id UUID REFERENCES transaction(id) ON DELETE CASCADE,
    type TEXT NOT NULL, amount INTEGER NOT NULL, percent NUMERIC,
    reason TEXT NOT NULL, approved_by UUID
)

CREATE TABLE IF NOT EXISTS payment_transaction (
    id UUID PRIMARY KEY,
    transaction_id UUID NOT NULL REFERENCES transaction(id) ON DELETE CASCADE,
    method TEXT NOT NULL, amount INTEGER NOT NULL,
    tendered INTEGER NOT NULL, change_amount INTEGER NOT NULL,
    reference TEXT, approved BOOLEAN NOT NULL DEFAULT FALSE,
    authorization_code TEXT
)

CREATE TABLE IF NOT EXISTS register (
    id UUID PRIMARY KEY, name TEXT NOT NULL, location_id UUID NOT NULL,
    is_open BOOLEAN NOT NULL DEFAULT FALSE,
    current_drawer_amount INTEGER NOT NULL DEFAULT 0,
    expected_drawer_amount INTEGER NOT NULL DEFAULT 0,
    opened_at TIMESTAMPTZ, opened_by UUID, last_transaction_time TIMESTAMPTZ
)

CREATE TABLE IF NOT EXISTS inventory_reservation (
    id UUID PRIMARY KEY, item_sku UUID NOT NULL,
    transaction_id UUID NOT NULL, quantity INTEGER NOT NULL,
    status TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

## Transaction Processing

### Transaction Lifecycle

1. **Creation**: Transaction inserted with status `CREATED` and zero totals.
2. **Item Addition**: `Service.Transaction.addItem` loads the transaction, calls `runTxCommand AddItemCmd`. State machine validates (`Created` and `InProgress` accept items). If valid, `AddTransactionItem` effect checks availability, creates reservation, inserts item.
3. **Payment Addition**: `addPaymentCmd` validates, then `AddPayment` effect inserts. DB layer auto-updates status -- payments >= total -> `COMPLETED`, else `IN_PROGRESS`.
4. **Finalization**: `finalizeTx` validates via `FinalizeCmd` (only `InProgress`). `FinalizeTransaction` decrements `menu_items.quantity`, marks reservations `Completed`, sets status `COMPLETED`.

### Reversal Operations

**Void**: Permitted from `Created`, `InProgress`, `Completed`. Terminal states reject at the machine level.

**Refund**: Only `Completed` transactions -- the topology enforces this. Creates inverse transaction with negated monetary amounts, type `Return`.

### Clear Transaction

Resets to empty state without the state machine (operational escape hatch): releases reservations, deletes items/payments, zeroes totals, sets status to `CREATED`. Can be called on a voided or refunded transaction if needed.

## Inventory Reservation System

1. **Check availability**: aggregate query for `menu_items.quantity - SUM(reserved)`
2. **Reserve**: insert reservation row with status `"Reserved"`
3. **Item removal**: reservation set to `"Released"`
4. **Finalization**: stock decremented, reservation set to `"Completed"`
5. **Clear**: all reservations for the transaction set to `"Released"`

Inventory exceptions (`ItemNotFound`, `InsufficientInventory`) are returned as `Either` values by the effect operation and converted to `err404`/`err400` in the service layer.

## Security and Configuration

### Security Headers

`securityHeadersMiddleware` in `App.hs` appends these headers to every response:

| Header | Value |
|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:` |

### CORS

Controlled by `ALLOWED_ORIGIN` env var sourced from sops. Empty/absent: all origins accepted (dev). Non-empty: locked to that origin (production). A separate `handleOptionsMiddleware` handles preflight `OPTIONS` requests before Servant routing.

### TLS

When `USE_TLS=true` and `TLS_CERT_FILE`/`TLS_KEY_FILE` point to existing files, the server starts with `warp-tls`. Falls back to plain HTTP with a log warning if files are missing.

### Server Configuration

| Setting | Env var | Default |
|---|---|---|
| Port | `PORT` | 8080 |
| DB host | `PGHOST` | `localhost` |
| DB port | `PGPORT` | 5432 |
| DB name | `PGDATABASE` | `cheeblr` |
| DB user | `PGUSER` | current system user |
| DB password | `PGPASSWORD` | bootstrap fallback string |
| CORS origin lock | `ALLOWED_ORIGIN` | (empty -- open) |
| Pool size | (hardcoded) | 10 |
| Pool acquisition timeout | (hardcoded) | 30 seconds |

## Development Guidelines

### Project Structure Convention

- `API/` -- Servant type definitions. No business logic. `API.OpenApi` owns the combined type.
- `Auth/Session.hs` -- Session resolution. `resolveSession` is the single auth entry point for all non-auth endpoints.
- `Effect/` -- Effect GADTs, smart constructors, IO and pure interpreters. Add operations here first before touching `Service/`.
- `State/` -- State machine definitions. Pure functions only.
- `Service/` -- Business logic over effect rows. No `DBPool`, no SQL, no `Handler`.
- `Server/` and `Server.hs` -- Request handlers. `DBPool` appears only in `runTxEff`/`runRegEff`/`runInvEff`.
- `DB/Schema.hs` -- Single source of truth for table structure.
- `DB/Database.hs`, `DB/Transaction.hs`, `DB/Auth.hs` -- Database operations and row conversion functions.
- `Types/` -- Domain models with Aeson and `ToSchema` instances. No effects. No database instances.

### Adding a New Database Operation

1. Add the `Rel8able` row type and `TableSchema` to `DB.Schema` if a schema change is needed
2. Implement in the appropriate `DB.*` module using rel8 and `runSession`
3. Add a constructor to the relevant effect GADT in `Effect/`
4. Add a smart constructor; update both IO and pure interpreters
5. Call the smart constructor from `Service/`, not the `DB.*` function directly
6. Add unit tests against the pure interpreter

### Error Handling

- Database operations use `try @SomeException`
- State machine validation via `guardTxEvent`/`guardRegEvent` returns `err409`
- `ItemNotFound` -> `err404`; `InsufficientInventory` -> `err400`
- Missing resources -> `err404`; unimplemented -> `err501`; capability violations -> `err403`
- Auth failures -> `err401`; rate limit -> `err429` with `Retry-After: 600`

### Known Issues and Tech Debt

- **Fine-grained capability enforcement incomplete**: All endpoints require a valid session token. Inventory write endpoints additionally enforce role-based capabilities (`capCanCreateItem`, `capCanEditItem`, `capCanDeleteItem`). Transaction and register endpoints are auth-gated but do not yet check fine-grained capabilities beyond authentication.
- **Ledger and compliance are stubs**: Endpoints exist and types are defined, but no database tables or real logic back them.
- **`PaymentMethod.Other` text round-trip**: Verify `showPaymentMethod (Other text)` / `parsePaymentMethod` round-trips correctly on all DB paths if this constructor matters in production.
- **`DiscountType` round-trip lossy**: `PercentOff` stores `Scientific` while the DB stores nullable `NUMERIC`. Fractional percent values may lose precision.
- **No inventory reservation expiry**: Reservations with status `"Reserved"` persist indefinitely if a transaction is abandoned without being cleared.
- **`error` calls in DB layer**: Several post-write "impossible" states use `error` rather than returning an HTTP error.
- **State machine and DB status can diverge**: `fromTransaction` trusts `transactionStatus` as stored. A partial DB write after a validated transition can cause divergence.
- **`clear` bypasses the state machine**: Intentional escape hatch, but means `clearTransaction` can be called on `VOIDED` or `REFUNDED` transactions.