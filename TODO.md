This is a great approach — understand the full picture before touching anything. Let me trace every dependency edge in the codebase and identify the tangles.

## Dependency Graph Analysis

Here's the full module dependency map, organized by layer:

### Layer 0: Pure Types (leaf nodes)

```
Types.UUID          → (nothing internal)
Types.Auth          → Types.UUID
Types.Register      → Types.UUID
Types.Inventory     → Types.UUID
Types.Transaction   → Types.UUID, Types.Inventory (none actually — just UUID)
Types.Formatting    → Types.Inventory, Types.UUID  ← PROBLEM
```

**Issue #1**: `Types.Formatting` imports `Types.Inventory` (specifically `ItemCategory`, `Species`) for the `FormValue` and `FieldValidator` instances. This means your "formatting types" are coupled to your domain types. In a generalized retail system, `Types.Formatting` shouldn't know about cannabis species.

### Layer 1: Config

```
Config.Network      → (nothing internal)
Config.Entity       → Types.UUID
Config.Auth         → Types.Auth, Types.UUID
Config.LiveView     → Config.Network
Config.InventoryFields → Types.Formatting, Types.Inventory,
                         Utils.Formatting, Utils.Validation  ← PROBLEM
```

**Issue #2**: `Config.InventoryFields` reaches down into `Utils.Formatting` and `Utils.Validation`. Config is supposed to be declarative data, but it's importing runtime validation functions and formatting utilities. This creates a config → utils → types cycle in terms of conceptual layers.

### Layer 2: Services & API

```
API.Request         → Config.Network, Services.AuthService
API.Inventory       → API.Request, Services.AuthService,
                       Types.Inventory, Config.LiveView
API.Transaction     → API.Request, Services.AuthService,
                       Types.Register, Types.Transaction, Types.UUID

Services.AuthService    → Config.Auth, Types.Auth, Types.UUID
Services.RegisterService → API.Transaction, Services.AuthService,
                           Types.Register, Types.UUID
Services.TransactionService → API.Transaction, Services.AuthService,
                               Types.Register, Types.Transaction, Types.UUID
```

This layer is actually **mostly okay** structurally. The API modules depend on Request + AuthService, services depend on API + Auth. The directional flow makes sense.

### Layer 3: Utils (HERE'S THE MESS)

```
Utils.Storage       → (nothing internal)
Utils.Money         → (nothing internal, just finance libs)
Utils.Formatting    → Config.LiveView, Types.Inventory
Utils.Validation    → Types.Formatting, Types.Inventory,
                       Types.UUID, Utils.Formatting
Utils.CartUtils     → Services.AuthService, Services.TransactionService,
                       Types.Register, Types.Transaction,
                       Types.Inventory, Types.UUID, Utils.Money
```

**Issue #3 (the big one)**: `Utils.CartUtils` is a Frankenstein module. It contains:

1. **Pure formatting** (`formatPrice`, `formatDiscretePrice`) — should be in Utils.Money
2. **Pure cart queries** (`getCartQuantityForSku`, `isItemAvailable`, `getAvailableQuantity`, `findUnavailableItems`, `findExistingItem`) — pure functions, good
3. **Pure cart math** (`calculateCartTotals`, `emptyCartTotals`) — duplicated from Services.TransactionService
4. **Local-only cart mutations** (`addItemToTransaction`, `removeItemFromTransaction`) — no API calls, used by LiveCart
5. **API-backed cart mutations** (`addItemToCart`, `removeItemFromCart`) — calls TransactionService, used by CreateTransaction

This module is simultaneously a utility, a service, and a duplicate of another service. It imports `Services.TransactionService` and also re-implements some of its functions.

### Layer 4: UI Components

```
UI.Components.Form        → Types.Formatting, Utils.Formatting, Utils.Validation
UI.Components.AuthGuard   → Types.Auth
UI.Components.UserSelector → Config.Auth, Services.AuthService, Types.Auth
```

### Layer 5: UI Pages

