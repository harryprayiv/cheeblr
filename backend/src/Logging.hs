-- {-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Logging
  ( -- * Setup
    initLogging
  , closeLogging
    -- * Context
  , LogCtx (..)
  , LogOutcome (..)
  , makeLogCtx
  , empLogCtx
    -- * HTTP
  , logHttpRequest
  , logHttpRequestTimed
  , startTimer
    -- * Inventory
  , logInventoryRead
  , logInventoryCreate
  , logInventoryUpdate
  , logInventoryDelete
    -- * Transaction
  , logTransactionCreate
  , logTransactionAddItem
  , logTransactionAddPayment
  , logTransactionFinalize
  , logTransactionVoid
  , logTransactionRefund
  , logTransactionClear
    -- * Register
  , logRegisterCreate
  , logRegisterOpen
  , logRegisterClose
    -- * Session / Auth
  , logSessionAccess
  , logAuthDenied
    -- * App
  , logAppStartup
  , logAppShutdown
  , logAppInfo
  , logAppWarn
  , logDbError
  ) where

import Control.Monad    (void)
import Data.Aeson        (ToJSON (..), object, (.=))
import Data.Maybe        (catMaybes, fromMaybe)
import Data.Text         (Text)
import qualified Data.Text as T
import Data.Time         (UTCTime, diffUTCTime, getCurrentTime)
import Data.UUID         (UUID)
import GHC.Generics      (Generic)
import Katip
import System.IO         (BufferMode (..), IOMode (..), hSetBuffering, openFile, stdout)
import Types.Auth        (UserRole)

-- ─── Structured payload ───────────────────────────────────────────────────────
--
-- Every log entry carries this payload in the JSON file scribe.
-- Compliance officers query on action, outcome, and resourceId.

data CheeblrPayload = CheeblrPayload
  { plAction      :: Text
  , plOutcome     :: Text
  , plUserId      :: Maybe Text
  , plUserRole    :: Maybe Text
  , plResourceId  :: Maybe Text
  , plAmountCents :: Maybe Int
  , plDetails     :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON CheeblrPayload where
  toJSON p = object $ catMaybes
    [ Just  ("action"       .= plAction p)
    , Just  ("outcome"      .= plOutcome p)
    , fmap  ("userId"       .=) (plUserId p)
    , fmap  ("userRole"     .=) (plUserRole p)
    , fmap  ("resourceId"   .=) (plResourceId p)
    , fmap  ("amountCents"  .=) (plAmountCents p)
    , fmap  ("details"      .=) (plDetails p)
    ]

instance ToObject CheeblrPayload

instance LogItem CheeblrPayload where
  -- V3 (file scribe): everything for compliance / audit trail
  payloadKeys V3 _ = AllKeys
  -- V2 (stdout scribe): just the operationally useful fields
  payloadKeys V2 _ = SomeKeys ["action", "userId", "outcome", "resourceId"]
  payloadKeys _  _ = SomeKeys ["action", "outcome"]

-- ─── Context ─────────────────────────────────────────────────────────────────

data LogOutcome
  = LogSuccess
  | LogFailure Text
  deriving (Show, Eq)

-- | Per-request logging context.  Build one at the top of each handler.
data LogCtx = LogCtx
  { lcEnv    :: LogEnv
  , lcUserId :: Text   -- X-User-Id header value, or UUID of employee
  , lcRole   :: Text   -- show UserRole
  }

-- | Build from the optional X-User-Id header and the resolved role.
makeLogCtx :: LogEnv -> Maybe Text -> UserRole -> LogCtx
makeLogCtx le mUid role = LogCtx
  { lcEnv    = le
  , lcUserId = fromMaybe "anonymous" mUid
  , lcRole   = T.pack (show role)
  }

-- | Build from a concrete employee UUID (used in POS endpoints that carry no
--   auth header but do carry an employee ID in the request body).
empLogCtx :: LogEnv -> UUID -> LogCtx
empLogCtx le empId = LogCtx le (showUUID empId) "employee"

-- ─── Init / teardown ─────────────────────────────────────────────────────────

-- | Initialise two scribes:
--   * stdout  – human-readable bracket format at V2 verbosity
--   * file    – newline-delimited JSON at V3 verbosity for compliance tooling
initLogging :: FilePath -> IO LogEnv
initLogging logFilePath = do
  fh <- openFile logFilePath AppendMode
  hSetBuffering fh LineBuffering

  stdoutScribe <- mkHandleScribeWithFormatter
    bracketFormat ColorIfTerminal stdout (permitItem InfoS) V2
  fileScribe   <- mkHandleScribeWithFormatter
    jsonFormat (ColorLog False) fh (permitItem InfoS) V3

  le  <- initLogEnv "cheeblr" "production"
  le' <- registerScribe "stdout"     stdoutScribe defaultScribeSettings le
  registerScribe     "compliance"  fileScribe   defaultScribeSettings le'

closeLogging :: LogEnv -> IO ()
closeLogging le = void $ closeScribes le

-- ─── Internal plumbing ───────────────────────────────────────────────────────

runLog :: LogEnv -> Namespace -> KatipContextT IO a -> IO a
runLog le ns = runKatipContextT le (mempty :: SimpleLogPayload) ns

emit :: LogEnv -> Namespace -> Severity -> CheeblrPayload -> Text -> IO ()
emit le ns sev payload msg =
  runLog le ns $
    katipAddContext payload $
      logFM sev (logStr msg)

mkPL
  :: Text          -- userId
  -> Text          -- role
  -> Text          -- action
  -> Maybe Text    -- resourceId
  -> LogOutcome
  -> Maybe Int     -- amountCents
  -> Maybe Text    -- details
  -> CheeblrPayload
mkPL uid role action res outcome amt dets = CheeblrPayload
  { plAction      = action
  , plOutcome     = outcomeText outcome
  , plUserId      = Just uid
  , plUserRole    = Just role
  , plResourceId  = res
  , plAmountCents = amt
  , plDetails     = dets
  }

outcomeText :: LogOutcome -> Text
outcomeText LogSuccess     = "success"
outcomeText (LogFailure e) = "failure: " <> e

outcomeSev :: LogOutcome -> Severity
outcomeSev LogSuccess         = InfoS
outcomeSev (LogFailure code)
  | "4" `T.isPrefixOf` code   = WarningS
  | otherwise                  = ErrorS

showUUID :: UUID -> Text
showUUID = T.pack . show

-- | Format an integer number of cents as "$D.CC".
fmtCents :: Int -> Text
fmtCents c =
  let sign = if c < 0 then "-" else ""
      ac   = abs c
      d    = ac `div` 100
      r    = ac `mod` 100
      cs   = if r < 10 then "0" <> T.pack (show r) else T.pack (show r)
  in sign <> "$" <> T.pack (show d) <> "." <> cs

-- ─── HTTP ────────────────────────────────────────────────────────────────────

logHttpRequest :: LogEnv -> Text -> Text -> Text -> IO ()
logHttpRequest le method path userId =
  runLog le "http" $
    logFM InfoS $ logStr $
      method <> " " <> path <> " userId=" <> userId

-- | Record the time before a handler runs, then pass the result to
--   logHttpRequestTimed to emit a single entry with the duration appended.
startTimer :: IO UTCTime
startTimer = getCurrentTime

logHttpRequestTimed :: LogEnv -> Text -> Text -> Text -> UTCTime -> IO ()
logHttpRequestTimed le method path userId t0 = do
  t1 <- getCurrentTime
  let ms = round (diffUTCTime t1 t0 * 1000) :: Int
  runLog le "http" $
    logFM InfoS $ logStr $
      method <> " " <> path <> " userId=" <> userId
      <> " durationMs=" <> T.pack (show ms)

-- ─── Inventory ───────────────────────────────────────────────────────────────

logInventoryRead :: LogCtx -> IO ()
logInventoryRead LogCtx{..} =
  emit lcEnv "inventory" InfoS
    (mkPL lcUserId lcRole "inventory.read" Nothing LogSuccess Nothing Nothing)
    ("Inventory read userId=" <> lcUserId)

logInventoryCreate :: LogCtx -> Text -> LogOutcome -> IO ()
logInventoryCreate LogCtx{..} sku outcome =
  emit lcEnv "inventory" (outcomeSev outcome)
    (mkPL lcUserId lcRole "inventory.create" (Just sku) outcome Nothing Nothing)
    ("INVENTORY CREATE sku=" <> sku <> " userId=" <> lcUserId
     <> " " <> outcomeText outcome)

logInventoryUpdate :: LogCtx -> Text -> LogOutcome -> IO ()
logInventoryUpdate LogCtx{..} sku outcome =
  emit lcEnv "inventory" (outcomeSev outcome)
    (mkPL lcUserId lcRole "inventory.update" (Just sku) outcome Nothing Nothing)
    ("INVENTORY UPDATE sku=" <> sku <> " userId=" <> lcUserId
     <> " " <> outcomeText outcome)

logInventoryDelete :: LogCtx -> Text -> LogOutcome -> IO ()
logInventoryDelete LogCtx{..} sku outcome =
  emit lcEnv "inventory" (outcomeSev outcome)
    (mkPL lcUserId lcRole "inventory.delete" (Just sku) outcome Nothing Nothing)
    ("INVENTORY DELETE sku=" <> sku <> " userId=" <> lcUserId
     <> " " <> outcomeText outcome)

-- ─── Transaction ─────────────────────────────────────────────────────────────

logTransactionCreate :: LogCtx -> UUID -> LogOutcome -> IO ()
logTransactionCreate LogCtx{..} txId outcome =
  emit lcEnv "transaction" (outcomeSev outcome)
    (mkPL lcUserId lcRole "transaction.create" (Just (showUUID txId)) outcome Nothing Nothing)
    ("Transaction created txId=" <> showUUID txId
     <> " empId=" <> lcUserId <> " " <> outcomeText outcome)

logTransactionAddItem :: LogCtx -> UUID -> UUID -> Int -> LogOutcome -> IO ()
logTransactionAddItem LogCtx{..} txId itemSku qty outcome =
  emit lcEnv "transaction" (outcomeSev outcome)
    (mkPL lcUserId lcRole "transaction.addItem" (Just (showUUID txId)) outcome Nothing
      (Just $ "sku=" <> showUUID itemSku <> " qty=" <> T.pack (show qty)))
    ("Item added txId=" <> showUUID txId
     <> " sku=" <> showUUID itemSku
     <> " qty=" <> T.pack (show qty)
     <> " " <> outcomeText outcome)

logTransactionAddPayment :: LogCtx -> UUID -> Int -> Text -> LogOutcome -> IO ()
logTransactionAddPayment LogCtx{..} txId amountCents method outcome =
  emit lcEnv "transaction" (outcomeSev outcome)
    (mkPL lcUserId lcRole "transaction.addPayment" (Just (showUUID txId)) outcome
      (Just amountCents) (Just $ "method=" <> method))
    ("Payment added txId=" <> showUUID txId
     <> " amount=" <> fmtCents amountCents
     <> " method=" <> method
     <> " " <> outcomeText outcome)

-- | Logged to the "compliance" namespace so it can be filtered independently.
logTransactionFinalize :: LogCtx -> UUID -> Int -> Int -> LogOutcome -> IO ()
logTransactionFinalize LogCtx{..} txId totalCents itemCount outcome =
  emit lcEnv "compliance" (outcomeSev outcome)
    (mkPL lcUserId lcRole "transaction.finalize" (Just (showUUID txId)) outcome
      (Just totalCents)
      (Just $ "items=" <> T.pack (show itemCount) <> " empId=" <> lcUserId))
    ("SALE COMPLETED txId=" <> showUUID txId
     <> " total=" <> fmtCents totalCents
     <> " items=" <> T.pack (show itemCount)
     <> " empId=" <> lcUserId
     <> " " <> outcomeText outcome)

-- | WarnS so voids surface in dashboards that filter out Info noise.
logTransactionVoid :: LogCtx -> UUID -> Text -> LogOutcome -> IO ()
logTransactionVoid LogCtx{..} txId reason outcome =
  emit lcEnv "compliance" WarningS
    (mkPL lcUserId lcRole "transaction.void" (Just (showUUID txId)) outcome
      Nothing (Just reason))
    ("TRANSACTION VOIDED txId=" <> showUUID txId
     <> " reason=" <> reason
     <> " empId=" <> lcUserId
     <> " " <> outcomeText outcome)

-- | WarnS so refunds surface alongside voids.
logTransactionRefund :: LogCtx -> UUID -> Text -> LogOutcome -> IO ()
logTransactionRefund LogCtx{..} txId reason outcome =
  emit lcEnv "compliance" WarningS
    (mkPL lcUserId lcRole "transaction.refund" (Just (showUUID txId)) outcome
      Nothing (Just reason))
    ("REFUND ISSUED txId=" <> showUUID txId
     <> " reason=" <> reason
     <> " empId=" <> lcUserId
     <> " " <> outcomeText outcome)

logTransactionClear :: LogCtx -> UUID -> LogOutcome -> IO ()
logTransactionClear LogCtx{..} txId outcome =
  emit lcEnv "transaction" InfoS
    (mkPL lcUserId lcRole "transaction.clear" (Just (showUUID txId)) outcome Nothing Nothing)
    ("Transaction cleared txId=" <> showUUID txId
     <> " empId=" <> lcUserId)

-- ─── Register ────────────────────────────────────────────────────────────────

logRegisterCreate :: LogCtx -> UUID -> LogOutcome -> IO ()
logRegisterCreate LogCtx{..} regId outcome =
  emit lcEnv "register" (outcomeSev outcome)
    (mkPL lcUserId lcRole "register.create" (Just (showUUID regId)) outcome Nothing Nothing)
    ("Register created regId=" <> showUUID regId
     <> " empId=" <> lcUserId
     <> " " <> outcomeText outcome)

-- | Cash-control event: logged to "compliance".
logRegisterOpen :: LogCtx -> UUID -> Int -> LogOutcome -> IO ()
logRegisterOpen LogCtx{..} regId startCash outcome =
  emit lcEnv "compliance" (outcomeSev outcome)
    (mkPL lcUserId lcRole "register.open" (Just (showUUID regId)) outcome
      (Just startCash) Nothing)
    ("REGISTER OPENED regId=" <> showUUID regId
     <> " startingCash=" <> fmtCents startCash
     <> " empId=" <> lcUserId
     <> " " <> outcomeText outcome)

-- | Non-zero variance is elevated to WarnS for management review.
logRegisterClose :: LogCtx -> UUID -> Int -> Int -> LogOutcome -> IO ()
logRegisterClose LogCtx{..} regId countedCash variance outcome =
  let sev = if variance /= 0 then WarningS else InfoS
  in emit lcEnv "compliance" sev
       (mkPL lcUserId lcRole "register.close" (Just (showUUID regId)) outcome
         (Just countedCash)
         (Just $ "variance=" <> fmtCents variance))
       ("REGISTER CLOSED regId=" <> showUUID regId
        <> " countedCash=" <> fmtCents countedCash
        <> " variance=" <> fmtCents variance
        <> " empId=" <> lcUserId
        <> " " <> outcomeText outcome)

-- ─── Session / Auth ──────────────────────────────────────────────────────────

logSessionAccess :: LogCtx -> IO ()
logSessionAccess LogCtx{..} =
  emit lcEnv "session" InfoS
    (mkPL lcUserId lcRole "session.read" Nothing LogSuccess Nothing Nothing)
    ("Session accessed userId=" <> lcUserId <> " role=" <> lcRole)

logAuthDenied :: LogEnv -> Text -> Text -> IO ()
logAuthDenied le userId reason =
  runLog le "auth" $
    logFM WarningS $ logStr $
      "AUTH DENIED userId=" <> userId <> " reason=" <> reason

-- ─── App lifecycle ───────────────────────────────────────────────────────────

logAppStartup :: LogEnv -> Int -> Bool -> IO ()
logAppStartup le port tls =
  runLog le "app" $
    logFM InfoS $ logStr $
      "Cheeblr starting on port " <> T.pack (show port)
      <> if tls then " [TLS]" else " [HTTP]"

logAppShutdown :: LogEnv -> IO ()
logAppShutdown le =
  runLog le "app" $
    logFM InfoS (logStr ("Cheeblr shutting down" :: Text))

logAppInfo :: LogEnv -> Text -> IO ()
logAppInfo le msg =
  runLog le "app" $ logFM InfoS (logStr msg)

logAppWarn :: LogEnv -> Text -> IO ()
logAppWarn le msg =
  runLog le "app" $ logFM WarningS (logStr msg)

logDbError :: LogEnv -> Text -> Text -> IO ()
logDbError le context errText =
  runLog le "db" $
    logFM ErrorS $ logStr $
      "DB error in " <> context <> ": " <> errText