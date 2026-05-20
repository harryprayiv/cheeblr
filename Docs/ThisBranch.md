# Plan

## Overall strategy

The primitives module(s) will live under `Types.Primitives.*`, with one module per primitive (or tightly-related pair). Reasons: avoids one giant `Types.Primitives` that recompiles whenever you touch any primitive, lets each module own its imports cleanly (e.g. `Token` needs crypto, `Money` doesn't), and matches your existing pattern of `Types.Public.AvailableItem`, `Types.Events.*`, etc.

Final intended layout:

- `Types.Primitives.Token` — `SessionToken`, `SessionTokenHash`
- `Types.Primitives.Money` — `SaleMoney`, `RefundMoney`, `Money` typeclass or shared API
- `Types.Primitives.Quantity` — `SaleQuantity`, `RefundQuantity`
- `Types.Primitives.Rate` — `TaxRate`, `DiscountPct` (these use `refined`)
- `Types.Primitives.UPC` — `UPC` with checksum validation
- `Types.Primitives.SKU` — newtype over `UUID`, replaces bare `UUID` for menu item identity

`Types.Inventory` and `Types.Transaction` import from these and stop using bare `Int`/`UUID`/`Scientific` for domain primitives.

## Option 2 implications (sale/refund split)

This affects `Money` and `Quantity`, not `SessionToken`. But worth restating now so we hold the line later: `negateTransactionItem`, `negatePaymentTransaction`, etc. stop taking a `TransactionItem` and returning a `TransactionItem`. They become explicit conversion functions, roughly `toRefundItem :: SaleTransactionItem -> RefundTransactionItem`. The refund path in `Service.Transaction.refundTx` does this conversion explicitly. The `Transaction` type itself might end up parameterized, or you'll have `SaleTransaction` and `RefundTransaction` as distinct types. That's a structural decision for the Money/Quantity phase, and we'll work through it then. For now, just register it as a known consequence.

We want two seperate types:

# Architecture decision: two separate types

For a financial system, separate `SaleTransaction` and `RefundTransaction` types are the correct move. The parameterized approach (`Transaction (k :: TxKind)`) is more compact but wrong here. Concrete reasons:

**Refunds aren't sales with a sign flipped.** A `RefundTransaction` must reference an original sale (`referenceTransactionId` is non-optional). A `SaleTransaction` never has that field set. This asymmetry isn't expressible as a phantom: `Transaction Sale` and `Transaction Refund` would have to share the same field set, forcing `Maybe UUID` on both even though one is required and one is forbidden.

**Different lifecycles, different state machines.** Sales go Created → InProgress → Completed → Voided/Refunded — five states, six transitions. Refunds are created Completed; they have no lifecycle. Trying to unify these in one state machine produces invalid states ("a refund that's InProgress" is meaningless). Separate types let each have its own machine.

**Phantom types are leaky at boundaries.** The phantom evaporates on serialization. The DB doesn't know about it. The wire doesn't know about it. To recover the type after `SELECT`, you need a runtime discriminator anyway, plus a `SomeTransaction` sum to hold both. That's the worst of both worlds: type-level ceremony with runtime dispatch underneath. Just commit to the distinction at every layer.

**Compliance treats them as different events.** Cannabis state reporting categorizes sales and returns under different filings. Reporting queries should return type-distinguished results, not "a list of transactions you must remember to filter." The type system can enforce correct categorization at the report-generation boundary.

**Real financial systems do this.** QuickBooks, NetSuite, SAP, Square — sales and returns are first-class distinct entities in their data models. Not because those systems lack expressive type systems, because the domain genuinely has two different events.

**Code duplication is the actual cost, and it's small.** SaleTransaction and RefundTransaction will share maybe 80% of their fields. That duplication is real but cheap. The correctness gain is large and ongoing.

The counter is: DRY suffers, and you can't write "a function that works on either kind" without a typeclass. Fine. Add a `IsTransaction` typeclass for the small handful of operations that genuinely don't care (e.g., `getCreatedAt`, `getEmployeeId`). That's how QuickBooks structures its API too.


## UPC

Real feature, added as a primitive in its own module. UPC-A is 12 digits with a mod-10 check digit. EAN-13 is 13 digits, also mod-10 checksum. Cannabis retail in the US is predominantly UPC-A, but vape cart batches often carry EAN-13. I'll support both via two constructors (or a sum type). Validation: numeric only, correct length, valid checksum. Storage: `Text` in the DB (preserves leading zeros), `Maybe UPC` on `MenuItem`. Schema migration adds a nullable `upc` column to `menu_items`.

Out of scope for phase 1 (Token). We'll do UPC as its own phase, probably after Money since it doesn't share infrastructure with the others.

## Phase 1: SessionToken

### What exists today

`type SessionToken = Text` in `DB.Auth`. It's a transparent alias, so every `Text` argument anywhere along the auth path is interchangeable with it. The DB stores the SHA-256 hex digest of the raw token bytes; the wire format is base64url-without-padding of those same raw bytes. The hash and the wire encoding are computed in `DB.Auth` via `hashTokenBytes`, `encodeTokenBytes`, `decodeTokenText`.

### Design decisions

**Two distinct newtypes, not one.** `SessionToken` for the raw secret (in cookies, headers, ephemeral memory). `SessionTokenHash` for the SHA-256 hex digest (in the DB, used for lookup). With both as separate types, the type system enforces that you can't accidentally compare a raw token to a hash, or pass a hash where a token is expected. Cheap and high-value.

**Internal representation is `ByteString` (raw bytes), not the base64url text.** This matches the existing on-the-wire/on-disk contract exactly: the SHA-256 hash is computed over the 32 raw bytes, and the base64url encoding is just a transport encoding. If we stored the base64url text and hashed that, we'd break every existing session in the database. Storing raw bytes preserves backward compatibility.

**Custom `Show` that redacts.** `SessionToken` shows as `SessionToken <redacted>`. This closes a real log-leakage hole; right now any accidental `show` of a token leaks it. `SessionTokenHash` shows the first 8 hex chars plus `...` for log debugging (hashes are non-secret but full hashes are still noisy).

**No `ToJSON`/`FromJSON` instance.** Tokens never appear in JSON bodies — only in cookies and headers. Omitting these instances means accidental serialization fails to compile. Defensive.

**Strict parsing.** `mkSessionToken :: Text -> Maybe SessionToken` validates by attempting base64url decode AND checking the result is exactly 32 bytes. Malformed cookies short-circuit before the DB query. This is a small performance win and a real defense against scanning attacks.

**Explicit reveal.** `revealSessionToken :: SessionToken -> Text` is the only way out of the newtype back to the raw text. Named to be ugly so it's grep-able in code review.

______


SessionToken phase complete. Summary of what landed:

- New module `Types.Primitives.Token` with `SessionToken` and `SessionTokenHash` as distinct newtypes, redacted `Show`, no `ToJSON` instance, smart constructor that validates base64url + 32-byte length.
- `DB.Auth` no longer holds the `type SessionToken = Text` alias; the three token-helper functions (`hashTokenBytes`, `encodeTokenBytes`, `decodeTokenText`) are gone, replaced by the new module's API.
- Auth header path (`Auth.Session.resolveSession`) and cookie path (`App.extractCookieToken`) both validate before any DB query.
- Existing session rows remain valid: wire format and hash function are byte-for-byte preserved.
- Test coverage now includes malformed-cookie short-circuit, which the old code didn't have.

Cabal change: add `Types.Primitives.Token` to `exposed-modules`. That's the only build-system touch.

Ready for Money next when you are. Worth noting up front: it's going to be a much bigger sprawl than this one. The sale/refund split means `negateTransactionItem`, `negatePaymentTransaction`, `negateDiscountRecord`, `negateTaxRecord` all change shape — and the call sites in `Service.Transaction.refundTx` and `DB.Transaction.refundTransaction` change with them. We'll also need to decide whether `Transaction` itself gets parameterized (`Transaction Sale` / `Transaction Refund`) or whether we introduce two separate types. Worth a planning round before any code, same as last time.

______

Money 2A

# Phase plan

This Money work has to be staged because the full split is large. Plan:

**2A (this turn): Money primitive only.** Introduce `Types.Primitives.Money` with `SaleMoney` and `RefundMoney` as distinct newtypes with smart constructors, scoped arithmetic, and explicit refund conversion. No caller changes yet. Self-contained, testable, no risk to running code.

**2B: Quantity primitive.** Same shape as Money: `SaleQuantity`, `RefundQuantity`, smart constructors, no caller changes.

**2C: Split `TransactionItem`.** Introduce `SaleTransactionItem` (uses `SaleMoney`, `SaleQuantity`) and `RefundTransactionItem`. This is the first phase that ripples into callers. The current `negateTransactionItem` becomes `toRefundItem :: SaleTransactionItem -> RefundTransactionItem`.

**2D: Split `PaymentTransaction`.** Same treatment.

**2E: Split `Transaction`.** This is the largest single piece. `SaleTransaction` and `RefundTransaction` with shared `IsTransaction` typeclass for the few common operations. State machine in `State.TransactionMachine` becomes specific to sales.

**2F: Service layer.** `Service.Transaction.refundTx` becomes the named conversion boundary. `DB.Transaction.refundTransaction` updates to take a `SaleTransaction` and return a `RefundTransaction`.

**2G: DB schema.** Probably add a `transaction_kind` discriminator column (or use the existing `transaction_type`). `hydrateTx` becomes `hydrateTx :: TransactionRow Result -> IO (Either SaleTransaction RefundTransaction)`.

**2H: Wire format.** Update OpenAPI schema and PureScript types. Wire format probably stays compatible (sign of `transactionTotal` distinguishes; the kind discriminator is on the wire already via `transactionType`).

I'm only delivering 2A in this turn. After it compiles and tests pass, we move to 2B, etc.

# 2A scope details

The `SaleMoney`/`RefundMoney` convention I'm using:

- `SaleMoney` wraps a non-negative `Int` (cents). Smart constructor rejects negative input.
- `RefundMoney` wraps a non-positive `Int` (cents). Smart constructor rejects positive input.
- `negateToRefund (SaleMoney 1500) = RefundMoney (-1500)`. The sign flip happens at the type boundary.

This preserves the existing on-disk convention (refunds have negative amounts) and gives the accounting summation property `sum(all transactions) = net revenue`. It also means the DB column `Int32` decodes to either type without changing the value, just dispatching on the row's `transaction_type`.

No `Num` instance. Reasoning: `Num` allows multiplication (cents squared has no meaning), `negate` (would violate the invariant), and `fromInteger` (bypasses validation). Explicit functions are clearer and safer. Cost is a few extra characters per arithmetic op. Worth it.

No `ToJSON`/`FromJSON`/`ToSchema` yet. These come in 2H when we wire the types into the API surface. For now, the module is purely internal Haskell, no boundary commitments.

## Cabal change

Add `Types.Primitives.Money` to `exposed-modules` in the library stanza, and `Test.Types.Primitives.MoneySpec` to `other-modules` in the test stanza.

---

That's 2A. Money primitive lands as a self-contained module with property-based test coverage. No callers change yet. Next phase (2B) is the Quantity primitive in the same shape, then the cascading work starts at 2C with `TransactionItem`. If anything in the design above bothers you (the no-`Num` decision, the sign convention, the `unsafeMk*` exposure), say so before we build on top of it.