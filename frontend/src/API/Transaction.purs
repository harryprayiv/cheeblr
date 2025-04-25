module API.Transaction where

import Prelude

import Data.Either (Either(..))
import Effect.Aff (Aff, attempt, error, throwError)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import NetworkConfig (currentConfig)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)
import Types.Register (CloseRegisterRequest, CloseRegisterResult, OpenRegisterRequest, Register)
import Types.UUID (UUID)
import Yoga.JSON (writeJSON)

baseUrl :: String
baseUrl = currentConfig.apiBaseUrl

handleResponse :: forall a. String -> Aff a -> Aff (Either String a)
handleResponse endpoint action = do
  result <- attempt action
  case result of
    Left err -> do
      let errorMsg = "Error in " <> endpoint <> ": " <> show err
      liftEffect $ Console.error errorMsg
      pure $ Left errorMsg
    Right response -> pure $ Right response

getRegister :: UUID -> Aff (Either String Register)
getRegister registerId = do
  liftEffect $ Console.log $ "Fetching register: " <> show registerId

  handleResponse "getRegister" do
    response <- fetch (baseUrl <> "/register/" <> show registerId)
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json

createRegister :: Register -> Aff (Either String Register)
createRegister register = do
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
          }
      }
    fromJSON response.json

openRegister :: OpenRegisterRequest -> UUID -> Aff (Either String Register)
openRegister request registerId = do
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
          }
      }
    fromJSON response.json

closeRegister :: CloseRegisterRequest -> UUID -> Aff (Either String CloseRegisterResult)
closeRegister request registerId = do
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
          }
      }
    fromJSON response.json

createTransaction :: Transaction -> Aff (Either String Transaction)
createTransaction transaction = do
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

addTransactionItem :: TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem item = do
  let content = writeJSON item
  liftEffect $ Console.log "Adding item to transaction..."
  liftEffect $ Console.log $ "Sending content: " <> content

  handleResponse "addTransactionItem" do
    response <- fetch (baseUrl <> "/transaction/item")
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json

removeTransactionItem :: UUID -> Aff (Either String Unit)
removeTransactionItem itemId = do
  liftEffect $ Console.log $ "Removing item from transaction: " <> show itemId

  handleResponse "removeTransactionItem" do
    -- Fixed warning: ignored response with underscore
    _ <- fetch (baseUrl <> "/transaction/item/" <> show itemId)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    pure unit

addPaymentTransaction
  :: PaymentTransaction -> Aff (Either String PaymentTransaction)
addPaymentTransaction payment = do
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
          }
      }
    fromJSON response.json

removePaymentTransaction :: UUID -> Aff (Either String Unit)
removePaymentTransaction paymentId = do
  liftEffect $ Console.log $ "Removing payment transaction: " <> show paymentId

  handleResponse "removePaymentTransaction" do
    -- Fixed warning: ignored response with underscore
    _ <- fetch (baseUrl <> "/transaction/payment/" <> show paymentId)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    pure unit

finalizeTransaction :: UUID -> Aff (Either String Transaction)
finalizeTransaction transactionId = do
  liftEffect $ Console.log $ "Finalizing transaction: " <> show transactionId

  handleResponse "finalizeTransaction" do
    response <- fetch
      (baseUrl <> "/transaction/finalize/" <> show transactionId)
      { method: POST
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json

getTransaction :: UUID -> Aff (Either String Transaction)
getTransaction transactionId = do
  liftEffect $ Console.log $ "Fetching transaction: " <> show transactionId

  handleResponse "getTransaction" do
    response <- fetch (baseUrl <> "/transaction/" <> show transactionId)
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json

voidTransaction :: UUID -> String -> Aff (Either String Transaction)
voidTransaction transactionId reason = do
  liftEffect $ Console.log $ "Voiding transaction: " <> show transactionId

  handleResponse "voidTransaction" do
    response <- fetch (baseUrl <> "/transaction/void/" <> show transactionId)
      { method: POST
      , body: writeJSON reason
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json