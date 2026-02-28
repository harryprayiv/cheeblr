## Module Dependency Graph

### Layer 1: Pure Types (no internal dependencies)

**`Types.UUID`** — depends on nothing internal. Clean leaf node.

**`Config.Network`** — depends on nothing. Clean leaf node.

**`Config.Entity`** — depends only on `Types.UUID`. Clean.

### Layer 2: Domain Types

**`Types.Auth`** — depends on `Types.UUID`. Clean.

**`Types.Formatting`** — depends on `Types.UUID`. Clean, but it's doing too much (validation rules live here alongside form field type definitions).

**`Types.Inventory`** — depends on `Types.UUID`. Clean.

**`Types.Transaction`** — depends on `Types.UUID`, `Data.Finance.*`. Clean.

**`Types.Register`** — depends on `Types.UUID`, `Data.Finance.*`. Clean.

### Layer 3: Config

**`Config.Auth`** — depends on `Types.Auth`, `Types.UUID`. Clean.

**`Config.LiveView`** — depends on `Config.Network`. Clean.

**`Config.InventoryFields`** — depends on `Types.Formatting`, `Types.Inventory`, `Utils.Formatting`, `Utils.Validation`. **First problem node** — a config module reaching into both utils.

### Layer 4: Services & Utils — HERE IS THE MESS

**`Utils.Validation`** — depends on `Types.Formatting`, `Types.Inventory`, `Types.UUID`, `Utils.Formatting`. Fine conceptually but it contains both generic validation primitives (`nonEmpty`, `alphanumeric`) AND domain-specific validators (`validateMenuItem`, `validateStrainLineage`). These should be separated.

**`Utils.Formatting`** — depends on `Config.LiveView`, `Types.Inventory`. A utils module depending on a config module and a domain type — that's an inversion.

**`Utils.Money`** — depends on `Data.Finance.*`. Clean.

**`Services.AuthService`** — depends on `Config.Auth`, `Types.Auth`, `Types.UUID`. Reasonably clean.

**`API.Request`** — depends on `Config.Network`, `Services.AuthService`. Clean.

**`API.Inventory`** — depends on `API.Request`, `Services.AuthService`, `Types.Inventory`, `Config.LiveView`. Clean.

**`API.Transaction`** — depends on `API.Request`, `Services.AuthService`, `Types.Register`, `Types.Transaction`, `Types.UUID`. Clean.

Now here are the two disaster modules:

---

### **`Services.TransactionService`** — Medium complexity, mostly fine

Depends on: `API.Transaction`, `Types.Register`, `Types.Transaction`, `Types.UUID`, `Services.AuthService`, `Data.Finance.*`

This one is actually reasonably scoped. It wraps API calls and provides `calculateCartTotals`, `startTransaction`, payment helpers. The main issue is that `calculateCartTotals` is duplicated (also in `RegisterService`).

### **`Services.RegisterService`** — THE PROBLEM MODULE

This is your God module. Let me list what it actually does:

1. **Register lifecycle** — `initLocalRegister`, `getOrInitLocalRegister`, `createLocalRegister`, `closeLocalRegister` (localStorage + API calls + state callbacks)
2. **Price formatting** — `formatPrice`, `formatDiscretePrice` (re-exports from `Utils.Money`)
3. **Cart quantity logic** — `getCartQuantityForSku`, `isItemAvailable`, `getAvailableQuantity`, `findUnavailableItems`
4. **Cart mutation (local/offline)** — `addItemToTransaction`, `removeItemFromTransaction`, `findExistingItem`
5. **Cart mutation (API-backed)** — `addItemToCart`, `removeItemFromCart`
6. **Cart totals** — `emptyCartTotals`, `calculateCartTotals` (DUPLICATED from TransactionService)
7. **Inventory queries** — `findUnavailableItems`

Its dependency list is enormous: `API.Transaction`, `Services.TransactionService`, `Types.Register`, `Types.Transaction`, `Types.Inventory`, `Types.UUID`, `Data.Finance.*`, `Utils.Money`, `Services.AuthService`, plus browser APIs (`Web.HTML`, `Web.Storage`).

And then both `UI.Transaction.CreateTransaction` and `UI.Transaction.LiveCart` import from it heavily, but they import **different subsets** and use the cart functions with different signatures (one is API-backed, one is local-only).

---

## The Actual Dependency Tangle Visualized

```
UI.Transaction.CreateTransaction
  ├── Services.RegisterService  (addItemToCart, removeItemFromCart, 
  │   │                          emptyCartTotals, formatDiscretePrice)
  │   ├── Services.TransactionService (createTransactionItem, 
  │   │   │                            removeTransactionItem, calculateCartTotals)
  │   │   └── API.Transaction
  │   ├── API.Transaction (directly too!)
  │   ├── Types.Inventory
  │   ├── Types.Transaction
  │   └── Utils.Money
  ├── Services.TransactionService (ALSO directly imported for 
  │                                 getRemainingBalance, paymentsCoversTotal,
  │                                 addPayment, finalizeTransaction, etc.)
  └── Types.Inventory

UI.Transaction.LiveCart
  ├── Services.RegisterService  (addItemToTransaction, removeItemFromTransaction,
  │   │                          calculateCartTotals, emptyCartTotals, 
  │   │                          formatDiscretePrice, formatPrice)
  │   └── (same tree as above, but uses LOCAL cart functions, not API-backed)
  └── Types.Inventory
```

The critical insight: **`RegisterService` is a bag of unrelated concerns that grew organically**. `CreateTransaction` uses the API-backed cart path. `LiveCart` uses the local cart path. Both go through the same module but touch completely different functions, which internally have completely different dependency requirements.

