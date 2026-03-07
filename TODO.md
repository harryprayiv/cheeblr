## GraphQL on Your Haskell Stack — A Complete Picture

### What GraphQL Actually Is

GraphQL is a **query language for your API**, not your database. This is the first and most important thing to internalize. It sits in exactly the same layer as your Servant REST routes — between the client and your business logic. PostgreSQL doesn't change at all. Your `postgresql-simple`, `hasql`, `beam`, or `persistent` queries are completely unaffected.

The fundamental shift is in *who decides the shape of the response*. With REST, your server defines what `/api/inventory` returns. With GraphQL, the **client sends a query** describing exactly which fields it wants, and the server resolves only those fields. This matters a lot for a POS inventory feed where you might want different subsets of product data on different screens.

---

### The Haskell GraphQL Ecosystem

The dominant library smart Haskell devs reach for is **`morpheus-graphql`**. It's mature, actively maintained, and designed to integrate with Warp/Servant rather than replace them.

There are a few others worth knowing:

- **`morpheus-graphql`** — code-first schema derivation using GHC generics and type-level machinery. This is the idiomatic choice.
- **`graphql-api`** — schema-first, very type-safe, but less active development.
- **`graphql`** — low-level parser/executor, useful if you're building infrastructure, not an app.

You'll use `morpheus-graphql`. Here's what the type machinery looks like:

```haskell
-- Define your GraphQL types using deriving
data InventoryItem m = InventoryItem
  { itemId       :: m ID
  , name         :: m Text
  , sku          :: m Text
  , quantity     :: m Int
  , price        :: m Int       -- cents, same as your existing domain type
  , category     :: m Text
  } deriving (Generic)

instance GQLType (InventoryItem m)

-- Define your Query root
data Query m = Query
  { inventoryItem  :: GetItemArgs -> m (InventoryItem m)
  , inventoryFeed  :: m [InventoryItem m]
  , lowStockItems  :: ThresholdArgs -> m [InventoryItem m]
  } deriving (Generic)

instance GQLType (Query m)

-- Resolvers are just IO actions hitting your existing DB layer
resolveInventoryFeed :: ResolveQ e () [InventoryItem (ResolveQ e ())]
resolveInventoryFeed = do
  items <- liftIO $ DB.getAllInventoryItems pool
  pure $ map toGQLItem items
```

The `m` type parameter is morpheus's resolver monad threading — it lets fields be resolved lazily. Your actual DB calls are the same functions you already have.

---

### Servant Integration — Adding GraphQL as a Route

You don't replace Servant. You add a GraphQL endpoint alongside your existing REST routes. It's literally one additional route:

```haskell
type API =
       -- Your existing REST routes
       "auth"        :> AuthAPI
  :<|> "transactions" :> TransactionAPI
  :<|> "api"         :> "v1" :> RestInventoryAPI
       -- New GraphQL endpoint
  :<|> "graphql"     :> ReqBody '[JSON] GQLRequest :> Post '[JSON] GQLResponse
       -- GraphQL subscriptions (WebSocket — handled separately, see below)
```

The GraphQL handler is thin:

```haskell
graphqlHandler :: GQLRequest -> AppM GQLResponse
graphqlHandler req = do
  pool <- asks dbPool
  liftIO $ interpreter (rootResolver pool) req

rootResolver :: Pool Connection -> GQLRootResolver IO () Query Mutation Subscription
rootResolver pool = GQLRootResolver
  { queryResolver        = Query { inventoryFeed = resolveInventoryFeed pool, ... }
  , mutationResolver     = Mutation { ... }
  , subscriptionResolver = Subscription { inventoryUpdates = resolveInventoryStream pool }
  }
```

---

### Subscriptions — The Real Reason You're Here

This is where GraphQL earns its place for your inventory feed use case. GraphQL **subscriptions** use WebSockets and push updates to clients when data changes. This is the idiomatic way to get "rapid updates."

The flow looks like:

1. Client opens a WebSocket to `/graphql/ws`
2. Client sends a subscription operation: `subscription { inventoryUpdates { itemId quantity } }`
3. Server maintains a channel (using STM `TBQueue` or `broadcast-chan`) connected to your PostgreSQL `LISTEN/NOTIFY` mechanism
4. When inventory changes (a transaction commits, a reservation fires), Postgres emits a NOTIFY, your Haskell listener picks it up, publishes to the channel, and all subscribed clients receive the delta

