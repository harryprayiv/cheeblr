# Cheeblr Security Plan

## Current State

Authentication is dev-mode only: a fixed `X-User-Id` header maps to hardcoded UUIDs in
`Auth.Simple`. Roles and capabilities are correctly modeled but nothing stops a client from
claiming any identity. TLS is wired up via `warp-tls` and `mkcert`, secrets are managed
through sops-nix, and the DB layer uses parameterized queries throughout. The foundation is
solid; the gap is a real identity layer.

---

## Architecture Decision: Opaque Session Tokens

For a dispensary POS the right choice is **server-side sessions stored in PostgreSQL**, not
JWT. The reasons are specific to the compliance context:

- **Immediate revocation.** Cannabis retail requires the ability to terminate an employee
  session the instant their shift ends or their access is revoked. JWT expiry cannot be
  shortened below the token's lifespan without a blacklist, which defeats the stateless
  argument anyway.
- **Auditability.** Session rows are first-class compliance records: who logged in, from
  which terminal, at what time, and when the session ended. Your Katip logging already hooks
  naturally into this.
- **Simplicity.** `servant-auth-server` is well-maintained but adds machinery (cookie or
  Bearer JWT, signer keys, claims types) that buys nothing here. A lookup of a random token
  against a sessions table is one indexed query and zero crypto at request time.
- **Alignment with your state machine design.** A session row can carry a `register_id`
  binding so that login at a specific terminal enforces the register state machine constraint
  without any extra plumbing.

The token itself is 32 bytes from `/dev/urandom`, base64url-encoded, stored as TEXT in
Postgres. SHA-256 of the raw token is stored in the DB so that a DB breach does not yield
usable tokens (same principle as password hashing, lighter weight since tokens are already
high entropy).

---

## Database Schema Changes

```sql
-- New tables, append to createTransactionTables or a new migration function.

CREATE TABLE IF NOT EXISTS users (
  id           UUID PRIMARY KEY,
  username     TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  email        TEXT,
  role         TEXT NOT NULL,
  location_id  UUID,
  password_hash TEXT NOT NULL,        -- Argon2id output, includes salt
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sessions (
  id           UUID PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash   TEXT NOT NULL UNIQUE,  -- SHA-256(raw_token), hex-encoded
  register_id  UUID,                  -- optional: binds session to a register
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at   TIMESTAMPTZ NOT NULL,
  revoked      BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_at   TIMESTAMPTZ,
  revoked_by   UUID REFERENCES users(id),
  user_agent   TEXT,
  ip_address   TEXT
);

CREATE INDEX IF NOT EXISTS sessions_token_hash_idx ON sessions (token_hash)
  WHERE NOT revoked AND expires_at > NOW();

CREATE INDEX IF NOT EXISTS sessions_user_id_idx ON sessions (user_id);

-- Login attempt log for rate limiting and compliance.
CREATE TABLE IF NOT EXISTS login_attempts (
  id           UUID PRIMARY KEY,
  username     TEXT NOT NULL,
  ip_address   TEXT NOT NULL,
  success      BOOLEAN NOT NULL,
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS login_attempts_ip_idx
  ON login_attempts (ip_address, attempted_at DESC);
CREATE INDEX IF NOT EXISTS login_attempts_username_idx
  ON login_attempts (username, attempted_at DESC);
```

Session expiry: 8 hours for cashier/manager terminals, 24 hours for admin. Configurable
via env var `SESSION_TTL_SECONDS`. No refresh tokens initially; re-login on expiry is
correct behavior for a POS.

---

## Backend Implementation Plan

### New packages to add to `backend.cabal` / `haskell.nix` inputs

```
argon2           -- Argon2id bindings (cryptonite has Bcrypt but Argon2id is preferred)
crypton          -- SHA-256 for token hashing (already likely transitive via warp-tls)
entropy          -- CSPRNG for token generation
base64-bytestring -- token encoding
```

