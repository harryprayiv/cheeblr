module API.Transaction where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe, maybe)
import Effect.Aff (Aff, attempt, error, throwError)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import NetworkConfig (currentConfig)
import Services.AuthService (AuthContext, getCurrentUserId)
import Types.Register (CloseRegisterRequest, CloseRegisterResult, OpenRegisterRequest, Register)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)
import Types.UUID (UUID)
import Yoga.JSON (readJSON_, writeJSON)

baseUrl :: String
baseUrl = currentConfig.apiBaseUrl

-- | Get the current user ID as a string for the X-User-Id header
getUserIdHeader :: Ref AuthContext -> Aff String
getUserIdHeader authRef = liftEffect $ show <$> getCurrentUserId authRef

handleResponse :: forall a. String -> Aff a -> Aff (Either String a)
handleResponse endpoint action = do
  result <- attempt action
  case result of
    Left err -> do
      let errorMsg = "Error in " <> endpoint <> ": " <> show err
      liftEffect $ Console.error errorMsg
      pure $ Left errorMsg
    Right response -> pure $ Right response

getRegister :: Ref AuthContext -> UUID -> Aff (Either String Register)
getRegister authRef registerId = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log $ "Fetching register: " <> show registerId

  handleResponse "getRegister" do
    response <- fetch (baseUrl <> "/register/" <> show registerId)
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

createRegister :: Ref AuthContext -> Register -> Aff (Either String Register)
createRegister authRef register = do
  userId <- getUserIdHeader authRef
  let content = writeJSON register
  liftEffect $ Console.log "Creating new register..."
  liftEffect $ Console.log $ "Sending content: " <> content

  handleResponse "createRegister" do
    response <- fetch (baseUrl <> "/register")
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

openRegister :: Ref AuthContext -> OpenRegisterRequest -> UUID -> Aff (Either String Register)
openRegister authRef request registerId = do
  userId <- getUserIdHeader authRef
  let content = writeJSON request
  liftEffect $ Console.log $ "Opening register: " <> show registerId
  liftEffect $ Console.log $ "Sending content: " <> content

  handleResponse "openRegister" do
    response <- fetch (baseUrl <> "/register/open/" <> show registerId)
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

closeRegister :: Ref AuthContext -> CloseRegisterRequest -> UUID -> Aff (Either String CloseRegisterResult)
closeRegister authRef request registerId = do
  userId <- getUserIdHeader authRef
  let content = writeJSON request
  liftEffect $ Console.log $ "Closing register: " <> show registerId
  liftEffect $ Console.log $ "Sending content: " <> content

  handleResponse "closeRegister" do
    response <- fetch (baseUrl <> "/register/close/" <> show registerId)
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

createTransaction :: Ref AuthContext -> Transaction -> Aff (Either String Transaction)
createTransaction authRef transaction = do
  userId <- getUserIdHeader authRef
  let content = writeJSON transaction
  liftEffect $ Console.log "Creating new transaction..."
  liftEffect $ Console.log $ "Sending content: " <> content

  handleResponse "createTransaction" do
    response <- fetch (baseUrl <> "/transaction")
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }

    if response.status >= 200 && response.status < 300 then do
      liftEffect $ Console.log $ "Transaction created successfully - status: "
        <> show response.status
      fromJSON response.json
    else do
      errorText <- response.text
      liftEffect $ Console.error $ "Server error: " <> errorText <> " (status "
        <> show response.status
        <> ")"
      throwError
        ( error $ "Server returned status " <> show response.status <> ": " <>
            errorText
        )

type ErrorResponse = { error :: String }

parseErrorResponse :: String -> String
parseErrorResponse str = 
  maybe str _.error (readJSON_ str :: Maybe ErrorResponse)

addTransactionItem :: Ref AuthContext -> TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem authRef item = do
  userId <- getUserIdHeader authRef
  let content = writeJSON item
  liftEffect $ Console.log "Adding item to transaction..."
  liftEffect $ Console.log $ "Sending content: " <> content

  result <- attempt do
    response <- fetch (baseUrl <> "/transaction/item")
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    
    if response.status >= 200 && response.status < 300
      then fromJSON response.json
      else do
        errorText <- response.text
        let cleanError = parseErrorResponse errorText
        liftEffect $ Console.error $ "Server error: " <> cleanError
        throwError (error cleanError)

  pure case result of
    Left err -> Left $ show err
    Right parsed -> Right parsed

removeTransactionItem :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removeTransactionItem authRef itemId = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log $ "Removing item from transaction: " <> show itemId

  handleResponse "removeTransactionItem" do
    _ <- fetch (baseUrl <> "/transaction/item/" <> show itemId)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    pure unit

clearTransaction :: Ref AuthContext -> UUID -> Aff (Either String Unit)
clearTransaction authRef transactionId = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log $ "Clearing transaction: " <> show transactionId

  result <- attempt do
    response <- fetch (baseUrl <> "/transaction/clear/" <> show transactionId)
      { method: POST
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    pure unit

  pure case result of
    Left err -> Left $ "Clear error: " <> show err
    Right _ -> Right unit

addPaymentTransaction
  :: Ref AuthContext -> PaymentTransaction -> Aff (Either String PaymentTransaction)
addPaymentTransaction authRef payment = do
  userId <- getUserIdHeader authRef
  let content = writeJSON payment
  liftEffect $ Console.log "Adding payment to transaction..."
  liftEffect $ Console.log $ "Sending content: " <> content

  handleResponse "addPaymentTransaction" do
    response <- fetch (baseUrl <> "/transaction/payment")
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

removePaymentTransaction :: Ref AuthContext -> UUID -> Aff (Either String Unit)
removePaymentTransaction authRef paymentId = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log $ "Removing payment transaction: " <> show paymentId

  handleResponse "removePaymentTransaction" do
    _ <- fetch (baseUrl <> "/transaction/payment/" <> show paymentId)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    pure unit

finalizeTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
finalizeTransaction authRef transactionId = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log $ "Finalizing transaction: " <> show transactionId

  handleResponse "finalizeTransaction" do
    response <- fetch
      (baseUrl <> "/transaction/finalize/" <> show transactionId)
      { method: POST
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

getTransaction :: Ref AuthContext -> UUID -> Aff (Either String Transaction)
getTransaction authRef transactionId = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log $ "Fetching transaction: " <> show transactionId

  handleResponse "getTransaction" do
    response <- fetch (baseUrl <> "/transaction/" <> show transactionId)
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json

voidTransaction :: Ref AuthContext -> UUID -> String -> Aff (Either String Transaction)
voidTransaction authRef transactionId reason = do
  userId <- getUserIdHeader authRef
  liftEffect $ Console.log $ "Voiding transaction: " <> show transactionId

  handleResponse "voidTransaction" do
    response <- fetch (baseUrl <> "/transaction/void/" <> show transactionId)
      { method: POST
      , body: writeJSON reason
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          , "X-User-Id": userId
          }
      }
    fromJSON response.json