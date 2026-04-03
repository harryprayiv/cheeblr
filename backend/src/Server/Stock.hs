{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE DataKinds  #-}


module Server.Stock
  ( stockServerImpl
  ) where

import           Control.Monad              (unless)
import           Control.Monad.IO.Class     (liftIO)
import qualified Data.ByteString.Lazy.Char8 as LBS
import           Data.Maybe                 (fromMaybe)
import           Data.Text                  (Text, pack)
import           Data.UUID                  (UUID)
import           Data.UUID.V4               (nextRandom)
import           Effectful                  (runEff, Eff, IOE)
import           Effectful.Error.Static     (runErrorNoCallStack, Error)
import           Servant                    hiding (throwError)
import qualified Servant

import           API.Stock
import           Auth.Session               (SessionContext (..), resolveSession)
import qualified DB.Stock                  as DBS
import           Effect.Clock               (runClockIO, Clock)
import           Effect.EventEmitter        (runEventEmitterProd, EventEmitter)
import           Effect.StockDb             (runStockDbIO, StockDb)
import qualified Service.Stock             as Svc
import           Server.Env                 (AppEnv (..))
import           Types.Auth
  ( AuthenticatedUser (..)
  , capabilitiesForRole
  , capCanFulfillOrders
  )
import           Types.Inventory            (MutationResponse (..))
import           Types.Location             (LocationId (..))
import           Types.Stock
import Network.Wai (responseLBS)
import           Network.HTTP.Types        (status200)

authCtx :: AppEnv -> Maybe Text -> Handler SessionContext
authCtx env = resolveSession (envDbPool env)

requireStock :: SessionContext -> Handler ()
requireStock ctx =
  unless (capCanFulfillOrders (capabilitiesForRole (auRole (scUser ctx)))) $
    Servant.throwError err403 { errBody = LBS.pack "Forbidden: stock room access required" }

runStockEff :: AppEnv -> Effectful.Eff
  '[ Effect.StockDb.StockDb
   , Effect.Clock.Clock
   , Effect.EventEmitter.EventEmitter
   , Effectful.Error.Static.Error ServerError
   , Effectful.IOE
   ] a -> Handler a
runStockEff env action = do
  result <-
    liftIO
    . runEff
    . runErrorNoCallStack @ServerError
    . runEventEmitterProd
        (envDbPool env)
        (envDomainBroadcaster env)
        Nothing Nothing Nothing
    . runClockIO
    . runStockDbIO (envDbPool env)
    $ action
  either Servant.throwError pure result

queueHandler :: AppEnv -> Maybe Text -> Maybe LocationId -> Handler [PullRequest]
queueHandler env mHeader mLocId = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let locId = fromMaybe (LocationId (read "00000000-0000-0000-0000-000000000000")) mLocId
  liftIO $ DBS.getPendingPulls (envDbPool env) locId

queueStreamHandler :: AppEnv -> Maybe Text -> Maybe LocationId -> Maybe Int -> Tagged Handler Application
queueStreamHandler _env _mHeader _mLocId _mCursor = Tagged $ \_req sendResp ->
  sendResp $ responseLBS Network.HTTP.Types.status200 [] "SSE stream not yet implemented"

pullDetailHandler :: AppEnv -> UUID -> Maybe Text -> Handler PullRequestDetail
pullDetailHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  mPr <- liftIO $ DBS.getPullRequest (envDbPool env) pullId
  case mPr of
    Nothing -> Servant.throwError err404 { errBody = LBS.pack "Pull request not found" }
    Just pr -> do
      msgs <- liftIO $ DBS.getPullMessages (envDbPool env) pullId
      pure PullRequestDetail { pdPullRequest = pr, pdMessages = msgs }

acceptHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
acceptHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let actorId = auUserId (scUser ctx)
  _ <- runStockEff env (Svc.acceptPull pullId actorId)
  pure $ MutationResponse True "Pull request accepted"

startHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
startHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let actorId = auUserId (scUser ctx)
  _ <- runStockEff env (Svc.startPull pullId actorId)
  pure $ MutationResponse True "Pull started"

fulfillHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
fulfillHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let actorId = auUserId (scUser ctx)
  _ <- runStockEff env (Svc.fulfillPull pullId actorId)
  pure $ MutationResponse True "Pull fulfilled"

issueHandler :: AppEnv -> UUID -> Maybe Text -> IssueReport -> Handler MutationResponse
issueHandler env pullId mHeader report = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let actorId = auUserId (scUser ctx)
  _ <- runStockEff env (Svc.reportIssue pullId (irNote report) actorId)
  pure $ MutationResponse True "Issue reported"

retryHandler :: AppEnv -> UUID -> Maybe Text -> Handler MutationResponse
retryHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let actorId = auUserId (scUser ctx)
  _ <- runStockEff env (Svc.retryPull pullId actorId)
  pure $ MutationResponse True "Pull retried"

messageHandler :: AppEnv -> UUID -> Maybe Text -> NewMessage -> Handler MutationResponse
messageHandler env pullId mHeader msg = do
  ctx <- authCtx env mHeader
  requireStock ctx
  let senderId = auUserId (scUser ctx)
      role     = show (auRole (scUser ctx))
  msgId <- liftIO nextRandom
  let pm = PullMessage
        { pmId            = msgId
        , pmPullRequestId = pullId
        , pmFromRole      = fromString role
        , pmSenderId      = senderId
        , pmMessage       = nmMessage msg
        , pmCreatedAt     = read "2024-01-01 00:00:00 UTC"
        }
  liftIO $ DBS.insertPullMessage (envDbPool env) pullId pm
  pure $ MutationResponse True "Message added"
  where
    fromString = Data.Text.pack

messagesHandler :: AppEnv -> UUID -> Maybe Text -> Handler [PullMessage]
messagesHandler env pullId mHeader = do
  ctx <- authCtx env mHeader
  requireStock ctx
  liftIO $ DBS.getPullMessages (envDbPool env) pullId

stockServerImpl :: AppEnv -> Server StockAPI
stockServerImpl env =
       queueHandler     env
  :<|> queueStreamHandler env
  :<|> pullDetailHandler  env
  :<|> acceptHandler      env
  :<|> startHandler       env
  :<|> fulfillHandler     env
  :<|> issueHandler       env
  :<|> retryHandler       env
  :<|> messageHandler     env
  :<|> messagesHandler    env