`argon2` wraps the reference C implementation. The relevant call is:

```haskell
import Crypto.Argon2 (hashEncoded, Argon2Config(..), Argon2Variant(..), defaultConfig)

hashPassword :: Text -> IO Text
hashPassword plaintext =
  let cfg = defaultConfig { configVariant = Argon2id }
  in hashEncoded cfg (TE.encodeUtf8 plaintext) <$> generateSalt 16
```

`verifyEncoded` from the same package handles comparison.

### New modules

**`DB.Auth`** — all auth DB operations

- `createUser :: DBPool -> NewUser -> IO UUID`
- `lookupUserByUsername :: DBPool -> Text -> IO (Maybe UserRow)`
- `createSession :: DBPool -> UUID -> Maybe UUID -> Text -> Text -> IO SessionToken`
- `lookupSession :: DBPool -> Text -> IO (Maybe (SessionRow, UserRow))`  
  Takes the raw token, hashes it, queries. Returns `Nothing` for revoked/expired.
- `revokeSession :: DBPool -> UUID -> Maybe UUID -> IO ()`
- `revokeAllUserSessions :: DBPool -> UUID -> IO ()`
- `recordLoginAttempt :: DBPool -> Text -> Text -> Bool -> IO ()`
- `recentFailedAttempts :: DBPool -> Text -> Text -> NominalDiffTime -> IO Int`

**`Auth.Session`** — replaces `Auth.Simple`

```haskell
data SessionContext = SessionContext
  { scUser    :: AuthenticatedUser
  , scSession :: SessionId
  }

type SessionHeader = Header "Authorization" Text

-- Extract "Bearer <token>" from header, look up session, return context or 403.
resolveSession
  :: DBPool
  -> Maybe Text
  -> Handler SessionContext
```

The `AuthenticatedUser` type stays unchanged. Everything downstream that currently calls
`lookupUser mUserId` instead calls `resolveSession pool mAuthHeader`, which returns a
`SessionContext` or throws `err401`.

**`API.Auth`** — new endpoints

```haskell
type AuthAPI =
       "auth" :> "login"  :> ReqBody '[JSON] LoginRequest  :> Post '[JSON] LoginResponse
  :<|> "auth" :> "logout" :> SessionHeader :> Post '[JSON] NoContent
  :<|> "auth" :> "me"     :> SessionHeader :> Get  '[JSON] SessionResponse
  :<|> "auth" :> "users"  :> SessionHeader :> Get  '[JSON] [UserSummary]          -- admin only
  :<|> "auth" :> "users"  :> SessionHeader :> ReqBody '[JSON] NewUser :> Post '[JSON] UserSummary

data LoginRequest = LoginRequest
  { loginUsername :: Text
  , loginPassword :: Text
  , loginRegisterId :: Maybe UUID  -- optional: bind session to a register
  } deriving (Generic, ToJSON, FromJSON, ToSchema)

data LoginResponse = LoginResponse
  { loginToken        :: Text
  , loginExpiresAt    :: UTCTime
  , loginUser         :: SessionResponse
  } deriving (Generic, ToJSON, FromJSON)
```

**`Server.Auth`** — handler implementations

Login flow:

1. Look up user by username. If not found, record failed attempt, return `err401` with a
   generic message. Never distinguish "no such user" from "wrong password" in the response.
2. Check recent failed attempts for this IP and username. If over threshold (5 per 10
   minutes), return `err429` before even touching the password.
3. Verify password with `Argon2.verifyEncoded`.
4. On success: generate 32 random bytes, base64url-encode as the token, store SHA-256
   of raw token in `sessions`. Return the raw token to the client.
5. Log both outcomes through Katip's existing `logAuthDenied` / a new `logAuthSuccess`.

### Integrating session auth into existing handlers

The current pattern in `Server.hs`:

