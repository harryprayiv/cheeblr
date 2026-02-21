Let me trace through this carefully. I'll map out the actual dependency graph and data flow, layer by layer.

---

## Layer 1: Types (the foundation)

These are relatively clean, as you noted. The key types and where they live:

**`Types.UUID`** — leaf dependency, no internal imports. Everything depends on this.

**`Types.Inventory`** — depends on `Types.UUID`. Defines `MenuItem`, `Inventory`, `StrainLineage`, `ItemCategory`, `Species`, plus the form input type aliases (`MenuItemFormInput`, `StrainLineageFormInput`). Also contains `InventoryResponse` (the API response wrapper). This module is doing double duty: it's both your domain model AND your serialization layer (all the `ReadForeign`/`WriteForeign` instances live here).

**`Types.Auth`** — depends on `Types.UUID`. Defines `UserRole`, `AuthenticatedUser`, `UserCapabilities`, and the capability constructors per role (`capabilitiesForRole`). This is self-contained and clean.

**`Types.Transaction`** — depends on `Types.UUID` and `Data.Finance.Money.Extended`. This is your heaviest type module. It defines `Transaction`, `TransactionItem`, `PaymentTransaction`, `PaymentMethod`, `DiscountType`, `TaxCategory`, `TaxRecord`, `Account`, `LedgerEntry`, plus all serialization. The ledger/accounting types (`Account`, `LedgerEntry`, `LedgerEntryType`, `AccountType`) are defined here but appear to be unused in the actual application — they're aspirational types that never got wired up.

**`Types.Common`** — depends on `Types.Inventory` and `Types.UUID`. This is where things start getting tangled. It defines:
- `ValidationRule` newtype (used everywhere in forms)
- `FieldConfig`, `DropdownConfig`, `TextAreaConfig` (form configuration types)
- `FormValue` and `FieldValidator` typeclasses with instances for `ItemCategory`, `Species`, `UUID`, etc.

**The problem with `Types.Common`**: It imports `Types.Inventory` to get `ItemCategory` and `Species` for the `FormValue`/`FieldValidator` instances. This means your "common" types module has a hard dependency on your domain types. If you wanted to make this generic across retail domains, `Types.Common` would need to lose those instances or they'd need to move to an orphan instance module or be co-located with the domain types.

**`Types.Register`** — depends on `Types.UUID` and `Data.Finance.Money`. Defines `Register`, `CartTotals`, `OpenRegisterRequest`, `CloseRegisterRequest`, `CloseRegisterResult`. Clean and focused.

---

## Layer 2: Config

**`Config.Network`** — leaf module, no internal dependencies. Just `apiBaseUrl` and `appOrigin`.

**`Config.Entity`** — depends on `Types.UUID`. Just dummy UUIDs for dev/testing. Used in `Main`.

**`Config.Auth`** — depends on `Types.Auth` and `Types.UUID`. Defines `DevUser` and hardcoded dev users. Provides `toAuthenticatedUser`, `devUserCapabilities`, `findDevUserById`. This is your dev-mode authentication stub.

**`Config.LiveView`** — depends on `Config.Network`. Defines `QueryMode`, `FetchConfig`, `LiveViewConfig`, sort field/order types. Used to configure inventory fetching and display.

**`Config.InventoryFields`** — depends on `Types.Common`, `Types.Inventory`, `Utils.Formatting`, `Utils.Validation`. This is a **massive** module of hand-written field configuration functions (one per form field: `nameConfig`, `brandConfig`, `priceConfig`, etc.). Each returns a `FieldConfig` record. This is the module your codegen was supposed to replace. It's entirely dispensary-specific — every field name, label, placeholder, and validation rule is hardcoded here.

---

## Layer 3: Services (this is where the complexity explodes)

### `Services.AuthService`
Depends on: `Config.Auth`, `Types.Auth`, `Types.UUID`

This is your auth context manager. It wraps a `Ref AuthContext` and exposes:
- `newAuthRef` — creates the ref
- `getCurrentUser`, `getCurrentUserId`, `setCurrentUser`, etc.
- A large number of capability-checking functions (`canViewInventory`, `canCreateItem`, `canEditItem`...) — 15+ individual functions that all do the same thing with different field accessors.

**Structural issue**: The auth ref (`Ref AuthContext`) gets threaded through almost everything as the first argument. It's effectively a global that's passed explicitly. Every API call, every service call, every UI component takes `Ref AuthContext` as its first parameter.

