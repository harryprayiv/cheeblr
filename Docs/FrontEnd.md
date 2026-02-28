# Cheeblr Frontend Documentation

## Table of Contents
- [Overview](#overview)
- [Technologies](#technologies)
- [Architecture](#architecture)
- [Module Map](#module-map)
- [Routing](#routing)
- [State Management](#state-management)
- [Authentication & Authorization](#authentication--authorization)
- [API Layer](#api-layer)
- [Domain Types](#domain-types)
- [Pages](#pages)
- [UI Components](#ui-components)
- [Services](#services)
- [Configuration](#configuration)
- [Validation](#validation)
- [Utilities](#utilities)
- [Development Notes](#development-notes)

---

## Overview

Cheeblr is a cannabis dispensary point-of-sale system. The frontend is a PureScript single-page application that provides inventory management (CRUD), a live menu view, and a full transaction/checkout workflow backed by a Haskell REST API. All monetary values are represented as `Discrete USD` (integer cents) to avoid floating-point rounding issues.

---

## Technologies

| Concern | Library / Approach |
|---|---|
| UI rendering | **Deku** — declarative, hooks-based UI with `Nut` as the renderable type |
| Reactivity / state | **FRP.Poll** — `Poll a` streams plus `create`/`push` for mutable cells |
| Routing | **Routing.Duplex** + **Routing.Hash** — hash-based (`/#/…`) client-side routing |
| HTTP | **Fetch** (purescript-fetch) with **Yoga.JSON** for (de)serialization |
| Money | **Data.Finance.Money** — `Discrete USD` (cents), `Dense USD`, formatting via `Data.Finance.Money.Format` |
| Validation | Custom `ValidationRule` newtype + **Data.Validation.Semigroup** for accumulating errors |
| Async effects | **Effect.Aff** for all API calls; `launchAff_` to fire-and-forget from `Effect` |
| Storage | **Web.Storage.Storage** (localStorage) for persisting the register ID across sessions |

---

## Architecture

```
Main.purs                        -- entry point, routing, global state
│
├── Pages/                       -- one module per route, wires services → UI
│   ├── LiveView                 -- inventory grid (read-only)
│   ├── CreateItem               -- new MenuItem form
│   ├── EditItem                 -- edit existing MenuItem
│   ├── DeleteItem               -- delete confirmation
│   ├── CreateTransaction        -- POS checkout page
│   └── TransactionHistory       -- placeholder
│
├── UI/                          -- presentational components
│   ├── Components/
│   │   ├── Form                 -- reusable form field builders
│   │   ├── AuthGuard            -- capability-gated rendering
│   │   └── UserSelector         -- dev-mode user switcher
│   ├── Inventory/
│   │   ├── MenuLiveView         -- inventory grid renderer
│   │   ├── ItemForm             -- shared create/edit form
│   │   └── DeleteItem           -- delete confirmation UI
│   └── Transaction/
│       └── CreateTransaction    -- full POS interface
│
├── Services/                    -- business logic (effectful)
│   ├── AuthService              -- dev auth state, role checks
│   ├── RegisterService          -- register lifecycle (create/open/close)
│   ├── TransactionService       -- transaction CRUD, totals, payments
│   └── Cart                     -- cart add/remove with inventory checks
│
├── API/                         -- HTTP request layer
│   ├── Request                  -- generic auth'd request helpers
│   ├── Inventory                -- inventory endpoints
│   └── Transaction              -- transaction/register/payment endpoints
│
├── Types/                       -- domain models + serialization instances
│   ├── Auth                     -- UserRole, UserCapabilities, AuthenticatedUser
│   ├── Inventory                -- MenuItem, Inventory, StrainLineage, Species, ItemCategory
│   ├── Transaction              -- Transaction, TransactionItem, PaymentTransaction, enums
│   ├── Register                 -- Register, CartTotals, open/close request types
│   ├── Formatting               -- FieldConfig, ValidationRule, FormValue class
│   └── UUID                     -- UUID newtype, generation, parsing
│
├── Config/                      -- compile-time constants
│   ├── Network                  -- API base URL, app origin
│   ├── LiveView                 -- sort config, query mode, refresh rate
│   ├── Auth                     -- dev user fixtures
│   ├── Entity                   -- dummy entity UUIDs for dev
│   └── InventoryFields          -- per-field FieldConfig/DropdownConfig builders
│
└── Utils/                       -- pure helpers
    ├── Formatting               -- cents→dollars, comma lists, enum values
    ├── Validation               -- ValidationRule combinators
    ├── Money                    -- formatPrice, fromDollars, toDollars, parseMoneyString
    └── Storage                  -- localStorage wrappers
```

---

## Module Map

| Module | Purpose |
|---|---|
| `Main` | Bootstraps the app: creates auth & route polls, pre-inits the register, sets up `matchesWith` routing, renders `nav` + routed page |
| `Route` | Defines the `Route` ADT and the `RouteDuplex'` codec; also exports the `nav` bar component |
| `Config.Network` | `localConfig` / `networkConfig` environment records (`apiBaseUrl`, `appOrigin`); `currentConfig` selects which is active |
| `Config.LiveView` | `LiveViewConfig` record, `QueryMode` (JsonMode / HttpMode), `SortField` / `SortOrder`, default configs |
| `Config.Auth` | `DevUser` fixtures for Customer / Cashier / Manager / Admin with hard-coded UUIDs |
| `Config.Entity` | Hard-coded dummy UUIDs for account, payment, transaction, employee, register, location |
| `Config.InventoryFields` | Builder functions returning `FieldConfig` or `DropdownConfig` for every inventory form field |

---

## Routing

Defined in `Route.purs`:

```purescript
data Route
  = LiveView
  | Create
  | Delete String
  | CreateTransaction
  | TransactionHistory
  | Edit String
```

| Route | Hash URL | Page module |
|---|---|---|
| `LiveView` | `/#/` | `Pages.LiveView` |
| `Create` | `/#/create` | `Pages.CreateItem` |
| `Edit uuid` | `/#/edit/:uuid` | `Pages.EditItem` |
| `Delete uuid` | `/#/delete/:uuid` | `Pages.DeleteItem` |
| `CreateTransaction` | `/#/transaction/create` | `Pages.CreateTransaction` |
| `TransactionHistory` | `/#/transaction/history` | `Pages.TransactionHistory` |

Navigation is defined in `Route.nav`, which renders a `<nav>` bar with links and highlights the active route by comparing against the `Poll Route`.

`Main.purs` calls `matchesWith (parse route) matcher` where `matcher` pattern-matches on the route, instantiates the page's `Nut`, and pushes it into a `Poll (Tuple Route Nut)` that Deku renders.

---

## State Management

The app uses **FRP.Poll** for all reactive state. The pattern is:

```purescript
-- create a mutable cell
cell <- liftST Poll.create
-- push a value
cell.push someValue
-- read reactively
cell.poll :: Poll a
```

### Global state (Main.purs)

| State | Type | Description |
|---|---|---|
| `authState` | `Poll AuthState` | Seeded with `defaultAuthState` (`SignedIn devAdmin`) |
| `currentRoute` | `Poll (Tuple Route Nut)` | Updated on every hash change |

### Component-level state

Pages and UI components use Deku hooks:

- `useState` — creates a `(a -> Effect Unit) /\ Poll a` pair
- `useHot` — like `useState` but the Poll replays the most recent value to new subscribers (used heavily in forms)

Derived/computed state is built with `<$>`, `<*>`, and `ado` notation over polls:

```purescript
let isFormValid = ado
      vN <- validNameV
      vB <- validBrandV
      -- ...
      in all (fromMaybe false) [vN, vB, ...]
```

---

## Authentication & Authorization

### Current implementation (dev mode)

There is no real auth flow yet. `Services.AuthService` defines:

```purescript
data AuthState = SignedIn DevUser | SignedOut
```

`defaultAuthState` is `SignedIn devAdmin`. The admin `DevUser` from `Config.Auth` is used by default everywhere. A `UserId` (type alias for `String`) is extracted via `userIdFromAuth` and threaded to all API calls as the `X-User-Id` header.

### Roles & capabilities

```purescript
data UserRole = Customer | Cashier | Manager | Admin
```

Each role maps to a `UserCapabilities` record (15 boolean fields like `capCanViewInventory`, `capCanProcessTransaction`, etc.) via `capabilitiesForRole`.

### Auth guards

`UI.Components.AuthGuard` provides combinators that conditionally render UI based on capabilities:

```purescript
whenCapable :: Poll UserCapabilities -> (UserCapabilities -> Boolean) -> Nut -> Nut
whenCanEditItem :: Poll UserCapabilities -> Nut -> Nut
whenManagerOrAbove :: Poll UserRole -> Nut -> Nut
withFallback :: Poll UserCapabilities -> (UserCapabilities -> Boolean) -> Nut -> Nut -> Nut
```

### Dev user selector

`UI.Components.UserSelector` renders a widget to switch between the four dev users at runtime. It is not currently wired into Main but is available for use.

---

## API Layer

### `API.Request` — Generic helpers

All requests go through helpers that attach standard headers (`Content-Type`, `Accept`, `Origin`, `X-User-Id`) and wrap the result in `Either String a`:

| Function | Signature (simplified) | Notes |
|---|---|---|
| `authGet` | `UserId -> URL -> Aff (Either String a)` | `GET` with relative URL appended to `apiBaseUrl` |
| `authGetFullUrl` | `UserId -> String -> Aff (Either String a)` | `GET` with absolute URL |
| `authPost` | `UserId -> URL -> req -> Aff (Either String res)` | `POST` with JSON body |
| `authPut` | `UserId -> URL -> req -> Aff (Either String res)` | `PUT` with JSON body |
| `authDelete` | `UserId -> URL -> Aff (Either String a)` | `DELETE`, expects JSON response |
| `authDeleteUnit` | `UserId -> URL -> Aff (Either String Unit)` | `DELETE`, ignores response body |
| `authPostUnit` | `UserId -> URL -> Aff (Either String Unit)` | `POST` with no body, ignores response |
| `authPostEmpty` | `UserId -> URL -> Aff (Either String a)` | `POST` with no body, parses response |
| `authPostChecked` | `UserId -> URL -> req -> Aff (Either String res)` | `POST` with status-code checking (non-2xx → error) |

`runRequest` is the internal wrapper that uses `attempt` and logs errors.

### `API.Inventory`

| Function | Endpoint | Method |
|---|---|---|
| `readInventory userId` | `GET /inventory` | `authGet` |
| `writeInventory userId menuItem` | `POST /inventory` | `authPost` |
| `updateInventory userId menuItem` | `PUT /inventory` | `authPut` |
| `deleteInventory userId itemId` | `DELETE /inventory/:id` | `authDelete` |
| `fetchInventory userId config mode` | dispatches to JSON or HTTP | — |
| `fetchInventoryFromJson config` | fetches `config.jsonPath` directly | raw `fetch` |
| `fetchInventoryFromHttp userId config` | `GET config.apiEndpoint` | `authGetFullUrl` |

### `API.Transaction`

| Function | Endpoint | Method |
|---|---|---|
| `getRegister userId registerId` | `GET /register/:id` | `authGet` |
| `createRegister userId register` | `POST /register` | `authPost` |
| `openRegister userId request registerId` | `POST /register/open/:id` | `authPost` |
| `closeRegister userId request registerId` | `POST /register/close/:id` | `authPost` |
| `createTransaction userId transaction` | `POST /transaction` | `authPostChecked` |
| `getTransaction userId transactionId` | `GET /transaction/:id` | `authGet` |
| `finalizeTransaction userId transactionId` | `POST /transaction/finalize/:id` | `authPostEmpty` |
| `voidTransaction userId transactionId reason` | `POST /transaction/void/:id` | `authPost` |
| `addTransactionItem userId item` | `POST /transaction/item` | `authPostChecked` |
| `removeTransactionItem userId itemId` | `DELETE /transaction/item/:id` | `authDeleteUnit` |
| `clearTransaction userId transactionId` | `POST /transaction/clear/:id` | `authPostUnit` |
| `addPaymentTransaction userId payment` | `POST /transaction/payment` | `authPost` |
| `removePaymentTransaction userId paymentId` | `DELETE /transaction/payment/:id` | `authDeleteUnit` |

---

## Domain Types

### `Types.Inventory`

#### `MenuItem` / `MenuItemRecord`

```purescript
newtype MenuItem = MenuItem MenuItemRecord

type MenuItemRecord =
  { sort :: Int
  , sku :: UUID
  , brand :: String
  , name :: String
  , price :: Discrete USD        -- stored as cents
  , measure_unit :: String
  , per_package :: String
  , quantity :: Int
  , category :: ItemCategory
  , subcategory :: String
  , description :: String
  , tags :: Array String
  , effects :: Array String
  , strain_lineage :: StrainLineage
  }
```

**Serialization note:** `price` is serialized as a raw `Int` (cents). The `ReadForeign` instance reads an `Int` and wraps it in `Discrete`. The `WriteForeign` instance `unwrap`s to emit the raw `Int`.

#### `ItemCategory`

```
Flower | PreRolls | Vaporizers | Edibles | Drinks | Concentrates | Topicals | Tinctures | Accessories
```

Implements `BoundedEnum` (cardinality 9), `Show`, `ReadForeign`/`WriteForeign` (string-based).

#### `Species`

```
Indica | IndicaDominantHybrid | Hybrid | SativaDominantHybrid | Sativa
```

Implements `BoundedEnum` (cardinality 5), serialized as strings.

#### `StrainLineage`

```purescript
data StrainLineage = StrainLineage
  { thc :: String, cbg :: String, strain :: String, creator :: String
  , species :: Species, dominant_terpene :: String, terpenes :: Array String
  , lineage :: Array String, leafly_url :: String, img :: String
  }
```

#### `Inventory` / `InventoryResponse`

```purescript
newtype Inventory = Inventory (Array MenuItem)

data InventoryResponse
  = InventoryData Inventory
  | Message String
```

The `ReadForeign InventoryResponse` instance handles two shapes: a raw JSON array (→ `InventoryData`) or an object with `{ type, value }` fields.

#### Sorting

`compareMenuItems :: LiveViewConfig -> MenuItem -> MenuItem -> Ordering` applies the config's `sortFields` array in priority order. Each `Tuple SortField SortOrder` is tried; `EQ` falls through to the next field.

#### Validation

`validateMenuItem :: MenuItemFormInput -> Either String MenuItem` validates all fields using `Data.Validation.Semigroup`, accumulating errors, then constructs a `MenuItem`. Delegates strain fields to `validateStrainLineage`.

### `Types.Transaction`

#### `Transaction`

```purescript
newtype Transaction = Transaction
  { transactionId :: UUID
  , transactionStatus :: TransactionStatus
  , transactionCreated :: DateTime
  , transactionCompleted :: Maybe DateTime
  , transactionCustomerId :: Maybe UUID
  , transactionEmployeeId :: UUID
  , transactionRegisterId :: UUID
  , transactionLocationId :: UUID
  , transactionItems :: Array TransactionItem
  , transactionPayments :: Array PaymentTransaction
  , transactionSubtotal :: DiscreteMoney USD
  , transactionDiscountTotal :: DiscreteMoney USD
  , transactionTaxTotal :: DiscreteMoney USD
  , transactionTotal :: DiscreteMoney USD
  , transactionType :: TransactionType
  , transactionIsVoided :: Boolean
  , transactionVoidReason :: Maybe String
  , transactionIsRefunded :: Boolean
  , transactionRefundReason :: Maybe String
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes :: Maybe String
  }
```

`Maybe` fields are serialized as `Nullable` via `toNullable` for JSON compatibility with the Haskell backend.

#### `TransactionItem`

```purescript
newtype TransactionItem = TransactionItem
  { transactionItemId :: UUID
  , transactionItemTransactionId :: UUID
  , transactionItemMenuItemSku :: UUID
  , transactionItemQuantity :: Int
  , transactionItemPricePerUnit :: DiscreteMoney USD
  , transactionItemDiscounts :: Array DiscountRecord
  , transactionItemTaxes :: Array TaxRecord
  , transactionItemSubtotal :: DiscreteMoney USD
  , transactionItemTotal :: DiscreteMoney USD
  }
```

#### `PaymentTransaction`

```purescript
newtype PaymentTransaction = PaymentTransaction
  { paymentId :: UUID
  , paymentTransactionId :: UUID
  , paymentMethod :: PaymentMethod
  , paymentAmount :: DiscreteMoney USD
  , paymentTendered :: DiscreteMoney USD
  , paymentChange :: DiscreteMoney USD
  , paymentReference :: Maybe String
  , paymentApproved :: Boolean
  , paymentAuthorizationCode :: Maybe String
  }
```

#### Enums

| Type | Values | Serialization |
|---|---|---|
| `TransactionStatus` | `Created \| InProgress \| Completed \| Voided \| Refunded` | Accepts both PascalCase and SCREAMING_SNAKE |
| `TransactionType` | `Sale \| Return \| Exchange \| InventoryAdjustment \| ManagerComp \| Administrative` | Same |
| `PaymentMethod` | `Cash \| Debit \| Credit \| ACH \| GiftCard \| StoredValue \| Mixed \| Other String` | Writes PascalCase; reads both forms; `Other` prefixed with `"OTHER:"` |
| `TaxCategory` | `RegularSalesTax \| ExciseTax \| CannabisTax \| LocalTax \| MedicalTax \| NoTax` | Same |
| `DiscountType` | `PercentOff Number \| AmountOff (Discrete USD) \| BuyOneGetOne \| Custom String (Discrete USD)` | Object with `discountType` discriminator |

#### Supporting records

```purescript
type TaxRecord =
  { taxCategory :: TaxCategory, taxRate :: Number
  , taxAmount :: DiscreteMoney USD, taxDescription :: String }

type DiscountRecord =
  { discountType :: DiscountType, discountAmount :: DiscreteMoney USD
  , discountReason :: String, discountApprovedBy :: Maybe UUID }
```

#### Ledger types (defined but backend-only)

`Account`, `LedgerEntry`, `LedgerEntryType`, `AccountType`, and `LedgerError` are defined in `Types.Transaction` with full `Show`/`ReadForeign`/`WriteForeign` instances but are not currently used by any frontend service or UI.

### `Types.Register`

```purescript
type Register =
  { registerId :: UUID, registerName :: String, registerLocationId :: UUID
  , registerIsOpen :: Boolean, registerCurrentDrawerAmount :: Int
  , registerExpectedDrawerAmount :: Int, registerOpenedAt :: Maybe DateTime
  , registerOpenedBy :: Maybe UUID, registerLastTransactionTime :: Maybe DateTime }

type OpenRegisterRequest =
  { openRegisterEmployeeId :: UUID, openRegisterStartingCash :: Int }

type CloseRegisterRequest =
  { closeRegisterEmployeeId :: UUID, closeRegisterCountedCash :: Int }

type CloseRegisterResult =
  { closeRegisterResultRegister :: Register, closeRegisterResultVariance :: Int }

type CartTotals =
  { subtotal :: Discrete USD, taxTotal :: Discrete USD
  , total :: Discrete USD, discountTotal :: Discrete USD }
```

### `Types.UUID`

```purescript
newtype UUID = UUID String
```

- `genUUID :: Effect UUID` — generates a v4 UUID client-side using `Effect.Random`
- `parseUUID :: String -> Maybe UUID` — validates against the standard regex
- `emptyUUID :: UUID` — all zeros
- Has `ReadForeign`/`WriteForeign` (string round-trip), `Eq`, `Ord`, `Show` (unwraps)

### `Types.Formatting`

Defines the form system's core types:

- `ValidationRule` — newtype wrapping `String -> Boolean`
- `FieldConfig` — `{ label, placeholder, defaultValue, validation, errorMessage, formatInput }`
- `DropdownConfig` — `{ label, options, defaultValue, emptyOption }`
- `TextAreaConfig` — `{ label, placeholder, defaultValue, rows, cols, errorMessage }`
- `FormValue` class — `fromFormValue :: String -> ValidationResult a` for `String`, `Number`, `Int`, `UUID`
- `FieldValidator` class — `validateField :: String -> Either String a` with error messages

---

## Pages

### `Pages.LiveView`

Fetches inventory via `fetchInventory` using `defaultViewConfig`, pushes result into `inventoryState.poll`, and renders via `UI.Inventory.MenuLiveView.createMenuLiveView`. Manages loading and error polls separately.

### `Pages.CreateItem`

Generates a fresh UUID via `genUUID`, passes it to `UI.Inventory.ItemForm.itemForm userId (CreateMode uuid)`.

### `Pages.EditItem`

Fetches full inventory, finds the `MenuItem` matching the UUID from the URL, then renders `itemForm userId (EditMode menuItem)`. Falls back to error UI if not found.

### `Pages.DeleteItem`

Same fetch-and-find pattern, then renders `UI.Inventory.DeleteItem.renderDeleteConfirmation userId itemId itemName`.

### `Pages.CreateTransaction`

The most complex page. Orchestrates:
1. Register initialization via `RegisterService.getOrInitLocalRegister`
2. Inventory fetch for item selection
3. Transaction creation via `TransactionService.startTransaction`
4. Renders `UI.Transaction.CreateTransaction.createTransaction` with all reactive state

### `Pages.TransactionHistory`

Placeholder: renders `"Transaction History - Coming Soon"`.

---

## UI Components

### `UI.Inventory.ItemForm`

Shared form for create and edit, parameterized by `FormMode`:

```purescript
data FormMode = CreateMode String | EditMode MenuItem

itemForm :: UserId -> FormMode -> Nut
```

- ~20 `useHot` hooks for field values + validation state
- `initValues :: FormMode -> FormInit` pre-populates from the `MenuItem` in edit mode (converting cents to decimal for price, joining arrays to comma strings, etc.)
- Validation state for edit mode starts as `Just true`; for create mode starts as `Just false`
- `isFormValid` is a derived `Poll Boolean` using `ado` across all validation polls
- On submit: collects all field values, runs `validateMenuItem`, then calls `writeInventory` (create) or `updateInventory` (edit)
- Uses helper functions: `vTextField`, `readOnlyField`, `textAreaField`, `selectField`, `plainTextField`, `sectionHeading`

### `UI.Inventory.MenuLiveView`

```purescript
createMenuLiveView :: Poll Inventory -> Poll Boolean -> Poll String -> Nut
```

Renders a grid of `renderItem` cards. Applies `compareMenuItems` sorting and optional out-of-stock filtering from `defaultViewConfig`. Each card shows brand, name, image, category, species, strain, price, description (truncated), quantity, and edit/delete action links.

### `UI.Inventory.DeleteItem`

```purescript
renderDeleteConfirmation :: UserId -> String -> String -> Nut
```

Warning panel with confirm/cancel buttons. Calls `deleteInventory` on confirm, shows success with link back to inventory.

### `UI.Transaction.CreateTransaction`

```purescript
createTransaction :: UserId -> Poll Inventory -> Poll Transaction -> Register -> Nut
```

Full POS interface with three panels:

**Left panel — Item selection:**
- Category tab filter (dynamically built from inventory)
- Text search filter
- Quantity input
- Inventory table with Add buttons
- Shows current cart quantity per item
- Disables items when out of stock or during processing

**Right panel — Cart:**
- Line items with name, qty, unit price, line total, remove button
- Subtotal / tax / total summary
- Payment section: method selector (Cash, Credit, Debit, ACH, GiftCard, StoredValue, Mixed, Other), amount/tendered/auth-code inputs
- Add Payment button that calls `TransactionService.addPayment`
- List of applied payments with remove buttons

**Bottom bar:**
- Clear Items button (calls `TransactionService.clearTransaction`)
- Remaining balance display
- Process Payment button (calls `TransactionService.finalizeTransaction`)
- Status message display
- Register info and transaction status indicator

### `UI.Components.Form`

Reusable form field builders:

| Function | Description |
|---|---|
| `makeTextField` | Text input with validation, error display, optional password mode |
| `makePasswordField` | Password-specific variant |
| `makeTextArea` | Multi-line textarea with validation |
| `makeNormalField` | `makeTextField` with `isPw = false` |
| `makeDescriptionField` | Pre-configured textarea for descriptions |
| `makeDropdown` | Select dropdown with optional empty option, validation |
| `makeEnumDropdown` | Builds a `DropdownConfig` from any `BoundedEnum` |

All fields follow the pattern: config → setValue callback → setValid callback → validPoll → Nut.

### `UI.Components.AuthGuard`

Capability-gated rendering using `Deku.Hooks.guard`:

```purescript
whenCapable :: Poll UserCapabilities -> (UserCapabilities -> Boolean) -> Nut -> Nut
withFallback :: Poll UserCapabilities -> (UserCapabilities -> Boolean) -> Nut -> Nut -> Nut
```

Convenience wrappers for each capability (`whenCanViewInventory`, `whenCanEditItem`, etc.) and role thresholds (`whenCashierOrAbove`, `whenManagerOrAbove`, `whenAdmin`).

### `UI.Components.UserSelector`

Dev-mode widget showing all four dev users as clickable buttons with role badges and icons. Tracks selected user reactively. Also provides `compactUserSelector` (dropdown variant) and `capabilityIndicator` (shows current user's permissions).

---

## Services

### `Services.AuthService`

Manages the dev auth state. Key exports:

| Function | Signature | Description |
|---|---|---|
| `defaultAuthState` | `AuthState` | `SignedIn devAdmin` |
| `userIdFromAuth` | `AuthState -> String` | Extracts UUID string, or `""` if signed out |
| `getCapabilities` | `AuthState -> Maybe UserCapabilities` | Role-based capability lookup |
| `checkCapability` | `(UserCapabilities -> Boolean) -> AuthState -> Boolean` | Predicate check |
| `canViewInventory`, `canProcessTransaction`, etc. | `AuthState -> Boolean` | Convenience wrappers |
| `getAvailableUsers` | `Array DevUser` | All dev user fixtures |
| `authStateForUserId` | `UUID -> Maybe AuthState` | Look up dev user by UUID |

### `Services.RegisterService`

Manages the register lifecycle. Uses `localStorage` to persist a register UUID across sessions.

| Function | Description |
|---|---|
| `getOrCreateRegisterId` | Reads from localStorage or generates + stores a new UUID |
| `createAndOpenRegister` | Creates register via API, then immediately opens it |
| `openExistingRegister` | Opens an already-created register |
| `getOrInitLocalRegister` | Tries `GET /register/:id`; if not found, creates + opens. **Used by `Pages.CreateTransaction`** |
| `initLocalRegister` | Tries GET; if found, re-opens; if not found, creates + opens. **Used by `Main` for pre-init** |
| `createLocalRegister` | Creates a named register at a location |
| `closeLocalRegister` | Closes a register, reports variance |

All functions take callbacks `(Register -> Effect Unit)` and `(String -> Effect Unit)` for success/error.

### `Services.TransactionService`

Core transaction operations:

| Function | Description |
|---|---|
| `startTransaction` | Creates a new `Transaction` with zero totals, `Created` status, sends to API |
| `getTransaction` | Fetches transaction by UUID |
| `createTransactionItem` | Builds a `TransactionItem` with computed tax (8% sales tax), sends to API |
| `addTransactionItem` | Sends a pre-built `TransactionItem` to API |
| `removeTransactionItem` | Removes item by UUID |
| `clearTransaction` | Clears all items from a transaction |
| `voidTransaction` | Voids a transaction with reason |
| `addPayment` | Creates a `PaymentTransaction` with change calculation, sends to API |
| `removePaymentTransaction` | Removes a payment |
| `finalizeTransaction` | Completes the transaction |

Pure calculation helpers:

| Function | Description |
|---|---|
| `emptyCartTotals` | Zero-valued `CartTotals` |
| `calculateCartTotals` | Folds over `Array TransactionItem` to sum subtotal, tax, total |
| `calculateTotalPayments` | Sums payment amounts |
| `paymentsCoversTotal` | Checks if total payments ≥ transaction total |
| `getRemainingBalance` | `max 0 (total - payments)` |

### `Services.Cart`

Higher-level cart operations used by the transaction UI:

| Function | Description |
|---|---|
| `addItemToCart` | Validates quantity, calls `TransactionService.createTransactionItem`, updates cart items + totals via callbacks |
| `removeItemFromCart` | Calls `TransactionService.removeTransactionItem`, updates state |
| `addItemToTransaction` | Client-side only version (no API call) — computes tax at 15%, handles quantity merging |
| `removeItemFromTransaction` | Client-side filter |
| `isItemAvailable` | Checks if requested qty + cart qty ≤ stock |
| `getAvailableQuantity` | Stock minus current cart quantity |
| `findUnavailableItems` | Returns items in cart that exceed inventory stock |
| `getCartQuantityForSku` | Looks up current cart quantity for a SKU |

**Note:** `addItemToCart` uses 8% tax (via `TransactionService.createTransactionItem`), while `addItemToTransaction` uses 15% tax. This is a known inconsistency — the server-side flow (`addItemToCart`) should be preferred.

---

## Configuration

### `Config.Network`

```purescript
currentConfig :: EnvironmentConfig  -- currently set to localConfig

localConfig   = { apiBaseUrl: "http://localhost:8080",       appOrigin: "http://localhost:5174" }
networkConfig = { apiBaseUrl: "http://192.168.8.248:8080",   appOrigin: "http://192.168.8.248:5174" }
```

### `Config.LiveView`

```purescript
defaultViewConfig :: LiveViewConfig
defaultViewConfig =
  { sortFields: [SortByQuantity /\ Descending, SortByCategory /\ Ascending, SortBySpecies /\ Descending]
  , hideOutOfStock: false
  , mode: HttpMode
  , refreshRate: 5000
  , screens: 1
  , fetchConfig: { apiEndpoint: "http://localhost:8080/inventory", jsonPath: "./inventory.json", corsHeaders: true }
  }
```

### `Config.Auth`

Four `DevUser` fixtures with hard-coded UUIDs, used for development auth:

| User | Role | UUID |
|---|---|---|
| `devCustomer` | Customer | `8244082f-...` |
| `devCashier` | Cashier | `0a6f2deb-...` |
| `devManager` | Manager | `8b75ea4a-...` |
| `devAdmin` | Admin | `d3a1f4f0-...` |

`defaultDevUser = devAdmin`

### `Config.Entity`

Dummy UUIDs for dev: `dummyAccountId`, `dummyPaymentId`, `dummyTransactionId`, `dummyEmployeeId`, `dummyRegisterId`, `dummyLocationId`.

### `Config.InventoryFields`

Builder functions like `nameConfig :: String -> FieldConfig`, `priceConfig :: String -> FieldConfig`, etc. Each encodes the label, placeholder, validation rule, error message, and input formatter for a specific inventory field. The `priceConfig` notably calls `formatCentsToDisplayDollars` on its default value.

---

## Validation

### `ValidationRule`

```purescript
newtype ValidationRule = ValidationRule (String -> Boolean)
```

### Built-in rules (`Utils.Validation`)

| Rule | Description |
|---|---|
| `nonEmpty` | Trimmed string is not `""` |
| `alphanumeric` | Matches `^[A-Za-z0-9-\s]+$` |
| `extendedAlphanumeric` | Allows `-_&+',.()`  |
| `percentage` | Matches `^\d{1,3}(\.\d{1,2})?%$` |
| `dollarAmount` | Parses as non-negative `Number` |
| `validMeasurementUnit` | One of: g, mg, kg, oz, lb, ml, l, ea, unit(s), pack(s), eighth, quarter, half, 1/8, 1/4, 1/2 |
| `validUrl` | HTTP(S) URL regex |
| `positiveInteger` | Parses as `Int > 0` |
| `nonNegativeInteger` | Parses as `Int >= 0` |
| `fraction` | Matches `^\d+/\d+$` |
| `commaList` | Matches `^[^,]*(,[^,]*)*$` |
| `validUUID` | Delegates to `parseUUID` |
| `maxLength n` | String length ≤ n |

### Combinators

```purescript
allOf :: Array ValidationRule -> ValidationRule  -- all must pass
anyOf :: Array ValidationRule -> ValidationRule  -- at least one must pass
```

### Semigroup validation (`Data.Validation.Semigroup`)

Used in `validateMenuItem` and `validateStrainLineage` — chains field validations with `andThen`, accumulates errors as `Array String`, and converts via `toEither` / `joinWith`.

### Preset bundles

`requiredText`, `requiredTextWithLimit`, `percentageField`, `moneyField`, `urlField`, `quantityField`, `commaListField`, `multilineText` — pre-built `{ validation, errorMessage, formatInput }` records.

---

## Utilities

### `Utils.Formatting`

| Function | Description |
|---|---|
| `formatCentsToDollars :: Int -> String` | `1299` → `"12.99"` (integer division) |
| `formatCentsToDecimal :: Int -> String` | `1299` → `"12.99"` (via `Number` division) |
| `formatCentsToDisplayDollars :: String -> String` | Parses string cents, divides by 100 |
| `formatDollarAmount :: String -> String` | Ensures two decimal places |
| `parseCommaList :: String -> Array String` | Splits on `,`, trims, removes empties |
| `getAllEnumValues :: BoundedEnum a => Array a` | Enumerates all values of a bounded enum |
| `invertOrdering :: Ordering -> Ordering` | Flips `LT`↔`GT` |
| `summarizeLongText :: String -> String` | Strips newlines, collapses whitespace, truncates at 100 chars |
| `ensureNumber :: String -> String` | Parses or defaults to `"0.0"` |
| `ensureInt :: String -> String` | Parses or defaults to `"0"` |

### `Utils.Money`

| Function | Description |
|---|---|
| `fromDollars :: Number -> Discrete USD` | Multiplies by 100, floors |
| `toDollars :: Discrete USD -> Number` | Divides by 100 |
| `formatMoney :: DiscreteMoney USD -> String` | `numericC` format (with currency symbol) |
| `formatMoney' :: DiscreteMoney USD -> String` | `numeric` format (no symbol) |
| `formatPrice :: DiscreteMoney USD -> String` | Alias for `formatMoney'` |
| `formatDiscretePrice :: Discrete USD -> String` | Converts to `DiscreteMoney` then formats |
| `formatDiscreteUSD :: Discrete USD -> String` | `numericC` format |
| `formatDiscreteUSD' :: Discrete USD -> String` | `numeric` format |
| `parseMoneyString :: String -> Maybe (Discrete USD)` | Parses string as dollars, converts to cents |

### `Utils.Storage`

Thin wrappers around `Web.Storage.Storage`:

```purescript
storeItem    :: String -> String -> Effect Unit
retrieveItem :: String -> Effect (Maybe String)
removeItem   :: String -> Effect Unit
clearStorage :: Effect Unit
```

---

## Development Notes

### Project structure convention
- `API/` — HTTP communication only, no business logic
- `Services/` — effectful business logic, orchestrates API calls
- `Types/` — pure domain models with serialization instances
- `Config/` — compile-time constants, no effects
- `UI/` — presentational components organized by domain
- `Pages/` — route handlers that wire services into UI
- `Utils/` — pure helper functions

### Known issues / tech debt
- **Tax rate inconsistency:** `Services.Cart.addItemToTransaction` uses 15% hardcoded tax; `Services.TransactionService.createTransactionItem` uses 8%. The API-backed flow should be canonical.
- **No real auth:** The system uses hard-coded dev users. The `X-User-Id` header is the only auth mechanism.
- **Ledger types unused:** `Account`, `LedgerEntry`, `LedgerEntryType`, `AccountType`, `LedgerError` are defined but not consumed by any frontend module.
- **`TransactionHistory` is a stub.**
- **Register ID in localStorage:** `getOrCreateRegisterId` persists across sessions but there's no UI to reset it.
- **`refreshRate` in `LiveViewConfig` is defined but no polling/auto-refresh is implemented.**

### Error handling pattern
All API calls return `Either String a`. Pages and services pattern match on the result and push errors into a status message poll or error poll for display. `attempt` from `Effect.Aff` is used to catch exceptions from `fetch` / `fromJSON`.

### Serialization conventions
- PureScript `Maybe a` → JSON `Nullable a` (via `toNullable`) for writes
- Backend sends `null` or absent fields → `ReadForeign` instances handle both
- Enum types accept both PascalCase (`"Created"`) and SCREAMING_SNAKE (`"CREATED"`) on read, emit PascalCase on write
- `UUID` round-trips as plain strings
- `Discrete USD` (cents) round-trips as `Int`
- `DiscreteMoney USD` uses Yoga.JSON's default `ReadForeign`/`WriteForeign` for the `Data.Finance.Money.Extended` wrapper