```haskell
getInventory :: Maybe Text -> Handler Inventory
getInventory mUserId = do
  let user = lookupUser mUserId
  ...
```

Becomes:

```haskell
getInventory :: Maybe Text -> Handler Inventory
getInventory mAuthHeader = do
  SessionContext{scUser = user} <- resolveSession pool mAuthHeader
  ...
```

The `SessionHeader` type alias stays as `Header "Authorization" Text` throughout. The
existing `AuthHeader = Header "X-User-Id" Text` in `API.Inventory` gets replaced. One
search-and-replace plus updating `resolveSession` call sites.

The `combinedServer` in `Server.hs` gains the `authServerImpl pool logEnv` arm wired into
`CheeblrAPI`.

---

## Frontend Implementation Plan

### New modules

**`Services.AuthService`** — extend existing module

The module already has `AuthState`, `defaultAuthState`, etc. The real-auth additions:

```purescript
type SessionToken = String

login :: String -> String -> Maybe UUID -> Aff (Either String { token :: SessionToken, user :: SessionResponse })
login username password mRegisterId =
  Request.postNoAuth "/auth/login" { loginUsername: username, loginPassword: password, loginRegisterId: mRegisterId }

logout :: SessionToken -> Aff (Either String Unit)
logout token = Request.authPostUnit' token "/auth/logout"

-- Store token in localStorage, load on startup.
persistToken :: SessionToken -> Effect Unit
loadToken :: Effect (Maybe SessionToken)
clearToken :: Effect Unit
```

`Request.authGet` and friends currently hardcode `"X-User-Id": userId`. Change the header
name to `"Authorization"` and the value to `"Bearer " <> token`. The `UserId` type alias
can stay as `String` and just carries the token instead of the UUID string — or rename it
to `SessionToken` for clarity.

**`Pages.Login`** — new page

A straightforward Deku form: username input, password input, submit button. On success,
push the token into a top-level poll and navigate to `LiveView`. On failure, show the error
inline. No routing entry needed beyond adding `Login` to `Route`.

**`Main.purs`** changes

On startup: call `loadToken`. If a token exists, call `GET /auth/me` to validate it. If
valid, restore the session. If the call returns 401, clear the stored token and show the
login page.

The current `defaultAuthState = SignedIn defaultDevUser` becomes
`defaultAuthState = SignedOut` in production. A build flag or config knob
(`Config.Auth.devMode`) can keep the old behavior for local development.

The `authState` poll (already in `Main.purs`) gets pushed `SignedIn` on successful login
with the `SessionResponse` data, and `SignedOut` on logout or 401 from any endpoint.

**Token storage**

Use `localStorage` for the raw token. This is appropriate for a POS where:

- The terminal is a dedicated machine, not a shared browser.
- The session has a short TTL (8 hours) and is revocable server-side.
- Storing in memory only would lose the session on page refresh, which is bad UX on a POS
  that might be refreshed by a cashier.

The token is opaque (no claims), so XSS stealing the token is the primary risk. Mitigate
via `Content-Security-Policy` headers (see below) rather than `HttpOnly` cookies, since
the API and frontend are on different origins in your current setup.

---

## Migration Path

The dev-mode `Auth.Simple` module stays in place behind a `devMode :: Bool` check in
`App.hs`. When `USE_REAL_AUTH=true` is set (add to sops secrets for production), the
`resolveSession` path is used. When false, `lookupUser` is used as today. This lets you
develop and test incrementally without breaking existing flows.

Migration sequence:

1. Add `users`, `sessions`, `login_attempts` tables.
2. Implement `DB.Auth`, `Auth.Session`, `API.Auth`, `Server.Auth`.
3. Add `USE_REAL_AUTH` env var. Wire it into `App.hs`.
4. Implement `Pages.Login` and token handling in the frontend.
5. With `USE_REAL_AUTH=false` (default), nothing changes.
6. Flip `USE_REAL_AUTH=true` in a test environment. Log in via the new form. Verify session
   lookup works. Verify logout revokes correctly. Verify expired sessions return 401.