```
UI.Inventory.CreateItem → API.Inventory, Config.InventoryFields,
                           Services.AuthService, Types.Inventory,
                           UI.Components.Form, Utils.Formatting,
                           Utils.Validation, Types.UUID

UI.Inventory.EditItem   → (same as CreateItem essentially)

UI.Inventory.DeleteItem → API.Inventory, Services.AuthService, Types.Inventory

UI.Inventory.MenuLiveView → Config.LiveView, Types.Inventory, Utils.Formatting

UI.Transaction.CreateTransaction → Services.AuthService,
                                    Services.TransactionService,
                                    Types.Inventory, Types.Register,
                                    Types.Transaction, Utils.CartUtils,
                                    Utils.Formatting

UI.Transaction.LiveCart → Types.Inventory, Types.Transaction,
                           Utils.CartUtils, Utils.Formatting
```

**Issue #4**: `CreateTransaction.purs` has its own inline `addItemToCart` function (~40 lines) that is nearly identical to `Utils.CartUtils.addItemToCart` but subtly different. Same name, different behavior. And the page ALSO imports `Utils.CartUtils.removeItemFromCart`. So a single page uses both a local definition and an import for the same conceptual operation.

**Issue #5**: `LiveCart` and `CreateTransaction` are two different implementations of essentially the same UI pattern (browse inventory → add to cart → see totals) but with different backing stores (local state vs API-persisted transactions). They share no component code.

---

## The Core Structural Problems

Here's what I see as the real tangles, ranked by severity:

**1. Cart logic is split across 3 locations with duplication:**

| Function | `Services.TransactionService` | `Utils.CartUtils` | `UI.Transaction.CreateTransaction` (inline) |
|---|---|---|---|
| `calculateCartTotals` | ✓ | ✓ (copy) | — |
| `emptyCartTotals` | ✓ | ✓ (copy) | — |
| `removeItemFromCart` | ✓ (API-backed) | ✓ (API-backed, different sig) | — |
| `addItemToCart` | — | ✓ (API-backed) | ✓ (inline, API-backed) |
| `addItemToTransaction` | — | ✓ (local-only) | — |

Three places, two of which call the API, one that doesn't, all doing cart math.

**2. `Types.Formatting` is a junk drawer:**
It defines `ValidationRule`, `FieldConfig`, `DropdownConfig`, `FormValue`, `FieldValidator`, plus `HTMLFormField` phantom types, PLUS domain-specific instances for `ItemCategory` and `Species`. This is simultaneously a form framework module and a domain module.

**3. Two separate cart paradigms with no shared abstraction:**
`LiveCart` uses fully local state (no persistence, direct array manipulation). `CreateTransaction` uses API-persisted state (every add/remove hits the server). Both render nearly identical UIs. There's no shared cart component or cart state interface.

**4. Config.InventoryFields knows about validation and formatting logic:**
This means you can't change validation rules without potentially affecting config, and config changes might break if validation utils change.

---

## Proposed Clean Layering

If you want my recommendation for how these should be organized (without writing code yet):

```
Layer 0: Types.*              — Pure data types, newtypes, instances only
Layer 1: Config.*             — Static configuration data only
Layer 2: Validation.*         — Pure validation rules (no domain knowledge)
Layer 3: Domain.Validation.*  — Domain-specific validation (MenuItem, etc.)
Layer 4: API.*                — HTTP communication only
Layer 5: Services.*           — Business logic orchestrating API calls
Layer 6: Cart.*               — Unified cart abstraction (pure + effectful)
Layer 7: UI.Components.*      — Reusable UI primitives
Layer 8: UI.Pages.*           — Page-level compositions
```

The key moves would be:

- Extract `ValidationRule`/`FieldConfig`/`DropdownConfig` out of `Types.Formatting` into their own module with zero domain imports
- Move all `ItemCategory`/`Species` `FormValue` instances to a domain-specific module
- Consolidate all cart logic into one `Cart` module with a clean separation between pure cart math and effectful cart operations
- Kill the duplication between `TransactionService` cart functions and `CartUtils`
- Extract a shared cart UI component that both `LiveCart` and `CreateTransaction` can use with different backing stores