### `Services.RegisterService`
Depends on: `API.Transaction`, `Services.AuthService`, `Types.Register`, `Types.UUID`, `Utils.UUID`, `Web.Storage`

This manages register lifecycle using `localStorage` for persistence of register IDs across page reloads. It has three main operations:

- `initLocalRegister` — gets or creates register ID from localStorage, tries to GET the register from the API, creates + opens it if not found
- `getOrInitLocalRegister` — same but doesn't re-open if already exists
- `createLocalRegister` / `closeLocalRegister`

**Structural issue**: `initLocalRegister` and `getOrInitLocalRegister` are almost identical functions with slightly different control flow. They both contain the same create-then-open pattern duplicated inline. Both take success/error callbacks (`Register -> Effect Unit` and `String -> Effect Unit`) rather than returning `Aff (Either String Register)`, which makes them hard to compose.

### `Services.TransactionService`
Depends on: `API.Transaction`, `Services.AuthService`, `Types.Register`, `Types.Transaction`, `Types.UUID`, `Utils.UUID`

This is your largest service module. It wraps `API.Transaction` calls with logging and provides:

- `startTransaction` — creates a new transaction and sends it to the API
- `createTransactionItem` — builds a `TransactionItem` with tax calculation and sends to API
- `addTransactionItem`, `removeTransactionItem` — thin API wrappers
- `clearTransaction`, `voidTransaction`, `finalizeTransaction` — thin API wrappers
- `addPayment`, `removePaymentTransaction` — payment management
- `removeItemFromCart` — takes callbacks for state updates (mixes service logic with UI state management)
- `calculateCartTotals` — pure calculation
- `calculateTotalPayments`, `paymentsCoversTotal`, `getRemainingBalance` — pure calculations
- `emptyCartTotals` — constant

**Structural issue**: This module mixes three different concerns:
1. API call wrappers (thin pass-throughs to `API.Transaction`)
2. Pure business logic (tax calculation, total calculation, payment validation)
3. UI state management (`removeItemFromCart` takes `setItems`, `setTotals`, `setCheckingInventory` callbacks)

The tax calculation in `createTransactionItem` hardcodes an 8% sales tax rate.

---

## Layer 4: API

### `API.Request`
Depends on: `Config.Network`, `Services.AuthService`

This is your HTTP client layer. It provides typed request functions (`authGet`, `authPost`, `authPut`, `authDelete`, etc.) that:
1. Get the current user ID from the auth ref
2. Make a fetch request with auth headers
3. Deserialize the response via `ReadForeign`
4. Wrap errors in `Either String a`

There are several variants: `authPostChecked` (checks status codes), `authPostEmpty` (no body), `authPostUnit` (ignores response), `authDeleteUnit`. These exist because the Haskell backend has inconsistent response patterns across endpoints.

### `API.Inventory`
Depends on: `API.Request`, `Services.AuthService`, `Types.Inventory`, `Config.LiveView`

CRUD for inventory plus the dual-mode fetch (JSON file vs HTTP). Clean and focused.

### `API.Transaction`
Depends on: `API.Request`, `Services.AuthService`, `Types.Register`, `Types.Transaction`, `Types.UUID`

Register and transaction CRUD. Also clean and focused. Note that `parseErrorResponse` lives here — it tries to parse error JSON from the backend, which is a presentation concern leaking into the API layer.

---

## Layer 5: Utils

### `Utils.UUID`
Depends on: `Types.UUID`, `Utils.Formatting`

Client-side UUID generation. Depends on `Utils.Formatting` just for `padStart`.

### `Utils.Formatting`
Depends on: `Config.LiveView`, `Types.Inventory`, `Types.UUID`

This is a grab-bag module. It contains:
- UUID display (`uuidToString`)
- Item lookup (`findItemNameBySku`, `findItemBySku`, `getItemName`)
- CSS class generation (`generateClassName`, `toClassName`)
- String formatting (`ensureNumber`, `ensureInt`, `padStart`, `parseCommaList`, `formatDollarAmount`)
- Money formatting (`formatCentsToDisplayDollars`, `formatCentsToDollars`, `formatCentsToDecimal`)
- Enum utilities (`getAllEnumValues`)
- Inventory sorting (`compareMenuItems`)
- Text summarization (`summarizeLongText`)