```haskell
-- Subscription resolver using morpheus's Event type
data Channel = InventoryChannel deriving (Eq, Show, Generic, Hashable)
data Content = InventoryUpdate InventoryItem

type Sub = Event Channel Content

resolveInventoryStream :: Pool Connection -> SubscriptionField (ResolveS Sub InventoryItem)
resolveInventoryStream pool = subscribe [InventoryChannel] $ do
  Event _ (InventoryUpdate item) <- ask
  pure $ toGQLSubscriptionItem item
```

Morpheus-graphql ships a WebSocket server component (`morpheus-graphql-subscriptions`) that handles the subscription protocol (currently `graphql-ws` protocol, which is what Apollo Client and most frontends expect).

---

### The Dual Stack Architecture You Described

Yes, this is completely idiomatic and many production Haskell services do exactly this. The pattern is:

```
REST  /auth/**          → JWT issuance, session management
REST  /transactions/**  → POS transaction processing, receipt generation
REST  /admin/**         → Manager/admin mutations where audit trail matters

GraphQL /graphql        → Inventory queries (client-driven field selection)
GraphQL /graphql (WS)   → Inventory subscription feed (real-time push)
```

Authentication bridges cleanly. You validate the same JWT in both paths:

```haskell
-- Your existing auth middleware works on GraphQL too
graphqlHandler :: AuthenticatedUser -> GQLRequest -> AppM GQLResponse
graphqlHandler user req =
  interpreter (rootResolver pool user) req
  -- Pass user's role/capabilities into the resolver context
  -- same capability check logic you already have
```

The GraphQL resolvers can enforce the same capability checks your REST handlers do — just thread the authenticated user through the resolver monad context.

---

### Parallel Request Handling

Nothing changes here. Warp is already running your request handlers concurrently on GHC green threads. Adding a GraphQL route is just adding another handler — Warp dispatches it the same way. Concurrent REST and GraphQL requests hitting PostgreSQL simultaneously is exactly what your connection pool already manages.

The one new concern is WebSocket connections for subscriptions — each open subscription is a long-lived green thread with a channel. GHC's RTS handles thousands of these cheaply. You don't need to configure anything special; just be aware of connection pool pressure if each subscription resolver is polling the DB rather than using LISTEN/NOTIFY.

---

### PureScript Frontend Changes

On the Deku side you have a few options:

**Option 1 — Hand-roll fetch calls** (least friction, consistent with your existing approach). GraphQL over HTTP is just a POST with `{"query": "...", "variables": {...}}`. You can keep using your existing `Fetch`/`Aff` infrastructure and parse the response manually.

**Option 2 — `purescript-graphql-client`**. This library exists and generates type-safe query functions from your GraphQL schema. It's the PureScript equivalent of Apollo codegen. Less mature than the JS ecosystem but functional.

**Option 3 — FFI to Apollo Client**. Some PureScript/Deku shops write thin FFI bindings to Apollo's JS client for subscription management, since Apollo's subscription WebSocket handling is battle-tested. Not idiomatic PureScript but pragmatic.

For subscriptions specifically, you'd use the browser `WebSocket` API (or a library wrapping it) to connect to `/graphql/ws` and implement the `graphql-ws` subprotocol message framing. This is the messiest part of the client side — it's why people reach for Apollo.

---

### What Actually Changes in Your Codebase

**Doesn't change:**
- PostgreSQL schema, migrations
- All your existing DB query functions
- Authentication/JWT logic
- Transaction processing logic
- Warp/TLS setup
- Nix flake (just add morpheus-graphql to your cabal deps)

**New additions:**
- GraphQL type definitions mirroring your domain types
- Resolver functions (thin wrappers over existing DB functions)
- WebSocket subscription server (morpheus ships this)
- LISTEN/NOTIFY integration for inventory change events
- Client-side subscription handling in PureScript

**Replaces (optionally):**
- Your `GET /inventory/**` family of REST endpoints — the GraphQL query surface covers these more flexibly. You can deprecate them gradually or keep both.

---

### Honest Assessment for Your Use Case

GraphQL subscriptions for the inventory feed is a genuinely good fit — real-time quantity updates, low-stock alerts, reservation state changes are all events that benefit from push rather than poll. The REST surface for transactions and auth is also the right call; mutations with complex business logic, audit trails, and precise error semantics are actually *harder* to express well in GraphQL than in REST.

The main cost is operational complexity: you now have two API paradigms, WebSocket connection management, and a subscription event bus to maintain. For a POS system where the inventory feed is a real UI concern (cashiers seeing quantity changes live), it's worth it. If you're just doing periodic refreshes, polling a REST endpoint every few seconds is simpler and plenty adequate.