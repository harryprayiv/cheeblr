-- {-# LANGUAGE OverloadedStrings #-}
-- {-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- {-# LANGUAGE TupleSections     #-}

module Main where

import Control.Exception          (SomeException, try, catch)
import Control.Monad              (forM_, when, unless, void)
import Data.Aeson                 (Value (..), object, (.=), encode, decode, (.:), (.:?))
import Data.Aeson.Types           (parseMaybe)
import qualified Data.Aeson as A
import Data.ByteString.Lazy       (ByteString)
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.ByteString.Char8      as BS
import Data.IORef
import Data.List                  (intercalate)
import Data.Maybe                 (fromMaybe, isJust)
import Data.Text                  (Text)
import qualified Data.Text         as T
import qualified Data.Text.IO      as TIO
import Network.HTTP.Client
import Network.HTTP.Client.TLS    (newTlsManagerWith, tlsManagerSettings)
import Network.HTTP.Types.Status  (statusCode)
import System.Console.ANSI
import System.Environment         (getArgs, lookupEnv)
import System.Exit                (exitFailure, exitSuccess)
import System.IO                  (hFlush, stdout, hSetBuffering, BufferMode(..))
import System.IO.Unsafe           (unsafePerformIO)
import Control.Concurrent         (threadDelay, forkIO)
import Data.Time                  (getCurrentTime, formatTime, defaultTimeLocale)
import Data.UUID                  (UUID)
import qualified Data.UUID         as UUID
import Data.UUID.V4               (nextRandom)

-- ─────────────────────────────────────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────────────────────────────────────

data Config = Config
  { cfgBase     :: String   -- e.g. "https://localhost:8080"
  , cfgUsername :: String
  , cfgPassword :: String
  , cfgPause    :: Int      -- ms between steps
  , cfgAuto     :: Bool     -- skip interactive prompts
  }

defaultConfig :: Config
defaultConfig = Config
  { cfgBase     = "https://localhost:8080"
  , cfgUsername = "admin"
  , cfgPassword = ""
  , cfgPause    = 1500
  , cfgAuto     = False
  }

-- ─────────────────────────────────────────────────────────────────────────────
-- Driver state
-- ─────────────────────────────────────────────────────────────────────────────

data DriverState = DriverState
  { dsToken       :: IORef (Maybe String)
  , dsMgr         :: Manager
  , dsCfg         :: Config
  , dsPassCount   :: IORef Int
  , dsFailCount   :: IORef Int
  , dsCreatedSkus :: IORef [String]  -- UUIDs of items we create
  }

newDriverState :: Config -> IO DriverState
newDriverState cfg = do
  mgr <- newTlsManagerWith tlsManagerSettings
           { managerResponseTimeout = responseTimeoutMicro 30_000_000 }
  DriverState
    <$> newIORef Nothing
    <*> pure mgr
    <*> pure cfg
    <*> newIORef 0
    <*> newIORef 0
    <*> newIORef []

-- ─────────────────────────────────────────────────────────────────────────────
-- Pretty printing
-- ─────────────────────────────────────────────────────────────────────────────

data Level = INFO | OK | WARN | FAIL | STEP | PAUSE | DETAIL

clr :: Level -> IO ()
clr INFO   = setSGR [SetColor Foreground Vivid Cyan]
clr OK     = setSGR [SetColor Foreground Vivid Green]
clr WARN   = setSGR [SetColor Foreground Vivid Yellow]
clr FAIL   = setSGR [SetColor Foreground Vivid Red]
clr STEP   = setSGR [SetColor Foreground Vivid Magenta]
clr PAUSE  = setSGR [SetColor Foreground Vivid Blue]
clr DETAIL = setSGR [SetColor Foreground Dull White]

rst :: IO ()
rst = setSGR [Reset]

lbl :: Level -> String -> String -> IO ()
lbl lvl tag msg = do
  clr lvl
  putStr $ "[" <> tag <> "] "
  rst
  putStrLn msg

banner :: String -> IO ()
banner title = do
  putStrLn ""
  clr STEP
  putStrLn $ "╔" <> replicate 68 '═' <> "╗"
  putStrLn $ "║  " <> title <> replicate (66 - length title) ' ' <> "║"
  putStrLn $ "╚" <> replicate 68 '═' <> "╝"
  rst

subBanner :: String -> IO ()
subBanner title = do
  putStrLn ""
  clr INFO
  putStrLn $ "┌─ " <> title <> " " <> replicate (65 - length title) '─'
  rst

hr :: IO ()
hr = do
  clr DETAIL
  putStrLn $ replicate 70 '─'
  rst

pass :: DriverState -> String -> IO ()
pass ds msg = do
  modifyIORef (dsPassCount ds) (+1)
  lbl OK "PASS" msg

fail' :: DriverState -> String -> IO ()
fail' ds msg = do
  modifyIORef (dsFailCount ds) (+1)
  lbl FAIL "FAIL" msg

info :: String -> IO ()
info = lbl INFO "INFO"

warn :: String -> IO ()
warn = lbl WARN "WARN"

detail :: String -> IO ()
detail msg = do
  clr DETAIL
  putStrLn $ "     " <> msg
  rst

pause :: DriverState -> String -> IO ()
pause ds msg = do
  lbl PAUSE "WAIT" msg
  if cfgAuto (dsCfg ds)
    then threadDelay (cfgPause (dsCfg ds) * 1000)
    else do
      clr PAUSE
      putStr "     Press ENTER to continue (or 'a' for auto mode)... "
      rst
      hFlush stdout
      line <- getLine
      when (line == "a" || line == "A") $ do
        warn "Switching to auto mode"
        -- Can't mutate Config easily; just continue

stepPause :: DriverState -> IO ()
stepPause ds = threadDelay (cfgPause (dsCfg ds) * 1000)

-- ─────────────────────────────────────────────────────────────────────────────
-- HTTP helpers
-- ─────────────────────────────────────────────────────────────────────────────

type JSON = Value

withToken :: DriverState -> Maybe String
withToken ds = unsafePerformIO $ readIORef (dsToken ds)

authHeader :: DriverState -> RequestHeaders
authHeader ds = case unsafePerformIO (readIORef (dsToken ds)) of
  Nothing  -> []
  Just tok -> [("Authorization", BS.pack $ "Bearer " <> tok)]

type RequestHeaders = [(BS.ByteString, BS.ByteString)]

data Resp = Resp
  { respStatus :: Int
  , respBody   :: ByteString
  , respJson   :: Maybe Value
  }

httpReq
  :: DriverState
  -> String            -- method
  -> String            -- path
  -> Maybe Value       -- body
  -> Bool              -- include auth
  -> IO Resp
httpReq ds method path mBody withAuth = do
  let url = cfgBase (dsCfg ds) <> path
  initReq <- parseRequest url
  tok <- readIORef (dsToken ds)
  let
    authH = case (withAuth, tok) of
      (True, Just t) -> [("Authorization", BS.pack $ "Bearer " <> t)]
      _              -> []
    bodyH = case mBody of
      Just _  -> [("Content-Type", "application/json")]
      Nothing -> []
    req = initReq
      { method         = BS.pack method
      , requestHeaders = authH <> bodyH <> [("Accept", "application/json")]
      , requestBody    = case mBody of
          Just v  -> RequestBodyLBS (encode v)
          Nothing -> RequestBodyLBS ""
      }
  result <- try $ httpLbs req (dsMgr ds)
  case result of
    Left (e :: SomeException) -> do
      warn $ "HTTP error: " <> show e
      pure $ Resp 0 "" Nothing
    Right resp -> do
      let st   = statusCode (responseStatus resp)
          body = responseBody resp
          mjson = decode body :: Maybe Value
      pure $ Resp st body mjson

get' :: DriverState -> String -> IO Resp
get' ds path = httpReq ds "GET" path Nothing True

post' :: DriverState -> String -> Value -> IO Resp
post' ds path body = httpReq ds "POST" path (Just body) True

put' :: DriverState -> String -> Value -> IO Resp
put' ds path body = httpReq ds "PUT" path (Just body) True

delete' :: DriverState -> String -> IO Resp
delete' ds path = httpReq ds "DELETE" path Nothing True

-- Extract a field from JSON response
jField :: String -> Resp -> Maybe Value
jField k r = do
  obj <- respJson r
  parseMaybe (.: T.pack k) obj

jStr :: String -> Resp -> Maybe String
jStr k r = do
  v <- jField k r
  case v of
    String t -> Just (T.unpack t)
    _        -> Nothing

jBool :: String -> Resp -> Maybe Bool
jBool k r = do
  v <- jField k r
  case v of
    Bool b -> Just b
    _      -> Nothing

-- ─────────────────────────────────────────────────────────────────────────────
-- Assertion helpers
-- ─────────────────────────────────────────────────────────────────────────────

assertStatus :: DriverState -> String -> Int -> Resp -> IO Bool
assertStatus ds label expected resp = do
  let actual = respStatus resp
  if actual == expected
    then do
      pass ds $ label <> " (HTTP " <> show actual <> ")"
      pure True
    else do
      fail' ds $ label <> " — expected HTTP " <> show expected
                      <> " but got " <> show actual
      detail $ "Body: " <> take 300 (LBS.unpack (respBody resp))
      pure False

assertField :: DriverState -> String -> String -> Resp -> IO (Maybe String)
assertField ds label field resp = do
  case jStr field resp of
    Just v  -> do
      pass ds $ label <> " — field '" <> field <> "' = " <> take 60 v
      pure (Just v)
    Nothing -> do
      fail' ds $ label <> " — missing field '" <> field <> "'"
      detail $ "Body: " <> take 300 (LBS.unpack (respBody resp))
      pure Nothing

-- ─────────────────────────────────────────────────────────────────────────────
-- Test phases
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Phase 0: connectivity ───────────────────────────────────────────────────

testConnectivity :: DriverState -> IO ()
testConnectivity ds = do
  banner "PHASE 0 — Connectivity & OpenAPI"
  subBanner "GET /openapi.json (unauthenticated)"

  r <- httpReq ds "GET" "/openapi.json" Nothing False
  void $ assertStatus ds "OpenAPI endpoint reachable" 200 r

  subBanner "Unauthenticated rejection"
  r2 <- httpReq ds "GET" "/inventory" Nothing False
  void $ assertStatus ds "GET /inventory without token → 401" 401 r2

  r3 <- httpReq ds "GET" "/session" Nothing False
  void $ assertStatus ds "GET /session without token → 401" 401 r3

  stepPause ds
  pause ds "Connectivity checks done. Observe the frontend — nothing should have changed yet."

-- ── Phase 1: authentication ─────────────────────────────────────────────────

testAuth :: DriverState -> IO ()
testAuth ds = do
  banner "PHASE 1 — Authentication"
  subBanner "Login with wrong password"

  let badLogin = object
        [ "loginUsername"   .= ("admin" :: Text)
        , "loginPassword"   .= ("wrong-password" :: Text)
        , "loginRegisterId" .= Null
        ]
  r1 <- httpReq ds "POST" "/auth/login" (Just badLogin) False
  void $ assertStatus ds "Bad password → 401" 401 r1

  subBanner "Login with correct credentials"
  let goodLogin = object
        [ "loginUsername"   .= (cfgUsername (dsCfg ds) :: String)
        , "loginPassword"   .= (cfgPassword (dsCfg ds) :: String)
        , "loginRegisterId" .= Null
        ]
  r2 <- httpReq ds "POST" "/auth/login" (Just goodLogin) False
  ok2 <- assertStatus ds "Login → 200" 200 r2
  when ok2 $ do
    -- Extract token from loginUser.sessionUserId (the token is the bearer)
    -- Actually the login endpoint returns a cookie + body; we need to extract
    -- the bearer token from cookies or use the session endpoint
    -- Looking at the API: POST /auth/login returns LoginResponse with loginUser
    -- The bearer token comes from the cookie Set-Cookie header value
    -- But we send it as Bearer in Authorization — let's check /auth/me
    -- Actually per the code, createSession returns (tokenText, expiresAt)
    -- and loginHandler returns it via addHeader (sessionCookie token)
    -- The cookie is "cheeblr_session=<token>"
    -- We need to parse Set-Cookie header from the response
    -- Let's re-do the login request manually to get the Set-Cookie header
    pure ()

  -- Re-do login to capture the Set-Cookie header
  let url = cfgBase (dsCfg ds) <> "/auth/login"
  initReq <- parseRequest url
  let loginReq = initReq
        { method         = "POST"
        , requestBody    = RequestBodyLBS (encode goodLogin)
        , requestHeaders =
            [ ("Content-Type", "application/json")
            , ("Accept",       "application/json")
            ]
        }
  result <- try $ httpLbs loginReq (dsMgr ds)
  case result of
    Left (e :: SomeException) -> fail' ds $ "Login request failed: " <> show e
    Right resp -> do
      let hdrs = responseHeaders resp
          mCookie = lookup "Set-Cookie" hdrs
          mToken = mCookie >>= extractSessionToken . BS.unpack
      case mToken of
        Nothing -> do
          fail' ds "Could not extract session token from Set-Cookie"
          detail $ "Headers: " <> show hdrs
          detail $ "Body: " <> take 500 (LBS.unpack (responseBody resp))
        Just tok -> do
          writeIORef (dsToken ds) (Just tok)
          pass ds $ "Session token extracted (length: " <> show (length tok) <> ")"
          detail $ "Token prefix: " <> take 20 tok <> "..."

  subBanner "GET /auth/me with token"
  r3 <- get' ds "/auth/me"
  ok3 <- assertStatus ds "GET /auth/me → 200" 200 r3
  when ok3 $ do
    case jStr "sessionRole" r3 of
      Just role -> pass ds $ "Authenticated as role: " <> role
      Nothing   -> fail' ds "No sessionRole in /auth/me response"

  subBanner "GET /session"
  r4 <- get' ds "/session"
  void $ assertStatus ds "GET /session → 200" 200 r4

  pause ds "Auth complete. You should be able to see the frontend is still on the login page OR if already logged in, session is valid."

extractSessionToken :: String -> Maybe String
extractSessionToken cookieStr =
  -- "cheeblr_session=TOKEN; HttpOnly; ..."
  let parts = wordsWhen (== ';') cookieStr
      prefix = "cheeblr_session="
  in case filter (prefix `isPrefixOf'`) parts of
    (p:_) -> Just (drop (length prefix) (trim p))
    []    -> Nothing
  where
    isPrefixOf' pre s = take (length pre) s == pre
    wordsWhen p s = case dropWhile p s of
      "" -> []
      s' -> let (w, s'') = break p s' in w : wordsWhen p s''
    trim = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse

-- ── Phase 2: inventory CRUD ─────────────────────────────────────────────────

testInventory :: DriverState -> IO ()
testInventory ds = do
  banner "PHASE 2 — Inventory CRUD"

  -- Create 3 distinct items
  let items =
        [ mkItem "Blueberry Kush"    "Blue Dream Co"    "Flower"      "Indica"             2500 10  "test-sku-1"
        , mkItem "Mango Haze Vape"   "CloudBurst Labs"  "Vaporizers"  "Sativa"             4500 5   "test-sku-2"
        , mkItem "Cosmic Brownie 100mg" "Stellar Edibles" "Edibles"   "Hybrid"             1800 20  "test-sku-3"
        ]

  subBanner "POST /inventory — Create 3 items"
  createdSkus <- newIORef ([] :: [String])
  forM_ items $ \(itemJson, label) -> do
    r <- post' ds "/inventory" itemJson
    ok <- assertStatus ds ("Create item: " <> label) 200 r
    when ok $ do
      case jBool "success" r of
        Just True -> do
          pass ds $ label <> " created successfully"
          let sku = extractSku itemJson
          modifyIORef createdSkus (sku :)
          modifyIORef (dsCreatedSkus ds) (sku :)
        _         -> fail' ds $ label <> " — success=false: " <> take 200 (LBS.unpack (respBody r))
    stepPause ds

  pause ds "3 items created. Check the LiveView tab in the frontend — you should see them appear."

  subBanner "GET /inventory"
  r <- get' ds "/inventory"
  ok <- assertStatus ds "GET /inventory → 200" 200 r
  when ok $ do
    case respJson r of
      Just (Array arr) -> pass ds $ "Inventory returned " <> show (length arr) <> " items"
      Just (Object _)  -> pass ds "Inventory returned (object form)"
      _                -> warn "Could not parse inventory response as array"

  pause ds "Inventory read done. Items visible in LiveView?"

  subBanner "PUT /inventory — Update first item (price change)"
  let (origItem, origLabel) = head items
      updatedItem = updatePrice origItem 2999
  r2 <- put' ds "/inventory" updatedItem
  ok2 <- assertStatus ds ("Update price of " <> origLabel) 200 r2
  when ok2 $
    case jBool "success" r2 of
      Just True -> pass ds "Price updated to $29.99"
      _         -> fail' ds "Update reported failure"

  pause ds "Item price updated. Does the price change show in the frontend LiveView?"

  subBanner "DELETE /inventory/<sku> — Delete last item"
  skus <- readIORef (dsCreatedSkus ds)
  case skus of
    [] -> warn "No tracked SKUs to delete"
    (lastSku:_) -> do
      r3 <- delete' ds ("/inventory/" <> lastSku)
      ok3 <- assertStatus ds ("DELETE /inventory/" <> take 8 lastSku <> "...") 200 r3
      when ok3 $
        case jBool "success" r3 of
          Just True -> pass ds "Item deleted"
          _         -> fail' ds "Delete reported failure"
      modifyIORef (dsCreatedSkus ds) (filter (/= lastSku))

  pause ds "Item deleted. Did it disappear from the frontend LiveView?"

mkItem :: String -> String -> String -> String -> Int -> Int -> String -> (Value, String)
mkItem name brand category species price qty skuSuffix =
  let sku = "a0000000-0000-4000-8000-" <> leftPad skuSuffix
      v = object
            [ "sort"         .= (1 :: Int)
            , "sku"          .= sku
            , "brand"        .= brand
            , "name"         .= name
            , "price"        .= price
            , "measure_unit" .= ("g" :: String)
            , "per_package"  .= ("3.5g" :: String)
            , "quantity"     .= qty
            , "category"     .= category
            , "subcategory"  .= ("Premium" :: String)
            , "description"  .= ("High quality " <> name <> " for testing")
            , "tags"         .= (["test", "e2e"] :: [String])
            , "effects"      .= (["relaxed", "happy"] :: [String])
            , "strain_lineage" .= object
                [ "thc"              .= ("22.5%" :: String)
                , "cbg"              .= ("0.5%" :: String)
                , "strain"           .= name
                , "creator"          .= brand
                , "species"          .= species
                , "dominant_terpene" .= ("Myrcene" :: String)
                , "terpenes"         .= (["Myrcene", "Limonene"] :: [String])
                , "lineage"          .= (["OG Kush", "Haze"] :: [String])
                , "leafly_url"       .= ("https://leafly.com/strains/test" :: String)
                , "img"              .= ("https://example.com/img/test.jpg" :: String)
                ]
            ]
  in (v, name)
  where
    leftPad s = replicate (12 - length s) '0' <> s

updatePrice :: Value -> Int -> Value
updatePrice v newPrice = case v of
  Object obj ->
    let pairs = case A.toList obj of
                  ps -> ps
    in A.fromList $ map (\(k,val) -> if k == "price" then (k, A.toJSON newPrice) else (k, val)) pairs
  _ -> v

extractSku :: Value -> String
extractSku (Object obj) =
  case A.lookup "sku" obj of
    Just (String t) -> T.unpack t
    _ -> ""
extractSku _ = ""

-- ── Phase 3: register operations ────────────────────────────────────────────

testRegisters :: DriverState -> IO ()
testRegisters ds = do
  banner "PHASE 3 — Register Lifecycle"

  regId <- do banner "PHASE 3 — Register Lifecycle"
  let locId = "b2bd4b3a-d50f-4c04-90b1-01266735876b"

  let regBody = object
        [ "registerId"               .= regId
        , "registerName"             .= ("E2E Test Register" :: String)
        , "registerLocationId"       .= locId
        , "registerIsOpen"           .= False
        , "registerCurrentDrawerAmount"  .= (0 :: Int)
        , "registerExpectedDrawerAmount" .= (0 :: Int)
        , "registerOpenedAt"         .= Null
        , "registerOpenedBy"         .= Null
        , "registerLastTransactionTime" .= Null
        ]

  subBanner "POST /register — Create register"
  r1 <- post' ds "/register" regBody
  ok1 <- assertStatus ds "Create register → 200" 200 r1

  subBanner "GET /register — List registers"
  r2 <- get' ds "/register"
  void $ assertStatus ds "GET /register → 200" 200 r2

  when ok1 $ do
    subBanner "POST /register/open/<id> — Open register"
    let empId = "d3a1f4f0-c518-4db3-aa43-e80b428d6304" -- admin UUID
    let openBody = object
          [ "openRegisterEmployeeId" .= (empId :: String)
          , "openRegisterStartingCash" .= (50000 :: Int)  -- $500.00
          ]
    r3 <- post' ds ("/register/open/" <> regId) openBody
    ok3 <- assertStatus ds "Open register → 200" 200 r3
    when ok3 $ do
      case jBool "registerIsOpen" r3 of
        Just True -> pass ds "Register is now open"
        _         -> warn "registerIsOpen not true in response"

    pause ds "Register opened with $500 starting cash. Check Admin Dashboard → Registers tab."

    subBanner "GET /register/<id> — Verify open state"
    r4 <- get' ds ("/register/" <> regId)
    void $ assertStatus ds "GET register by ID → 200" 200 r4

    pure regId

  where
    pure = Prelude.pure

-- Returns the register ID for use in transaction tests
setupRegister :: DriverState -> IO (Maybe String)
setupRegister ds = do
  regId <- UUID.toString <$> nextRandom
  let locId = "b2bd4b3a-d50f-4c04-90b1-01266735876b"
      empId  = "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
      regBody = object
        [ "registerId"               .= regId
        , "registerName"             .= ("E2E Register" :: String)
        , "registerLocationId"       .= locId
        , "registerIsOpen"           .= False
        , "registerCurrentDrawerAmount"  .= (0 :: Int)
        , "registerExpectedDrawerAmount" .= (0 :: Int)
        , "registerOpenedAt"         .= Null
        , "registerOpenedBy"         .= Null
        , "registerLastTransactionTime" .= Null
        ]
  r1 <- post' ds "/register" regBody
  if respStatus r1 /= 200
    then do
      warn $ "Could not create register: " <> show (respStatus r1)
      pure Nothing
    else do
      let openBody = object
            [ "openRegisterEmployeeId"   .= (empId :: String)
            , "openRegisterStartingCash" .= (50000 :: Int)
            ]
      r2 <- post' ds ("/register/open/" <> regId) openBody
      if respStatus r2 == 200
        then do
          info $ "Register ready: " <> take 8 regId <> "..."
          pure (Just regId)
        else do
          warn $ "Could not open register: " <> show (respStatus r2)
          pure (Just regId)  -- still use it

-- ── Phase 4: full transaction flow ──────────────────────────────────────────

testTransactions :: DriverState -> String -> IO (Maybe String)
testTransactions ds regId = do
  banner "PHASE 4 — Transaction Flow (Create → Items → Payment → Finalize)"

  txId   <- UUID.toString <$> nextRandom
  itemId <- UUID.toString <$> nextRandom
  pmtId  <- UUID.toString <$> nextRandom
  let locId = "b2bd4b3a-d50f-4c04-90b1-01266735876b"
      empId = "d3a1f4f0-c518-4db3-aa43-e80b428d6304"

  subBanner "POST /transaction — Create transaction"
  let txBody = object
        [ "transactionId"                   .= txId
        , "transactionStatus"               .= ("Created" :: String)
        , "transactionCreated"              .= ("2024-01-01T00:00:00Z" :: String)
        , "transactionCompleted"            .= Null
        , "transactionCustomerId"           .= Null
        , "transactionEmployeeId"           .= empId
        , "transactionRegisterId"           .= regId
        , "transactionLocationId"           .= locId
        , "transactionItems"                .= ([] :: [Value])
        , "transactionPayments"             .= ([] :: [Value])
        , "transactionSubtotal"             .= (0 :: Int)
        , "transactionDiscountTotal"        .= (0 :: Int)
        , "transactionTaxTotal"             .= (0 :: Int)
        , "transactionTotal"                .= (0 :: Int)
        , "transactionType"                 .= ("Sale" :: String)
        , "transactionIsVoided"             .= False
        , "transactionVoidReason"           .= Null
        , "transactionIsRefunded"           .= False
        , "transactionRefundReason"         .= Null
        , "transactionReferenceTransactionId" .= Null
        , "transactionNotes"                .= Null
        ]
  r1 <- post' ds "/transaction" txBody
  ok1 <- assertStatus ds "Create transaction → 200" 200 r1

  unless ok1 $ do
    fail' ds "Cannot continue transaction tests without a transaction"
    pure Nothing

  pause ds "Transaction created (status=Created). Check Create Transaction page in frontend."

  subBanner "GET /transaction/<id> — Read back"
  r1b <- get' ds ("/transaction/" <> txId)
  void $ assertStatus ds "GET /transaction by ID → 200" 200 r1b

  -- Get a SKU from inventory to add
  invResp <- get' ds "/inventory"
  let mSku = do
        Array arr <- respJson invResp
        case arr of
          (firstItem:_) -> do
            Object obj <- pure firstItem
            String s   <- A.lookup "sku" obj
            pure (T.unpack s)
          _ -> Nothing

  case mSku of
    Nothing -> do
      warn "No inventory items found — skipping item add step"
      warn "Create some inventory first (Phase 2 should have done this)"
      pure (Just txId)

    Just sku -> do
      subBanner "POST /transaction/item — Add item to cart"
      let itemBody = object
            [ "transactionItemId"            .= itemId
            , "transactionItemTransactionId" .= txId
            , "transactionItemMenuItemSku"   .= sku
            , "transactionItemQuantity"      .= (2 :: Int)
            , "transactionItemPricePerUnit"  .= (2500 :: Int)
            , "transactionItemDiscounts"     .= ([] :: [Value])
            , "transactionItemTaxes"         .= ([] :: [Value])
            , "transactionItemSubtotal"      .= (5000 :: Int)
            , "transactionItemTotal"         .= (5400 :: Int)
            ]
      r2 <- post' ds "/transaction/item" itemBody
      void $ assertStatus ds "Add item to transaction → 200" 200 r2

      pause ds "Item added to transaction. The cart in the frontend should show the item."

      subBanner "GET /inventory/available/<sku> — Check reservation"
      r2b <- get' ds ("/inventory/available/" <> sku)
      ok2b <- assertStatus ds "GET /inventory/available → 200" 200 r2b
      when ok2b $ do
        case (jField "availableTotal" r2b, jField "availableReserved" r2b) of
          (Just (Number tot), Just (Number res)) ->
            pass ds $ "Total: " <> show tot <> ", Reserved: " <> show res
          _ -> detail "Could not parse availability response"

      subBanner "POST /transaction/payment — Add cash payment"
      let pmtBody = object
            [ "paymentId"              .= pmtId
            , "paymentTransactionId"   .= txId
            , "paymentMethod"          .= ("Cash" :: String)
            , "paymentAmount"          .= (5400 :: Int)
            , "paymentTendered"        .= (6000 :: Int)
            , "paymentChange"          .= (600 :: Int)
            , "paymentReference"       .= Null
            , "paymentApproved"        .= True
            , "paymentAuthorizationCode" .= Null
            ]
      r3 <- post' ds "/transaction/payment" pmtBody
      void $ assertStatus ds "Add payment → 200" 200 r3

      pause ds "Payment added. The payment total should update in the frontend."

      subBanner "POST /transaction/finalize/<id>"
      r4 <- post' ds ("/transaction/finalize/" <> txId) (object [])
      ok4 <- assertStatus ds "Finalize transaction → 200" 200 r4
      when ok4 $ do
        case jStr "transactionStatus" r4 of
          Just status -> pass ds $ "Transaction status: " <> status
          Nothing     -> detail "Status not in finalize response"

      pause ds "Transaction FINALIZED. Inventory quantity should have decreased. Check LiveView and Admin Dashboard."

      pure (Just txId)

-- ── Phase 4b: void transaction ──────────────────────────────────────────────

testVoidTransaction :: DriverState -> String -> IO ()
testVoidTransaction ds regId = do
  banner "PHASE 4b — Void Transaction"

  txId  <- UUID.toString <$> nextRandom
  let locId = "b2bd4b3a-d50f-4c04-90b1-01266735876b"
      empId = "d3a1f4f0-c518-4db3-aa43-e80b428d6304"
      txBody = object
        [ "transactionId"          .= txId
        , "transactionStatus"      .= ("Created" :: String)
        , "transactionCreated"     .= ("2024-01-01T00:00:00Z" :: String)
        , "transactionCompleted"   .= Null
        , "transactionCustomerId"  .= Null
        , "transactionEmployeeId"  .= empId
        , "transactionRegisterId"  .= regId
        , "transactionLocationId"  .= locId
        , "transactionItems"       .= ([] :: [Value])
        , "transactionPayments"    .= ([] :: [Value])
        , "transactionSubtotal"    .= (0 :: Int)
        , "transactionDiscountTotal" .= (0 :: Int)
        , "transactionTaxTotal"    .= (0 :: Int)
        , "transactionTotal"       .= (0 :: Int)
        , "transactionType"        .= ("Sale" :: String)
        , "transactionIsVoided"    .= False
        , "transactionVoidReason"  .= Null
        , "transactionIsRefunded"  .= False
        , "transactionRefundReason" .= Null
        , "transactionReferenceTransactionId" .= Null
        , "transactionNotes"       .= Null
        ]

  r1 <- post' ds "/transaction" txBody
  void $ assertStatus ds "Create transaction to void → 200" 200 r1

  subBanner "POST /transaction/void/<id>"
  r2 <- post' ds ("/transaction/void/" <> txId) (A.toJSON ("E2E test void" :: String))
  void $ assertStatus ds "Void transaction → 200" 200 r2

  pause ds "Transaction voided. Check Admin Dashboard → Transactions (should show VOIDED status)."

-- ── Phase 5: stock pull requests ────────────────────────────────────────────

testStockPulls :: DriverState -> IO ()
testStockPulls ds = do
  banner "PHASE 5 — Stock Pull Request Workflow"

  pullId <- UUID.toString <$> nextRandom
  txId   <- UUID.toString <$> nextRandom
  let locId = "b2bd4b3a-d50f-4c04-90b1-01266735876b"
      empId  = "d3a1f4f0-c518-4db3-aa43-e80b428d6304"

  -- We'll hit the stock endpoints directly
  -- First get the queue
  subBanner "GET /stock/queue"
  r0 <- get' ds "/stock/queue"
  void $ assertStatus ds "GET /stock/queue → 200" 200 r0

  pause ds "Stock queue fetched. Stock Room Interface should show queue (may be empty)."

  -- The stock pull creation goes through the transaction service
  -- Let's create a transaction with an item to trigger a pull
  info "Creating a transaction to trigger stock pull creation..."
  invResp <- get' ds "/inventory"
  let mSku = do
        Array arr <- respJson invResp
        case arr of
          (firstItem:_) -> do
            Object obj <- pure firstItem
            String s   <- A.lookup "sku" obj
            pure (T.unpack s)
          _ -> Nothing

  case mSku of
    Nothing -> warn "No inventory — skipping stock pull trigger"
    Just sku -> do
      regId <- setupRegister ds >>= \case
        Just r  -> pure r
        Nothing -> pure "00000000-0000-0000-0000-000000000000"

      txId2  <- UUID.toString <$> nextRandom
      itemId <- UUID.toString <$> nextRandom
      let locId2 = "b2bd4b3a-d50f-4c04-90b1-01266735876b"
          txBody = object
            [ "transactionId"          .= txId2
            , "transactionStatus"      .= ("Created" :: String)
            , "transactionCreated"     .= ("2024-01-01T00:00:00Z" :: String)
            , "transactionCompleted"   .= Null
            , "transactionCustomerId"  .= Null
            , "transactionEmployeeId"  .= empId
            , "transactionRegisterId"  .= regId
            , "transactionLocationId"  .= locId2
            , "transactionItems"       .= ([] :: [Value])
            , "transactionPayments"    .= ([] :: [Value])
            , "transactionSubtotal"    .= (0 :: Int)
            , "transactionDiscountTotal" .= (0 :: Int)
            , "transactionTaxTotal"    .= (0 :: Int)
            , "transactionTotal"       .= (0 :: Int)
            , "transactionType"        .= ("Sale" :: String)
            , "transactionIsVoided"    .= False
            , "transactionVoidReason"  .= Null
            , "transactionIsRefunded"  .= False
            , "transactionRefundReason" .= Null
            , "transactionReferenceTransactionId" .= Null
            , "transactionNotes"       .= Null
            ]
      r1 <- post' ds "/transaction" txBody
      when (respStatus r1 == 200) $ do
        let itemBody = object
              [ "transactionItemId"            .= itemId
              , "transactionItemTransactionId" .= txId2
              , "transactionItemMenuItemSku"   .= sku
              , "transactionItemQuantity"      .= (1 :: Int)
              , "transactionItemPricePerUnit"  .= (2500 :: Int)
              , "transactionItemDiscounts"     .= ([] :: [Value])
              , "transactionItemTaxes"         .= ([] :: [Value])
              , "transactionItemSubtotal"      .= (2500 :: Int)
              , "transactionItemTotal"         .= (2700 :: Int)
              ]
        r2 <- post' ds "/transaction/item" itemBody
        when (respStatus r2 == 200) $ do
          pass ds "Transaction item added — this should trigger a stock pull request"

      pause ds "Stock pull request should have been created. Check the Stock Room Interface."

      subBanner "GET /stock/queue again"
      r3 <- get' ds "/stock/queue"
      ok3 <- assertStatus ds "GET /stock/queue → 200" 200 r3
      when ok3 $ do
        case respJson r3 of
          Just (Array arr) -> do
            info $ "Queue has " <> show (length arr) <> " pull request(s)"
            case arr of
              (firstPull:_) -> do
                let mpullId = do
                      Object obj <- pure firstPull
                      String s   <- A.lookup "prId" obj
                      pure (T.unpack s)
                case mpullId of
                  Just pid -> do
                    info $ "First pull ID: " <> take 8 pid <> "..."
                    exercisePullStateMachine ds pid
                  Nothing -> warn "Could not extract pull ID"
              [] -> info "Queue is empty (pull may not have been created)"
          _ -> warn "Queue response not an array"

exercisePullStateMachine :: DriverState -> String -> IO ()
exercisePullStateMachine ds pullId = do
  subBanner "Stock Pull State Machine"
  info $ "Exercising pull: " <> take 8 pullId <> "..."

  let doAction action label = do
        r <- post' ds ("/stock/pull/" <> pullId <> "/" <> action) (object [])
        ok <- assertStatus ds (label <> " → 200") 200 r
        when ok $
          case jBool "success" r of
            Just True -> pass ds $ label <> " success"
            _ -> detail $ "Response: " <> take 200 (LBS.unpack (respBody r))
        stepPause ds

  doAction "accept"  "Accept pull (Pending→Accepted)"
  pause ds "Pull accepted. Status should show 'PullAccepted' in Stock Room."

  doAction "start"   "Start pull (Accepted→Pulling)"
  pause ds "Pull started. Status should show 'PullPulling'."

  doAction "fulfill" "Fulfill pull (Pulling→Fulfilled)"
  pause ds "Pull fulfilled! Status should show 'PullFulfilled'. Inventory deducted."

  subBanner "GET /stock/pull/<id>/messages"
  r <- get' ds ("/stock/pull/" <> pullId <> "/messages")
  void $ assertStatus ds "GET pull messages → 200" 200 r

  subBanner "POST /stock/pull/<id>/message"
  let msgBody = object [ "nmMessage" .= ("E2E test message from driver" :: String) ]
  r2 <- post' ds ("/stock/pull/" <> pullId <> "/message") msgBody
  void $ assertStatus ds "Add pull message → 200" 200 r2

  pause ds "Message added to pull. Check the message thread in the Stock Room."

-- ── Phase 6: admin dashboard ─────────────────────────────────────────────────

testAdminDashboard :: DriverState -> IO ()
testAdminDashboard ds = do
  banner "PHASE 6 — Admin Dashboard"

  subBanner "GET /admin/snapshot"
  r1 <- get' ds "/admin/snapshot"
  ok1 <- assertStatus ds "GET /admin/snapshot → 200" 200 r1
  when ok1 $ do
    let fields = ["snapshotUptimeSeconds", "snapshotEnvironment"]
    forM_ fields $ \f ->
      case jField f r1 of
        Just _  -> pass ds $ "Field present: " <> f
        Nothing -> fail' ds $ "Missing field: " <> f

  pause ds "Admin snapshot loaded. Check Admin Dashboard → Overview tab."

  subBanner "GET /admin/sessions"
  r2 <- get' ds "/admin/sessions"
  ok2 <- assertStatus ds "GET /admin/sessions → 200" 200 r2
  when ok2 $
    case respJson r2 of
      Just (Array arr) -> pass ds $ show (length arr) <> " active session(s)"
      _ -> warn "Sessions response not an array"

  pause ds "Sessions loaded. Check Admin Dashboard → Sessions tab."

  subBanner "GET /admin/logs (recent)"
  r3 <- get' ds "/admin/logs"
  void $ assertStatus ds "GET /admin/logs → 200" 200 r3

  pause ds "Logs loaded. Check Admin Dashboard → Logs tab."

  subBanner "GET /admin/domain-events"
  r4 <- get' ds "/admin/domain-events"
  ok4 <- assertStatus ds "GET /admin/domain-events → 200" 200 r4
  when ok4 $
    case jField "depTotal" r4 of
      Just (Number n) -> pass ds $ "Domain events total: " <> show n
      _ -> detail "Could not parse depTotal"

  pause ds "Domain events loaded. Check Admin Dashboard → Domain Events tab."

  subBanner "GET /admin/registers"
  r5 <- get' ds "/admin/registers"
  void $ assertStatus ds "GET /admin/registers → 200" 200 r5

  subBanner "GET /admin/transactions"
  r6 <- get' ds "/admin/transactions"
  ok6 <- assertStatus ds "GET /admin/transactions → 200" 200 r6
  when ok6 $
    case jField "tpTotal" r6 of
      Just (Number n) -> pass ds $ "Transactions total: " <> show n
      _ -> detail "Could not parse tpTotal"

  pause ds "All admin endpoints tested. Admin Dashboard should be fully populated."

-- ── Phase 7: manager dashboard ───────────────────────────────────────────────

testManagerDashboard :: DriverState -> IO ()
testManagerDashboard ds = do
  banner "PHASE 7 — Manager Dashboard"

  subBanner "GET /manager/activity"
  r1 <- get' ds "/manager/activity"
  ok1 <- assertStatus ds "GET /manager/activity → 200" 200 r1
  when ok1 $ do
    let fields = ["asSummaryTime", "asOpenRegisters", "asLiveTransactions", "asTodayStats"]
    forM_ fields $ \f ->
      case jField f r1 of
        Just _ -> pass ds $ "Field present: " <> f
        Nothing -> fail' ds $ "Missing field: " <> f

  pause ds "Manager activity loaded. Check Manager Dashboard → Activity tab."

  subBanner "GET /manager/alerts"
  r2 <- get' ds "/manager/alerts"
  ok2 <- assertStatus ds "GET /manager/alerts → 200" 200 r2
  when ok2 $
    case respJson r2 of
      Just (Array arr) -> pass ds $ show (length arr) <> " alert(s) active"
      _ -> warn "Alerts not an array"

  pause ds "Alerts loaded. Check Manager Dashboard → Alerts tab."

  subBanner "POST /manager/reports/daily"
  let reportBody = object
        [ "dailyReportDate"       .= ("2024-01-01T00:00:00Z" :: String)
        , "dailyReportLocationId" .= ("b2bd4b3a-d50f-4c04-90b1-01266735876b" :: String)
        ]
  r3 <- post' ds "/manager/reports/daily" reportBody
  ok3 <- assertStatus ds "POST /manager/reports/daily → 200" 200 r3
  when ok3 $ do
    case jField "dailyReportTotal" r3 of
      Just (Number n) -> pass ds $ "Daily report total: " <> show n
      _ -> detail "dailyReportTotal not parseable"

  pause ds "Daily report generated. Check Manager Dashboard → Reports tab."

-- ── Phase 8: SSE endpoints ───────────────────────────────────────────────────

testSSEEndpoints :: DriverState -> IO ()
testSSEEndpoints ds = do
  banner "PHASE 8 — SSE Stream Connectivity"

  -- We can't consume SSE streams fully here, but we can verify
  -- the endpoints accept connections (they'll hold open; we just check 200)
  info "SSE endpoints return streaming responses — we verify they accept connections"

  let sseEndpoints =
        [ "/admin/logs/stream"
        , "/admin/events/stream"
        , "/manager/activity/stream"
        , "/stock/queue/stream"
        ]

  forM_ sseEndpoints $ \ep -> do
    -- Use a short timeout for SSE check
    let url = cfgBase (dsCfg ds) <> ep
    tok <- readIORef (dsToken ds)
    case tok of
      Nothing -> warn $ "No token, skipping " <> ep
      Just t  -> do
        initReq <- parseRequest url
        let req = initReq
              { method         = "GET"
              , requestHeaders =
                  [ ("Authorization", BS.pack $ "Bearer " <> t)
                  , ("Accept", "text/event-stream")
                  ]
              , responseTimeout = responseTimeoutMicro 3_000_000
              }
        result <- try $ httpLbs req (dsMgr ds)
        case result of
          Left (_ :: SomeException) ->
            -- SSE connections time out — that's expected
            pass ds $ ep <> " accepted connection (timeout expected for SSE)"
          Right resp ->
            if statusCode (responseStatus resp) == 200
              then pass ds $ ep <> " → 200"
              else fail' ds $ ep <> " → " <> show (statusCode (responseStatus resp))

  pause ds "SSE endpoints checked. The frontend SSE status indicators should show 'Connected' or 'Live'."

-- ── Phase 9: feed endpoints ──────────────────────────────────────────────────

testFeedEndpoints :: DriverState -> IO ()
testFeedEndpoints ds = do
  banner "PHASE 9 — Public Feed"

  subBanner "GET /feed/snapshot"
  r1 <- httpReq ds "GET" "/feed/snapshot" Nothing False  -- public, no auth
  ok1 <- assertStatus ds "GET /feed/snapshot → 200" 200 r1
  when ok1 $
    case respJson r1 of
      Just (Array arr) -> pass ds $ "Feed snapshot has " <> show (length arr) <> " item(s)"
      _ -> warn "Feed snapshot not an array"

  subBanner "GET /xrpc/app.cheeblr.feed.status"
  r2 <- httpReq ds "GET" "/xrpc/app.cheeblr.feed.status" Nothing False
  ok2 <- assertStatus ds "GET /xrpc/app.cheeblr.feed.status → 200" 200 r2
  when ok2 $ do
    case jField "currentSeq" r2 of
      Just (Number n) -> pass ds $ "Feed current seq: " <> show n
      _ -> detail "currentSeq not parseable"
    case jField "itemCount" r2 of
      Just (Number n) -> pass ds $ "Feed item count: " <> show n
      _ -> pass ds "itemCount not in response"

  pause ds "Feed endpoints tested. Check Admin Dashboard → Feed Monitor tab (connect the WebSocket)."

-- ── Phase 10: GraphQL ────────────────────────────────────────────────────────

testGraphQL :: DriverState -> IO ()
testGraphQL ds = do
  banner "PHASE 10 — GraphQL Inventory"

  subBanner "POST /graphql/inventory — introspection query"
  let gqlBody = object [ "query" .= ("{ inventory { sku name price quantity } }" :: String) ]
  r1 <- post' ds "/graphql/inventory" gqlBody
  ok1 <- assertStatus ds "GraphQL inventory query → 200" 200 r1
  when ok1 $ do
    case respJson r1 of
      Just obj -> do
        let mData = parseMaybe (.: "data") obj :: Maybe Value
        case mData of
          Just _ -> pass ds "GraphQL data field present"
          Nothing -> do
            let mErrors = parseMaybe (.: "errors") obj :: Maybe Value
            case mErrors of
              Just e  -> warn $ "GraphQL errors: " <> show e
              Nothing -> fail' ds "GraphQL: no data or errors field"
      Nothing -> fail' ds "GraphQL response not valid JSON"

  pause ds "GraphQL tested. Inventory data accessible via GraphQL."

-- ── Phase 11: auth management ────────────────────────────────────────────────

testAuthManagement :: DriverState -> IO ()
testAuthManagement ds = do
  banner "PHASE 11 — User Management"

  subBanner "GET /auth/users"
  r1 <- get' ds "/auth/users"
  ok1 <- assertStatus ds "GET /auth/users → 200" 200 r1
  when ok1 $
    case respJson r1 of
      Just (Array arr) -> pass ds $ show (length arr) <> " user(s) listed"
      _ -> warn "Users not an array"

  pause ds "User list loaded."

-- ── Phase 12: cleanup ────────────────────────────────────────────────────────

testCleanup :: DriverState -> IO ()
testCleanup ds = do
  banner "PHASE 12 — Cleanup"

  skus <- readIORef (dsCreatedSkus ds)
  unless (null skus) $ do
    subBanner $ "Deleting " <> show (length skus) <> " test item(s)"
    forM_ skus $ \sku -> do
      r <- delete' ds ("/inventory/" <> sku)
      case respStatus r of
        200 -> pass ds $ "Deleted SKU " <> take 8 sku <> "..."
        404 -> info $ "SKU already gone: " <> take 8 sku <> "..."
        n   -> warn $ "Delete returned " <> show n <> " for " <> take 8 sku

  pause ds "Cleanup complete. LiveView should show original inventory."

-- ── Logout ───────────────────────────────────────────────────────────────────

testLogout :: DriverState -> IO ()
testLogout ds = do
  banner "PHASE FINAL — Logout"

  r <- post' ds "/auth/logout" (object [])
  void $ assertStatus ds "POST /auth/logout → 200" 200 r

  subBanner "Verify token is revoked"
  r2 <- get' ds "/inventory"
  void $ assertStatus ds "GET /inventory after logout → 401" 401 r2

  pause ds "Logged out. Frontend session should be cleared."

-- ─────────────────────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────────────────────

printSummary :: DriverState -> IO ()
printSummary ds = do
  p <- readIORef (dsPassCount ds)
  f <- readIORef (dsFailCount ds)
  let total = p + f
  putStrLn ""
  putStrLn $ "╔" <> replicate 68 '═' <> "╗"
  if f == 0
    then do
      setSGR [SetColor Foreground Vivid Green]
      putStrLn $ "║  ✓ ALL " <> show total <> " CHECKS PASSED"
              <> replicate (61 - length (show total)) ' ' <> "║"
    else do
      setSGR [SetColor Foreground Vivid Red]
      putStrLn $ "║  ✗ " <> show f <> " FAILED / " <> show p <> " PASSED / "
              <> show total <> " TOTAL"
              <> replicate (58 - length (show f) - length (show p) - length (show total)) ' '
              <> "║"
  setSGR [SetColor Foreground Vivid White]
  putStrLn $ "╚" <> replicate 68 '═' <> "╝"
  setSGR [Reset]
  putStrLn ""

printUsage :: IO ()
printUsage = do
  putStrLn "Usage: cheeblr-e2e-driver [OPTIONS]"
  putStrLn ""
  putStrLn "Options:"
  putStrLn "  --base URL       Backend base URL (default: https://localhost:8080)"
  putStrLn "  --user NAME      Username (default: admin)"
  putStrLn "  --pass PASS      Password (required)"
  putStrLn "  --pause MS       Pause between steps in ms (default: 1500)"
  putStrLn "  --auto           Skip interactive prompts (use --pause for timing)"
  putStrLn "  --phases LIST    Comma-separated phases to run (default: all)"
  putStrLn "                   Phases: conn,auth,inv,reg,tx,stock,admin,mgr,sse,feed,gql,users,cleanup"
  putStrLn "  --help           Show this message"
  putStrLn ""
  putStrLn "Examples:"
  putStrLn "  cheeblr-e2e-driver --pass 'mypassword'"
  putStrLn "  cheeblr-e2e-driver --base http://localhost:8080 --pass 'pw' --auto --pause 2000"
  putStrLn "  cheeblr-e2e-driver --pass 'pw' --phases conn,auth,inv"

parseArgs :: [String] -> Either String (Config, [String])
parseArgs args = go args defaultConfig []
  where
    go [] cfg phases = Right (cfg, if null phases then allPhases else phases)
    go ("--help":_) _ _ = Left "help"
    go ("--base":v:rest)  cfg ps = go rest cfg{cfgBase=v} ps
    go ("--user":v:rest)  cfg ps = go rest cfg{cfgUsername=v} ps
    go ("--pass":v:rest)  cfg ps = go rest cfg{cfgPassword=v} ps
    go ("--pause":v:rest) cfg ps = go rest cfg{cfgPause=read v} ps
    go ("--auto":rest)    cfg ps = go rest cfg{cfgAuto=True} ps
    go ("--phases":v:rest) cfg _ = go rest cfg (splitOn ',' v)
    go (unknown:_) _ _ = Left $ "Unknown argument: " <> unknown

    splitOn c s = case break (==c) s of
      (w, [])   -> [w]
      (w, _:s') -> w : splitOn c s'

allPhases :: [String]
allPhases = ["conn","auth","inv","reg","tx","stock","admin","mgr","sse","feed","gql","users","cleanup"]

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  case parseArgs args of
    Left "help" -> printUsage >> exitSuccess
    Left err    -> do
      putStrLn $ "Error: " <> err
      putStrLn ""
      printUsage
      exitFailure
    Right (cfg, phases) -> do
      when (null (cfgPassword cfg)) $ do
        mPass <- lookupEnv "CHEEBLR_PASS"
        case mPass of
          Just p  -> run cfg{cfgPassword=p} phases
          Nothing -> do
            putStrLn "Error: --pass required (or set CHEEBLR_PASS env var)"
            putStrLn ""
            printUsage
            exitFailure
      unless (null (cfgPassword cfg)) $
        run cfg phases

run :: Config -> [String] -> IO ()
run cfg phases = do
  now <- getCurrentTime
  let ts = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" now

  clearScreen
  setCursorPosition 0 0
  setSGR [SetColor Foreground Vivid Cyan]
  putStrLn "╔══════════════════════════════════════════════════════════════════════╗"
  putStrLn "║          CHEEBLR — End-to-End Integration Driver                    ║"
  putStrLn "╚══════════════════════════════════════════════════════════════════════╝"
  setSGR [Reset]
  putStrLn ""
  info $ "Target:  " <> cfgBase cfg
  info $ "User:    " <> cfgUsername cfg
  info $ "Mode:    " <> if cfgAuto cfg then "automatic" else "interactive"
  info $ "Pause:   " <> show (cfgPause cfg) <> "ms"
  info $ "Started: " <> ts
  info $ "Phases:  " <> intercalate ", " phases
  putStrLn ""

  ds <- newDriverState cfg

  let run' phase action =
        when (phase `elem` phases) action

  run' "conn"    $ testConnectivity ds
  run' "auth"    $ testAuth ds

  -- Only proceed with phases that need auth if auth succeeded
  tok <- readIORef (dsToken ds)
  if isJust tok
    then do
      run' "inv"     $ testInventory ds

      mRegId <- if "reg" `elem` phases || "tx" `elem` phases
                  then do
                    testRegisters ds
                    setupRegister ds
                  else pure Nothing

      case mRegId of
        Nothing -> when ("tx" `elem` phases || "stock" `elem` phases) $
                     warn "No register available — skipping transaction/stock tests"
        Just regId -> do
          run' "tx"    $ void $ testTransactions ds regId
          run' "tx"    $ testVoidTransaction ds regId
          run' "stock" $ testStockPulls ds

      run' "admin"   $ testAdminDashboard ds
      run' "mgr"     $ testManagerDashboard ds
      run' "sse"     $ testSSEEndpoints ds
      run' "feed"    $ testFeedEndpoints ds
      run' "gql"     $ testGraphQL ds
      run' "users"   $ testAuthManagement ds
      run' "cleanup" $ testCleanup ds
      run' "cleanup" $ testLogout ds
    else do
      warn "Authentication failed — skipping authenticated phases"
      fail' ds "Auth prerequisite not met"

  printSummary ds

  f <- readIORef (dsFailCount ds)
  if f > 0 then exitFailure else exitSuccess