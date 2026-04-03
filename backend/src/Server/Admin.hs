{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Server.Admin
  ( adminServerImpl
  ) where

import           Control.Concurrent.STM         (atomically, readTVar, readTVarIO)
import           Control.Monad                   (unless)
import           Control.Monad.IO.Class          (liftIO)
import qualified Data.ByteString.Lazy.Char8     as LBS
import           Data.Int                        (Int64)
import           Data.Maybe                      (fromMaybe)
import           Data.Text                       (Text)
import qualified Data.Text                      as T
import           Data.Time                       (diffUTCTime, getCurrentTime)
import           Data.UUID                       (UUID)
import qualified Data.Vector                    as V
import           Network.HTTP.Types.Status       (status401, status403)
import           Network.Wai                     (responseLBS)
import           Servant

import           API.Admin
import           API.Transaction                 (Register (..))
import           Auth.Session                    (SessionContext (..), resolveSession)
import           Config.App                      (cfgDbPoolSize, cfgEnvironment,
                                                   cfgLowStockThreshold)
import qualified DB.Auth                        as DBA
import           DB.Schema                       (sessId, sessCreatedAt,
                                                   sessLastSeenAt, sessUserId,
                                                   userRole)
import qualified DB.Events                      as DBE
import qualified DB.Transaction                 as DBT
import           DB.Database                     (getAllMenuItems)
import           Infrastructure.AvailabilityState (allAvailableItems)
import           Infrastructure.Broadcast        (currentSeq, historyDepth,
                                                   historyFrom, publish)
import           Infrastructure.SSE              (sseStream)
import           Logging                         (logAppInfo)
import           Server.Env                      (AppEnv (..))
import           Server.Metrics                  (Metrics (..))
import           Data.Foldable                   (toList)
import           Types.Admin
import           Types.Auth
  ( AuthenticatedUser (..)
  , UserRole (..)
  , capabilitiesForRole
  , capCanViewAdminDashboard
  , capCanPerformAdminActions
  )
import           Types.Events.Domain             (DomainEvent (..))
import           Types.Events.Log                (LogEvent (..))
import           Types.Events.Session            (SessionEvent (..))
import           Types.Inventory                 (Inventory (..), MutationResponse (..))
import qualified Types.Inventory                as TI
import           Types.Public.AvailableItem      (aiInStock)
import           Types.Transaction
  ( Transaction (..)
  , TransactionStatus (..)
  )

-- ---------------------------------------------------------------------------
-- Auth helpers
-- ---------------------------------------------------------------------------

authCtx :: AppEnv -> Maybe Text -> Handler SessionContext
authCtx env = resolveSession (envDbPool env)

requireAdmin :: SessionContext -> Handler ()
requireAdmin ctx =
  unless (capCanViewAdminDashboard (capabilitiesForRole (auRole (scUser ctx)))) $
    throwError err403 { errBody = LBS.pack "Forbidden: admin access required" }

requireAdminActions :: SessionContext -> Handler ()
requireAdminActions ctx =
  unless (capCanPerformAdminActions (capabilitiesForRole (auRole (scUser ctx)))) $
    throwError err403 { errBody = LBS.pack "Forbidden: admin actions required" }

parseRoleText :: Text -> UserRole
parseRoleText "Customer" = Customer
parseRoleText "Cashier"  = Cashier
parseRoleText "Manager"  = Manager
parseRoleText "Admin"    = Admin
parseRoleText _          = Cashier

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

snapshotHandler :: AppEnv -> Maybe Text -> Handler AdminSnapshot
snapshotHandler env mHeader = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  now  <- liftIO getCurrentTime
  let uptimeSecs = round (diffUTCTime now (envStartTime env)) :: Int

  sessions   <- liftIO $ buildSessionInfos env
  registers  <- liftIO $ DBT.getAllRegisters (envDbPool env)
  let openRegs = filter registerIsOpen registers

  txs        <- liftIO $ DBT.getAllTransactions (envDbPool env)
  let liveTxs  = filter (\tx -> transactionStatus tx `elem` [Created, InProgress]) txs

  Inventory itemVec <- liftIO $ getAllMenuItems (envDbPool env)
  let invItems  = V.toList itemVec
      threshold = cfgLowStockThreshold (envConfig env)
      invSummary = InventorySummary
        { invItemCount     = length invItems
        , invTotalValue    = sum [TI.price i * TI.quantity i | i <- invItems]
        , invLowStockCount = length [i | i <- invItems, TI.quantity i > 0,
                                        TI.quantity i <= threshold]
        , invTotalReserved = 0
        }

  availSummary <- liftIO $ do
    st  <- readTVarIO (envAvailabilityState env)
    ts  <- getCurrentTime
    let ais = allAvailableItems st ts
    pure AvailabilitySummary
      { avInStockCount    = length (filter aiInStock ais)
      , avOutOfStockCount = length (filter (not . aiInStock) ais)
      , avTotalItems      = length ais
      }

  (qCount, eCount) <- liftIO $ atomically $
    (,) <$> readTVar (mDbQueryCount (envMetrics env))
        <*> readTVar (mDbErrorCount  (envMetrics env))
  let dbStats = DbStats
        { dbPoolSize   = cfgDbPoolSize (envConfig env)
        , dbPoolIdle   = 0
        , dbPoolInUse  = 0
        , dbQueryCount = qCount
        , dbErrorCount = eCount
        }

  logD   <- liftIO $ historyDepth (envLogBroadcaster env)
  domD   <- liftIO $ historyDepth (envDomainBroadcaster env)
  stockD <- liftIO $ historyDepth (envStockBroadcaster env)
  availD <- liftIO $ historyDepth (envAvailabilityBroadcaster env)
  availS <- liftIO $ currentSeq   (envAvailabilityBroadcaster env)
  let bcStats = BroadcasterStats
        { bcLogDepth          = logD
        , bcDomainDepth       = domD
        , bcStockDepth        = stockD
        , bcAvailabilityDepth = availD
        , bcAvailabilitySeq   = availS
        }

  pure AdminSnapshot
    { snapshotTime                = now
    , snapshotBuildInfo           = envBuildInfo env
    , snapshotEnvironment         = cfgEnvironment (envConfig env)
    , snapshotUptimeSeconds       = uptimeSecs
    , snapshotActiveSessions      = sessions
    , snapshotOpenRegisters       = openRegs
    , snapshotLiveTransactions    = liveTxs
    , snapshotInventorySummary    = invSummary
    , snapshotAvailabilitySummary = availSummary
    , snapshotDbStats             = dbStats
    , snapshotBroadcasterStats    = bcStats
    }

buildSessionInfos :: AppEnv -> IO [SessionInfo]
buildSessionInfos env = do
  rows <- DBA.listActiveSessions (envDbPool env)
  pure $ map toInfo rows
  where
    toInfo (sess, user) = SessionInfo
      { siSessionId = sessId      sess
      , siUserId    = sessUserId  sess
      , siRole      = parseRoleText (userRole user)
      , siCreatedAt = sessCreatedAt   sess
      , siLastSeen  = sessLastSeenAt  sess
      }

sessionsHandler :: AppEnv -> Maybe Text -> Handler [SessionInfo]
sessionsHandler env mHeader = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  liftIO $ buildSessionInfos env

revokeSessionHandler :: AppEnv -> UUID -> Maybe Text -> Handler NoContent
revokeSessionHandler env sessionId mHeader = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  let actorId = auUserId (scUser ctx)
  -- fetch target userId before revoking so we can emit correct event
  mSess <- liftIO $ DBA.getSessionById (envDbPool env) sessionId
  liftIO $ DBA.revokeSession (envDbPool env) sessionId (Just actorId)
  now <- liftIO getCurrentTime
  case mSess of
    Just sess ->
      liftIO $ publish (envDomainBroadcaster env) $ SessionEvt SessionRevoked
        { sesUserId    = sessUserId sess
        , sesActorId   = actorId
        , sesTimestamp = now
        }
    Nothing -> pure ()
  liftIO $ logAppInfo (envLogEnv env) $
    "Admin revoked session " <> T.pack (show sessionId) <>
    " by " <> T.pack (show actorId)
  pure NoContent

logsHandler
  :: AppEnv
  -> Maybe Text
  -> Maybe Text -> Maybe Text -> Maybe Text -> Maybe Int -> Maybe Int64
  -> Handler LogPage
logsHandler env mHeader mSev mComp mTrace mLimit mCursor = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  let cursor = fromMaybe 0 mCursor
      limit  = fromMaybe 100 mLimit
  history  <- liftIO $ historyFrom (envLogBroadcaster env) cursor
  let entries  = toList history
      filtered = filter (matchesLog mSev mComp mTrace . snd) entries
      total    = length filtered
      page     = take limit filtered
      nextCur  = if total > limit && not (null page)
                   then Just (fst (last page) + 1)
                   else Nothing
  pure LogPage
    { lpEntries    = map snd page
    , lpNextCursor = nextCur
    , lpTotal      = total
    }

matchesLog :: Maybe Text -> Maybe Text -> Maybe Text -> LogEvent -> Bool
matchesLog mSev mComp mTrace le =
     maybe True (== leSeverity  le) mSev
  && maybe True (== leComponent le) mComp
  && maybe True (\t -> leTraceId le == Just t) mTrace

logStreamHandler
  :: AppEnv -> Maybe Text -> Maybe Int64 -> Tagged Handler Application
logStreamHandler env mHeader mCursor = Tagged $ \req sendResp -> do
  result <- runHandler (authCtx env mHeader)
  case result of
    Left err -> sendResp $ responseLBS status401 [] (errBody err)
    Right ctx ->
      if capCanViewAdminDashboard (capabilitiesForRole (auRole (scUser ctx)))
        then sseStream (envLogBroadcaster env) mCursor req sendResp
        else sendResp $ responseLBS status403 [] "Forbidden"

eventStreamHandler
  :: AppEnv -> Maybe Text -> Maybe Int64 -> Tagged Handler Application
eventStreamHandler env mHeader mCursor = Tagged $ \req sendResp -> do
  result <- runHandler (authCtx env mHeader)
  case result of
    Left err -> sendResp $ responseLBS status401 [] (errBody err)
    Right ctx ->
      if capCanViewAdminDashboard (capabilitiesForRole (auRole (scUser ctx)))
        then sseStream (envDomainBroadcaster env) mCursor req sendResp
        else sendResp $ responseLBS status403 [] "Forbidden"

transactionsHandler
  :: AppEnv -> Maybe Text -> Maybe TransactionStatus -> Maybe Int -> Handler TransactionPage
transactionsHandler env mHeader mStatus mLimit = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  txs <- liftIO $ DBT.getAllTransactions (envDbPool env)
  let filtered = maybe txs (\s -> filter ((== s) . transactionStatus) txs) mStatus
      lim      = fromMaybe 50 mLimit
      total    = length filtered
      page     = take lim filtered
      nextCur  = if total > lim && not (null page)
                   then Just (transactionId (last page))
                   else Nothing
  pure TransactionPage
    { tpTransactions = page
    , tpNextCursor   = nextCur
    , tpTotal        = total
    }

transactionDetailHandler :: AppEnv -> UUID -> Maybe Text -> Handler TransactionDetail
transactionDetailHandler env txId mHeader = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  mTx <- liftIO $ DBT.getTransactionById (envDbPool env) txId
  case mTx of
    Nothing -> throwError err404 { errBody = LBS.pack "Transaction not found" }
    Just tx -> do
      events <- liftIO $ DBE.queryDomainEvents (envDbPool env) (Just txId) Nothing Nothing 100
      pure TransactionDetail
        { tdTransaction  = tx
        , tdDomainEvents = events
        }

registersHandler :: AppEnv -> Maybe Text -> Handler [Register]
registersHandler env mHeader = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  liftIO $ DBT.getAllRegisters (envDbPool env)

domainEventsHandler
  :: AppEnv
  -> Maybe Text
  -> Maybe UUID -> Maybe Text -> Maybe Int64 -> Maybe Int
  -> Handler DomainEventPage
domainEventsHandler env mHeader mAggId mTraceId mCursor mLimit = do
  ctx <- authCtx env mHeader
  requireAdmin ctx
  let lim = fromMaybe 50 mLimit
  events <- liftIO $ DBE.queryDomainEvents (envDbPool env) mAggId mTraceId mCursor lim
  pure DomainEventPage
    { depEvents     = events
    , depNextCursor = if length events == lim && not (null events)
                        then Just (derSeq (last events) + 1)
                        else Nothing
    , depTotal      = length events
    }

actionsHandler :: AppEnv -> Maybe Text -> AdminAction -> Handler MutationResponse
actionsHandler env mHeader action = do
  ctx <- authCtx env mHeader
  requireAdminActions ctx
  let actorId = auUserId (scUser ctx)
  now <- liftIO getCurrentTime
  case action of
    RevokeSession sessionId -> do
      mSess <- liftIO $ DBA.getSessionById (envDbPool env) sessionId
      liftIO $ DBA.revokeSession (envDbPool env) sessionId (Just actorId)
      case mSess of
        Just sess ->
          liftIO $ publish (envDomainBroadcaster env) $ SessionEvt SessionRevoked
            { sesUserId    = sessUserId sess
            , sesActorId   = actorId
            , sesTimestamp = now
            }
        Nothing -> pure ()
      liftIO $ logAppInfo (envLogEnv env) $
        "Admin action: RevokeSession " <> T.pack (show sessionId)
      pure $ MutationResponse True "Session revoked"

    ClearRateLimitForIp ip -> do
      liftIO $ DBA.clearRateLimitForIp (envDbPool env) ip
      liftIO $ logAppInfo (envLogEnv env) $
        "Admin action: ClearRateLimitForIp " <> ip
      pure $ MutationResponse True ("Rate limit cleared for " <> ip)

    ForceCloseRegister _ _ ->
      pure $ MutationResponse False "Not yet implemented"

    SetLowStockThreshold _ ->
      pure $ MutationResponse False "Not yet implemented"

    TriggerSnapshotExport ->
      pure $ MutationResponse False "Not yet implemented"

-- ---------------------------------------------------------------------------
-- Server
-- ---------------------------------------------------------------------------

adminServerImpl :: AppEnv -> Server AdminAPI
adminServerImpl env =
       snapshotHandler       env
  :<|> sessionsHandler       env
  :<|> revokeSessionHandler  env
  :<|> logsHandler           env
  :<|> logStreamHandler      env
  :<|> eventStreamHandler    env
  :<|> transactionsHandler   env
  :<|> transactionDetailHandler env
  :<|> registersHandler      env
  :<|> domainEventsHandler   env
  :<|> actionsHandler        env