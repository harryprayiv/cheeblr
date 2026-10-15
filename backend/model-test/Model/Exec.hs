{-# LANGUAGE OverloadedStrings #-}

-- Sending commands to a running backend and reading its state back.
--
-- Shared is set up once per process: the HTTP connection, one signed-in
-- session per actor, and the rules. Run is set up once per generated
-- sequence: three new menu items, and the lists that map register and
-- sale slots to the ids the backend knows. Each sequence works on its own
-- items, registers and sales, so sequences do not disturb each other and
-- the database needs no reset between them.
module Model.Exec
  ( Shared (..)
  , Run (..)
  , setup
  , newRun
  , forkRun
  , endRun
  , execute
  , executeWith
  , readStock
  , catalogue
  ) where

import Control.Exception (throwIO)
import Control.Monad (forM, forM_, unless, void)
import Data.Aeson (Value (..), object, toJSON, (.=))
import qualified Data.ByteString as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (elemIndex, find, sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Data.UUID.V4 (nextRandom)
import System.Environment (getEnv, lookupEnv)
import Text.Read (readMaybe)

import Model.Client
import Model.Types

data Shared = Shared
  { sharedHttp     :: Http
  , sharedTokens   :: IORef (Map Actor Text)
  , sharedUsers    :: Map Actor UUID
  , sharedRules    :: Rules
  , sharedLocation :: UUID
  }

data Run = Run
  { runShared    :: Shared
  , runSkus      :: [UUID]
  , runRegisters :: IORef [UUID]
  , runSales     :: IORef [UUID]
  }

-- Unit price in cents and starting stock of the menu items each sequence
-- gets. The stock is small so that sequences run out of it.
catalogue :: [(Int, Int)]
catalogue = [(1999, 8), (1250, 3), (333, 1)]

failSetup :: String -> Reply -> IO a
failSetup what reply =
  throwIO . userError $
    "model test setup: " <> what <> " answered " <> show (replyStatus reply) <> ": " <> bodyText reply

envOr :: String -> String -> IO String
envOr name fallback = fromMaybe fallback <$> lookupEnv name

-- "restock" or "no-restock", as the backend reads RESTOCK_ON_VOID and
-- RESTOCK_ON_REFUND.
restocks :: String -> IO Bool
restocks name = do
  raw <- envOr name "no-restock"
  case raw of
    "restock"    -> pure True
    "no-restock" -> pure False
    other        -> throwIO (userError (name <> " must be restock or no-restock, got " <> other))

-- Signs in and returns the session token and the user id.
signIn :: Http -> Text -> Text -> IO (Text, UUID)
signIn http username password = do
  reply <-
    call http Nothing "POST" "/auth/login" . Just $
      object
        [ "loginUsername"   .= username
        , "loginPassword"   .= password
        , "loginRegisterId" .= Null
        ]
  case (replyStatus reply, replyToken reply, decodeLoginUserId reply) of
    (200, Just token, Just userId) -> pure (token, userId)
    _                              -> failSetup ("login as " <> T.unpack username) reply

-- Reads the environment, signs in as the admin, creates two cashiers and
-- a customer with names unique to this process, and signs in as each.
--
--   MODEL_BASE_URL        the backend, for example http://localhost:18083
--   MODEL_ADMIN_PASSWORD  the admin account's password
--   MODEL_ADMIN_USERNAME  default admin
--   MODEL_TAX_PPM         default 80000, the placeholder rule of a new database
--   RESTOCK_ON_VOID, RESTOCK_ON_REFUND   as given to the backend
setup :: IO Shared
setup = do
  base      <- getEnv "MODEL_BASE_URL"
  adminName <- T.pack <$> envOr "MODEL_ADMIN_USERNAME" "admin"
  adminPass <- T.pack <$> getEnv "MODEL_ADMIN_PASSWORD"
  taxRaw    <- envOr "MODEL_TAX_PPM" "80000"
  taxPpm    <- case readMaybe taxRaw of
    Just ppm -> pure ppm
    Nothing  -> throwIO (userError ("MODEL_TAX_PPM is not a number: " <> taxRaw))
  onVoid    <- restocks "RESTOCK_ON_VOID"
  onRefund  <- restocks "RESTOCK_ON_REFUND"
  http      <- newHttp base
  location  <- nextRandom
  suffix    <- T.take 8 . UUID.toText <$> nextRandom
  (adminToken, adminId) <- signIn http adminName adminPass
  others <- forM [(CashierA, "Cashier"), (CashierB, "Cashier"), (Customer, "Customer")] $ \(actor, role) -> do
    password <- UUID.toText <$> nextRandom
    let username = "model-" <> T.toLower (T.pack (show actor)) <> "-" <> suffix
    created <-
      call http (Just adminToken) "POST" "/auth/users" . Just $
        object
          [ "newReqUsername"    .= username
          , "newReqDisplayName" .= username
          , "newReqEmail"       .= Null
          , "newReqRole"        .= (role :: Text)
          , "newReqLocationId"  .= location
          , "newReqPassword"    .= password
          ]
    unless (replyStatus created == 200) $
      failSetup ("creating user " <> T.unpack username) created
    (token, userId) <- signIn http username password
    pure (actor, token, userId)
  tokens <-
    newIORef . Map.fromList $
      (Admin, adminToken) : [(actor, token) | (actor, token, _) <- others]
  pure
    Shared
      { sharedHttp     = http
      , sharedTokens   = tokens
      , sharedUsers    = Map.fromList ((Admin, adminId) : [(actor, userId) | (actor, _, userId) <- others])
      , sharedRules    =
          Rules
            { rulesTaxPpm          = taxPpm
            , rulesRestockOnVoid   = onVoid
            , rulesRestockOnRefund = onRefund
            , rulesPrices          = Map.fromList (zip [0 ..] (map fst catalogue))
            , rulesStock           = Map.fromList (zip [0 ..] (map snd catalogue))
            }
      , sharedLocation = location
      }

-- A request with an actor's session. Anonymous sends no cookie. When the
-- backend rotates the session token, the new one is kept.
as :: Shared -> Actor -> BS.ByteString -> String -> Maybe Value -> IO Reply
as shared actor method path body = do
  tokens <- readIORef (sharedTokens shared)
  reply  <- call (sharedHttp shared) (Map.lookup actor tokens) method path body
  forM_ (replyToken reply) $ \fresh ->
    unless (actor == Anonymous) $
      modifyIORef' (sharedTokens shared) (Map.insert actor fresh)
  pure reply

menuItem :: UUID -> Int -> Int -> Int -> Value
menuItem sku slot price stock =
  object
    [ "sort"           .= (0 :: Int)
    , "sku"            .= sku
    , "brand"          .= ("Model" :: Text)
    , "name"           .= ("Model item " <> T.pack (show slot))
    , "price"          .= price
    , "measure_unit"   .= ("g" :: Text)
    , "per_package"    .= ("3.5" :: Text)
    , "quantity"       .= stock
    , "category"       .= ("Flower" :: Text)
    , "subcategory"    .= ("Indoor" :: Text)
    , "description"    .= ("created by the model test" :: Text)
    , "tags"           .= ([] :: [Text])
    , "effects"        .= ([] :: [Text])
    , "strain_lineage" .=
        object
          [ "thc"              .= ("20%" :: Text)
          , "cbg"              .= ("1%" :: Text)
          , "strain"           .= ("Model" :: Text)
          , "creator"          .= ("Model" :: Text)
          , "species"          .= ("Hybrid" :: Text)
          , "dominant_terpene" .= ("Myrcene" :: Text)
          , "terpenes"         .= ([] :: [Text])
          , "lineage"          .= ([] :: [Text])
          , "leafly_url"       .= ("https://example.com" :: Text)
          , "img"              .= ("https://example.com/i.jpg" :: Text)
          ]
    ]

-- Creates the menu items of one sequence through POST /inventory.
newRun :: Shared -> IO Run
newRun shared = do
  skus <- forM (zip [0 ..] catalogue) $ \(slot, (price, stock)) -> do
    sku   <- nextRandom
    reply <- as shared Admin "POST" "/inventory" (Just (menuItem sku slot price stock))
    unless (replyStatus reply == 200 && decodeMutationSuccess reply == Just True) $
      failSetup "creating a menu item" reply
    pure sku
  registers <- newIORef []
  sales     <- newIORef []
  pure (Run shared skus registers sales)

-- A run that sells the same menu items as the given one but has its own
-- registers and sales. Model.Parallel gives one to each puppet, so that
-- the puppets contend for stock and for nothing else.
forkRun :: Run -> IO Run
forkRun run = do
  registers <- newIORef []
  sales     <- newIORef []
  pure run {runRegisters = registers, runSales = sales}

-- On-hand and reserved quantity of every menu item of a run, by slot.
readStock :: Run -> IO (Map Int StockView)
readStock run = do
  pairs <- forM (zip [0 ..] (runSkus run)) $ \(slot, sku) -> do
    raw <-
      decodeStock
        <$> as (runShared run) Admin "GET" ("/inventory/available/" <> UUID.toString sku) Nothing
    pure (slot, fmap (\s -> StockView (rawStockTotal s) (rawStockReserved s)) raw)
  pure (Map.fromList [(slot, view) | (slot, Just view) <- pairs])

-- Removes the menu items of a sequence that passed, so that the inventory
-- does not grow with every sequence. The answer is not checked.
endRun :: Run -> IO ()
endRun run =
  forM_ (runSkus run) $ \sku ->
    void (as (runShared run) Admin "DELETE" ("/inventory/" <> UUID.toString sku) Nothing)

at :: [a] -> Int -> Maybe a
at items index
  | index < 0 = Nothing
  | otherwise = case drop index items of
      (item : _) -> Just item
      []         -> Nothing

-- The id for a slot. A slot the run has no id for gives the nil UUID,
-- which the backend does not know.
idAt :: [UUID] -> Int -> String
idAt ids slot = UUID.toString (fromMaybe UUID.nil (at ids slot))

-- What a command did, before the state is read back.
data Sent = Sent
  { sentReply      :: Reply
  , sentSale       :: Maybe Int
  , sentRegister   :: Maybe Int
  , sentBodyIsSale :: Bool
  }

-- Sends one command, then reads back the sale and the register it named
-- and the stock of every menu item, all with the admin session.
execute :: Run -> Cmd -> IO Observed
execute = executeWith True

-- The same, with the stock read back only when asked. A puppet running
-- beside other puppets cannot predict the stock, so it does not read it.
executeWith :: Bool -> Run -> Cmd -> IO Observed
executeWith withStock run cmd = do
  registers <- readIORef (runRegisters run)
  sales     <- readIORef (runSales run)
  let shared   = runShared run
      skus     = runSkus run
      regId    = idAt registers
      saleId   = idAt sales
      skuId    = idAt skus
      onSale slot reply     = Sent reply (Just slot) Nothing True
      onRegister slot reply = Sent reply Nothing (Just slot) False
  sent <- case cmd of
    CreateRegister actor -> do
      newId <- nextRandom
      reply <-
        as shared actor "POST" "/register" . Just $
          object
            [ "registerId"                   .= newId
            , "registerName"                 .= ("Model register" :: Text)
            , "registerLocationId"           .= sharedLocation shared
            , "registerIsOpen"               .= False
            , "registerCurrentDrawerAmount"  .= (0 :: Int)
            , "registerExpectedDrawerAmount" .= (0 :: Int)
            , "registerOpenedAt"             .= Null
            , "registerOpenedBy"             .= Null
            , "registerLastTransactionTime"  .= Null
            ]
      if replyStatus reply == 200
        then do
          modifyIORef' (runRegisters run) (++ [newId])
          pure (onRegister (length registers) reply)
        else pure (Sent reply Nothing Nothing False)

    OpenRegister actor reg cash ->
      onRegister reg
        <$> as shared actor "POST" ("/register/open/" <> regId reg)
              (Just (object ["openRegisterStartingCash" .= cash]))

    CloseRegister actor reg counted ->
      onRegister reg
        <$> as shared actor "POST" ("/register/close/" <> regId reg)
              (Just (object ["closeRegisterCountedCash" .= counted]))

    StartSale actor reg -> do
      reply <-
        as shared actor "POST" "/pos/sale" . Just $
          object
            [ "startSaleRegisterId" .= regId reg
            , "startSaleLocationId" .= sharedLocation shared
            ]
      case (replyStatus reply, decodeSale reply) of
        (200, Just sale) -> do
          modifyIORef' (runSales run) (++ [rawSaleId sale])
          pure (onSale (length sales) reply)
        _ -> pure (Sent reply Nothing Nothing False)

    AddItem actor sale sku quantity ->
      onSale sale
        <$> as shared actor "POST" "/pos/sale/item"
              ( Just $
                  object
                    [ "addItemSaleId"   .= saleId sale
                    , "addItemSku"      .= skuId sku
                    , "addItemQuantity" .= quantity
                    ]
              )

    -- The line id is read from the sale first, as the sale screen has it
    -- from the sale it shows.
    RemoveItem actor sale sku -> do
      current <- decodeSale <$> as shared Admin "GET" ("/sale/" <> saleId sale) Nothing
      let lineId =
            maybe UUID.nil rawLineId $
              current >>= find (\l -> Just (rawLineSku l) == at skus sku) . rawSaleLines
      onSale sale
        <$> as shared actor "DELETE" ("/pos/sale/item/" <> UUID.toString lineId) Nothing

    AddPayment actor sale method amount tendered ->
      onSale sale
        <$> as shared actor "POST" "/pos/sale/payment"
              ( Just $
                  object
                    [ "addPaymentSaleId"    .= saleId sale
                    , "addPaymentMethod"    .= show method
                    , "addPaymentAmount"    .= amount
                    , "addPaymentTendered"  .= tendered
                    , "addPaymentReference" .= Null
                    ]
              )

    RemovePayment actor sale method amount -> do
      current <- decodeSale <$> as shared Admin "GET" ("/sale/" <> saleId sale) Nothing
      let matches p = rawPaymentMethod p == show method && rawPaymentAmount p == amount
          paymentId = maybe UUID.nil rawPaymentId (current >>= find matches . rawSalePayments)
      onSale sale
        <$> as shared actor "DELETE" ("/pos/sale/payment/" <> UUID.toString paymentId) Nothing

    Clear actor sale ->
      onSale sale <$> as shared actor "POST" ("/pos/sale/clear/" <> saleId sale) Nothing

    Finalize actor sale ->
      onSale sale <$> as shared actor "POST" ("/pos/sale/finalize/" <> saleId sale) Nothing

    Void actor sale ->
      onSale sale
        <$> as shared actor "POST" ("/sale/void/" <> saleId sale)
              (Just (toJSON ("voided by the model test" :: Text)))

    -- A refund answers with the refund transaction, not with the sale.
    Refund actor sale -> do
      reply <-
        as shared actor "POST" ("/sale/refund/" <> saleId sale)
          (Just (toJSON ("refunded by the model test" :: Text)))
      pure (Sent reply (Just sale) Nothing False)

    Audit -> do
      reply <- as shared Admin "GET" "/auth/me" Nothing
      pure (Sent reply Nothing Nothing False)

  -- The lists as they are after the command.
  registersNow <- readIORef (runRegisters run)
  salesNow     <- readIORef (runSales run)
  let users = sharedUsers shared
      ownerOf userId = lookup userId [(uid, actor) | (actor, uid) <- Map.toList users]
      toSaleView raw =
        SaleView
          { viewOwner     = ownerOf (rawSaleEmployee raw)
          , viewRegister  = elemIndex (rawSaleRegister raw) registersNow
          , viewStatus    = rawSaleStatus raw
          , viewLines     =
              Map.fromListWith (+)
                [ (fromMaybe (-1) (elemIndex (rawLineSku l) skus), rawLineQuantity l)
                | l <- rawSaleLines raw
                ]
          , viewPayments  = sort [(rawPaymentMethod p, rawPaymentAmount p) | p <- rawSalePayments raw]
          , viewSubtotal  = rawSaleSubtotal raw
          , viewTax       = rawSaleTax raw
          , viewTotal     = rawSaleTotal raw
          , viewLineTotal = sum (map rawLineTotal (rawSaleLines raw))
          }
      toRegisterView raw = RegisterView (rawRegisterOpen raw) (rawRegisterExpected raw)
      readSale slot =
        fmap toSaleView . decodeSale
          <$> as shared Admin "GET" ("/sale/" <> idAt salesNow slot) Nothing
      readRegister slot =
        fmap toRegisterView . decodeRegister
          <$> as shared Admin "GET" ("/register/" <> idAt registersNow slot) Nothing
      present pairs = Map.fromList [(slot, view) | (slot, Just view) <- pairs]
      reply = sentReply sent

  sale     <- maybe (pure Nothing) readSale (sentSale sent)
  register <- maybe (pure Nothing) readRegister (sentRegister sent)
  stock    <- if withStock then readStock run else pure Map.empty
  (allSales, allRegisters) <-
    if cmd == Audit
      then do
        saleViews     <- forM [0 .. length salesNow - 1] (\slot -> (,) slot <$> readSale slot)
        registerViews <- forM [0 .. length registersNow - 1] (\slot -> (,) slot <$> readRegister slot)
        pure (Just (present saleViews), Just (present registerViews))
      else pure (Nothing, Nothing)
  pure
    Observed
      { obsStatus   = replyStatus reply
      , obsBody     = bodyText reply
      , obsBodySale =
          if sentBodyIsSale sent && replyStatus reply == 200
            then toSaleView <$> decodeSale reply
            else Nothing
      , obsSale         = sale
      , obsRegister     = register
      , obsVariance     =
          case cmd of
            CloseRegister {} | replyStatus reply == 200 -> decodeCloseResult reply
            _                                           -> Nothing
      , obsStock        = stock
      , obsAllSales     = allSales
      , obsAllRegisters = allRegisters
      }