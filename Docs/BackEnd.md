# Cheeblr Backend Documentation

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
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

The system uses a layered architecture with Servant for type-safe API definitions and PostgreSQL for persistence. All monetary values are stored as integer cents to avoid floating-point rounding.

## Architecture

### Architectural Layers

1. **API Layer** (`API/`): Type-level API definitions using Servant's DSL. `API.Inventory` defines the inventory CRUD endpoints with auth headers. `API.Transaction` defines the POS, register, ledger, and compliance endpoints plus all request/response types that aren't domain models.
2. **Server Layer** (`Server.hs`, `Server/Transaction.hs`): Request handlers. `Server` handles inventory endpoints with capability checks. `Server.Transaction` implements all POS subsystem handlers (transactions, registers, ledger, compliance).
3. **Database Layer** (`DB/`): `DB.Database` handles inventory CRUD and connection pooling. `DB.Transaction` handles all transaction, register, reservation, and payment database operations.
4. **Auth Layer** (`Auth/Simple.hs`): Dev-mode authentication via `X-User-Id` header lookup against a fixed set of dev users, with role-based capability gating.
5. **Types Layer** (`Types/`): Domain models — `Types.Inventory` (menu items, strain lineage, inventory response), `Types.Transaction` (transactions, payments, taxes, discounts, compliance, ledger), `Types.Auth` (roles, capabilities).
6. **Application Core** (`App.hs`): Server bootstrap, CORS configuration, middleware setup.

### Key Technologies

| Concern | Library |
|---|---|
| API definition | **Servant** — type-level web DSL |
| Database | **postgresql-simple** with `sql` quasiquoter |
| Connection pooling | **resource-pool** (`Data.Pool`) |
| HTTP server | **Warp** |
| JSON | **Aeson** (derived + manual instances) |
| CORS | **wai-cors** with custom OPTIONS middleware |
| UUID generation | **uuid** + **uuid-v4** (`Data.UUID.V4.nextRandom`) |

### System Flow

1. Warp receives request, custom OPTIONS middleware handles preflight
2. `wai-cors` applies CORS headers
3. Servant routes to handler in `Server` (inventory) or `Server.Transaction` (POS subsystem)
4. Inventory handlers extract user from `X-User-Id` header via `Auth.Simple.lookupUser`, check capabilities
5. Handlers interact with database layer (`DB.Database` or `DB.Transaction`)
6. Database layer uses connection pool, executes parameterized queries
7. Results serialized as JSON and returned

## Core Components

### Main Application (`App.hs`)

Bootstraps the server: reads system username for DB config, initializes connection pool, creates all tables, configures CORS, and starts Warp on port 8080.

```haskell
data AppConfig = AppConfig
  { dbConfig :: DBConfig
  , serverPort :: Int
  }
```

Default configuration:
- **Database**: `localhost:5432/cheeblr`, current system user, password `"postgres"`, pool size 10
- **Server**: port 8080, binds all interfaces

CORS is configured to allow any origin (`corsOrigins = Nothing`) with all standard methods and custom headers (`x-requested-with`, `x-user-id`). A separate `handleOptionsMiddleware` intercepts `OPTIONS` requests directly to handle preflight before Servant routing.

### Combined Server (`Server.hs`)

```haskell
type API = InventoryAPI :<|> PosAPI

combinedServer :: Pool Connection -> Server API
combinedServer pool = inventoryServer pool :<|> posServerImpl pool
```

`inventoryServer` handles the four inventory CRUD endpoints. Each handler extracts the user from the `X-User-Id` header via `lookupUser`, derives capabilities from the user's role, and gates write operations behind capability checks (`capCanCreateItem`, `capCanEditItem`, `capCanDeleteItem`). Read (GET) is allowed for all authenticated users.

The inventory GET response includes the user's `UserCapabilities` alongside the inventory data, allowing the frontend to render UI based on permissions.

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

It looks up the user, checks the capability predicate, and either returns the user or throws `err403`. Currently, only inventory write endpoints use explicit capability checks (directly in handlers rather than via `requireAuth`). Transaction endpoints do not yet enforce capabilities.

### InventoryResponse with Capabilities

The `GET /inventory` response includes the requesting user's capabilities:

```haskell
data InventoryResponse
  = InventoryData { inventoryItems :: Inventory, inventoryCapabilities :: UserCapabilities }
  | Message Text
```

JSON shape for `InventoryData`:
```json
{ "type": "data", "value": [...items...], "capabilities": {...} }
```

This allows the frontend to gate UI elements without a separate capabilities endpoint.

## API Reference

### Inventory Endpoints

