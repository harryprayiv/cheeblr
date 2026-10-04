# Cheeblr Frontend Documentation

## Table of Contents
- [Overview](#overview)
- [Technologies](#technologies)
- [Architecture](#architecture)
- [Module Map](#module-map)
- [Routing](#routing)
- [State Management](#state-management)
- [Async Loading Pattern](#async-loading-pattern)
- [Authentication & Authorization](#authentication--authorization)
- [API Layer](#api-layer)
- [Domain Types](#domain-types)
- [Pages](#pages)
- [UI Components](#ui-components)
- [Services](#services)
- [Configuration](#configuration)
- [Forms and Parsing](#forms-and-parsing)
- [Utilities](#utilities)
- [Development Notes](#development-notes)

---

## Overview

Cheeblr is a cannabis dispensary point-of-sale system. The frontend is a PureScript single-page application that provides inventory management (CRUD), a live menu view, and a full transaction/checkout workflow backed by a Haskell REST API. All monetary values are represented as `Discrete USD` (integer cents) to avoid floating-point rounding issues.

---

## Technologies

| Concern | Library / Approach |
|---|---|
| UI rendering | **Deku** -- declarative, hooks-based UI with `Nut` as the renderable type |
| Reactivity / state | **FRP.Poll** -- `Poll a` streams plus `create`/`push` for mutable cells |
| Routing | **Routing.Duplex** + **Routing.Hash** -- hash-based (`/#/…`) client-side routing |
| HTTP | **Fetch** (purescript-fetch) with **Yoga.JSON** for (de)serialization |
| Money | **Data.Finance.Money** -- `Discrete USD` (cents), `Dense USD`, formatting via `Data.Finance.Money.Format` |
| Forms and validation | `UI.Form` (applicative form builder) + `UI.Form.Parser` (`String -> Either String a` field parsers); errors accumulate with **Data.Validation.Semigroup** |
| Async effects | **Effect.Aff** for all API calls; `run` helper to push results into polls, `parSequence_` for parallel loading, `killFiber` for cancellation on route change |
| Parallelism | **Control.Parallel** -- `parallel`/`sequential` for concurrent data fetching within a single route |
| Storage | **Web.Storage.Storage** (localStorage) for persisting the register ID across sessions |

---

## Architecture

```
Main.purs                        -- entry point, routing, async loading orchestration
│
├── Pages/                       -- route-level renderers
│   ├── LiveView                 -- inventory grid (read-only)
│   ├── CreateItem / EditItem / DeleteItem
│   ├── CreateTransaction        -- POS checkout page (hands off to UI.Transaction)
│   ├── Login                    -- sign-in form
│   ├── Admin/                   -- Dashboard, State (tabs), Tabs/ (Overview, LogViewer, FeedMonitor)
│   ├── Manager/                 -- Dashboard, State (tabs), Panels/ (ActivityFeed, Alerts, Stats, Reports)
│   ├── Stock/                   -- stockroom pull queue
│   ├── Feed/Monitor
│   └── TransactionHistory       -- placeholder
│
├── UI/                          -- presentational components
│   ├── Form                     -- applicative form builder
│   ├── Form/Parser              -- field parsers
│   ├── Remote                   -- useRemote hook, onMount, viewRemote
│   ├── Tabs                     -- shared tab bar
│   ├── Components/
│   │   ├── AuthGuard            -- capability-gated rendering
│   │   └── UserSelector         -- dev-mode user switcher
│   ├── Inventory/
│   │   ├── MenuLiveView         -- inventory grid renderer
│   │   ├── ItemForm             -- shared create/edit form (on UI.Form)
│   │   └── DeleteItem           -- delete confirmation UI
│   └── Transaction/
│       ├── Model                -- pure functions over the sale (tested)
│       ├── InventoryPicker      -- category tabs, search, quantity, inventory table
│       ├── CartView             -- cart lines and totals
│       ├── PaymentPanel         -- payment form and payment list
│       ├── ActionBar            -- clear, remaining balance, process payment, new sale
│       └── CreateTransaction    -- composes the five modules above
│
├── Services/                    -- effectful logic
│   ├── AuthService              -- auth state, role checks
│   ├── RegisterService          -- register lifecycle (create/open/close)
│   ├── SaleActions              -- the sale commands the transaction screen sends
│   ├── TransactionService       -- startSale, getSale, void, refund, legacy pure helpers
│   └── Cart                     -- legacy pure availability helpers (tests only)
│
├── API/                         -- HTTP request layer
│   ├── Request                  -- generic auth'd request helpers
│   ├── Auth, Inventory, Register, Reservation, Refund, Manager, Admin, Stock
│   ├── Sale                     -- read sales, void, refund
│   └── SaleCommand              -- /pos/sale commands; every call returns the whole sale
│
├── GraphQL/                     -- inventory GraphQL queries
│
├── Types/                       -- domain models + serialization instances
│   ├── Auth, Session, Inventory, Register, Location, Stock, Feed, Admin, Manager
│   ├── RemoteData               -- NotAsked | Loading | Failure | Success
│   ├── Transaction              -- enums (status, payment method, tax category, ...)
│   ├── Transaction/Sale         -- Item, Tax, Discount, Payment, SaleTransaction
│   ├── Transaction/Refund
│   ├── Primitives/Money, Primitives/Quantity
│   └── UUID
│
├── Config/                      -- compile-time constants
│   ├── Network, LiveView, Auth, Entity
│
└── Utils/                       -- helpers
    ├── Formatting, Money, Storage, SSE, WebSocket, Audio
```

## Module Map

| Module | Purpose |
|---|---|
| `Main` | Bootstraps the app: creates auth & route polls, pre-inits the register, sets up `matchesWith` routing with `run` + `parSequence_` for async loading, cancels in-flight loads on route change via `killFiber`, renders `nav` + routed page |
| `Route` | Defines the `Route` ADT and the `RouteDuplex'` codec; also exports the `nav` bar component |
| `Config.Network` | `localConfig` / `networkConfig` environment records (`apiBaseUrl`, `appOrigin`); `currentConfig` selects which is active |
| `Config.LiveView` | `LiveViewConfig` record, `QueryMode` (JsonMode / HttpMode), `SortField` / `SortOrder`, default configs |
| `Config.Auth` | `DevUser` fixtures for Customer / Cashier / Manager / Admin with hard-coded UUIDs |
| `Config.Entity` | Hard-coded dummy UUIDs for account, payment, transaction, employee, register, location |
| `UI.Form` / `UI.Form.Parser` | Applicative form builder and the field parsers every form uses |
| `UI.Remote` | `useRemote` hook for one backend request, `onMount`, and `viewRemote` for drawing a `RemoteData` |
| `UI.Transaction.*` | The POS screen: a pure `Model`, four view modules, and `CreateTransaction` composing them |
| `Services.SaleActions` / `API.SaleCommand` | The sale commands; each returns the whole sale from the backend |

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

`Main.purs` calls `matchesWith (parse route) matcher` where `matcher`:
1. Cancels any in-flight loading from the previous route via `killFiber`
2. Launches the current route's loaders in parallel via `parSequence_`
3. Builds the page `Nut` (passing `pure Loading <|> poll` so pages always start with a loading state)
4. Pushes the `Tuple Route Nut` for Deku to render

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
| `inventory` | `Poll InventoryLoadStatus` | Pushed by `run` on `LiveView` route |
| `editItem` | `Poll EditItemStatus` | Pushed by `run` on `Edit` route |
| `deleteItem` | `Poll DeleteItemStatus` | Pushed by `run` on `Delete` route |
| `txPage` | `Poll TxPageStatus` | Pushed by `run` on `CreateTransaction` route |
| `prevAction` | `Ref (Aff Unit)` | Tracks the previous route's loading fiber for cancellation |

### Component-level state

Pages and UI components use Deku hooks:

- `useState` creates a `(a -> Effect Unit) /\ Poll a` pair
- `useHot` is like `useState` but the Poll replays the most recent value to new subscribers

Derived state is built with `<$>`, `<*>` and `ado` over polls. Three shared abstractions sit on top of the hooks so pages do not hand-roll cells:

- **Forms**: `UI.Form` allocates one cell per field internally. A page never declares per-field setters or validity cells. See [Forms and Parsing](#forms-and-parsing).
- **Backend requests**: `UI.Remote.useRemote initial request` owns one request and exposes `{ value :: Poll (RemoteData a), reload, refresh }`. `reload` shows the loading state; `refresh` refetches while the current value stays on screen.
- **Mount effects**: `UI.Remote.onMount effect` runs an effect when an element is created. Do not use `DL.load_` on a `div` or `span` for this: browsers do not raise `load` on those elements, so the handler never runs.

The transaction screen keeps four cells: the sale exactly as the backend last returned it, the inventory (`useRemote`), an `Activity` value saying which request is running, and a status message. It never edits the sale locally.

## Async Loading Pattern

The app follows the pattern from [purescript-deku-realworld](https://github.com/mfp22/purescript-deku-realworld): all async data loading is centralized in `Main.purs`, and pages are pure renderers that receive `Poll`s of typed status ADTs.

### The `run` helper

```purescript
run :: forall a r. Aff a -> { push :: a -> Effect Unit | r } -> Aff Unit
run aff { push } = aff >>= liftEffect <<< push
```

Takes an `Aff` computation and a poll creator (anything with a `push` field), runs the computation, and pushes the result. This decouples data fetching from rendering.

### Route-driven loading with `parSequence_`

Inside the route matcher, each route declares its loaders as an array of `Aff Unit` actions (each built with `run`). `parSequence_` runs them all in parallel:

```purescript
newAction <- launchAff $ killFiber (error "route changed") pa *>
  parSequence_ case r of
    LiveView ->
      [ run (loadInventoryStatus userId) inventory ]
    CreateTransaction ->
      [ run (loadTxPageData userId) txPage ]
    Edit uuid ->
      [ run (loadEditItem userId uuid) editItem ]
    Delete uuid ->
      [ run (loadDeleteItem userId uuid) deleteItem ]
    _ -> []
```

### Fiber cancellation on route change

A `Ref (Aff Unit)` (`prevAction`) tracks the previous route's loading fiber. On every route change, `killFiber` cancels it before launching new loaders. This prevents stale data from arriving after the user has navigated away.

### Loading status ADTs

Each route that needs async data defines a status ADT:

```purescript
-- Pages.LiveView
data InventoryLoadStatus = InventoryLoading | InventoryLoaded Inventory | InventoryError String

-- Pages.EditItem
data EditItemStatus = EditLoading | EditReady MenuItem | EditNotFound String | EditError String

-- Pages.DeleteItem
data DeleteItemStatus = DeleteLoading | DeleteReady String String | DeleteNotFound String | DeleteError String

-- Pages.CreateTransaction
data TxPageStatus
  = TxPageLoading
  | TxPageReady Inventory Register Sale.SaleTransaction
  | TxPageDegraded String Register Sale.SaleTransaction  -- inventory failed; sale still usable
  | TxPageError String
```

Pages receive `pure Loading <|> poll` so they always render a loading state initially, then the loaded data once it arrives.

Data that a page fetches for itself (dashboards, reports, the transaction screen's inventory) uses the shared `Types.RemoteData` type with `UI.Remote.useRemote` instead of a per-page ADT:

```purescript
data RemoteData a = NotAsked | Loading | Failure String | Success a
```

### Parallel loading for CreateTransaction

The `CreateTransaction` route is the most complex -- it needs inventory, a register, and a new transaction. These are loaded in parallel using `sequential`/`parallel`:

```purescript
loadTxPageData userId = do
  Tuple invResult regTxResult <- sequential $
    Tuple
      <$> parallel (loadInventoryResult userId)
      <*> parallel (loadRegisterAndStartTx userId)
  -- combine results into TxPageStatus
```

The register initialization (which is callback-based) is wrapped into `Aff` via `makeAff`:

```purescript
getOrInitRegisterAff :: String -> UUID -> UUID -> Aff (Either String Register)
getOrInitRegisterAff userId locationId employeeId =
  makeAff \cb -> do
    RegisterService.getOrInitLocalRegister userId locationId employeeId
      (\register -> cb (Right (Right register)))
      (\err -> cb (Right (Left err)))
    pure nonCanceler
```

### Loading functions

All loading functions are pure `Aff` computations defined in `Main.purs`:

| Function | Returns | Description |
|---|---|---|
| `loadInventoryStatus` | `Aff InventoryLoadStatus` | Fetches inventory via `fetchInventory`, wraps in status ADT |
| `loadEditItem` | `Aff EditItemStatus` | Fetches full inventory, finds item by UUID |
| `loadDeleteItem` | `Aff DeleteItemStatus` | Same fetch-and-find, extracts item ID and name |
| `loadTxPageData` | `Aff TxPageStatus` | Parallel loads inventory + (register init → start transaction) |
| `getOrInitRegisterAff` | `Aff (Either String Register)` | `makeAff` wrapper around callback-based `RegisterService.getOrInitLocalRegister` |

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

### `API.Request` -- Generic helpers

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
| `fetchInventory userId config mode` | dispatches to JSON or HTTP | -- |
| `fetchInventoryFromJson config` | fetches `config.jsonPath` directly | raw `fetch` |
| `fetchInventoryFromHttp userId config` | `GET config.apiEndpoint` | `authGetFullUrl` |

### `API.Sale`

Read access to sales, plus the two manager operations.

| Function | Endpoint | Method |
|---|---|---|
| `getAllSales userId` | `GET /sale` | `authGet` |
| `getSale userId saleId` | `GET /sale/:id` | `authGet` |
| `voidSale userId saleId reason` | `POST /sale/void/:id` | `authPost` |
| `refundSale userId saleId reason` | `POST /sale/refund/:id` | `authPost` |

### `API.SaleCommand`

The register's sale commands. Every function returns `Aff (Either String Sale.SaleTransaction)`: the whole sale as the backend holds it after the command. Requests carry no price, tax, total, change or id. The record field names match the backend's `Types.Transaction.Request` exactly.

| Function | Endpoint | Body |
|---|---|---|
| `startSale userId request` | `POST /pos/sale` | `{ startSaleEmployeeId, startSaleRegisterId, startSaleLocationId }` |
| `addItem userId request` | `POST /pos/sale/item` | `{ addItemSaleId, addItemSku, addItemQuantity }` |
| `removeItem userId itemId` | `DELETE /pos/sale/item/:id` | none |
| `addPayment userId request` | `POST /pos/sale/payment` | `{ addPaymentSaleId, addPaymentMethod, addPaymentAmount, addPaymentTendered, addPaymentReference }` |
| `removePayment userId paymentId` | `DELETE /pos/sale/payment/:id` | none |
| `clear userId saleId` | `POST /pos/sale/clear/:id` | none |
| `finalize userId saleId` | `POST /pos/sale/finalize/:id` | none |

Amounts are integer cents. `addPaymentTendered` is optional; without it the payment is exact.

### Other API modules

`API.Auth` (login, logout, session validation), `API.Register`, `API.Reservation`, `API.Refund`, `API.Manager`, `API.Admin` and `API.Stock` follow the same pattern as `API.Inventory`: thin functions over `API.Request` helpers.

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

### `Types.Transaction`

`Types.Transaction` holds the enums shared by sales and refunds: `TransactionStatus` (`Created`, `InProgress`, `Completed`, `Voided`, `Refunded`), `PaymentMethod` (`Cash`, `Debit`, `Credit`, `ACH`, `GiftCard`, `StoredValue`, `Mixed`, `Other String`), `TaxCategory`, `DiscountType` and the transaction type. It also still defines ledger and compliance record types that no frontend module consumes.

### `Types.Transaction.Sale`

The sale as it crosses the wire. Field names match the backend records exactly.

```purescript
type Item =
  { itemId            :: UUID
  , itemTransactionId :: UUID
  , itemMenuItemSku   :: UUID
  , itemQuantity      :: SaleQuantity
  , itemPricePerUnit  :: SaleMoney
  , itemDiscounts     :: Array Discount
  , itemTaxes         :: Array Tax
  , itemSubtotal      :: SaleMoney
  , itemTotal         :: SaleMoney
  }

type Tax =
  { taxCategory :: TaxCategory, taxRate :: Number, taxAmount :: SaleMoney, taxDescription :: String }

type Payment =
  { paymentId :: UUID, paymentTransactionId :: UUID, paymentMethod :: PaymentMethod
  , paymentAmount :: SaleMoney, paymentTendered :: SaleMoney, paymentChange :: SaleMoney
  , paymentReference :: Maybe String, paymentApproved :: Boolean
  , paymentAuthorizationCode :: Maybe String }
```

`SaleTransaction` carries `saleId`, `saleStatus`, timestamps, the employee, register and location ids, `saleItems`, `salePayments`, the four totals (`saleSubtotal`, `saleDiscountTotal`, `saleTaxTotal`, `saleTotal`), `saleKind`, and the void and refund flags with their reasons.

Every amount, tax line and total in a sale is computed by the backend. The frontend displays them and never recomputes them. `Types.Transaction.Refund` mirrors this shape with negated money for refunds.

### `Types.Primitives.Money` and `Types.Primitives.Quantity`

`SaleMoney` (non-negative cents) and `SaleQuantity` newtypes with accessors such as `saleMoneyCents`, `saleMoneyDiscrete` and `saleQuantityCount`.

### `Types.RemoteData`

`RemoteData a = NotAsked | Loading | Failure String | Success a`, with a `Functor` instance and `fromEither`. Used with `UI.Remote`.

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

- `genUUID :: Effect UUID` -- generates a v4 UUID client-side using `Effect.Random`
- `parseUUID :: String -> Maybe UUID` -- validates against the standard regex
- `emptyUUID :: UUID` -- all zeros
- Has `ReadForeign`/`WriteForeign` (string round-trip), `Eq`, `Ord`, `Show` (unwraps)

## Pages

All pages are **pure renderers** that receive `Poll`s of typed status ADTs. They contain no `launchAff_`, no `Poll.create`, and no `Effect` wrappers. Async loading is handled entirely by `Main.purs`.

### `Pages.LiveView`

```purescript
page :: Poll AuthState -> Poll InventoryLoadStatus -> Nut
```

Receives a `Poll InventoryLoadStatus` and pattern matches on it:
- `InventoryLoading` → loading indicator
- `InventoryLoaded inv` → delegates to `UI.Inventory.MenuLiveView.renderInventory` with `defaultViewConfig`
- `InventoryError err` → error message

Data is loaded by `Main.loadInventoryStatus` which calls `fetchInventory` with the default view config.

### `Pages.CreateItem`

```purescript
page :: Poll AuthState -> UserId -> String -> Nut
```

Takes a pre-generated UUID string (created in `Main`'s matcher via `genUUID`) and passes it to `UI.Inventory.ItemForm.itemForm userId (CreateMode uuid)`. No async loading needed -- this is a pure form.

### `Pages.EditItem`

```purescript
page :: Poll AuthState -> UserId -> Poll EditItemStatus -> Nut
```

Receives a `Poll EditItemStatus` and pattern matches:
- `EditLoading` → loading indicator
- `EditReady menuItem` → renders `itemForm userId (EditMode menuItem)`
- `EditNotFound uuid` → error via `renderError`
- `EditError msg` → error via `renderError`

Data is loaded by `Main.loadEditItem` which fetches the full inventory and finds the item by UUID.

### `Pages.DeleteItem`

```purescript
page :: Poll AuthState -> UserId -> Poll DeleteItemStatus -> Nut
```

Receives a `Poll DeleteItemStatus` and pattern matches:
- `DeleteLoading` → loading indicator
- `DeleteReady itemId itemName` → renders `UI.Inventory.DeleteItem.renderDeleteConfirmation`
- `DeleteNotFound uuid` → error via `renderError`
- `DeleteError msg` → error via `renderError`

Data is loaded by `Main.loadDeleteItem` which fetches inventory and extracts the item's ID and name.

### `Pages.CreateTransaction`

```purescript
page :: Poll AuthState -> UserId -> Poll TxPageStatus -> Nut
```

Receives a `Poll TxPageStatus` with the data loaded in parallel by `Main.loadTxPageData`:

- `TxPageLoading` shows a loading indicator
- `TxPageReady inventory register sale` renders `UI.Transaction.CreateTransaction.createTransaction` with `Success inventory`, the sale and the register as plain values
- `TxPageDegraded err register sale` renders the same screen with `Failure "Inventory unavailable: ..."`; the picker shows the error and its Refresh button retries
- `TxPageError err` shows the error via `renderError`

The loading function runs the inventory fetch and register-init-then-start-sale concurrently using `parallel`/`sequential`. The first sale is opened by `Services.TransactionService.startSale`, which sends a start command to the backend.

### `Pages.Login`

Built on `UI.Form` with its own `Style` (hints hidden). Sign In is disabled until both fields are non-blank. On success it maps the backend role to a user, pushes `SignedIn`, and navigates to `/#/`.

### `Pages.Admin.Dashboard` and `Pages.Manager.Dashboard`

Each holds a tab cell and one `useRemote` request (the admin snapshot, the manager activity summary) loaded by `onMount` and by a Refresh button. Tabs are drawn with `UI.Tabs.tabBar`. Panels receive `Poll (RemoteData a)` and draw it with `UI.Remote.viewRemote`. The manager Reports panel owns its own request, starting `NotAsked` and fetched on a button press.

### `Pages.TransactionHistory`

```purescript
page :: Nut
```

Placeholder: renders `"Transaction History - Coming Soon"`. No async loading, returns a `Nut` directly.

---

## UI Components

### `UI.Inventory.ItemForm`

```purescript
data FormMode = CreateMode String | EditMode MenuItem

menuItemForm :: FormMode -> Form MenuItem
itemForm     :: UserId -> FormMode -> Nut
renderError  :: String -> Nut
```

`menuItemForm` is one applicative `Form MenuItem` made of four `section` sub-forms (Basic Info, Strain & Lineage, Compliance, Media & Links). Adding a field means adding one line to its section and one name to that section's result record. `itemForm` runs the form and owns only the status message and the submitting flag.

- Initial text comes from the item in `EditMode` and is blank in `CreateMode`. Edit mode parses the stored values, so an item whose stored data fails a rule shows a hint and cannot be saved until fixed.
- Price uses `Parser.cents`. Category and species use the enum `select`. The SKU is a `readOnly` field.
- The submit button is styled disabled while the form is invalid, and the click handler ignores an invalid result. Create calls `form.reset` on success; edit does not.
- Known issue: after a successful create the form keeps the same pre-generated SKU.

### `UI.Inventory.MenuLiveView`

```purescript
createMenuLiveView :: Poll Inventory -> Poll Boolean -> Poll String -> Nut
renderInventory :: LiveViewConfig -> Inventory -> Nut
```

`renderInventory` is the pure rendering function used by the refactored `Pages.LiveView`. It takes a `LiveViewConfig` and an `Inventory`, applies `compareMenuItems` sorting and optional out-of-stock filtering, and renders a grid of `renderItem` cards. Each card shows brand, name, image, category, species, strain, price, description (truncated), quantity, and edit/delete action links.

`createMenuLiveView` is the older poll-based wrapper that manages loading and error state internally -- still available but no longer used by the page.

### `UI.Inventory.DeleteItem`

```purescript
renderDeleteConfirmation :: UserId -> String -> String -> Nut
```

Warning panel with confirm/cancel buttons. Calls `deleteInventory` on confirm, shows success with link back to inventory.

### `UI.Transaction`

The POS screen is six modules under `UI/Transaction/`.

**`Model`** (pure, covered by `test/TransactionModel.purs`)

- `Activity`: `Idle | AddingItem | RemovingItem | AddingPayment | RemovingPayment | Clearing | Finalizing | StartingSale`. Every button is disabled while it is not `Idle`.
- `visibleItems`, `categoriesIn`: inventory filtering by category (`Maybe ItemCategory`) and search text.
- `quantityInCart`, `availableToAdd`, `addBlocker`: client-side hints. The backend reports quantities net of all reservations, so nothing is subtracted on the client, and the backend makes the real decision.
- `totals`, `paidCents`, `remainingCents`: read from the sale.
- `finalizeBlockers`: the reasons the sale cannot be completed. Must agree with the backend's `Domain.SaleRules.finalizeProblems`.

**`CreateTransaction`**

```purescript
createTransaction :: UserId -> RemoteData Inventory -> Sale.SaleTransaction -> Register -> Nut
```

`createTransaction` holds which sale is on screen and rebuilds `saleScreen` when a new sale starts, so filters, the payment form and the message start clean. `saleScreen` owns the four cells described under State Management. Every action goes through one function, `perform`, which sets the `Activity`, runs the command, replaces the sale with the backend's answer, sets the message, and refreshes the inventory.

A status panel lists what blocks the next step: the payment form's errors and `finalizeBlockers`.

**`InventoryPicker`**: category tabs, search, quantity, and the inventory table. The table is rebuilt only when the inventory or a filter changes; per-row cart counts and button states follow Polls.

**`CartView`**: cart lines and the subtotal, tax and total from the sale.

**`PaymentPanel`**: the payment form (`UI.Form`): a `choice` button group for the method, amount, Tendered (visible only for Cash) and Auth Code (visible only for Credit). Lists existing payments with remove buttons.

**`ActionBar`**: Clear Items, remaining balance, Process Payment. Once the sale is closed, Process Payment is replaced by New Sale.

### `UI.Form`, `UI.Remote`, `UI.Tabs`

See [Forms and Parsing](#forms-and-parsing) for `UI.Form` and `UI.Form.Parser`.

**`UI.Remote`**

```purescript
useRemote :: forall a. RemoteData a -> Aff (Either String a) -> (Remote a -> Nut) -> Nut
onMount   :: forall r. Effect Unit -> Poll (Attribute r)
viewRemote :: forall a. RemoteView -> (a -> Nut) -> Poll (RemoteData a) -> Nut
```

`standardView loadingText` and `quietView` are ready-made `RemoteView` values.

**`UI.Tabs`**

`tabBar style tabs selected select` renders one button per tab, labelled with `show`, with `" active"` appended to the selected tab's class.

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
| `getOrInitLocalRegister` | Tries `GET /register/:id`; if not found, creates + opens. **Wrapped by `Main.getOrInitRegisterAff` for use in parallel loading** |
| `initLocalRegister` | Tries GET; if found, re-opens; if not found, creates + opens. **Used by `Main` for pre-init on startup** |
| `createLocalRegister` | Creates a named register at a location |
| `closeLocalRegister` | Closes a register, reports variance |

All functions take callbacks `(Register -> Effect Unit)` and `(String -> Effect Unit)` for success/error. `Main.getOrInitRegisterAff` wraps `getOrInitLocalRegister` into `Aff (Either String Register)` via `makeAff` so it can participate in parallel loading.

### `Services.TransactionService`

- `startSale userId { employeeId, registerId, locationId }` sends a start command (`API.SaleCommand.startSale`). The backend generates the sale id.
- `getSale`, `voidSale`, `refundSale` wrap `API.Sale`.
- `calculateCartTotals`, `calculateTotalPayments`, `paymentsCoversTotal`, `getRemainingBalance`, `emptyCartTotals` are pure helpers that the app no longer uses. Only `test/Cart.purs` imports them.

There is no client-side pricing. The functions that built items and payments in the browser were removed.

### `Services.SaleActions`

What the transaction screen calls. Each function sends one command through `API.SaleCommand` and returns the sale the backend answers with.

| Function | Sends |
|---|---|
| `addItem userId saleId menuItem quantity` | sale id, SKU, quantity |
| `removeItem userId saleId itemId` | item id |
| `addPayment userId saleId input` | method, amount, optional tendered, optional reference |
| `removePayment userId saleId paymentId` | payment id |
| `clear userId saleId` | sale id |
| `finalize userId saleId` | sale id |
| `startNext userId previousSale` | the employee, register and location ids of the finished sale |

### `Services.Cart`

Five pure availability helpers (`getCartQuantityForSku`, `isItemAvailable`, `getAvailableQuantity`, `findUnavailableItems`, `findExistingItem`). The app no longer uses them; only `test/Cart.purs` does. `isItemAvailable` and `getAvailableQuantity` subtract the cart quantity from an inventory quantity the backend has already netted of reservations, so they undercount. The transaction screen uses `UI.Transaction.Model` instead.

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

## Forms and Parsing

### `UI.Form.Parser`

A field parser turns the raw text of an input into a typed value or the message shown beside the field:

```purescript
type Parser a = String -> Either String a
```

There is no separate Boolean validity rule and no second parse at submit. String-returning parsers chain with `>=>`, for example `required >=> alphanumeric >=> maxLen 50`.

| Parser | Result | Notes |
|---|---|---|
| `anyText`, `trimmed` | `String` | never fail |
| `required` | `String` | trims; fails when blank |
| `optional p` | `Maybe a` | blank is `Nothing` |
| `alphanumeric`, `extendedAlphanumeric` | `String` | character-set rules |
| `maxLen n` | `String` | |
| `nonNegativeInt`, `positiveInt` | `Int` | |
| `cents` | `Int` | dollars to integer cents by digit arithmetic; `"19.99"` is `1999` |
| `percentage` | `String` | requires the trailing `%`; value between 0 and 100 |
| `measurementUnit` | `String` | fixed list of units |
| `url` | `String` | `http://` or `https://` |
| `uuid` | `UUID` | |
| `commaList` | `Array String` | never fails; trims entries, drops blanks |

### `UI.Form`

```purescript
newtype Form a   -- Functor, Apply, Applicative. No Monad instance.

type Built a =
  { view   :: Array Nut
  , result :: Poll (V (Array String) a)
  , reset  :: Effect Unit
  }

runForm     :: forall a. Form a -> (Built a -> Nut) -> Nut
runFormWith :: forall a. Style -> Form a -> (Built a -> Nut) -> Nut
isValid     :: forall a. Built a -> Poll Boolean
```

A form is written as one `ado` block. Each field owns one cell holding its raw text. Validity is the field's parser mapped over that cell and is never stored, so it cannot go stale. Errors from all fields accumulate in `result`.

```purescript
credentialsForm :: Form Credentials
credentialsForm = ado
  username <- textAutofocus { label: "Username", placeholder: "Enter username", initial: "" } required
  password' <- password { label: "Password", placeholder: "Enter password", initial: "" } anyPassword
  in { username, password: password' }
```

| Field | Use |
|---|---|
| `text`, `textAutofocus`, `password`, `textArea` | text inputs with a parser |
| `readOnly` | a visible, disabled value that still goes through a parser |
| `select` | dropdown over a `BoundedEnum`; option values are enum indices |
| `choice` | button group over an explicit list, for types that are not `BoundedEnum` |
| `section title form` | groups a sub-form under a heading |
| `visibleWhen poll form` | shows or hides a sub-form; hidden it yields `Nothing` and its errors do not count |
| `dependent form f` | passes the first form's parsed value as a `Poll` to a second form built once |

All CSS classes come from a `Style` record passed at the run site (`defaultStyle`, or a page's own). Setting `hint = "hidden"` hides the per-field hints for forms that report problems elsewhere.

The applicative restriction is deliberate. The set of fields is static, which is what makes `reset` and error accumulation derivable. `dependent` and `visibleWhen` cover fields that depend on another field's value without creating or destroying fields.

### Where each form lives

- `UI.Inventory.ItemForm.menuItemForm`: the item create and edit form
- `Pages.Login.credentialsForm`: sign-in
- `UI.Transaction.PaymentPanel.paymentForm`: payment method, amount, tendered, auth code

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
- `API/` -- HTTP communication only, no business logic
- `Services/` -- effectful business logic, orchestrates API calls
- `Types/` -- pure domain models with serialization instances
- `Config/` -- compile-time constants, no effects
- `UI/` -- presentational components organized by domain
- `Pages/` -- pure renderers that receive `Poll`s of status ADTs (no async loading)
- `Utils/` -- pure helper functions
- `Main.purs` -- owns all async loading, route matching, and fiber lifecycle

### Async loading architecture
- All data fetching is centralized in `Main.purs` using the `run` helper pattern
- Pages are pure functions from `Poll Status -> Nut` with no side effects
- Route changes cancel in-flight loading via `killFiber` on the previous fiber
- `parSequence_` runs multiple loaders in parallel per route
- Callback-based APIs (like `RegisterService`) are wrapped into `Aff` via `makeAff`
- Each route's loader returns a typed status ADT; pages pattern match on `Loading | Ready data | Error msg`
- Pages receive `pure Loading <|> poll` to always start with a loading state

### Known issues / tech debt
- **Dead pure helpers:** `Services.Cart` and the totals helpers in `Services.TransactionService` are used only by `test/Cart.purs`.
- **`DL.load_` on non-loading elements:** `Pages.Stock.Interface` and `UI.Inventory.MenuLiveView` still attach `DL.load_` to elements that never raise `load`. Move them to `UI.Remote.onMount`.
- **Item form:** the SKU is reused after a successful create; the strict `alphanumeric` rule blocks editing stored names that contain punctuation.
- **Transaction screen inventory is refetched, not pushed:** it refreshes after every action and on Refresh; the backend availability stream is not wired to it.
- **No real auth:** The system uses hard-coded dev users. The `X-User-Id` header is the only auth mechanism.
- **Ledger types unused:** `Account`, `LedgerEntry`, `LedgerEntryType`, `AccountType`, `LedgerError` are defined but not consumed by any frontend module.
- **`TransactionHistory` is a stub.**
- **Register ID in localStorage:** `getOrCreateRegisterId` persists across sessions but there's no UI to reset it.
- **`refreshRate` in `LiveViewConfig` is defined but no polling/auto-refresh is implemented.**
- **`createMenuLiveView` is vestigial:** The old poll-based wrapper in `UI.Inventory.MenuLiveView` is still exported but no longer used by `Pages.LiveView`, which calls `renderInventory` directly.

### Error handling pattern
All API calls return `Either String a`. Loading functions in `Main.purs` wrap these into typed status ADTs. Pages pattern match on error variants and delegate to `renderError` for consistent error display. `attempt` from `Effect.Aff` is used to catch exceptions from `fetch` / `fromJSON`.

### Serialization conventions
- PureScript `Maybe a` → JSON `Nullable a` (via `toNullable`) for writes
- Backend sends `null` or absent fields → `ReadForeign` instances handle both
- Enum types accept both PascalCase (`"Created"`) and SCREAMING_SNAKE (`"CREATED"`) on read, emit PascalCase on write
- `UUID` round-trips as plain strings
- `Discrete USD` (cents) round-trips as `Int`
- `DiscreteMoney USD` uses Yoga.JSON's default `ReadForeign`/`WriteForeign` for the `Data.Finance.Money.Extended` wrapper
