{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Server.Stock (
  stockServerImpl,
  isStockEvent,
) where

import Control.Applicative ((<|>))
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Text (Text, pack)
import Data.Time (getCurrentTime)
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import Effectful (Eff, IOE, runEff)
import Effectful.Error.Static (Error, runErrorNoCallStack)
import Network.HTTP.Types.Status (status401, status403)
import Network.Wai (responseLBS)
import Servant hiding (throwError)
import qualified Servant

import API.Stock
import Auth.Session (SessionContext (..), resolveSession)
import qualified DB.Stock as DBS
import Effect.Clock (Clock, runClockIO)
import Effect.EventEmitter (EventEmitter, runEventEmitterProd)
import Effect.StockDb (StockDb, runStockDbIO)
import Infrastructure.SSE (filteredSseStream)
import Server.Env (AppEnv (..))
import qualified Service.Stock as Svc
import Types.Auth (
  AuthenticatedUser (..),
  capCanFulfillOrders,
  capabilitiesForRole,
 )
import Types.Events.Domain (DomainEvent (..))
import Types.Inventory (MutationResponse (..))
import Types.Location (LocationId (..))
import Types.Stock

authCtx :: AppEnv -> Maybe Text -> Handler SessionContext
authCtx env = resolveSession (envDbPool env)

requireStock :: SessionContext -> Handler ()
requireStock ctx =
  unless (capCanFulfillOrders (capabilitiesForRole (auRole (scUser ctx)))) $
    Servant.throwError err403 {errBody = LBS.pack "Forbidden: stock room access required"}

isStockEvent :: DomainEvent -> Bool
isStockEvent (StockEvt _) = True
isStockEvent _            = False

runStockEff ::
  AppEnv ->
  Eff
    '[ StockDb
     , Clock
     , EventEmitter
     , Error ServerError
     , IOE
     ]
    a ->
  Handler a
runStockEff env action = do
  result <-
    liftIO
      . runEff
      . runErrorNoCallStack @ServerError
      . runEventEmitterProd
          (envDbPool env)
          (envDomainBroadcaster env)
          Nothing
          Nothing
          Nothing
      . runClockIO
      . runStockDbIO (envDbPool env)
      $ action
  either Servant.throwError pure result

-- | Return pending pull requests for a location.
-- Resolution order for locationId:
--   1. Explicit query param (useful for admin/manager overrides)
--   2. The authenticated user's own location (normal stock room flow)
--   3. 400 if neither is available
queueHandler :: AppEnv -> Maybe Text -> Maybe LocationId -> Handler [PullRequest]
queueHandler env mHeader mLocId = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let mEffectiveLocId = mLocId <|> auLocationId (scUser ctx)
  case mEffectiveLocId of
    Nothing ->
      Servant.throwError
        err400
          { errBody =
              LBS.pack
                "locationId required: not provided in query and not set on user account"
          }
    Just locId ->
      liftIO $ DBS.getPendingPulls (envDbPool env) locId

queueStreamHandler ::
  AppEnv -> Maybe Text -> Maybe LocationId -> Maybe Int -> Tagged Handler Application
queueStreamHandler env mHeader _mLocId mCursor = Tagged $ \req sendResp -> do
  result <- runHandler (authCtx env mHeader)
  case result of
    Left err -> sendResp $ responseLBS status401 [] (errBody err)
    Right ctx ->
      if capCanFulfillOrders (capabilitiesForRole (auRole (scUser ctx)))
        then
          filteredSseStream
            isStockEvent
            (envDomainBroadcaster env)
            (fmap fromIntegral mCursor)
            req
            sendResp
        else sendResp $ responseLBS status403 [] "Forbidden"

pullDetailHandler :: AppEnv -> UUID -> Maybe Text -> Handler PullRequestDetail
pullDetailHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  mPr <- liftIO $ DBS.getPullRequest (envDbPool env) pullId
  case mPr of
    Nothing -> Servant.throwError err404 {errBody = LBS.pack "Pull request not found"}
    Just pr -> do
      msgs <- liftIO $ DBS.getPullMessages (envDbPool env) pullId
      pure PullRequestDetail {pdPullRequest = pr, pdMessages = msgs}

acceptHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
acceptHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  _ <- runStockEff env (Svc.acceptPull pullId (auUserId (scUser ctx)))
  pure $ MutationResponse True "Pull request accepted"

startHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
startHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  _ <- runStockEff env (Svc.startPull pullId (auUserId (scUser ctx)))
  pure $ MutationResponse True "Pull started"

fulfillHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
fulfillHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  _ <- runStockEff env (Svc.fulfillPull pullId (auUserId (scUser ctx)))
  pure $ MutationResponse True "Pull fulfilled"

issueHandler :: AppEnv -> UUID -> Maybe Text -> IssueReport -> Handler MutationResponse
issueHandler env pullId mHeader report = do
  ctx <- authCtx env mHeader
  requireStock ctx
  _ <- runStockEff env (Svc.reportIssue pullId (irNote report) (auUserId (scUser ctx)))
  pure $ MutationResponse True "Issue reported"

retryHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
retryHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  _ <- runStockEff env (Svc.retryPull pullId (auUserId (scUser ctx)))
  pure $ MutationResponse True "Pull retried"

messageHandler :: AppEnv -> UUID -> Maybe Text -> NewMessage -> Handler MutationResponse
messageHandler env pullId mHeader msg = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let
    senderId = auUserId (scUser ctx)
    role     = pack $ show (auRole (scUser ctx))
  msgId <- liftIO nextRandom
  now   <- liftIO getCurrentTime
  let pm =
        PullMessage
          { pmId            = msgId
          , pmPullRequestId = pullId
          , pmFromRole      = role
          , pmSenderId      = senderId
          , pmMessage       = nmMessage msg
          , pmCreatedAt     = now
          }
  liftIO $ DBS.insertPullMessage (envDbPool env) pullId pm
  pure $ MutationResponse True "Message added"

messagesHandler :: AppEnv -> UUID -> Maybe Text -> Handler [PullMessage]
messagesHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  liftIO $ DBS.getPullMessages (envDbPool env) pullId

stockServerImpl :: AppEnv -> Server StockAPI
stockServerImpl env =
  queueHandler env
    :<|> queueStreamHandler env
    :<|> pullDetailHandler env
    :<|> acceptHandler env
    :<|> startHandler env
    :<|> fulfillHandler env
    :<|> issueHandler env
    :<|> retryHandler env
    :<|> messageHandler env
    :<|> messagesHandler env