module API.Transaction where

import Prelude

import Data.Either (Either(..))
import Effect.Aff (Aff, attempt)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Fetch (Method(..), fetch)
import Fetch.Yoga.Json (fromJSON)
import NetworkConfig (currentConfig)
import Types.Transaction (PaymentTransaction, Transaction, TransactionItem)
import Types.System (CloseRegisterRequest, CloseRegisterResult, OpenRegisterRequest, Register)
import Types.UUID (UUID)
import Yoga.JSON (writeJSON)

baseUrl :: String
baseUrl = currentConfig.apiBaseUrl

-- Get a register by ID
getRegister :: UUID -> Aff (Either String Register)
getRegister registerId = do
  result <- attempt do
    liftEffect $ Console.log $ "Fetching register: " <> show registerId

    response <- fetch (baseUrl <> "/register/" <> show registerId)
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json

  pure case result of
    Left err -> Left $ "Get register error: " <> show err
    Right response -> Right response

-- Create a new register
createRegister :: Register -> Aff (Either String Register)
createRegister register = do
  result <- attempt do
    let content = writeJSON register
    liftEffect $ Console.log "Creating new register..."

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

  pure case result of
    Left err -> Left $ "Create register error: " <> show err
    Right response -> Right response

-- Open a register
openRegister :: OpenRegisterRequest -> UUID -> Aff (Either String Register)
openRegister request registerId = do
  result <- attempt do
    let content = writeJSON request
    liftEffect $ Console.log $ "Opening register: " <> show registerId

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

  pure case result of
    Left err -> Left $ "Open register error: " <> show err
    Right response -> Right response

-- Close a register
closeRegister
  :: CloseRegisterRequest -> UUID -> Aff (Either String CloseRegisterResult)
closeRegister request registerId = do
  result <- attempt do
    let content = writeJSON request
    liftEffect $ Console.log $ "Closing register: " <> show registerId

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

  pure case result of
    Left err -> Left $ "Close register error: " <> show err
    Right response -> Right response

-- Create a new transaction
createTransaction :: Transaction -> Aff (Either String Transaction)
createTransaction transaction = do
  result <- attempt do
    let content = writeJSON transaction
    liftEffect $ Console.log "Creating new transaction..."
    liftEffect $ Console.log $ "Sending content: " <> content

    response <- fetch (baseUrl <> "/transaction")
      { method: POST
      , body: content
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json

  pure case result of
    Left err -> Left $ "Create transaction error: " <> show err
    Right response -> Right response

-- Add an item to a transaction
addTransactionItem :: TransactionItem -> Aff (Either String TransactionItem)
addTransactionItem item = do
  result <- attempt do
    let content = writeJSON item
    liftEffect $ Console.log "Adding item to transaction..."

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

  pure case result of
    Left err -> Left $ "Add item error: " <> show err
    Right response -> Right response

-- Remove an item from a transaction
removeTransactionItem :: UUID -> Aff (Either String Unit)
removeTransactionItem itemId = do
  result <- attempt do
    liftEffect $ Console.log $ "Removing item from transaction: " <> show itemId

    _ <- fetch (baseUrl <> "/transaction/item/" <> show itemId)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    pure unit

  pure case result of
    Left err -> Left $ "Remove item error: " <> show err
    Right _ -> Right unit

-- Add a payment to a transaction
addPaymentTransaction
  :: PaymentTransaction -> Aff (Either String PaymentTransaction)
addPaymentTransaction payment = do
  result <- attempt do
    let content = writeJSON payment
    liftEffect $ Console.log "Adding payment to transaction..."

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

  pure case result of
    Left err -> Left $ "Add payment error: " <> show err
    Right response -> Right response

-- Remove a payment from a transaction
removePaymentTransaction :: UUID -> Aff (Either String Unit)
removePaymentTransaction paymentId = do
  result <- attempt do
    liftEffect $ Console.log $ "Removing payment from transaction: " <> show
      paymentId

    _ <- fetch (baseUrl <> "/transaction/payment/" <> show paymentId)
      { method: DELETE
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    pure unit

  pure case result of
    Left err -> Left $ "Remove payment error: " <> show err
    Right _ -> Right unit

-- Finalize a transaction
finalizeTransaction :: UUID -> Aff (Either String Transaction)
finalizeTransaction transactionId = do
  result <- attempt do
    liftEffect $ Console.log $ "Finalizing transaction: " <> show transactionId

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

  pure case result of
    Left err -> Left $ "Finalize transaction error: " <> show err
    Right response -> Right response

-- Get a transaction by ID
getTransaction :: UUID -> Aff (Either String Transaction)
getTransaction transactionId = do
  result <- attempt do
    liftEffect $ Console.log $ "Fetching transaction: " <> show transactionId

    response <- fetch (baseUrl <> "/transaction/" <> show transactionId)
      { method: GET
      , headers:
          { "Content-Type": "application/json"
          , "Accept": "application/json"
          , "Origin": currentConfig.appOrigin
          }
      }
    fromJSON response.json

  pure case result of
    Left err -> Left $ "Get transaction error: " <> show err
    Right response -> Right response

voidTransaction :: UUID -> String -> Aff (Either String Transaction)
voidTransaction transactionId reason = do
  result <- attempt do
    liftEffect $ Console.log $ "Voiding transaction: " <> show transactionId

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

  pure case result of
    Left err -> Left $ "Void transaction error: " <> show err
    Right response -> Right response