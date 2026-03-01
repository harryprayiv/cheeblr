# Cheeblr Frontend ↔ Backend JSON Contract Analysis

## Critical Mismatch Found

### 1. `DiscountType` — BREAKING

**Backend** (Generic-derived `ToJSON`):
```json
{"tag":"PercentOff","contents":10.0}
{"tag":"AmountOff","contents":500}
{"tag":"BuyOneGetOne"}
{"tag":"Custom","contents":["Employee",250]}
```

**Frontend** (`WriteForeign`):
```json
{"discountType":"PERCENT_OFF","percent":10.0,"amount":0.0}
{"discountType":"AMOUNT_OFF","percent":0.0,"amount":"5.00"}
{"discountType":"BUY_ONE_GET_ONE","percent":0.0,"amount":0.0}
{"discountType":"CUSTOM","name":"Employee","percent":0.0,"amount":"2.50"}
```

**Frontend** (`ReadForeign`) expects the flat `{discountType: "...", ...}` format.

The backend's Generic-derived JSON for sum types with fields produces **tagged unions**, but the frontend expects a **flat discriminated object**. These are incompatible.

**Impact**: Any transaction with discounts will fail to deserialize on one side or the other.

**Fix**: Add custom `ToJSON`/`FromJSON` instances for `DiscountType` in the backend that match the frontend's format.

---

## Potential Issues

### 2. `InventoryResponse` — Asymmetric but functional

**Backend**: `{type: "data", value: <inventory>, capabilities: <caps>}`
**Frontend reads**: extracts only `type` and `value`, ignores `capabilities`
**Frontend writes**: `{type: "data", value: <inventory>}` (no capabilities)

This works for backend→frontend but means the frontend never uses server-sent capabilities. The frontend computes capabilities locally from `capabilitiesForRole`. If capability definitions drift between Haskell and PureScript, users could see different permissions than the server enforces.

### 3. `DiscreteMoney USD` vs `Int` — Needs verification

Backend monetary fields (`transactionItemPricePerUnit`, `paymentAmount`, etc.) are `Int` (cents).
Frontend uses `DiscreteMoney USD` from `Data.Finance.Money.Extended`.

The `fromDiscrete'` / `toDiscrete` functions convert between `Discrete USD` (Int newtype) and `DiscreteMoney USD`. The wire format of `DiscreteMoney` needs to serialize as a plain integer for compatibility.

### 4. `PaymentMethod` `Other` variant — Minor

Backend `showPaymentMethod (Other text) = "OTHER"` (drops the text!)
Frontend `show (Other s) = "OTHER:" <> s` (preserves it)

The backend DB serialization loses the `Other` payload. The JSON `ToJSON`/`FromJSON` instances preserve it correctly, but the DB roundtrip doesn't.

---

## Compatible Types (Verified)

| Type | Backend ToJSON | Frontend WriteForeign | Status |
|------|---------------|----------------------|--------|
| `UserRole` | `"Customer"`, `"Cashier"`, etc. | `"Customer"`, `"Cashier"`, etc. | ✅ |
| `TransactionStatus` | `"Created"`, `"InProgress"`, etc. | `"Created"`, `"InProgress"`, etc. | ✅ |
| `TransactionType` | `"Sale"`, `"Return"`, etc. | `"Sale"`, `"Return"`, etc. | ✅ |
| `PaymentMethod` | `"Cash"`, `"Debit"`, `"Other:x"` | `"Cash"`, `"Debit"`, `"Other:x"` | ✅ |
| `TaxCategory` | `"RegularSalesTax"`, etc. | `"RegularSalesTax"`, etc. | ✅ |
| `ItemCategory` | `"Flower"`, `"PreRolls"`, etc. | `"Flower"`, `"PreRolls"`, etc. | ✅ |
| `Species` | `"Indica"`, `"Hybrid"`, etc. | `"Indica"`, `"Hybrid"`, etc. | ✅ |
| `MenuItem` | field names match, price as Int | field names match, price as Int | ✅ |
| `Transaction` | Generic field names | readImpl reads matching fields | ✅ |
| `TransactionItem` | Generic field names | readImpl reads matching fields | ✅ |
| `PaymentTransaction` | Custom FromJSON with .:? | WriteForeign with Nullable | ✅ |
| `TaxRecord` | Generic | Record type alias | ✅ |
| `Register` | Generic | Record type alias | ✅ |

## Test Strategy

1. **Backend `Test.Integration.JsonContractSpec`**: Construct JSON matching frontend output, verify backend parses it. Serialize backend types, verify structure matches what frontend expects.

2. **Frontend `Test.JsonContract`**: Construct JSON matching backend output, verify frontend parses it. Serialize frontend types, verify structure matches what backend expects.