All inventory endpoints require the `X-User-Id` header.

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/inventory` | Any role | Returns all inventory items with user capabilities |
| POST | `/inventory` | `capCanCreateItem` | Add a new menu item |
| PUT | `/inventory` | `capCanEditItem` | Update an existing menu item |
| DELETE | `/inventory/:sku` | `capCanDeleteItem` | Delete a menu item by SKU UUID |

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

#### Inventory & InventoryResponse

```haskell
newtype Inventory = Inventory { items :: V.Vector MenuItem }

data InventoryResponse
  = InventoryData { inventoryItems :: Inventory, inventoryCapabilities :: UserCapabilities }
  | Message Text
```

`Inventory` serializes as a bare JSON array (custom `ToJSON`/`FromJSON`). `InventoryResponse` serializes as `{ "type": "data"|"message", "value": ..., "capabilities": ... }`.

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
2. **Item Addition** (`POST /transaction/item`): Validates inventory availability (stock minus active reservations), creates an `inventory_reservation` with status `"Reserved"`, inserts the transaction item with associated taxes and discounts.
3. **Payment Addition** (`POST /transaction/payment`): Inserts payment, then auto-updates transaction status — if total payments ≥ transaction total, status becomes `COMPLETED`, otherwise `IN_PROGRESS`.
4. **Finalization** (`POST /transaction/finalize/:id`): Decrements actual `menu_items.quantity` by reserved amounts, changes reservation status from `"Reserved"` to `"Completed"`, sets transaction status to `COMPLETED` with completion timestamp.

### Transaction Reversal Operations

**Void** (`POST /transaction/void/:id`): Sets status to `VOIDED`, marks `is_voided = TRUE`, records reason. Does not create a new transaction or reverse inventory.

**Refund** (`POST /transaction/refund/:id`): Creates a new inverse transaction with negated monetary amounts, type `Return`, referencing the original transaction. Marks the original as `is_refunded = TRUE`. The refund transaction gets its own UUID and items/payments are negated copies of the original.

### Clear Transaction (`POST /transaction/clear/:id`)

Resets a transaction to empty state:
1. Releases all active reservations (status → `"Released"`)
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

### Server Configuration

| Setting | Value |
|---|---|
| Port | 8080 |
| DB host | localhost |
| DB port | 5432 |
| DB name | cheeblr |
| DB user | Current system user (`getLoginName`) |
| DB password | `"postgres"` |
| Pool size | 10 |
| Pool idle timeout | 0.5 seconds |
| Pool max connections | 10 |

## Development Guidelines

### Project Structure Convention

- `API/` — Servant type definitions and request/response types. No business logic.
- `Auth/` — Authentication/authorization. Currently dev-only with fixed users.
- `Server/` and `Server.hs` — Request handlers. Inventory handlers in `Server.hs`, POS handlers in `Server/Transaction.hs`.
- `DB/` — Database operations. Parameterized queries, connection pooling, all SQL lives here.
- `Types/` — Domain models with serialization instances. No effects.

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
- Transaction item addition uses custom `InventoryException` types caught and converted to `err400` with JSON error bodies
- Missing resources return `err404`
- Unimplemented endpoints return `err501`
- Capability violations return `err403`
- Server logging goes to both stdout (handler activity) and stderr (database operations, table creation)

### Known Issues / Tech Debt

- **No real authentication**: `X-User-Id` header is trusted without verification. Default user is cashier, not admin.
- **Backend default vs frontend default**: Backend defaults to `cashier-1` when no header provided; frontend sends admin UUID. This mismatch is harmless in dev but worth noting.
- **Capability enforcement incomplete**: Only inventory write endpoints check capabilities. Transaction, register, and other endpoints do not enforce role-based access.
- **Ledger and compliance are stubs**: Endpoints exist and types are defined, but no database tables or real logic back them.
- **`PaymentMethod.Other` text dropped on DB write**: `showPaymentMethod (Other text) = "OTHER"` — the custom text payload is lost in the database.
- **`DiscountType` round-trip lossy**: `parseDiscountType` reconstructs from a `(Text, Maybe Int)` tuple, but `PercentOff` stores the percent as `Scientific` in Haskell while the DB stores it as a nullable `NUMERIC` on the discount row.
- **No inventory reservation expiry**: Reservations with status `"Reserved"` persist indefinitely if a transaction is abandoned without being cleared or finalized.
- **`error` calls in DB layer**: Several functions (e.g., `finalizeTransaction`, `refundTransaction`) use `error` for "impossible" states (record not found after insert/update), which would crash the server thread rather than returning an HTTP error.