---

## Proposed Clean Architecture

Here's how I'd separate things. Seven focused modules replacing the current tangle:

```
Services/
  AuthService.purs          ← stays as-is (already clean)
  RegisterService.purs      ← ONLY register lifecycle (init, open, close)
  TransactionService.purs   ← ONLY transaction API operations

Cart/
  CartTypes.purs            ← CartTotals, cart-related type aliases
  CartCalculations.purs     ← calculateCartTotals, emptyCartTotals (ONE copy)
  CartInventory.purs        ← getCartQuantityForSku, isItemAvailable, 
                               getAvailableQuantity, findUnavailableItems,
                               findExistingItem
  CartLocal.purs            ← addItemToTransaction, removeItemFromTransaction
                               (pure/local cart operations, no API)
  CartAPI.purs              ← addItemToCart, removeItemFromCart
                               (API-backed cart operations, depends on 
                                TransactionService)

Utils/
  Validation/
    Rules.purs              ← nonEmpty, alphanumeric, percentage, etc.
                               (ZERO domain imports)
    MenuItem.purs           ← validateMenuItem, validateStrainLineage
                               (domain-specific, imports Types.Inventory)
  Formatting/
    Money.purs              ← formatCentsToDollars, formatDiscretePrice, etc.
                               (merge current Utils.Money + price formatters)
    Text.purs               ← summarizeLongText, parseCommaList, ensureInt, etc.
    Sort.purs               ← compareMenuItems (currently in Utils.Formatting,
                               depends on Config.LiveView — that's fine here)
```

### What this achieves

**`RegisterService` shrinks from ~300 lines / 7 concerns to ~120 lines / 1 concern** (register lifecycle only). It keeps localStorage interaction and the init/open/close API flow.

**Cart operations get a clean dependency DAG:**
```
CartTypes          (leaf — just type aliases)
CartCalculations   (depends on CartTypes, Types.Transaction)
CartInventory      (depends on CartTypes, Types.Inventory, Types.Transaction)
CartLocal          (depends on CartCalculations, CartInventory, Types.Transaction)
CartAPI            (depends on CartCalculations, CartInventory, 
                    TransactionService, Services.AuthService)
```

**`Utils.Formatting` stops depending on `Config.LiveView`** — the sort comparison function moves to its own module or into a `Sort` utils module that explicitly takes config.

**`Utils.Validation` splits cleanly** — generic rules have zero domain knowledge, domain validators import the types they validate.

**Duplication dies** — `calculateCartTotals` exists in ONE place (`CartCalculations`), not two.

---

## The Migration Path

The safe way to do this without breaking anything:

1. **Create `Cart/CartTypes.purs`** — just move `CartTotals` re-export and `emptyCartTotals` there. Update imports in consuming modules. Compile, test.

2. **Create `Cart/CartCalculations.purs`** — move `calculateCartTotals` there (delete the duplicate). Update imports. Compile, test.

3. **Create `Cart/CartInventory.purs`** — move the pure inventory query functions (`getCartQuantityForSku`, `isItemAvailable`, etc.). Compile, test.

4. **Create `Cart/CartLocal.purs`** — move `addItemToTransaction`, `removeItemFromTransaction`. Compile, test.

5. **Create `Cart/CartAPI.purs`** — move `addItemToCart`, `removeItemFromCart`. Compile, test.

6. **Strip `RegisterService`** down to just register lifecycle. Compile, test.

7. **Split `Utils.Validation`** into `Rules` + `MenuItem` validator. Compile, test.

8. **Split `Utils.Formatting`** into `Money`, `Text`, `Sort`. Compile, test.

Each step is a pure mechanical refactor — move function, update imports, verify compilation. No logic changes. No behavior changes. The key lesson from yesterday: never change logic and structure simultaneously.

___

Newest Comparison to Deku Real World

Looking at both codebases, here's what stands out. The realworld app has a clear architectural pattern that your cheeblr app has drifted from as it's grown. Let me break down the key differences and a concrete refactoring plan.

## Core Architectural Gaps

**2. Auth threading is heavy**

You pass `Ref AuthContext` through literally everything. The realworld app passes `Poll AuthState` and extracts tokens at the call site. Your approach forces every function signature to carry the ref, whereas polls compose naturally.

**4. No parallel loading**

The realworld app uses `parSequence_` and `parallel`/`sequential` to load multiple resources concurrently. Your route handlers do sequential fetches with manual error handling at each step.

## Refactoring Steps Left

### Phase 2: Replace Ref AuthContext with Poll AuthState

**Goal:** Auth flows through polls, not refs.

- Define an `AuthState` ADT similar to the realworld app (SignedIn user | SignedOut)
- Create a top-level `Poll AuthState` in Main
- API functions take a token string, not a ref — the caller extracts the token from the poll at the call site
- This eliminates the ref threading and makes components testable in isolation

### Phase 5: Adopt the `run` + parallel loading pattern

**Goal:** Clean async data loading.

Steal the realworld app's `run` helper directly:

```purescript
run :: forall a r. Aff a -> { push :: a -> Effect Unit | r } -> Aff Unit
run aff { push } = aff >>= liftEffect <<< push
```

Use `parSequence_` for routes that need multiple resources (CreateTransaction needs both inventory and a register).

## Suggested Priority Order

5. **Phase 2** (auth polls) — most invasive change, touches every API call
6. **Phase 5** (parallel loading) — polish, do last

The key insight from the realworld app isn't any single technique — it's that components are self-contained units that receive data via polls and handle their own lifecycle. Your current architecture has Main orchestrating everything, which is why it's grown unwieldy. Push the logic down into the pages/components and Main becomes trivially simple.

