# Cheeblr: Cannabis Dispensary Management System

A full-stack cannabis dispensary point-of-sale and inventory management system built with PureScript (frontend) and Haskell (backend) on PostgreSQL — emphasizing type safety, functional programming, and reproducible builds via Nix.

[![License](https://www.gnu.org/graphics/agplv3-155x51.png)](https://www.gnu.org/licenses/agpl-3.0.html)

[![Nix Environment](https://github.com/harryprayiv/cheeblr/actions/workflows/nix-check.yml/badge.svg?branch=main)](https://github.com/harryprayiv/cheeblr/actions/workflows/nix-check.yml)
[![CI & Unit Tests](https://github.com/harryprayiv/cheeblr/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/harryprayiv/cheeblr/actions/workflows/ci.yml)

## Documentation

- [Frontend Documentation](./Docs/FrontEnd.md) — PureScript/Deku SPA architecture, async loading pattern, page modules, services
- [Backend Documentation](./Docs/BackEnd.md) — Haskell/Servant API, database layer, transaction processing, inventory reservations
- [Nix Development Environment](./Docs/NixDevEnvironment.md) — Setup, TLS, sops secrets management, service scripts, and test suite
- [Dependencies](./Docs/Dependencies.md) — Project dependency listing
- [To Do list](./Docs/TODO.md) — Planned features and optimizations
- [Security Recommendations](./Docs/SecurityStrategies.md) — Planned security and authentication upgrades

## Features

### Inventory Management
- **Comprehensive Product Tracking**: Detailed cannabis product data including strain lineage, THC/CBD content, terpene profiles, species classification, and Leafly integration
- **Real-Time Inventory Reservations**: Items are reserved when added to a transaction cart, preventing overselling during concurrent sessions. Reservations are released on item removal or transaction cancellation, and committed on finalization
- **Role-Based Access Control**: Dev-mode auth system with four roles (Customer, Cashier, Manager, Admin) and 15 granular capabilities governing inventory CRUD, transaction processing, register management, and reporting access
- **Flexible Sorting & Filtering**: Multi-field priority sorting (quantity, category, species) with configurable sort order and optional out-of-stock hiding
- **Complete CRUD Operations**: Create, read, update, and delete inventory items with full strain lineage data
- **GraphQL Inventory API**: Inventory queries available via `/graphql/inventory` using `morpheus-graphql` (backend) and `purescript-graphql-client` (frontend), scoped to read-only inventory access

### Point-of-Sale System
- **Full Transaction Lifecycle**: Create → add items (with reservation) → add payments → finalize (commits inventory) or clear (releases reservations)
- **Parallel Data Loading**: The POS page loads inventory, initializes the register, and starts a transaction concurrently using the frontend's `parSequence_` pattern; degrades gracefully to `TxPageDegraded` state on partial load failure
- **Multiple Payment Methods**: Cash, credit, debit, ACH, gift card, stored value, mixed, and custom payment types with change calculation
- **Tax Management**: Per-item tax records with category tracking (regular sales, excise, cannabis, local, medical)
- **Discount Support**: Percentage-based, fixed amount, BOGO, and custom discount types with approval tracking
- **Automatic Total Recalculation**: Server-side recalculation of subtotals, taxes, discounts, and totals on item/payment changes

### Financial Operations
- **Cash Register Management**: Open registers with starting cash, close with counted cash and automatic variance calculation
- **Register Persistence**: Register IDs stored in localStorage, auto-recovered on page load via get-or-create pattern
- **Transaction Modifications**: Void (marks existing transaction) and refund (creates inverse transaction with negated amounts) operations with reason tracking
- **Payment Status Tracking**: Transaction status auto-updates based on payment coverage (payments ≥ total → Completed)

### Compliance Infrastructure
- **Customer Verification Types**: Age verification, medical card, ID scan, visual inspection, patient registration, purchase limit check
- **Compliance Records**: Per-transaction compliance tracking with verification status, state reporting status, and reference IDs
- **Reporting Stubs**: Compliance and daily financial report endpoints defined with types — implementation pending

## Technology Stack

### Frontend
| Concern | Technology |
|---|---|
| Language | **PureScript** — strongly-typed FP compiling to JavaScript |
| UI | **Deku** — declarative, hooks-based rendering with `Nut` as the renderable type |
| State | **FRP.Poll** — reactive streams with `create`/`push` for mutable cells |
| Routing | **Routing.Duplex** + **Routing.Hash** — hash-based client-side routing |
| HTTP | **purescript-fetch** with **Yoga.JSON** for serialization |
| GraphQL | **purescript-graphql-client** with `AffjaxWebClient` — inventory queries via `/graphql/inventory` |
| Money | **Data.Finance.Money** — `Discrete USD` (integer cents) with formatting |
| Async | **Effect.Aff** with `run` helper, `parSequence_`, `killFiber` for route-driven loading |
| Parallelism | **Control.Parallel** — concurrent data fetching within a single route |

### Backend
| Concern | Technology |
|---|---|
| Language | **Haskell** |
| API | **Servant** — type-level REST API definitions |
| GraphQL | **morpheus-graphql** — inventory-scoped GraphQL resolver at `/graphql/inventory` |
| Database | **postgresql-simple** with `sql` quasiquoter, **resource-pool** for connection management |
| Server | **Warp** + **warp-tls** — HTTPS via TLS 1.2+ with mkcert certs in development |
| JSON | **Aeson** (derived + manual instances) |
| Auth | Dev-mode `X-User-Id` header lookup with role-based capabilities |

### Infrastructure
| Concern | Technology |
|---|---|
| Database | **PostgreSQL** with reservation-based inventory, cascading deletes, parameterized queries |
| Dev Environment | **Nix** flakes — reproducible builds, per-machine dev shells |
| Secrets | **sops** + **age** — encrypted `secrets/cheeblr.yaml`, key derived from SSH ed25519 key |
| TLS | **mkcert** for local dev certs; **warp-tls** for HTTPS on the backend; **Vite** HTTPS config |
| Build (Haskell) | **Cabal** via haskell.nix / CHaP |
| Build (PureScript) | **Spago** |
| Testing | Haskell unit + integration tests; 484 PureScript tests; ephemeral-PostgreSQL integration harness |

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
sops-status         # verify everything is wired up

# Start everything
pg-start
deploy              # tmux session: backend (HTTPS :8080) + frontend (HTTPS :5173) + pg-stats
```

See [Nix Development Environment](./Docs/NixDevEnvironment.md) for the full command reference, individual service scripts (`backend-start`, `frontend-start`, etc.), and the test suite.

### API Overview

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
| POST | `/graphql/inventory` | GraphQL endpoint — inventory queries (read-only) |

#### Transactions
| Method | Endpoint | Description |
|---|---|---|
| GET | `/transaction` | List all transactions |
| GET | `/transaction/:id` | Get transaction with items and payments |
| POST | `/transaction` | Create transaction |
| PUT | `/transaction/:id` | Update transaction |
| POST | `/transaction/void/:id` | Void with reason |
| POST | `/transaction/refund/:id` | Create inverse refund transaction |
| POST | `/transaction/item` | Add item (checks availability, creates reservation) |
| DELETE | `/transaction/item/:id` | Remove item (releases reservation) |
| POST | `/transaction/payment` | Add payment |
| DELETE | `/transaction/payment/:id` | Remove payment |
| POST | `/transaction/finalize/:id` | Finalize (commits inventory, completes reservations) |
| POST | `/transaction/clear/:id` | Clear all items/payments, release reservations |

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

- **`Main.purs`** owns all async data fetching, route matching, and fiber lifecycle management
- **Pages** are pure renderers: `Poll Status → Nut` — no side effects, no `launchAff_`, no `Poll.create`
- **Route changes** cancel in-flight loading via `killFiber` on the previous fiber
- **`parSequence_`** runs multiple loaders in parallel per route
- **Status ADTs** per page (`Loading | Ready data | Error msg | Degraded partialData`) provide type-safe loading states
- **`pure Loading <|> poll`** ensures pages always start with a loading state
- **`TxPageDegraded`** allows the transaction page to render with partial data when non-critical loads fail

```
Main.purs (orchestration)
  ├── Route matcher → killFiber prev → parSequence_ loaders → build page Nut
  ├── Loading functions: loadInventoryStatus, loadEditItem, loadDeleteItem, loadTxPageData
  └── Callback-to-Aff wrappers (makeAff) for RegisterService integration

Pages/ (pure renderers)
  ├── LiveView:           Poll InventoryLoadStatus → Nut
  ├── EditItem:           Poll EditItemStatus → Nut
  ├── DeleteItem:         Poll DeleteItemStatus → Nut
  ├── CreateTransaction:  Poll TxPageStatus → Nut  (parallel: inventory + register + tx; degrades gracefully)
  ├── CreateItem:         UserId → String → Nut
  └── TransactionHistory: Nut (placeholder)
```

### Backend Architecture

```
App.hs (bootstrap, CORS, TLS middleware, warp-tls)
  ├── Server.hs (inventory + session handlers with capability checks)
  ├── Server/GraphQL.hs (morpheus-graphql resolver, /graphql/inventory)
  ├── Server/Transaction.hs (POS: transactions, registers, ledger, compliance)
  ├── Auth/Simple.hs (dev auth: X-User-Id → role → capabilities)
  ├── DB/Database.hs (inventory CRUD, connection pooling)
  ├── DB/Transaction.hs (transactions, reservations, registers, payments)
  └── Types/ (domain models with Aeson + postgresql-simple instances)
```

### Response Types

- **`InventoryResponse`** — plain array newtype of inventory items (capabilities separated)
- **`MutationResponse`** — uniform wrapper for all write operations (success/failure + message)
- **Session endpoint** — user capabilities delivered independently of inventory data

### Data Flow

1. **Item Selection**: User adds item → backend checks `quantity - reserved` → creates reservation → returns item
2. **Cart Management**: Items tracked via transaction items table → server recalculates totals on each change
3. **Payment Processing**: Payments added → server checks if payments ≥ total → auto-updates status
4. **Finalization**: `menu_items.quantity` decremented → reservations marked `Completed` → transaction `COMPLETED`
5. **Cancellation**: `POST /transaction/clear/:id` → reservations `Released` → items/payments deleted → totals zeroed

### Database Schema

| Table | Purpose |
|---|---|
| `menu_items` | Product catalog with stock quantities |
| `strain_lineage` | Cannabis-specific attributes (THC, terpenes, lineage) — FK to `menu_items` |
| `transaction` | Transaction records with status, totals, void/refund tracking |
| `transaction_item` | Line items — FK to `transaction` with CASCADE |
| `transaction_tax` | Per-item tax records — FK to `transaction_item` with CASCADE |
| `discount` | Discounts on items or transactions — FK with CASCADE |
| `payment_transaction` | Payment records — FK to `transaction` with CASCADE |
| `inventory_reservation` | Reservation tracking (Reserved → Completed/Released) |
| `register` | Cash register state and history |

## Security

- **TLS everywhere**: backend runs warp-tls; frontend Vite dev server configured for HTTPS; all service scripts inject `USE_TLS`, `TLS_CERT_FILE`, `TLS_KEY_FILE` from sops
- **Parameterized queries** throughout — no string interpolation in SQL
- **Type safety** across the full stack — shared domain types between PureScript and Haskell enforce JSON contract at compile time (contract tests catch serialization divergence)
- **Role-based capabilities** — 15 granular permissions mapped to 4 roles, enforced on inventory writes
- **Input validation** — frontend (ValidationRule combinators) and backend (type-level constraints via Servant)
- **Secrets management** — database password and TLS cert/key stored in sops-encrypted `secrets/cheeblr.yaml`; never in plaintext on disk
- **Audit trail** — transactions track void/refund reasons, reference transactions, and modification timestamps

**Current limitation**: Authentication is dev-mode only (`X-User-Id` header with fixed users). See [Security Recommendations](./Docs/SecurityStrategies.md) for the planned upgrade path to libsodium public-key challenge-response.

## Testing

```bash
test-unit             # Haskell unit tests + 484 PureScript tests (no services needed)
test-integration      # ephemeral PostgreSQL + backend on :18080, HTTP integration suite
test-integration-tls  # same as above with TLS; validates cert SAN and plain-HTTP rejection
test-suite            # all three phases in sequence
test-smoke            # hit live backend on :8080, check endpoint and JSON contract health
```

Integration tests spin up and tear down their own isolated PostgreSQL instance so they can run independently of `pg-start`.

## Development Status

### Implemented
-  Full inventory CRUD with strain lineage
-  Inventory reservation system (reserve on cart add, release on remove, commit on finalize)
-  Complete transaction lifecycle (create → items → payments → finalize/void/refund/clear)
-  Multiple payment methods with change calculation
-  Cash register open/close with variance tracking
-  Tax and discount record management
-  Role-based capability system (4 roles, 15 capabilities)
-  Dev auth with `X-User-Id` header and user switcher widget
-  Centralized async loading with fiber cancellation on route change
-  Parallel data loading for POS page (inventory + register + transaction)
-  `TxPageDegraded` state for resilient POS page loading
-  `MutationResponse` uniform write response type
-  `/session` endpoint — user capabilities separated from inventory payload
-  TLS/HTTPS via warp-tls + mkcert; all service scripts TLS-aware
-  sops secrets management (DB password + TLS certs)
-  GraphQL inventory API (`/graphql/inventory`) via morpheus-graphql + purescript-graphql-client
-  Comprehensive test suite (Haskell unit + integration, 484 PureScript tests, ephemeral-DB harness, TLS wire checks)
-  JSON contract tests between PureScript and Haskell catching serialization divergence

### In Progress
-  Daily financial reporting (endpoints exist, implementation pending)
-  Compliance verification system (types and stubs defined)
-  GraphQL WebSocket subscriptions for live inventory via PostgreSQL `LISTEN/NOTIFY`

### Planned
-  Real authentication (libsodium public-key challenge-response, replacing dev `X-User-Id`)
-  Capability enforcement on transaction/register endpoints
-  Inventory reservation expiry (cleanup of abandoned reservations)
-  Transaction history page (currently a placeholder)
-  Advanced reporting and analytics
-  Multi-location support
-  Third-party integrations (Metrc, Leafly)

## 📜 License

This project is licensed under the GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007 — see the LICENSE file for details. 

## 🤝 Contributing

Contributions are welcome. Please feel free to submit a Pull Request.

## Support


If you like my style, Cardano ADA donations fund continued work.

[![Donate ADA](https://img.shields.io/badge/Donate-ADA-0033AD?style=for-the-badge&logo=cardano&logoColor=white)](https://cardanoscan.io/address/addr1qxankwszy6zaclef8vq5fjn3008689yswvangmz604npjhms7402kf0h964awtj8d6xz7lzlvnrq6hz6wu6k845pzkvspum4l7)