**Structural issue**: This module depends on `Types.Inventory` and `Config.LiveView`, which means your "utility" module has domain knowledge baked in. `compareMenuItems` knows about `StrainLineage`. `generateClassName` knows about `ItemCategory` and `Species`. `findItemNameBySku` operates on `Inventory`. These should live closer to their domain.

### `Utils.Validation`
Depends on: `Types.Common`, `Types.Inventory`, `Types.UUID`, `Utils.Formatting`

Two distinct halves:
1. **Generic validation rules** — `nonEmpty`, `alphanumeric`, `percentage`, `dollarAmount`, `validUrl`, `maxLength`, `allOf`, `anyOf`, etc. These operate on `ValidationRule` (which is just `String -> Boolean`) and are domain-agnostic.
2. **Domain-specific validation** — `validateMenuItem`, `validateStrainLineage`, `validateCategory`, `validateSpecies`. These use the `V (Array String)` applicative for accumulating errors and are entirely dispensary-specific.

Also contains preset bundles (`requiredText`, `percentageField`, `moneyField`, etc.) that combine validation + error messages.

### `Utils.Money`
Depends on: `Data.Finance.Money`, `Data.Finance.Money.Extended`

Clean utility module for money formatting and conversion. No domain dependencies.

### `Utils.CartUtils`
Depends on: `Services.AuthService`, `Services.TransactionService`, `Types.Inventory`, `Types.Transaction`, `Types.Register`, `Types.UUID`, `Utils.Money`, `Utils.UUID`

**This is where the dependency graph gets really bad.** This module contains:

1. **Pure functions**: `formatPrice`, `formatDiscretePrice`, `getCartQuantityForSku`, `isItemAvailable`, `getAvailableQuantity`, `findUnavailableItems`, `calculateCartTotals`, `emptyCartTotals`, `removeItemFromTransaction`, `findExistingItem`

2. **Effectful cart operations with API calls**: `addItemToCart` (calls `TransactionService.createTransactionItem`), `removeItemFromCart` (calls `TransactionService.removeTransactionItem`)

3. **Effectful cart operations without API calls**: `addItemToTransaction` (local-only, generates UUIDs, builds transaction items with hardcoded 15% tax)

So you have **three different "add to cart" implementations** across the codebase:
- `Utils.CartUtils.addItemToCart` — calls the API, used by `CreateTransaction`
- `Utils.CartUtils.addItemToTransaction` — local only with 15% tax, used by `LiveCart`

