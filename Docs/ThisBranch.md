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