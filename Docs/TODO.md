# To Do

Status as of 2026-10-04. Items are ordered by priority within each section.

## Correctness

1. **Make add-item atomic.** `DB.Transaction.addTransactionItem` runs its availability check, item insert, reservation insert and totals update as separate statements with no row lock. Two registers can both take the last unit. Move it into one SQL transaction with `SELECT ... FOR UPDATE` on the menu item. `finalizeTransaction` has the same shape.
2. **Make the in-memory `TransactionDb` interpreter maintain sale totals.** The PostgreSQL interpreter does. Then let the service specs assert totals. Any behaviour that exists in only one interpreter is a place a production bug can hide.
3. **Supply real tax rules.** The `tax_rule` table ships with one placeholder 8% rule. Add an endpoint or admin screen for editing rules. Extend `Domain.Pricing.TaxRule` if a real rule needs a tax charged on another tax, or discounts in the taxable base.
4. **Decide whether clearing a sale cancels its stock pulls.** Removing a single item cancels them; clear does not.
5. **Reservation expiry.** Reservations for abandoned sales persist until the sale is cleared.

## Contract between backend and frontend

1. **Golden JSON fixtures.** A Haskell test writes fixture files for the sale types and the three sale request types; a PureScript test decodes them.
2. **Put the `/pos/sale` routes in the OpenAPI document.** `SaleCommandAPI` is served beside `CheeblrAPI`.
3. **Status check in `API.Request.authDelete`.** A non-2xx response can surface as a JSON parse error.

## Frontend

1. **Replace `DL.load_` on elements that never raise `load`.** `Pages.Stock.Interface`, `UI.Inventory.MenuLiveView` and any others should use `UI.Remote.onMount`.
2. **Remove dead helpers.** `Services.Cart` and the totals helpers in `Services.TransactionService` are used only by `test/Cart.purs`.
3. **Item form.** Generate a fresh SKU after a successful create. Decide whether name-like fields move from `alphanumeric` to `extendedAlphanumeric`.
4. **Live inventory on the transaction screen.** It refetches after each action; wire it to the backend availability stream.
5. **Unknown backend role must not fall back to Admin on login.**
6. **Replace the hardcoded dummy location and employee ids** in `Config.Entity` with values from the session and register selection.
7. **Environment selection.** `Config.Network.currentConfig` is hardcoded to the localhost config.
8. **Capability-gate the nav links.**
9. **Transaction history page** (currently a placeholder).

## Backend

1. **Capability enforcement on sale and register endpoints.** They require a valid session but do not check fine-grained capabilities.
2. **Payment processor integration.** Payments are marked approved when recorded.
3. **Discounts in the sale flow.** Types and storage exist; nothing creates one.
4. **Ledger and compliance endpoints** are stubs.
5. **Daily financial reporting.**

## Later

- Advanced reporting and analytics
- Multi-location support beyond tax rules
- Third-party integrations (Metrc, Leafly)
- GraphQL subscriptions for live inventory

## Testing

```bash
test-unit             # Haskell unit and property tests + PureScript tests
test-integration      # ephemeral PostgreSQL + backend, HTTP integration suite
test-integration-tls  # the same with TLS
test-suite            # all phases in sequence
test-smoke            # hit a live backend, check endpoints and JSON contracts
```
