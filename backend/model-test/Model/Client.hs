{-# LANGUAGE OverloadedStrings #-}

-- HTTP and JSON for the model test.
--
-- Requests are built the way the front end builds them: a JSON body, the
-- session in the cheeblr_session cookie, no Authorization header. The
-- responses are decoded here with their own small parsers and not with
-- the backend's types, so that this suite depends on the wire format and
-- on nothing inside the backend.
module Model.Client
  ( Http (..)
  , Reply (..)
  , newHttp
  , call
  , bodyText
  , RawSale (..)
  , RawLine (..)
  , RawPayment (..)
  , RawRegister (..)
  , RawStock (..)
  , decodeSale
  , decodeRegister
  , decodeStock
  , decodeCloseResult
  , decodeLoginUserId
  , decodeMutationSuccess
  ) where

import Data.Aeson (FromJSON (..), Value, decode, encode, withObject, (.:))
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.UUID (UUID)
import qualified Network.HTTP.Client as HC
import Network.HTTP.Types.Status (statusCode)

data Http = Http
  { httpManager :: HC.Manager
  , httpBase    :: String
    -- ^ for example http://localhost:18083, with no trailing slash
  }

data Reply = Reply
  { replyStatus :: Int
  , replyBody   :: LBS.ByteString
  , replyToken  :: Maybe Text
    -- ^ the session token from a Set-Cookie header, when one was sent
  }

newHttp :: String -> IO Http
newHttp base = do
  manager <- HC.newManager HC.defaultManagerSettings
  pure (Http manager base)

-- One request. A status other than 2xx is an ordinary result and is not
-- thrown.
call :: Http -> Maybe Text -> BS.ByteString -> String -> Maybe Value -> IO Reply
call http token method path body = do
  initial <- HC.parseRequest (httpBase http <> path)
  let headers =
        [("Accept", "application/json")]
          ++ [("Cookie", "cheeblr_session=" <> TE.encodeUtf8 t) | Just t <- [token]]
          ++ [("Content-Type", "application/json") | isJust body]
      request =
        initial
          { HC.method          = method
          , HC.requestHeaders  = headers
          , HC.requestBody     = HC.RequestBodyLBS (maybe LBS.empty encode body)
          , HC.cookieJar       = Nothing
          , HC.responseTimeout = HC.responseTimeoutMicro 60000000
          }
  response <- HC.httpLbs request (httpManager http)
  pure
    Reply
      { replyStatus = statusCode (HC.responseStatus response)
      , replyBody   = HC.responseBody response
      , replyToken  = lookup "Set-Cookie" (HC.responseHeaders response) >>= tokenFrom
      }

-- "cheeblr_session=TOKEN; HttpOnly; ..." gives TOKEN. The cookie that
-- clears the session has an empty value and gives Nothing.
tokenFrom :: BS.ByteString -> Maybe Text
tokenFrom header = do
  rest <- T.stripPrefix "cheeblr_session=" (TE.decodeUtf8 header)
  let token = T.takeWhile (/= ';') rest
  if T.null token then Nothing else Just token

-- The start of a response body, for failure reports.
bodyText :: Reply -> String
bodyText = take 300 . LBS8.unpack . replyBody

data RawLine = RawLine
  { rawLineId       :: UUID
  , rawLineSku      :: UUID
  , rawLineQuantity :: Int
  , rawLineTotal    :: Int
  }

instance FromJSON RawLine where
  parseJSON = withObject "sale line" $ \o ->
    RawLine
      <$> o .: "itemId"
      <*> o .: "itemMenuItemSku"
      <*> o .: "itemQuantity"
      <*> o .: "itemTotal"

data RawPayment = RawPayment
  { rawPaymentId     :: UUID
  , rawPaymentMethod :: String
  , rawPaymentAmount :: Int
  }

instance FromJSON RawPayment where
  parseJSON = withObject "payment" $ \o ->
    RawPayment
      <$> o .: "paymentId"
      <*> o .: "paymentMethod"
      <*> o .: "paymentAmount"

data RawSale = RawSale
  { rawSaleId       :: UUID
  , rawSaleStatus   :: String
  , rawSaleEmployee :: UUID
  , rawSaleRegister :: UUID
  , rawSaleLines    :: [RawLine]
  , rawSalePayments :: [RawPayment]
  , rawSaleSubtotal :: Int
  , rawSaleTax      :: Int
  , rawSaleTotal    :: Int
  }

instance FromJSON RawSale where
  parseJSON = withObject "sale" $ \o ->
    RawSale
      <$> o .: "saleId"
      <*> o .: "saleStatus"
      <*> o .: "saleEmployeeId"
      <*> o .: "saleRegisterId"
      <*> o .: "saleItems"
      <*> o .: "salePayments"
      <*> o .: "saleSubtotal"
      <*> o .: "saleTaxTotal"
      <*> o .: "saleTotal"

data RawRegister = RawRegister
  { rawRegisterOpen     :: Bool
  , rawRegisterExpected :: Int
  }

instance FromJSON RawRegister where
  parseJSON = withObject "register" $ \o ->
    RawRegister
      <$> o .: "registerIsOpen"
      <*> o .: "registerExpectedDrawerAmount"

data RawStock = RawStock
  { rawStockTotal    :: Int
  , rawStockReserved :: Int
  }

instance FromJSON RawStock where
  parseJSON = withObject "available inventory" $ \o ->
    RawStock
      <$> o .: "availableTotal"
      <*> o .: "availableReserved"

decodeSale :: Reply -> Maybe RawSale
decodeSale = decode . replyBody

decodeRegister :: Reply -> Maybe RawRegister
decodeRegister = decode . replyBody

decodeStock :: Reply -> Maybe RawStock
decodeStock = decode . replyBody

-- The variance from a close-register answer.
decodeCloseResult :: Reply -> Maybe Int
decodeCloseResult reply = do
  value <- decode (replyBody reply) :: Maybe Value
  parseMaybe (withObject "close result" (.: "closeRegisterResultVariance")) value

-- The user id from a login answer.
decodeLoginUserId :: Reply -> Maybe UUID
decodeLoginUserId reply = do
  value <- decode (replyBody reply) :: Maybe Value
  parseMaybe
    (withObject "login" $ \o -> o .: "loginUser" >>= withObject "session" (.: "sessionUserId"))
    value

-- The success flag of an inventory mutation answer.
decodeMutationSuccess :: Reply -> Maybe Bool
decodeMutationSuccess reply = do
  value <- decode (replyBody reply) :: Maybe Value
  parseMaybe (withObject "mutation" (.: "success")) value