And **three different "calculate totals" implementations**:
- `Utils.CartUtils.calculateCartTotals`
- `Services.TransactionService.calculateCartTotals`
- (They're actually identical code, duplicated)

And **two different "remove from cart" implementations**:
- `Utils.CartUtils.removeItemFromCart` — calls API
- `Utils.CartUtils.removeItemFromTransaction` — local only
- `Services.TransactionService.removeItemFromCart` — calls API (different callback signature)

### `Utils.Storage`
Depends on: `Web.HTML`, `Web.Storage`

Clean localStorage wrapper. Only used by `Services.RegisterService` (which actually imports `Web.Storage` directly instead of using this module).

---

## Layer 6: UI Components

### `UI.Components.Form`
Depends on: `Types.Common`, `Utils.Formatting`, `Utils.Validation`

Generic form input constructors: `makeTextField`, `makeDropdown`, `makeDescriptionField`, `makePasswordField`, `makeTextArea`, `makeEnumDropdown`. These take a config record + state setter callbacks and return `Nut`.

Has a `formField` element wrapper and `formFieldValue`/`formFieldValidation` that use `attributeAtYourOwnRisk` for custom attributes — these appear unused.

Every field component follows the same pattern: render an input element, attach `keyup`/`input` listeners that call `setValue` and `setValid`, render a conditional error message. The Description field gets special-cased inside `makeTextField` with an `if config.label == "Description"` check, which is a code smell.

### `UI.Components.AuthGuard`
Depends on: `Types.Auth`

Capability-gated rendering using `guard` from Deku. Provides `whenCapable`, `whenCanViewInventory`, `whenCanEditItem`, etc. Also `whenRoleAtLeast`, `withFallback`, `disabledUnless`. **These guards are defined but never actually used in any UI component** — there's no authorization enforcement in the current UI.

### `UI.Components.UserSelector`
Depends on: `Config.Auth`, `Services.AuthService`, `Types.Auth`

Dev-mode user switcher widget. Also appears unused — it's defined but never mounted in `Main`.

---

## Layer 7: UI Pages

### `UI.Inventory.MenuLiveView`
Depends on: `Config.LiveView`, `Types.Inventory`, `Utils.Formatting`

Read-only inventory display. Takes `Poll Inventory`, `Poll Boolean` (loading), `Poll String` (error). Renders filtered/sorted inventory cards. Relatively clean — it's purely presentational.

### `UI.Inventory.CreateItem`
Depends on: `API.Inventory`, `Config.InventoryFields`, `Services.AuthService`, `Types.Inventory`, `UI.Components.Form`, `Utils.Formatting`, `Utils.UUID`, `Utils.Validation`

The create form. This is where state management complexity is most visible. It creates **23 separate `useState` hooks for field values** and **23 separate `useState` hooks for validation states**, totaling 46 state atoms. Then `isFormValid` is an applicative expression that combines all 23 validation polls.

The submit handler collects all 23 values via applicative, builds a `MenuItemFormInput`, runs `validateMenuItem`, then calls `writeInventory`. The reset function manually resets all 46 state atoms.

### `UI.Inventory.EditItem`
Depends on: same as CreateItem

Almost identical to CreateItem but pre-populates from an existing `MenuItem`. Same 46 state atoms pattern. The two modules share no code despite being ~90% identical.

### `UI.Inventory.DeleteItem`
Depends on: `API.Inventory`, `Services.AuthService`, `Types.Inventory`

Simple confirmation dialog. Clean.

### `UI.Transaction.LiveCart`
Depends on: `Types.Inventory`, `Types.Transaction`, `Types.Register`, `Utils.CartUtils`, `Utils.Formatting`

Local-only cart (no API calls for item management). Uses `addItemToTransaction` from `CartUtils` which does **local-only** tax calculation at 15%. Has its own `addItemToCart` and `removeItemFromCart` functions defined in a `where` clause that delegate to `CartUtils`.

### `UI.Transaction.CreateTransaction`
Depends on: `Services.AuthService`, `Services.TransactionService`, `Types.Inventory`, `Types.Transaction`, `Types.Register`, `Utils.CartUtils`, `Utils.Formatting`

The full POS transaction page. Uses `addItemToCart` from `CartUtils` which calls the **API** for item management. Has payment processing, finalization, void support. This is the most complex UI component — it manages cart items, payments, totals, processing state, inventory errors, search/filter state, and payment form fields all in one component.

**Key difference from LiveCart**: `CreateTransaction` sends every cart add/remove to the backend (inventory reservation), while `LiveCart` is purely client-side. They share the same visual layout but completely different data flow.

---

## The Main Module

`Main` is the router. It pattern-matches on `Route` and for each route:
1. Sets up any needed state polls
2. Fetches data if needed
3. Pushes a `Tuple Route Nut` to `currentRoute`

Register initialization happens at startup via `RegisterService.initLocalRegister`. Transaction creation happens when navigating to `CreateTransaction` via a callback-heavy flow that chains register initialization → transaction creation → inventory fetch.

---

## Summary of the core structural problems

**Duplicated business logic**: Cart totals calculation exists in 2 places (identical). Tax calculation exists in 3 places (different rates). Add-to-cart exists in 3 places (different behaviors). Remove-from-cart exists in 3 places.

**Mixed concerns in services**: `TransactionService` and `CartUtils` both mix pure business logic with effectful API calls with UI state management callbacks. There's no clear boundary between "compute the new state" and "persist it" and "update the UI."

**Callback-heavy state management**: Both `RegisterService` and the cart operations take success/error callbacks instead of returning values. This makes composition difficult and leads to deeply nested callback chains in `Main`.

**Unused code**:`UI.Components.AuthGuard` (defined but unused), `UI.Components.UserSelector` (defined but unused), ledger types in `Types.Transaction`.

**Domain specificity in generic layers**: `Utils.Formatting`, `Utils.Validation`, `Types.Common`, and `Config.InventoryFields` all have hard dependencies on dispensary-specific types (`ItemCategory`, `Species`, `StrainLineage`).

**Form boilerplate**: CreateItem and EditItem each maintain 46 state atoms with no shared abstraction. `Config.InventoryFields` has 20+ nearly identical config functions.

**Inconsistent API patterns**: The `API.Request` module has 8 different request variants because the backend endpoints have inconsistent response shapes. `authPost` vs `authPostChecked` vs `authPostEmpty` vs `authPostUnit` reflects backend inconsistency leaking into the frontend.