# Cheeblr: Dispensary Management System

A full-stack cannabis dispensary point-of-sale and inventory management system built with PureScript (frontend) and Haskell (backend) on PostgreSQL, emphasizing type safety, functional programming, and reproducible builds via Nix. 

[![License](https://www.gnu.org/graphics/agplv3-155x51.png)](https://www.gnu.org/licenses/agpl-3.0.html)

## Documentation

- [Frontend Documentation](./Docs/FrontEnd.md) -- PureScript/Deku SPA architecture, async loading pattern, page modules, services
- [Backend Documentation](./Docs/BackEnd.md) -- Haskell/Servant API, effect layer, database layer, transaction processing, inventory reservations
- [State Machine Design](./Docs/Crem.md) -- crem topology encoding, singleton witnesses, and tradeoffs vs. dependent types
- [Nix Development Environment](./Docs/NixDevEnvironment.md) -- Setup, TLS, sops secrets management, service scripts, and test suite
- [Dependencies](./Docs/Dependencies.md) -- Project dependency listing
- [To Do list](./Docs/TODO.md) -- Planned features and optimizations
- [Security](./Docs/SecurityStrategies.md) -- Authentication architecture, security headers, rate limiting, deployment checklist

## Features

### Inventory Management

- **Comprehensive Product Tracking**: Detailed cannabis product data including strain lineage, THC/CBD content, terpene profiles, species classification, and Leafly integration
- **Real-Time Inventory Reservations**: Items are reserved when added to a transaction cart, preventing overselling during concurrent sessions. Reservations are released on item removal or transaction cancellation, and committed on finalization
- **Role-Based Access Control**: Four roles (Customer, Cashier, Manager, Admin) and 15 granular capabilities governing inventory CRUD, transaction processing, register management, and reporting access. Capabilities are derived from the authenticated session at request time.
- **Flexible Sorting and Filtering**: Multi-field priority sorting (quantity, category, species) with configurable sort order and optional out-of-stock hiding
- **Complete CRUD Operations**: Create, read, update, and delete inventory items with full strain lineage data
- **GraphQL Inventory API**: Inventory queries available via `/graphql/inventory` using `morpheus-graphql` (backend) and hand-rolled HTTP POST queries (frontend), scoped to inventory access with capability enforcement
- **OpenAPI3 Schema**: Machine-readable API schema served at `/openapi.json`, generated at runtime via `servant-openapi3`

### Point-of-Sale System

- **Full Sale Lifecycle**: Start -> add items (with reservation) -> add payments -> finalize (commits inventory) or clear (releases reservations). A sale can only be completed through finalize, and finalize is refused until the sale has items and its payments cover the total.
- **Server-Side Pricing**: The register sends intent only (which SKU, how many, how much was paid). The backend looks up the menu price, applies the tax rules in force, computes change, and generates every id. No client-computed money is accepted.
- **Tax Rules as Data**: Rules live in a `tax_rule` table keyed by optional location, optional item category, tax category, rate, rounding mode and an effective date range. An item can carry several tax lines (sales, excise, local). All money is integer cents and rates are integer parts per million; each tax is rounded once and the rounded amount is stored.
- **Compile-Time State Machine Enforcement**: Transaction and register state transitions are validated at compile time via [crem](https://github.com/tweag/crem). The permitted topology is a type-level constraint; illegal transitions are rejected with `409 Conflict`.
- **Parallel Data Loading**: The POS page loads inventory, initializes the register, and starts a sale concurrently using the frontend's `parSequence_` pattern; degrades gracefully to `TxPageDegraded` state on partial load failure
- **Multiple Payment Methods**: Cash, credit, debit, ACH, gift card, stored value, mixed, and custom payment types with change calculated on the server
- **Discount Support**: Percentage-based, fixed amount, BOGO, and custom discount types with approval tracking (types and storage exist; the sale flow does not create discounts yet)
- **Stored Totals**: Sale subtotal, tax and total are sums over stored line amounts, refreshed whenever an item is added or removed

### Financial Operations

- **Cash Register Management**: Open registers with starting cash, close with counted cash and automatic variance calculation. Register open/close transitions are enforced by the same state machine layer as transactions.
- **Register Persistence**: Register IDs stored in localStorage, auto-recovered on page load via get-or-create pattern
- **Transaction Modifications**: Void (marks existing transaction) and refund (creates inverse transaction with negated amounts) operations with reason tracking

### Security

- **Session-Based Authentication**: Opaque 32-byte CSPRNG tokens; SHA-256 hashes stored in PostgreSQL. Instant revocation, 8-hour hard expiry, 30-minute inactivity timeout. Sessions bind optionally to a register ID for cashier terminal enforcement.
- **Argon2id Password Hashing**: 3 iterations, 64 MB memory, Argon2id variant. PHC-format storage (salt and parameters included in the hash string).
- **Rate Limiting**: Two independent checks on every login attempt -- 5 failures per username+IP and 20 failures per IP across all usernames, in a 10-minute window, stored in PostgreSQL.
- **Security Headers**: HSTS, CSP, X-Frame-Options, X-Content-Type-Options, and Referrer-Policy on every response via `securityHeadersMiddleware`.
- **CORS Lockdown**: `ALLOWED_ORIGIN` env var sourced from sops controls the CORS policy. Empty = open (dev); non-empty = locked to that origin (production).
- **Compliance Audit Trail**: `sessions` table records login time, terminal IP, user agent, and register binding. `login_attempts` records all successes and failures.

### Compliance Infrastructure

- **Customer Verification Types**: Age verification, medical card, ID scan, visual inspection, patient registration, purchase limit check
- **Compliance Records**: Per-transaction compliance tracking with verification status, state reporting status, and reference IDs
- **Reporting Stubs**: Compliance and daily financial report endpoints defined with types -- implementation pending

## Technology Stack

### Frontend

| Concern | Technology |
|---|---|
| Language | **PureScript** -- strongly-typed FP compiling to JavaScript |
| UI | **Deku** -- declarative, hooks-based rendering with `Nut` as the renderable type |
| State | **FRP.Poll** -- reactive streams with `create`/`push` for mutable cells |
| Routing | **Routing.Duplex** + **Routing.Hash** -- hash-based client-side routing |
| HTTP | **purescript-fetch** with **Yoga.JSON** for serialization |
| GraphQL | Hand-rolled HTTP POST to `/graphql/inventory` -- no npm dependencies |
| Money | **Data.Finance.Money** -- `Discrete USD` (integer cents) with formatting |
| Forms | `UI.Form` -- applicative form builder; `UI.Form.Parser` -- `String -> Either String a` field parsers |
| Async | **Effect.Aff** with `run` helper, `parSequence_`, `killFiber` for route-driven loading |
| Parallelism | **Control.Parallel** -- concurrent data fetching within a single route |

### Backend

| Concern | Technology |
|---|---|
| Language | **Haskell** |
| API | **Servant** -- type-level REST API definitions |
| OpenAPI3 | **servant-openapi3** -- schema generated at runtime, served at `/openapi.json` |
| Effects | **effectful** -- algebraic effects mediating all service-to-database communication; IO and pure in-memory interpreters per effect |
| State Machines | **crem** -- topology-indexed state machines with compile-time transition enforcement |
| Singleton Types | **singletons-base** -- bridges type-level and value-level for runtime vertex recovery |
| GraphQL | **morpheus-graphql** -- inventory-scoped GraphQL resolver at `/graphql/inventory` |
| Database queries | **rel8** -- type-safe, composable Haskell queries over `Rel8able` table schemas |
| Database driver | **hasql** -- high-performance PostgreSQL driver with typed sessions and statements |
| Connection pooling | **hasql-pool** -- connection pool over hasql connections |
| Schema definitions | **DB.Schema** -- `Rel8able` row types and `TableSchema` values for every table |
| Server | **Warp** + **warp-tls** -- HTTPS via TLS 1.2+ with mkcert certs in development |
| JSON | **Aeson** (derived + manual instances) |
| Auth | Session tokens + Argon2id passwords; `Auth.Session.resolveSession` on all endpoints |
| Password hashing | **argon2** -- Argon2id (3 iterations, 64 MB memory) |
| Cryptography | **crypton** (SHA-256), **entropy** (CSPRNG), **bytestring-base64-url** (token encoding) |

### Infrastructure

| Concern | Technology |
|---|---|
| Database | **PostgreSQL** with reservation-based inventory, cascading deletes, parameterized queries |
| Dev Environment | **Nix** flakes -- reproducible builds, per-machine dev shells |
| Secrets | **sops** + **age** -- encrypted `secrets/cheeblr.yaml`, key derived from SSH ed25519 key |
| TLS | **mkcert** for local dev certs; **warp-tls** for HTTPS on the backend; **Vite** HTTPS config |
| Build (Haskell) | **Cabal** via haskell.nix / CHaP |
| Build (PureScript) | **Spago** |
| Testing | Haskell unit + integration tests (pure in-memory interpreters for service-layer unit tests, ephemeral-PostgreSQL for integration); hedgehog property tests for the pure pricing and tax modules; PureScript unit tests |

## Getting Started

### Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled

### Development Setup

```bash
git clone https://github.com/harryprayiv/cheeblr.git
cd cheeblr
nix develop

# First-time: set up secrets and TLS
sops-init-key       # derive age key from ~/.ssh/id_ed25519
sops-bootstrap      # create secrets/cheeblr.yaml with a random DB password
tls-setup           # generate mkcert dev certs for localhost
tls-sops-update     # encrypt certs into secrets/cheeblr.yaml

# Start database and create the admin user
pg-start
bootstrap-admin     # creates admin user, stores password in sops (run once)
sops-get admin_password  # retrieve the generated password when needed

sops-status         # verify everything is wired up

# Start everything
deploy              # tmux session: backend (HTTPS :8080) + frontend (HTTPS :5173) + pg-stats
```

The login page is served at `https://localhost:5173/#/login`. Use the admin credentials from `sops-get admin_password` for the first login. Additional users can be created via `POST /auth/users` (Admin role required).

See [Nix Development Environment](./Docs/NixDevEnvironment.md) for the full command reference, individual service scripts, and the test suite.

### API Overview

#### Auth

| Method | Endpoint | Description |
|---|---|---|
| POST | `/auth/login` | Username + password -> session token (8h expiry) |
| POST | `/auth/logout` | Revoke current session immediately |
| GET | `/auth/me` | Current user role and capabilities |
| GET | `/auth/users` | List users (Admin only) |
| POST | `/auth/users` | Create user (Admin only) |

#### Session

| Method | Endpoint | Description |
|---|---|---|
| GET | `/session` | Current user capabilities (separated from inventory payload) |

#### Inventory

| Method | Endpoint | Description |
|---|---|---|
| GET | `/inventory` | All items with available quantities |
| POST | `/inventory` | Create item (Manager+) |
| PUT | `/inventory` | Update item (Cashier+) |
| DELETE | `/inventory/:sku` | Delete item (Manager+) |
| GET | `/inventory/available/:sku` | Real-time availability (total, reserved, actual) |
| POST | `/inventory/reserve` | Reserve inventory for a transaction |
| DELETE | `/inventory/release/:id` | Release a reservation |
| POST | `/graphql/inventory` | GraphQL endpoint -- inventory queries |
| GET | `/openapi.json` | OpenAPI3 schema for the full API |

#### Sales

Reading sales and manager operations:

| Method | Endpoint | Description |
|---|---|---|
| GET | `/sale` | List all sales |
| GET | `/sale/:id` | Get a sale with items and payments |
| POST | `/sale/void/:id` | Void with reason |
| POST | `/sale/refund/:id` | Create inverse refund transaction |
| GET | `/refund` | List refunds |
| GET | `/refund/:id` | Get a refund |

Sale commands. Each returns the whole sale; request bodies carry no prices, totals or ids:

| Method | Endpoint | Description |
|---|---|---|
| POST | `/pos/sale` | Open a new sale for an employee, register and location |
| POST | `/pos/sale/item` | Add a quantity of a SKU (prices the line, checks availability, creates reservation) |
| DELETE | `/pos/sale/item/:id` | Remove item (releases reservation) |
| POST | `/pos/sale/payment` | Record a payment (computes change) |
| DELETE | `/pos/sale/payment/:id` | Remove payment |
| POST | `/pos/sale/clear/:id` | Clear all items/payments from an open sale, release reservations |
| POST | `/pos/sale/finalize/:id` | Finalize (refused if empty or underpaid; commits inventory, completes reservations) |

#### Registers

| Method | Endpoint | Description |
|---|---|---|
| GET | `/register` | List registers |
| GET | `/register/:id` | Get register |
| POST | `/register` | Create register |
| POST | `/register/open/:id` | Open with starting cash |
| POST | `/register/close/:id` | Close with counted cash, returns variance |

## Architecture

### Frontend Architecture

The frontend follows a centralized async loading pattern:

- **`Main.purs`** owns route matching, route-level data fetching, and fiber lifecycle management
- **Pages** render from a `Poll` of a status ADT supplied by `Main`
- **Route changes** cancel in-flight loading via `killFiber` on the previous fiber
- **`parSequence_`** runs multiple loaders in parallel per route
- **Status ADTs** per page (`Loading | Ready data | Error msg | Degraded partialData`) provide type-safe loading states
- **Auth flow**: `Main.purs` validates the session against `GET /auth/me` on startup and either restores the session or redirects to `/#/login`

Three shared abstractions keep pages small:

- **`UI.Form`**: an applicative form builder. A form is one `ado` block of fields; each field pairs an input with a parser (`String -> Either String a`). Validity is derived, never stored, and errors accumulate across fields.
- **`UI.Remote`**: `useRemote` owns one backend request as a `RemoteData` value with `reload` and `refresh`; `onMount` runs an effect when an element is created.
- **`UI.Transaction`**: the POS screen. A pure, tested `Model` plus four view modules. The screen keeps the sale exactly as the backend returns it and computes no money.

### Backend Architecture

```
App.hs (securityHeadersMiddleware, CORS, TLS, warp)
  |- Server.hs (inventory + session; resolveSession on every handler; runInvEff)
  |- Server/Auth.hs (login/logout/me/users; rate limiting via login_attempts table)
  |- Server/Transaction.hs (sale reads, void, refund, registers: runTxEff / runRegEff)
  |- Server/SaleCommand.hs (/pos/sale commands: runSaleEff)
  |- Service/Sale.hs (server-side pricing, tax, change, ids, finalize guard; wraps Service/Transaction)
  |- Service/Transaction.hs (load state via TransactionDb, run TxMachine, call effect or 409)
  |- Domain/Pricing.hs, Domain/TaxRule.hs, Domain/SaleRules.hs (pure rules: integer money, tax selection, change, finalize checks)
  |- Service/Register.hs (load state via RegisterDb, run RegMachine, call effect or 409)
  |- Auth/Session.hs (resolveSession: extract Bearer token, SHA-256 hash, lookup session)
  |- Effect/InventoryDb.hs (IO -> DB.Database; pure -> Map)
  |- Effect/TransactionDb.hs (IO -> DB.Transaction; pure -> TxStore)
  |- Effect/RegisterDb.hs (IO -> DB.Transaction; pure -> RegStore)
  |- Effect/TaxRules.hs (IO -> DB.TaxRule; pure -> list of stored rules)
  |- Effect/GenUUID.hs (IO -> nextRandom; pure -> supply list)
  |- Effect/Clock.hs (IO -> getCurrentTime; pure -> fixed time)
  |- State/TransactionMachine.hs (TxTopology GADT, compile-time transition enforcement)
  |- State/RegisterMachine.hs (RegTopology GADT, compile-time transition enforcement)
  |- API/OpenApi.hs (CheeblrAPI composition, /openapi.json)
  |- API/SaleCommand.hs (SaleCommandAPI, served beside CheeblrAPI)
  |- DB/Schema.hs (Rel8able row types and TableSchema for every table including auth)
  |- DB/Database.hs (inventory CRUD via rel8/hasql)
  |- DB/Transaction.hs (transactions, reservations, registers, payments)
  |- DB/TaxRule.hs (tax_rule table, strict row decoding, placeholder seed)
  |- DB/Auth.hs (users, sessions, login_attempts; Argon2id; CSPRNG tokens)
  '- Types/ (domain models with Aeson instances; no database-layer instances)
```

### Database Schema

| Table | Purpose |
|---|---|
| `users` | Credentials, role, active flag |
| `sessions` | Token hashes, register binding, expiry, revocation |
| `login_attempts` | Rate limiting and compliance audit trail |
| `menu_items` | Product catalog with stock quantities |
| `strain_lineage` | Cannabis-specific attributes -- FK to `menu_items` |
| `transaction` | Transaction records with status, totals, void/refund tracking |
| `transaction_item` | Line items -- FK to `transaction` with CASCADE |
| `transaction_tax` | Per-item tax records -- FK to `transaction_item` with CASCADE |
| `discount` | Discounts on items or transactions -- FK with CASCADE |
| `payment_transaction` | Payment records -- FK to `transaction` with CASCADE |
| `inventory_reservation` | Reservation tracking (Reserved -> Completed/Released) |
| `tax_rule` | Tax rules by location, item category and effective date range |
| `register` | Cash register state and history |

## Testing

```bash
test-unit             # Haskell unit tests + PureScript tests (no services needed)
test-integration      # ephemeral PostgreSQL + backend on :18080, HTTP integration suite
test-integration-tls  # same as above with TLS; validates cert SAN and plain-HTTP rejection
test-suite            # all three phases in sequence
test-smoke            # hit live backend on :8080, check endpoint and JSON contract health
```

Haskell unit tests run the full service layer against pure in-memory interpreters, and the pure pricing, tax rule and sale rule modules are covered by property tests. Integration tests spin up and tear down their own isolated PostgreSQL instance.

## Development Status

### Implemented

- Full inventory CRUD with strain lineage
- Inventory reservation system (reserve on cart add, release on remove, commit on finalize)
- Complete sale lifecycle (start -> items -> payments -> finalize/void/refund/clear)
- Server-side pricing: the backend owns unit price, tax, totals, change and ids; finalize is refused for empty or underpaid sales
- Tax rules as data (per location and item category, effective-dated), integer money, per-rule rounding
- Applicative form builder (`UI.Form`) with parsing at the input boundary; item, login and payment forms built on it
- POS screen split into a pure tested model and view modules; sale state comes only from the backend
- Compile-time state machine enforcement for transactions and registers via crem
- Algebraic effect layer with IO and pure in-memory interpreters; service layer is pool-free
- Multiple payment methods with change calculation
- Cash register open/close with variance tracking and state machine validation
- Tax and discount record storage
- Role-based capability system (4 roles, 15 capabilities)
- Session-based authentication: Argon2id passwords, CSPRNG opaque tokens, SHA-256 hash storage, instant revocation, register binding
- Rate limiting: per-credential (5/10 min) and per-IP across all usernames (20/10 min), DB-backed
- `POST /auth/login`, `POST /auth/logout`, `GET /auth/me`, `POST /auth/users` endpoints
- `bootstrap-admin` command for first-run credential generation via sops
- Security headers on all responses: HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- CORS lockdown via `ALLOWED_ORIGIN` sops secret (open in dev, locked in production)
- Centralized async loading with fiber cancellation on route change
- Parallel data loading for POS page (inventory + register + transaction)
- `TxPageDegraded` state for resilient POS page loading
- `/session` endpoint -- user capabilities separated from inventory payload
- TLS/HTTPS via warp-tls + mkcert; all service scripts TLS-aware
- sops secrets management (DB password, TLS certs, admin password, allowed origin)
- GraphQL inventory API via morpheus-graphql
- OpenAPI3 schema at `/openapi.json` via servant-openapi3
- Database layer on rel8 + hasql + hasql-pool
- Comprehensive test suite (unit, property, integration, TLS wire checks, JSON contract tests, PureScript tests)

### In Progress

- Atomic add-item (one SQL transaction with a row lock, so concurrent registers cannot oversell)
- Golden JSON fixtures shared by the Haskell and PureScript test suites
- Sale command routes in the OpenAPI document
- Real tax rules (the `tax_rule` table ships with a placeholder) and a way to edit them
- Daily financial reporting (endpoints exist, implementation pending)
- Compliance verification system (types and stubs defined)
- GraphQL WebSocket subscriptions for live inventory via PostgreSQL `LISTEN/NOTIFY`

### Planned

- Capability enforcement on transaction/register endpoints
- Inventory reservation expiry (cleanup of abandoned reservations)
- Transaction history page (currently a placeholder)
- Advanced reporting and analytics
- Multi-location support
- Third-party integrations (Metrc, Leafly)
- Libsodium public-key challenge-response (upgrade path for highest-security deployments)

## 📜 License

This project is licensed under the GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007 -- see the LICENSE file for details. 

## 🤝 Contributing

Contributions are welcome. Please feel free to submit a Pull Request.

## Support


If you like my style, Cardano ADA donations fund continued work. 

[![Donate ADA](https://img.shields.io/badge/Donate-ADA-0033AD?style=for-the-badge&logo=cardano&logoColor=white)](https://cardanoscan.io/address/addr1qxankwszy6zaclef8vq5fjn3008689yswvangmz604npjhms7402kf0h964awtj8d6xz7lzlvnrq6hz6wu6k845pzkvspum4l7)