7. Flip in staging, then production.
8. After all endpoints are verified, delete `Auth.Simple` and the `USE_REAL_AUTH` flag.

---

## Rate Limiting

Implement in `Server.Auth` using the `login_attempts` table rather than in-memory state.
This survives server restarts and works correctly if you ever run multiple instances.

```haskell
checkLoginRateLimit :: DBPool -> Text -> Text -> Handler ()
checkLoginRateLimit pool username ip = do
  failedCount <- liftIO $ recentFailedAttempts pool username ip (10 * 60)
  when (failedCount >= 5) $
    throwError err429
      { errBody = "Too many failed login attempts. Try again in 10 minutes."
      , errHeaders = [("Retry-After", "600")]
      }
```

No external caching layer needed. The `login_attempts_ip_idx` index makes this a fast
bounded query.

---

## Security Headers

Add to the WAI middleware chain in `App.hs`:

```haskell
securityHeadersMiddleware :: Middleware
securityHeadersMiddleware app req respond =
  app req $ \response ->
    respond $ mapResponseHeaders
      ( [ ("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        , ("X-Content-Type-Options",    "nosniff")
        , ("X-Frame-Options",           "DENY")
        , ("Referrer-Policy",           "strict-origin-when-cross-origin")
        , ("Content-Security-Policy",
           "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:")
        ] <>
      ) response
```

The `unsafe-inline` on `style-src` is a concession to Tailwind's inline styles. Tighten
this when you move to a build-time CSS extraction step.

---

## CORS Lockdown

The current CORS policy in `App.hs` has `corsOrigins = Nothing` (allow all). For
production, change to:

```haskell
corsOrigins = Just (["https://your-production-domain.com"], True)
```

Add `ALLOWED_ORIGIN` to sops secrets. The dev environment keeps `Nothing` via the
`USE_REAL_AUTH` / `NODE_ENV` flag.

---

## Admin User Bootstrap

Add a `cheeblr-bootstrap-admin` command to the Nix devShell that:

1. Connects to the DB.
2. Checks whether any users exist.
3. If not, generates a random password, creates an admin user, prints the credentials once
   to stdout, and exits.

This prevents storing any initial credentials in the repo and gives a clean first-run
experience. Document this in the README.

---

## Compliance Notes Specific to Cannabis Retail

- **Session binding to register.** The `register_id` column on `sessions` means you can
  enforce that a cashier's session only creates transactions on the register they logged
  into. The state machine in `State.RegisterMachine` can check this at the service layer.
- **Shift end = session revocation.** When `closeRegister` is called, call
  `revokeAllUserSessions` for the cashier unless they are a manager who may continue on
  another register.
- **Audit trail.** The `sessions` table combined with Katip's compliance log gives you a
  complete picture: login time, terminal, every transaction event, logout time. This is
  exactly what state regulators want to see.
- **Inactivity timeout.** Update `last_seen_at` on each authenticated request. Add a
  `CHECK_INACTIVITY_MINUTES` env var (default 30). Any session where
  `last_seen_at < NOW() - interval` is treated as expired by `lookupSession`.

---

## Implementation Order

1. `DB.Auth` module and schema migration (backend, no API surface changes).
2. `Server.Auth` login/logout endpoints and integration tests.
3. `Auth.Session.resolveSession` replacing `Auth.Simple.lookupUser` behind the `USE_REAL_AUTH` flag.
4. `Pages.Login` in PureScript with token persistence.
5. Switch `Request.*` functions to `Authorization: Bearer` header.
6. Wire `USE_REAL_AUTH=true` in test environment, run full integration suite.
7. Security headers and CORS lockdown.
8. Rate limiting on login endpoint.
9. Bootstrap admin command.
10. Delete dev-mode auth code.