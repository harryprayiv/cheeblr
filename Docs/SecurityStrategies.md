# Cheeblr Security Documentation

This document outlines the security architecture, best practices, and implementation guidelines for the Cheeblr application when deployed on a public network.

## Table of Contents

1. [Security Principles](#security-principles)
2. [Authentication Architecture](#authentication-architecture)
3. [Transport Layer Security](#transport-layer-security)
4. [WebSocket Security](#websocket-security)
5. [Rate Limiting and Protection](#rate-limiting-and-protection)
6. [Deployment Checklist](#deployment-checklist)
7. [Security Audit Guidelines](#security-audit-guidelines)

## Security Principles

### Core Security Principles for Public Networks

| Principle | Description | Security Level | Implementation Difficulty |
|-----------|-------------|---------------|---------------------------|
| End-to-End Encryption | All communications are encrypted using TLS (HTTPS) | Very High | Low |
| Server-side Session Auth | Opaque tokens stored in PostgreSQL; revocable instantly | Very High | Medium |
| Replay Attack Protection | Tokens are 32 bytes of CSPRNG entropy; SHA-256 hash stored in DB | Very High | Low |
| Argon2id Password Hashing | Passwords hashed with Argon2id (3 iterations, 64 MB memory) | Very High | Low |
| Rate Limiting | Per-credential and per-IP limits enforced at DB level | High | Low |
| Security Headers | HSTS, CSP, X-Frame-Options, X-Content-Type-Options on all responses | High | Low |

## Authentication Architecture

### Why Server-Side Sessions Over JWT

For a cannabis dispensary POS the compliance requirements drive the architecture:

- **Immediate revocation.** Sessions can be terminated the instant an employee's shift ends or access is revoked. JWT expiry cannot be shortened below the token lifespan without a blacklist, which defeats the stateless argument anyway.
- **Auditability.** The `sessions` table is a first-class compliance record: who logged in, from which terminal, at what time, and when the session ended.
- **Register binding.** A session row carries a `register_id` column so the register state machine can enforce that a cashier's session only creates transactions on the register they logged into.
- **Simplicity.** A single indexed lookup of a SHA-256 hash against the `sessions` table is one query and zero cryptography at request time.

### Current Implementation

**Status**: Fully implemented. The dev-mode `X-User-Id` header and `Auth.Simple` module have been deleted. All endpoints require a valid `Authorization: Bearer <token>` header resolved through `Auth.Session.resolveSession`.

#### Token Lifecycle

1. Client `POST /auth/login` with username and password.
2. Server checks per-credential and per-IP rate limits before touching the password.
3. Server looks up user by username, verifies Argon2id hash with `verifyPassword`.
4. On success: 32 bytes from `/dev/urandom` are base64url-encoded as the raw token. The SHA-256 of the raw bytes is stored in `sessions.token_hash`. Only the raw token is returned to the client — the DB never holds anything usable if breached.
5. Client stores the raw token in `localStorage` and sends it as `Authorization: Bearer <token>` on every request.
6. Server hashes the incoming token and does a single indexed lookup. A miss, expired row, or revoked row all return 401.
7. Each successful lookup updates `sessions.last_seen_at` for inactivity tracking.
8. Logout calls `revokeSession`, setting `sessions.revoked = true` immediately.

#### Session Expiry and Inactivity

- Hard expiry: 8 hours from login (`sessions.expires_at`).
- Inactivity: controlled by `CHECK_INACTIVITY_MINUTES` env var (default 30). Sessions where `last_seen_at < NOW() - interval` are treated as expired by `lookupSession`.
- No refresh tokens. Re-login on expiry is correct behavior for a POS terminal.

#### Database Schema

```sql
CREATE TABLE users (
  id            UUID PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  display_name  TEXT NOT NULL,
  email         TEXT,
  role          TEXT NOT NULL,         -- Customer | Cashier | Manager | Admin
  location_id   UUID,
  password_hash TEXT NOT NULL,         -- Argon2id PHC string, includes salt
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sessions (
  id            UUID PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash    TEXT NOT NULL UNIQUE,  -- SHA-256(raw_token), hex-encoded
  register_id   UUID,                  -- optional: binds session to a register
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL,
  revoked       BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_at    TIMESTAMPTZ,
  revoked_by    UUID REFERENCES users(id),
  user_agent    TEXT,
  ip_address    TEXT
);

CREATE TABLE login_attempts (
  id           UUID PRIMARY KEY,
  username     TEXT NOT NULL,
  ip_address   TEXT NOT NULL,
  success      BOOLEAN NOT NULL,
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### Frontend Token Handling

The raw token is stored in `localStorage` under the key `cheeblr_session_token`. On startup `Main.purs` calls `loadToken`; if a token is present it validates it against `GET /auth/me` before restoring the session. A 401 response clears the stored token and redirects to the login page. All API request functions in `API.Request` send `Authorization: Bearer <token>` on every call.

#### Admin Bootstrap

The `bootstrap-admin` devshell command generates a random password, creates the initial admin user, and stores the password encrypted in sops. It is a no-op if any users already exist. Run once after the first `pg-start`.

### Authentication Method Comparison

| Authentication Method | Security Level | Ease of Use | Privacy | Implementation Complexity | Notes |
|----------------------|----------------|-------------|---------|---------------------------|-------|
| Server-side opaque sessions (current) | ★★★★☆ | ★★★★★ | ★★★★☆ | ★★☆☆☆ | Instant revocation, compliance-friendly |
| Libsodium public-key challenge-response | ★★★★★ | ★★★☆☆ | ★★★★★ | ★★★★☆ | Upgrade path for highest-security deployments |
| JWT with secure signatures | ★★★★☆ | ★★★★☆ | ★★★★☆ | ★★★☆☆ | Unsuitable here: no instant revocation without a blacklist |
| OAuth 2.0 / OpenID Connect | ★★★★☆ | ★★★★★ | ★★☆☆☆ | ★★★☆☆ | Not suitable for air-gapped POS terminals |
| Dev-mode X-User-Id header | ★☆☆☆☆ | ★★★★★ | ☆☆☆☆☆ | ★☆☆☆☆ | Deleted. Never use in any deployed environment. |

## Transport Layer Security

### TLS Configuration Guidelines

All Cheeblr communications use TLS 1.2+ with the following configuration:

| Setting | Recommendation | Security Level |
|---------|---------------|----------------|
| Minimum TLS Version | TLS 1.2 (TLS 1.3 preferred) | ★★★★★ |
| Cipher Suites | Strong AEAD ciphers only (AES-GCM, ChaCha20-Poly1305) | ★★★★★ |
| Certificate Type | OV or EV from trusted CA (mkcert for dev) | ★★★★☆ |
| Key Length | RSA 2048+ or ECC P-256+ | ★★★★★ |
| HSTS | Enabled — `max-age=31536000; includeSubDomains` | ★★★★★ |
| Certificate Renewal | Automatic via Let's Encrypt or similar | ★★★★☆ |
| OCSP Stapling | Enabled (requires CA-issued cert) | ★★★★☆ |

**Implementation status**: Fully implemented. `warp-tls` handles TLS termination on the backend. Certificates are generated by `mkcert` for dev/LAN use and stored encrypted in `secrets/cheeblr.yaml` via sops. All service scripts (`backend-start`, `deploy`, `launch-dev`, etc.) inject `USE_TLS`, `TLS_CERT_FILE`, and `TLS_KEY_FILE` from sops at launch time. For production, replace the mkcert cert with a CA-issued certificate and update the sops secrets accordingly.

### Security Headers

All responses carry the following headers, applied by `securityHeadersMiddleware` in `App.hs` before any other middleware:

| Header | Value | Purpose |
|--------|-------|---------|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Prevents protocol downgrade attacks |
| `X-Content-Type-Options` | `nosniff` | Prevents MIME-type sniffing |
| `X-Frame-Options` | `DENY` | Prevents clickjacking |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limits referrer leakage |
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:` | Limits injection attack surface |

The `unsafe-inline` on `style-src` is a concession to Tailwind's inline styles. Tighten this when CSS is extracted at build time.

### CORS Policy

CORS is controlled by the `ALLOWED_ORIGIN` environment variable sourced from sops:

- **Empty or absent** (default for dev/staging): `corsOrigins = Nothing` — all origins accepted.
- **Non-empty** (production): `corsOrigins = Just ([origin], True)` — locked to that single origin.

Set `allowed_origin` in `secrets/cheeblr.yaml` to the production frontend URL before going live.

## WebSocket Security

**Planned**: GraphQL WebSocket subscriptions over WSS for live inventory updates via PostgreSQL `LISTEN/NOTIFY`. When implemented:

- Connections will require a valid session token in the initial handshake before any subscription data is sent.
- Messages will be validated against the same capability model used by the HTTP API.
- The same `resolveSession` path used for HTTP requests will gate WebSocket upgrades.

Authentication handshake requirements will be defined when this feature is implemented.

## Rate Limiting and Protection

### Implementation

Rate limiting is enforced in `Server.Auth.checkLoginRateLimit` using the `login_attempts` table. Storing state in PostgreSQL rather than in-process memory means limits survive server restarts and work correctly across multiple instances.

Two independent checks run before any password work on every login attempt:

| Check | Threshold | Window | Purpose |
|-------|-----------|--------|---------|
| Per credential (username + IP) | 5 failures | 10 minutes | Locks out repeated attempts against a single account |
| Per IP (all usernames) | 20 failures | 10 minutes | Catches credential-stuffing attacks that rotate across usernames to evade the per-credential limit |

Both return `429 Too Many Requests` with a `Retry-After: 600` header. The response body distinguishes the two cases for compliance log clarity.

The `login_attempts_ip_idx` index on `(ip_address, attempted_at DESC)` and `login_attempts_username_idx` on `(username, attempted_at DESC)` keep both queries fast under load.

### Recommended Additional Measures

| Measure | Status | Notes |
|---------|--------|-------|
| IP-based rate limiting on login | ✅ Implemented | Per-IP across all usernames |
| Per-credential rate limiting | ✅ Implemented | Per username+IP pair |
| Request throttling (all endpoints) | ⬜ Planned | WAI middleware; not yet needed at POS scale |
| CAPTCHA after repeated failures | ⬜ Not planned | POS terminals are not public-facing web forms |
| IP reputation blocking | ⬜ Planned | Appropriate when moving to public network |

## Deployment Checklist

### Security Configuration Checklist

✅ TLS 1.2+ configured with strong ciphers (`warp-tls`, `mkcert` for dev; replace with CA cert for production)  
✅ All endpoints use HTTPS (plain HTTP rejected by `warp-tls` when `USE_TLS=true`)  
✅ TLS cert and private key stored encrypted via sops — never in plaintext on disk  
✅ All service scripts inject TLS env vars from sops at runtime  
✅ Parameterized queries throughout — no SQL string interpolation  
✅ Argon2id password hashing (3 iterations, 64 MB memory, Argon2id variant)  
✅ Opaque session tokens — raw token never stored in DB, only SHA-256 hash  
✅ Session table with hard expiry, inactivity timeout, and instant revocation  
✅ Session binding to register ID for cashier terminal enforcement  
✅ `POST /auth/login`, `POST /auth/logout`, `GET /auth/me` endpoints  
✅ `POST /auth/users` (admin only) for user creation  
✅ `bootstrap-admin` command for secure first-run credential generation  
✅ Admin password stored encrypted in sops after bootstrap  
✅ Dev-mode `X-User-Id` auth and `Auth.Simple` module fully deleted  
✅ Role-based capabilities enforced on all inventory endpoints  
✅ Rate limiting: per-credential (5/10 min) and per-IP (20/10 min) on login  
✅ Login attempts logged to DB for compliance and rate limit state  
✅ CORS locked to `ALLOWED_ORIGIN` env var (open in dev, locked in production)  
✅ HTTP security headers: HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy  
✅ JSON contract tests between PureScript and Haskell catch serialization divergence  
✅ Integration tests include TLS wire checks (cert SAN validation, plain-HTTP rejection)  
⬜ CORS `ALLOWED_ORIGIN` set to production frontend URL in sops  
⬜ mkcert dev cert replaced with CA-issued certificate  
⬜ `pg-rotate-credentials` run before production deployment  
⬜ Capability enforcement extended to transaction and register endpoints  
⬜ Request throttling middleware on all endpoints  
⬜ WebSocket connections authenticated before use (required before enabling GraphQL subscriptions)  
⬜ OCSP stapling (requires CA-issued cert)  
⬜ Libsodium public-key challenge-response (upgrade path for highest-security deployments)  

## Security Audit Guidelines

Before deploying Cheeblr to a public network, conduct a security audit covering:

1. **Authentication Implementation**
   - Verify Argon2id parameters are appropriate for the deployment hardware
   - Confirm token entropy: 32 bytes from `System.Entropy.getEntropy` via `/dev/urandom`
   - Confirm the DB stores only SHA-256 hashes, never raw tokens
   - Verify `lookupSession` correctly rejects expired and revoked sessions
   - Test that `revokeAllUserSessions` fires when `closeRegister` is called

2. **Transport Security**
   - Replace mkcert dev cert with a CA-issued certificate
   - Verify TLS configuration using SSL Labs or equivalent
   - Confirm `Strict-Transport-Security` header is present on all responses
   - Test that plain HTTP requests are rejected when `USE_TLS=true`
   - Verify cert SAN covers all hostnames in use

3. **API Security**
   - Confirm all endpoints return 401 with no `Authorization` header
   - Confirm all endpoints return 401 with an expired or revoked token
   - Verify capability enforcement on inventory write endpoints
   - Extend capability enforcement to transaction and register endpoints before production
   - Test rate limiting: confirm 429 after 5 failed logins from same username+IP, and after 20 from same IP across any usernames

4. **WebSocket Security**
   - Define and implement authentication handshake before enabling GraphQL subscriptions
   - Verify WSS is used exclusively (no plain `ws://`)

5. **Secrets Management**
   - Verify sops age keys are not committed to the repository
   - Confirm `secrets/cheeblr.yaml` is committed (encrypted) and `~/.config/sops/age/keys.txt` is not
   - Rotate database password before production deployment (`pg-rotate-credentials`)
   - Set `allowed_origin` in sops to the production frontend URL
   - Verify `/run/secrets/cheeblr/` permissions are correct on NixOS deployments (`0750`, owned by service user)

6. **Compliance Audit Trail**
   - Verify `sessions` table captures login time, terminal IP, user agent, and register binding
   - Confirm Katip compliance log receives `logTransactionFinalize`, `logRegisterOpen`, `logRegisterClose` events
   - Confirm `login_attempts` table records both successes and failures
   - Verify `logAuthDenied` fires on every 401 from `loginHandler`