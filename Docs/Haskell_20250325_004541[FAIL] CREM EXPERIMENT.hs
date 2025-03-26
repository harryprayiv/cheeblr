{-
Generated: 2025-03-25 00:45:44
Hash: 7881e2e15f950e74be82b13cfbea49ad57f8af911d76db2b62e9d4f065a0842a
-}

{-
COMPILE_STATUS: false
BUILD_OUTPUT:
Configuration is affected by the following files:
- cabal.project
Build profile: -w ghc-9.6.6 -O1
In order, the following will be built (use -v for more details):
 - cheeblr-backend-0.0.0.3 (lib) (file src/Server/Transaction.hs changed)
 - cheeblr-backend-0.0.0.3 (exe:cheeblr-backend) (configuration changed)
Preprocessing library for cheeblr-backend-0.0.0.3...
Building library for cheeblr-backend-0.0.0.3...
[ 4 of 12] Compiling State.Transaction ( src/State/Transaction.hs, dist-newstyle/build/x86_64-linux/ghc-9.6.6/cheeblr-backend-0.0.0.3/build/State/Transaction.o, dist-newstyle/build/x86_64-linux/ghc-9.6.6/cheeblr-backend-0.0.0.3/build/State/Transaction.dyn_o ) [Source file changed]

src/State/Transaction.hs:131:14: error: [GHC-76037]
    Not in scope: type constructor or class ‘STransactionStateVertex’
    Suggested fix: Perhaps use ‘TransactionStateVertex’ (line 36)
    |
131 |   SomeState (STransactionStateVertex s) (TransactionState (StateIndexType s))
    |              ^^^^^^^^^^^^^^^^^^^^^^^

src/State/Transaction.hs:137:58: error:
    Ambiguous occurrence ‘StateMachineT’
    It could refer to
       either ‘Crem.StateMachine.StateMachineT’,
              imported from ‘Crem.StateMachine’ at src/State/Transaction.hs:25:45-61
           or ‘State.Transaction.StateMachineT’,
              defined at src/State/Transaction.hs:136:1
    |
137 |   runStateMachine :: cmd -> m (evt, TxTypes.Transaction, StateMachineT m cmd evt) 
    |                                                          ^^^^^^^^^^^^^

src/State/Transaction.hs:178:65: error:
    Ambiguous occurrence ‘StateMachineT’
    It could refer to
       either ‘Crem.StateMachine.StateMachineT’,
              imported from ‘Crem.StateMachine’ at src/State/Transaction.hs:25:45-61
           or ‘State.Transaction.StateMachineT’,
              defined at src/State/Transaction.hs:136:1
    |
178 | createTransaction :: UUID -> UTCTime -> UUID -> UUID -> UUID -> StateMachineT Identity TransactionCommand TransactionEvent
    |                                                                 ^^^^^^^^^^^^^

src/State/Transaction.hs:190:73: error:
    Ambiguous occurrence ‘StateMachineT’
    It could refer to
       either ‘Crem.StateMachine.StateMachineT’,
              imported from ‘Crem.StateMachine’ at src/State/Transaction.hs:25:45-61
           or ‘State.Transaction.StateMachineT’,
              defined at src/State/Transaction.hs:136:1
    |
190 | transactionStateMachine :: TxTypes.Transaction -> TransactionCommand -> StateMachineT Identity TransactionCommand TransactionEvent
    |                                                                         ^^^^^^^^^^^^^

src/State/Transaction.hs:232:3: error: [GHC-76037]
    Not in scope: type constructor or class ‘STransactionStateVertex’
    Suggested fix: Perhaps use ‘TransactionStateVertex’ (line 36)
    |
232 |   STransactionStateVertex s ->
    |   ^^^^^^^^^^^^^^^^^^^^^^^
Error: [Cabal-7125]
Failed to build cheeblr-backend-0.0.0.3 (which is required by exe:cheeblr-backend from cheeblr-backend-0.0.0.3).

-}

-- FILE: ./backend/src/State/Transaction.hs
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TypeApplications #-}

module State.Transaction where

import qualified Data.Text as T
import GHC.Generics (Generic)
import Data.Kind (Type)
import Data.Aeson (ToJSON(..), FromJSON(..), object, (.:), (.=), withObject)
import qualified Data.Aeson.Key as Key
import Crem.BaseMachine (BaseMachineT (..), InitialState(..), pureResult, ActionResult(..))
import Crem.StateMachine (StateMachine(..), StateMachineT(..), unrestrictedMachine)
import Crem.Topology (Topology(..), AllowAllTopology)
import Crem.Render.RenderableVertices (RenderableVertices(..))
import Data.UUID (UUID)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Functor.Identity (Identity)
import Data.Singletons (SingKind(..), SomeSing(..), Sing)
import qualified Data.Singletons as Sing
import qualified Types.Transaction as TxTypes

data TransactionStateVertex
  = NotStarted
  | TxCreated
  | TxInProgress
  | TxCompleted
  | TxVoided
  | TxRefunded
  deriving (Eq, Show, Enum, Bounded)

data instance Sing (s :: TransactionStateVertex) where
  SNotStarted :: Sing 'NotStarted
  STxCreated :: Sing 'TxCreated
  STxInProgress :: Sing 'TxInProgress
  STxCompleted :: Sing 'TxCompleted
  STxVoided :: Sing 'TxVoided
  STxRefunded :: Sing 'TxRefunded

instance SingKind TransactionStateVertex where
  type Demote TransactionStateVertex = TransactionStateVertex
  fromSing SNotStarted = NotStarted
  fromSing STxCreated = TxCreated
  fromSing STxInProgress = TxInProgress
  fromSing STxCompleted = TxCompleted
  fromSing STxVoided = TxVoided
  fromSing STxRefunded = TxRefunded

  toSing NotStarted = SomeSing SNotStarted
  toSing TxCreated = SomeSing STxCreated
  toSing TxInProgress = SomeSing STxInProgress
  toSing TxCompleted = SomeSing STxCompleted
  toSing TxVoided = SomeSing STxVoided
  toSing TxRefunded = SomeSing STxRefunded

instance RenderableVertices TransactionStateVertex where
  vertices = [NotStarted, TxCreated, TxInProgress, TxCompleted, TxVoided, TxRefunded]

transactionStateTopology :: Topology TransactionStateVertex
transactionStateTopology =
  Topology
    [ (NotStarted, [TxCreated])
    , (TxCreated, [TxInProgress])
    , (TxInProgress, [TxCompleted, TxVoided])
    , (TxCompleted, [TxVoided, TxRefunded])
    , (TxVoided, [])
    , (TxRefunded, [])
    ]

type TransactionTopology = 'Topology '[ '(NotStarted, '[TxCreated])
                                       , '(TxCreated, '[TxInProgress])
                                       , '(TxInProgress, '[TxCompleted, TxVoided])
                                       , '(TxCompleted, '[TxVoided, TxRefunded])
                                       , '(TxVoided, '[])
                                       , '(TxRefunded, '[])
                                       ]
data TransactionEvent
  = TransactionCreated UUID
  | ItemAdded TxTypes.TransactionItem
  | ItemUpdated TxTypes.TransactionItem
  | ItemRemoved UUID
  | PaymentAdded TxTypes.PaymentTransaction
  | PaymentRemoved UUID
  | TransactionFinalized UTCTime
  | TransactionVoided Text UTCTime
  | TransactionRefunded Text UTCTime UUID
  | TransactionUpdated UUID
  | TransactionCompleted UUID
  | CommandRejected Text
  | IllegalStateTransition Text

data NotStarted
data TxCreated
data TxInProgress
data TxCompleted
data TxVoided
data TxRefunded

data TransactionState s where
  NotStartedState :: TransactionState NotStarted
  CreatedState :: TxTypes.Transaction -> TransactionState TxCreated
  InProgressState :: TxTypes.Transaction -> TransactionState TxInProgress
  CompletedState :: TxTypes.Transaction -> TransactionState TxCompleted
  VoidedState :: Either (TransactionState TxCreated) (TransactionState TxInProgress) -> Text -> TransactionState TxVoided
  RefundedState :: TransactionState TxCompleted -> Text -> TransactionState TxRefunded

data SomeTransactionState = forall (s :: TransactionStateVertex).
  SomeState (STransactionStateVertex s) (TransactionState (StateIndexType s))

newtype StateWrapper (v :: TransactionStateVertex) =
  StateWrapper { unwrapState :: TransactionState (StateIndexType v) }

newtype StateMachineT m cmd evt = StateMachineT {
  runStateMachine :: cmd -> m (evt, TxTypes.Transaction, StateMachineT m cmd evt)
}

type family StateIndexType (s :: TransactionStateVertex) :: Type where
  StateIndexType 'NotStarted = NotStarted
  StateIndexType 'TxCreated = TxCreated
  StateIndexType 'TxInProgress = TxInProgress
  StateIndexType 'TxCompleted = TxCompleted
  StateIndexType 'TxVoided = TxVoided
  StateIndexType 'TxRefunded = TxRefunded

fromTransaction :: TxTypes.Transaction -> Either Text SomeTransactionState
fromTransaction tx =
  case TxTypes.transactionStatus tx of
    TxTypes.Created -> Right $ SomeState STxCreated (CreatedState tx)
    TxTypes.InProgress -> Right $ SomeState STxInProgress (InProgressState tx)
    TxTypes.Completed -> Right $ SomeState STxCompleted (CompletedState tx)
    TxTypes.Voided -> Right $ SomeState STxVoided (error "Cannot construct VoidedState directly from Transaction")
    TxTypes.Refunded -> Right $ SomeState STxRefunded (error "Cannot construct RefundedState directly from Transaction")

data TransactionCommand
  = InitTransaction UUID UTCTime UUID UUID UUID
  | AddItem TxTypes.TransactionItem
  | UpdateItem TxTypes.TransactionItem
  | RemoveItem UUID
  | AddPayment TxTypes.PaymentTransaction
  | RemovePayment UUID
  | FinalizeTransaction UTCTime
  | VoidTransaction Text UTCTime
  | RefundTransaction Text UTCTime UUID
  deriving (Show, Eq, Generic)

type family TransitionOK (s :: TransactionStateVertex) (t :: TransactionStateVertex) :: Bool where
  TransitionOK 'NotStarted 'TxCreated = 'True
  TransitionOK 'TxCreated 'TxInProgress = 'True
  TransitionOK 'TxInProgress 'TxCompleted = 'True
  TransitionOK 'TxInProgress 'TxVoided = 'True
  TransitionOK 'TxCompleted 'TxVoided = 'True
  TransitionOK 'TxCompleted 'TxRefunded = 'True
  TransitionOK _ _ = 'False

createTransaction :: UUID -> UTCTime -> UUID -> UUID -> UUID -> StateMachineT Identity TransactionCommand TransactionEvent
createTransaction transId created employeeId registerId locationId =
  StateMachineT $ \cmd ->
    case cmd of
      InitTransaction tid c eid rid lid ->
        let tx = createEmptyTransaction tid c eid rid lid
        in return (TransactionCreated tid, tx, transactionStateMachine tx)
      _ ->
        return (IllegalStateTransition (T.pack "Only InitTransaction is valid for a new transaction"),
                createEmptyTransaction transId created employeeId registerId locationId,
                transactionStateMachine (createEmptyTransaction transId created employeeId registerId locationId))

transactionStateMachine :: TxTypes.Transaction -> TransactionCommand -> StateMachineT Identity TransactionCommand TransactionEvent
transactionStateMachine tx cmd =
  StateMachineT $ \nextCmd ->
    case (TxTypes.transactionStatus tx, cmd) of
      (TxTypes.Created, AddItem item) ->
        let updatedTx = tx { TxTypes.transactionItems = item : TxTypes.transactionItems tx,
                             TxTypes.transactionStatus = TxTypes.InProgress }
        in return (ItemAdded item, updatedTx, transactionStateMachine updatedTx)

      (TxTypes.InProgress, AddItem item) ->
        let updatedTx = tx { TxTypes.transactionItems = item : TxTypes.transactionItems tx }
        in return (ItemAdded item, updatedTx, transactionStateMachine updatedTx)

      (TxTypes.InProgress, RemoveItem itemId) ->
        let updatedTx = tx { TxTypes.transactionItems = filter (\i -> TxTypes.transactionItemId i /= itemId) (TxTypes.transactionItems tx) }
        in return (ItemRemoved itemId, updatedTx, transactionStateMachine updatedTx)

      (TxTypes.InProgress, AddPayment payment) ->
        let updatedTx = tx { TxTypes.transactionPayments = payment : TxTypes.transactionPayments tx }
        in return (PaymentAdded payment, updatedTx, transactionStateMachine updatedTx)

      (TxTypes.InProgress, RemovePayment paymentId) ->
        let updatedTx = tx { TxTypes.transactionPayments = filter (\p -> TxTypes.paymentId p /= paymentId) (TxTypes.transactionPayments tx) }
        in return (PaymentRemoved paymentId, updatedTx, transactionStateMachine updatedTx)

      (TxTypes.InProgress, FinalizeTransaction timestamp) ->
        let updatedTx = tx { TxTypes.transactionStatus = TxTypes.Completed, TxTypes.transactionCompleted = Just timestamp }
        in return (TransactionFinalized timestamp, updatedTx, transactionStateMachine updatedTx)

      (TxTypes.Completed, VoidTransaction reason timestamp) ->
        let updatedTx = tx { TxTypes.transactionStatus = TxTypes.Voided, TxTypes.transactionIsVoided = True, TxTypes.transactionVoidReason = Just reason }
        in return (TransactionVoided reason timestamp, updatedTx, transactionStateMachine updatedTx)

      (TxTypes.Completed, RefundTransaction reason timestamp refundId) ->
        let updatedTx = tx { TxTypes.transactionStatus = TxTypes.Refunded, TxTypes.transactionIsRefunded = True, TxTypes.transactionRefundReason = Just reason }
        in return (TransactionRefunded reason timestamp refundId, updatedTx, transactionStateMachine updatedTx)

      (_, _) ->
        return (IllegalStateTransition (T.pack "Invalid state transition"), tx, transactionStateMachine tx)

handleCommand :: forall (s :: TransactionStateVertex).
  STransactionStateVertex s ->
  TransactionState (StateIndexType s) ->
  TransactionCommand ->
  ActionResult
    Identity
    (AllowAllTopology @TransactionStateVertex)
    StateWrapper
    s
    TransactionEvent
handleCommand SNotStarted NotStartedState (InitTransaction transId created employeeId registerId locationId) =
  let tx = createEmptyTransaction transId created employeeId registerId locationId
  in ActionResult $ pure (TransactionCreated transId, StateWrapper $ CreatedState tx)

handleCommand STxCreated (CreatedState tx) (AddItem item) =
  let updatedTx = tx { TxTypes.transactionItems = item : TxTypes.transactionItems tx,
                      TxTypes.transactionStatus = TxTypes.InProgress }
  in ActionResult $ pure (ItemAdded item, StateWrapper $ InProgressState updatedTx)

handleCommand STxInProgress (InProgressState tx) (AddItem item) =
  let updatedTx = tx { TxTypes.transactionItems = item : TxTypes.transactionItems tx }
  in pureResult (ItemAdded item) (StateWrapper $ InProgressState updatedTx)

handleCommand STxInProgress (InProgressState tx) (RemoveItem itemId) =
  let updatedTx = tx { TxTypes.transactionItems = filter (\i -> TxTypes.transactionItemId i /= itemId) (TxTypes.transactionItems tx) }
  in pureResult (ItemRemoved itemId) (StateWrapper $ InProgressState updatedTx)

handleCommand STxInProgress (InProgressState tx) (AddPayment payment) =
  let updatedTx = tx { TxTypes.transactionPayments = payment : TxTypes.transactionPayments tx }
  in pureResult (PaymentAdded payment) (StateWrapper $ InProgressState updatedTx)

handleCommand STxInProgress (InProgressState tx) (RemovePayment paymentId) =
  let updatedTx = tx { TxTypes.transactionPayments = filter (\p -> TxTypes.paymentId p /= paymentId) (TxTypes.transactionPayments tx) }
  in pureResult (PaymentRemoved paymentId) (StateWrapper $ InProgressState updatedTx)

handleCommand STxInProgress (InProgressState tx) (FinalizeTransaction timestamp) =
  let updatedTx = tx { TxTypes.transactionStatus = TxTypes.Completed, TxTypes.transactionCompleted = Just timestamp }
  in ActionResult $ pure (TransactionFinalized timestamp, StateWrapper $ CompletedState updatedTx)

handleCommand STxCompleted (CompletedState tx) (VoidTransaction reason timestamp) =
  let updatedTx = tx { TxTypes.transactionStatus = TxTypes.Voided, TxTypes.transactionIsVoided = True, TxTypes.transactionVoidReason = Just reason }
  in ActionResult $ pure (TransactionVoided reason timestamp, StateWrapper $ VoidedState (Right $ InProgressState updatedTx) reason)

handleCommand STxCompleted (CompletedState tx) (RefundTransaction reason timestamp refundId) =
  let updatedTx = tx { TxTypes.transactionStatus = TxTypes.Refunded, TxTypes.transactionIsRefunded = True, TxTypes.transactionRefundReason = Just reason }
  in ActionResult $ pure (TransactionRefunded reason timestamp refundId, StateWrapper $ RefundedState (CompletedState tx) reason)

handleCommand sing state _ =
  pureResult (IllegalStateTransition (T.pack "Invalid state transition")) (StateWrapper state)

createEmptyTransaction :: UUID -> UTCTime -> UUID -> UUID -> UUID -> TxTypes.Transaction
createEmptyTransaction transId created employeeId registerId locationId =
  TxTypes.Transaction
    { TxTypes.transactionId = transId
    , TxTypes.transactionStatus = TxTypes.Created
    , TxTypes.transactionCreated = created
    , TxTypes.transactionCompleted = Nothing
    , TxTypes.transactionCustomerId = Nothing
    , TxTypes.transactionEmployeeId = employeeId
    , TxTypes.transactionRegisterId = registerId
    , TxTypes.transactionLocationId = locationId
    , TxTypes.transactionItems = []
    , TxTypes.transactionPayments = []
    , TxTypes.transactionSubtotal = 0
    , TxTypes.transactionDiscountTotal = 0
    , TxTypes.transactionTaxTotal = 0
    , TxTypes.transactionTotal = 0
    , TxTypes.transactionType = TxTypes.Sale
    , TxTypes.transactionIsVoided = False
    , TxTypes.transactionVoidReason = Nothing
    , TxTypes.transactionIsRefunded = False
    , TxTypes.transactionRefundReason = Nothing
    , TxTypes.transactionReferenceTransactionId = Nothing
    , TxTypes.transactionNotes = Nothing
    }

data TransactionParams = TransactionParams
  { tpTransactionId :: UUID
  , tpEmployeeId :: UUID
  , tpRegisterId :: UUID
  , tpLocationId :: UUID
  , tpCustomerId :: Maybe UUID
  , tpCreatedTime :: UTCTime
  , tpType :: TxTypes.TransactionType
  } deriving (Show, Eq, Generic)

type family StateTransaction (state :: TransactionStateVertex) :: Type where
  StateTransaction 'TxCreated = TxTypes.Transaction
  StateTransaction 'TxInProgress = TxTypes.Transaction
  StateTransaction 'TxCompleted = TxTypes.Transaction
  StateTransaction 'TxVoided = TxTypes.Transaction
  StateTransaction 'TxRefunded = TxTypes.Transaction

toTransaction :: TransactionState v -> TxTypes.Transaction
toTransaction (CreatedState tx) = tx
toTransaction (InProgressState tx) = tx
toTransaction (CompletedState tx) = tx
toTransaction (VoidedState (Left createdState) reason) =
  let baseTransaction = toTransaction createdState
  in baseTransaction
      { TxTypes.transactionStatus = TxTypes.Voided
      , TxTypes.transactionIsVoided = True
      , TxTypes.transactionVoidReason = Just reason
      }
toTransaction (VoidedState (Right inProgressState) reason) =
  let baseTransaction = toTransaction inProgressState
  in baseTransaction
      { TxTypes.transactionStatus = TxTypes.Voided
      , TxTypes.transactionIsVoided = True
      , TxTypes.transactionVoidReason = Just reason
      }
toTransaction (RefundedState completedState reason) =
  let baseTransaction = toTransaction completedState
  in baseTransaction
      { TxTypes.transactionStatus = TxTypes.Refunded
      , TxTypes.transactionIsRefunded = True
      , TxTypes.transactionRefundReason = Just reason
      }

calculateSubtotal :: [TxTypes.TransactionItem] -> Int
calculateSubtotal items = sum $ map TxTypes.transactionItemSubtotal items

calculateDiscountTotal :: [TxTypes.TransactionItem] -> Int
calculateDiscountTotal items = sum $ concatMap (map TxTypes.discountAmount . TxTypes.transactionItemDiscounts) items

calculateTaxTotal :: [TxTypes.TransactionItem] -> Int
calculateTaxTotal items = sum $ concatMap (map TxTypes.taxAmount . TxTypes.transactionItemTaxes) items

calculateTotal :: [TxTypes.TransactionItem] -> Int
calculateTotal items = calculateSubtotal items - calculateDiscountTotal items + calculateTaxTotal items

sumPayments :: [TxTypes.PaymentTransaction] -> Int
sumPayments = sum . map TxTypes.paymentAmount

class StateTransition (from :: Type) (to :: Type) where
  transition :: TransactionState from -> TransactionEvent -> TransactionState to

instance ToJSON TransactionEvent where
  toJSON (TransactionCreated txId) =
    object [ Key.fromString "type" .= T.pack "created", Key.fromString "transactionId" .= txId ]
  toJSON (TransactionUpdated txId) =
    object [ Key.fromString "type" .= T.pack "updated", Key.fromString "transactionId" .= txId ]
  toJSON (TransactionCompleted txId) =
    object [ Key.fromString "type" .= T.pack "completed", Key.fromString "transactionId" .= txId ]
  toJSON (TransactionVoided reason txId) =
    object [ Key.fromString "type" .= T.pack "voided", Key.fromString "transactionId" .= txId, Key.fromString "reason" .= reason ]
  toJSON (TransactionRefunded reason txId _) =
    object [ Key.fromString "type" .= T.pack "refunded", Key.fromString "transactionId" .= txId, Key.fromString "reason" .= reason ]
  toJSON (CommandRejected msg) =
    object [ Key.fromString "type" .= T.pack "rejected", Key.fromString "message" .= msg ]
  toJSON _ =
    object [ Key.fromString "type" .= T.pack "unknown" ]

instance ToJSON TransactionParams where
  toJSON params =
    object [ Key.fromString "transactionId" .= tpTransactionId params
           , Key.fromString "employeeId" .= tpEmployeeId params
           , Key.fromString "registerId" .= tpRegisterId params
           , Key.fromString "locationId" .= tpLocationId params
           , Key.fromString "customerId" .= tpCustomerId params
           , Key.fromString "createdTime" .= tpCreatedTime params
           , Key.fromString "type" .= tpType params
           ]

instance FromJSON TransactionParams where
  parseJSON = withObject "TransactionParams" $ \v ->
    TransactionParams
      <$> v .: Key.fromString "transactionId"
      <*> v .: Key.fromString "employeeId"
      <*> v .: Key.fromString "registerId"
      <*> v .: Key.fromString "locationId"
      <*> v .: Key.fromString "customerId"
      <*> v .: Key.fromString "createdTime"
      <*> v .: Key.fromString "type"-- END OF: ./backend/src/State/Transaction.hs

-- FILE: ./backend/app/Main.hs
module Main where

import App (run)

main :: IO ()
main = run
-- END OF: ./backend/app/Main.hs

-- FILE: ./backend/src/API/Inventory.hs
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module API.Inventory where

import Data.UUID
import Servant
import Types.Inventory
import API.Transaction (PosAPI)

type InventoryAPI =
  "inventory" :> Get '[JSON] InventoryResponse
    :<|> "inventory" :> ReqBody '[JSON] MenuItem :> Post '[JSON] InventoryResponse
    :<|> "inventory" :> ReqBody '[JSON] MenuItem :> Put '[JSON] InventoryResponse
    :<|> "inventory" :> Capture "sku" UUID :> Delete '[JSON] InventoryResponse

inventoryAPI :: Proxy InventoryAPI
inventoryAPI = Proxy

type API =
  InventoryAPI
    :<|> PosAPI

api :: Proxy API
api = Proxy-- END OF: ./backend/src/API/Inventory.hs

-- FILE: ./backend/src/API/Transaction.hs
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DeriveGeneric #-}

module API.Transaction where

import Data.UUID
import Servant
import Types.Transaction
import Data.Text
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Time (UTCTime)
import GHC.Generics (Generic)

type TransactionAPI =
  "transaction" :> Get '[JSON] [Transaction]
    :<|> "transaction" :> Capture "id" UUID :> Get '[JSON] Transaction
    :<|> "transaction" :> ReqBody '[JSON] Transaction :> Post '[JSON] Transaction
    :<|> "transaction" :> Capture "id" UUID :> ReqBody '[JSON] Transaction :> Put '[JSON] Transaction
    :<|> "transaction" :> "void" :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Transaction
    :<|> "transaction" :> "refund" :> Capture "id" UUID :> ReqBody '[JSON] Text :> Post '[JSON] Transaction
    :<|> "transaction" :> "item" :> ReqBody '[JSON] TransactionItem :> Post '[JSON] TransactionItem
    :<|> "transaction" :> "item" :> Capture "id" UUID :> Delete '[JSON] NoContent
    :<|> "transaction" :> "payment" :> ReqBody '[JSON] PaymentTransaction :> Post '[JSON] PaymentTransaction
    :<|> "transaction" :> "payment" :> Capture "id" UUID :> Delete '[JSON] NoContent
    :<|> "transaction" :> "finalize" :> Capture "id" UUID :> Post '[JSON] Transaction

type RegisterAPI =
  "register" :> Get '[JSON] [Register]
    :<|> "register" :> Capture "id" UUID :> Get '[JSON] Register
    :<|> "register" :> ReqBody '[JSON] Register :> Post '[JSON] Register
    :<|> "register" :> Capture "id" UUID :> ReqBody '[JSON] Register :> Put '[JSON] Register
    :<|> "register" :> "open" :> Capture "id" UUID :> ReqBody '[JSON] OpenRegisterRequest :> Post '[JSON] Register
    :<|> "register" :> "close" :> Capture "id" UUID :> ReqBody '[JSON] CloseRegisterRequest :> Post '[JSON] CloseRegisterResult

type LedgerAPI =
  "ledger" :> "entry" :> Get '[JSON] [LedgerEntry]
    :<|> "ledger" :> "entry" :> Capture "id" UUID :> Get '[JSON] LedgerEntry
    :<|> "ledger" :> "account" :> Get '[JSON] [Account]
    :<|> "ledger" :> "account" :> Capture "id" UUID :> Get '[JSON] Account
    :<|> "ledger" :> "account" :> ReqBody '[JSON] Account :> Post '[JSON] Account
    :<|> "ledger" :> "report" :> "daily" :> ReqBody '[JSON] DailyReportRequest :> Post '[JSON] DailyReportResult

type ComplianceAPI =
  "compliance" :> "verification" :> ReqBody '[JSON] CustomerVerification :> Post '[JSON] CustomerVerification
    :<|> "compliance" :> "record" :> Capture "transaction_id" UUID :> Get '[JSON] ComplianceRecord
    :<|> "compliance" :> "report" :> ReqBody '[JSON] ComplianceReportRequest :> Post '[JSON] ComplianceReportResult

type PosAPI =
  TransactionAPI
    :<|> RegisterAPI
    :<|> LedgerAPI
    :<|> ComplianceAPI

posAPI :: Proxy PosAPI
posAPI = Proxy

data OpenRegisterRequest = OpenRegisterRequest
  { openRegisterEmployeeId :: UUID
  , openRegisterStartingCash :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON OpenRegisterRequest
instance FromJSON OpenRegisterRequest

data CloseRegisterRequest = CloseRegisterRequest
  { closeRegisterEmployeeId :: UUID
  , closeRegisterCountedCash :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON CloseRegisterRequest
instance FromJSON CloseRegisterRequest

data CloseRegisterResult = CloseRegisterResult
  { closeRegisterResultRegister :: Register
  , closeRegisterResultVariance :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON CloseRegisterResult
instance FromJSON CloseRegisterResult

data DailyReportRequest = DailyReportRequest
  { dailyReportDate :: UTCTime
  , dailyReportLocationId :: UUID
  } deriving (Show, Eq, Generic)

instance ToJSON DailyReportRequest
instance FromJSON DailyReportRequest

data DailyReportResult = DailyReportResult
  { dailyReportCash :: Int
  , dailyReportCard :: Int
  , dailyReportOther :: Int
  , dailyReportTotal :: Int
  , dailyReportTransactions :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON DailyReportResult
instance FromJSON DailyReportResult

data ComplianceReportRequest = ComplianceReportRequest
  { complianceReportStartDate :: UTCTime
  , complianceReportEndDate :: UTCTime
  , complianceReportLocationId :: UUID
  } deriving (Show, Eq, Generic)

instance ToJSON ComplianceReportRequest
instance FromJSON ComplianceReportRequest

newtype ComplianceReportResult = ComplianceReportResult
  { complianceReportContent :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON ComplianceReportResult
instance FromJSON ComplianceReportResult

data Register = Register
  { registerId :: UUID
  , registerName :: Text
  , registerLocationId :: UUID
  , registerIsOpen :: Bool
  , registerCurrentDrawerAmount :: Int
  , registerExpectedDrawerAmount :: Int
  , registerOpenedAt :: Maybe UTCTime
  , registerOpenedBy :: Maybe UUID
  , registerLastTransactionTime :: Maybe UTCTime
  } deriving (Show, Eq, Generic)

instance ToJSON Register
instance FromJSON Register-- END OF: ./backend/src/API/Transaction.hs

-- FILE: ./backend/src/App.hs

module App where

import API.Inventory (api)
import DB.Database (initializeDB, createTables, DBConfig(..))
import DB.Transaction (createTransactionTables)
import Network.HTTP.Types.Header
import Network.HTTP.Types.Method
import qualified Network.Wai.Handler.Warp as Warp
import Network.Wai.Middleware.Cors
import Servant
import Server (combinedServer, combinedServerWithStateMachine)
import System.Posix.User (getLoginName)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Data.Maybe (fromMaybe)

data AppConfig = AppConfig
  { dbConfig :: DBConfig
  , serverPort :: Int
  , useStateMachine :: Bool
  }

run :: IO ()
run = do
  currentUser <- getLoginName


  useStateMachineEnv <- lookupEnv "USE_STATE_MACHINE"
  let useStateMachine = fromMaybe False $ readMaybe =<< useStateMachineEnv


  portEnv <- lookupEnv "PORT"
  let port = fromMaybe 8080 $ readMaybe =<< portEnv

  let config =
        AppConfig
          { dbConfig =
              DBConfig
                { dbHost = "localhost"
                , dbPort = 5432
                , dbName = "cheeblr"
                , dbUser = currentUser
                , dbPassword = "postgres"
                , poolSize = 10
                }
          , serverPort = port
          , useStateMachine = useStateMachine
          }

  pool <- initializeDB (dbConfig config)

  createTables pool
  createTransactionTables pool

  putStrLn $ "Starting server on all interfaces, port " ++ show (serverPort config)
  putStrLn "=================================="
  putStrLn $ "Server running on port " ++ show (serverPort config)
  putStrLn $ "Using state machine implementation: " ++ (if useStateMachine config then "YES" else "NO")
  putStrLn "You can access this application from other devices on your network using:"
  putStrLn $ "http://YOUR_MACHINE_IP:" ++ show (serverPort config)
  putStrLn "=================================="

  let
    corsPolicy =
      CorsResourcePolicy
        { corsOrigins = Nothing
        , corsMethods = [methodGet, methodPost, methodPut, methodDelete, methodOptions]
        , corsRequestHeaders = [hContentType, hAccept, hAuthorization, hOrigin, hContentLength]
        , corsExposedHeaders = Nothing
        , corsMaxAge = Just 3600
        , corsVaryOrigin = False
        , corsRequireOrigin = False
        , corsIgnoreFailures = False
        }


    serverImpl = if useStateMachine config
                 then combinedServerWithStateMachine pool
                 else combinedServer pool

    app = cors (const $ Just corsPolicy) $ serve api serverImpl

  Warp.run (serverPort config) app-- END OF: ./backend/src/App.hs

-- FILE: ./backend/src/DB/Database.hs
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module DB.Database where

import Control.Concurrent (threadDelay)
import Control.Exception (catch, throwIO, SomeException)
import qualified Data.Pool as Pool
import qualified Data.Vector as V
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.SqlQQ (sql)
import Database.PostgreSQL.Simple.Types (PGArray (..))
import System.IO (hPutStrLn, stderr)
import Types.Inventory
import Data.UUID
import Servant (Handler)
import Control.Monad.IO.Class (liftIO)
import Control.Exception.Base (try)
import Control.Monad.Error.Class (throwError)
import Data.Text (pack)
import Servant.Server (err404)

data DBConfig = DBConfig
  { dbHost :: String
  , dbPort :: Int
  , dbName :: String
  , dbUser :: String
  , dbPassword :: String
  , poolSize :: Int
  }

initializeDB :: DBConfig -> IO (Pool.Pool Connection)
initializeDB config = do
  let poolConfig =
        Pool.defaultPoolConfig
          (connectWithRetry config)
          close
          0.5
          10
  pool <- Pool.newPool poolConfig

  Pool.withResource pool $ \conn -> do
    _ <- query_ conn "SELECT 1" :: IO [Only Int]
    pure ()

  pure pool

connectWithRetry :: DBConfig -> IO Connection
connectWithRetry DBConfig {..} = go 5
  where
    go :: Int -> IO Connection
    go retriesLeft = do
      let connInfo =
            defaultConnectInfo
              { connectHost = dbHost
              , connectPort = fromIntegral dbPort
              , connectDatabase = dbName
              , connectUser = dbUser
              , connectPassword = dbPassword
              }

      catch
        (connect connInfo)
        (`handleConnError` retriesLeft)

    handleConnError :: SqlError -> Int -> IO Connection
    handleConnError e retriesLeft
      | retriesLeft == 0 = do
          hPutStrLn stderr $ "Failed to connect to database after 5 attempts: " ++ show e
          throwIO e
      | otherwise = do
          hPutStrLn stderr "Database connection attempt failed, retrying in 5 seconds..."
          threadDelay 5000000
          go (retriesLeft - 1)

withConnection :: Pool.Pool Connection -> (Connection -> IO a) -> IO a
withConnection = Pool.withResource

createTables :: Pool.Pool Connection -> IO ()
createTables pool = withConnection pool $ \conn -> do
  _ <-
    execute_
      conn
      [sql|
        CREATE TABLE IF NOT EXISTS menu_items (
            sort INT NOT NULL,
            sku UUID PRIMARY KEY,
            brand TEXT NOT NULL,
            name TEXT NOT NULL,
            price INTEGER NOT NULL,
            measure_unit TEXT NOT NULL,
            per_package TEXT NOT NULL,
            quantity INT NOT NULL,
            category TEXT NOT NULL,
            subcategory TEXT NOT NULL,
            description TEXT NOT NULL,
            tags TEXT[] NOT NULL,
            effects TEXT[] NOT NULL
        )
    |]

  _ <-
    execute_
      conn
      [sql|
        CREATE TABLE IF NOT EXISTS strain_lineage (
            sku UUID PRIMARY KEY REFERENCES menu_items(sku),
            thc TEXT NOT NULL,
            cbg TEXT NOT NULL,
            strain TEXT NOT NULL,
            creator TEXT NOT NULL,
            species TEXT NOT NULL,
            dominant_terpene TEXT NOT NULL,
            terpenes TEXT[] NOT NULL,
            lineage TEXT[] NOT NULL,
            leafly_url TEXT NOT NULL,
            img TEXT NOT NULL
        )
    |]
  pure ()

insertMenuItem :: Pool.Pool Connection -> MenuItem -> IO ()
insertMenuItem pool MenuItem {..} = withConnection pool $ \conn -> do
  _ <-
    execute
      conn
      [sql|
        INSERT INTO menu_items
            (sort, sku, brand, name, price, measure_unit, per_package,
             quantity, category, subcategory, description, tags, effects)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      |]
      ( sort
      , sku
      , brand
      , name
      , price
      , measure_unit
      , per_package
      , quantity
      , show category
      , subcategory
      , description
      , PGArray $ V.toList tags
      , PGArray $ V.toList effects
      )

  let StrainLineage {..} = strain_lineage
  _ <-
    execute
      conn
      [sql|
        INSERT INTO strain_lineage
            (sku, thc, cbg, strain, creator, species, dominant_terpene,
             terpenes, lineage, leafly_url, img)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      |]
      ( sku
      , thc
      , cbg
      , strain
      , creator
      , show species
      , dominant_terpene
      , PGArray $ V.toList terpenes
      , PGArray $ V.toList lineage
      , leafly_url
      , img
      )
  pure ()

deleteMenuItem :: Pool.Pool Connection -> UUID -> Handler InventoryResponse
deleteMenuItem pool uuid = do
  liftIO $ putStrLn $ "Received request to delete menu item with UUID: " ++ show uuid

  result <- liftIO $ try @SomeException $ do

    _ <- withConnection pool $ \conn ->
      execute
        conn
        "DELETE FROM strain_lineage WHERE sku = ?"
        (Only uuid)

    withConnection pool $ \conn ->
      execute
        conn
        "DELETE FROM menu_items WHERE sku = ?"
        (Only uuid)

  case result of
    Left e -> do
      let errMsg = pack $ "Error deleting item: " <> show e
      liftIO $ putStrLn $ "Error in delete operation: " ++ show e
      return $ Message errMsg
    Right affected ->
      if affected > 0
        then return $ Message "Item deleted successfully"
        else throwError err404

getAllMenuItems :: Pool.Pool Connection -> IO Inventory
getAllMenuItems pool = withConnection pool $ \conn -> do
  items <-
    query_
      conn
      [sql|
        SELECT m.*,
               s.thc, s.cbg, s.strain, s.creator, s.species,
               s.dominant_terpene, s.terpenes, s.lineage,
               s.leafly_url, s.img
        FROM menu_items m
        JOIN strain_lineage s ON m.sku = s.sku
        ORDER BY m.sort
      |]
  return $ Inventory $ V.fromList items

updateExistingMenuItem :: Pool.Pool Connection -> MenuItem -> IO ()
updateExistingMenuItem pool MenuItem {..} = withConnection pool $ \conn -> do
  _ <-
    execute
      conn
      [sql|
        UPDATE menu_items
        SET sort = ?, brand = ?, name = ?, price = ?, measure_unit = ?,
            per_package = ?, quantity = ?, category = ?, subcategory = ?,
            description = ?, tags = ?, effects = ?
        WHERE sku = ?
      |]
      ( sort
      , brand
      , name
      , price
      , measure_unit
      , per_package
      , quantity
      , show category
      , subcategory
      , description
      , PGArray $ V.toList tags
      , PGArray $ V.toList effects
      , sku
      )

  let StrainLineage {..} = strain_lineage
  _ <-
    execute
      conn
      [sql|
        UPDATE strain_lineage
        SET thc = ?, cbg = ?, strain = ?, creator = ?, species = ?,
            dominant_terpene = ?, terpenes = ?, lineage = ?,
            leafly_url = ?, img = ?
        WHERE sku = ?
      |]
      ( thc
      , cbg
      , strain
      , creator
      , show species
      , dominant_terpene
      , PGArray $ V.toList terpenes
      , PGArray $ V.toList lineage
      , leafly_url
      , img
      , sku
      )
  pure ()-- END OF: ./backend/src/DB/Database.hs

-- FILE: ./backend/src/DB/Transaction.hs
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}

{-# OPTIONS_GHC -Wno-name-shadowing #-}
{-# OPTIONS_GHC -Wno-unused-do-bind #-}
{-# OPTIONS_GHC -Wno-unused-matches #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module DB.Transaction where

import Control.Monad.IO.Class (liftIO)
import Data.Pool (Pool, withResource)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Data.UUID (UUID, toString)
import Data.UUID.V4 (nextRandom)
import Database.PostgreSQL.Simple
  ( Connection
  , Only(..)

  , execute
  , execute_

  , query
  , query_, FromRow

  )
import Database.PostgreSQL.Simple.FromRow ( FromRow(..), field )
import Database.PostgreSQL.Simple.SqlQQ (sql)
import System.IO (hPutStrLn, stderr)

import Types.Transaction
    ( DiscountRecord(discountAmount, discountType, discountReason,
                     discountApprovedBy),
      DiscountType(..),
      PaymentMethod(..),
      PaymentTransaction(paymentTransactionId, paymentMethod,
                         paymentReference, paymentApproved, paymentAuthorizationCode,
                         paymentId, paymentAmount, paymentTendered, paymentChange),
      TaxCategory(..),
      TaxRecord(taxAmount, taxCategory, taxRate, taxDescription),
      Transaction(..),
      TransactionItem(..),
      TransactionStatus(..),
      TransactionType(..) )
import API.Transaction (
    OpenRegisterRequest(..),
    Register(..),
    CloseRegisterRequest(..),
    CloseRegisterResult(CloseRegisterResult, closeRegisterResultRegister, closeRegisterResultVariance)
  )
import Data.Scientific (Scientific)
import Control.Monad (void)

type ConnectionPool = Pool Connection
type DBAction a = Connection -> IO a

withConnection :: ConnectionPool -> (Connection -> IO a) -> IO a
withConnection = withResource

createTransactionTables :: ConnectionPool -> IO ()
createTransactionTables pool = withConnection pool $ \conn -> do
  hPutStrLn stderr "Creating transaction tables..."
  do
    results <- query_ conn "SELECT 1 FROM information_schema.tables WHERE table_name = 'transaction'" :: IO [Only Int]
    case results of
      [] -> do
        hPutStrLn stderr "Transaction tables not found, creating..."
        void $ execute_ conn
          [sql|
            CREATE TABLE IF NOT EXISTS transaction (
              id UUID PRIMARY KEY,
              status TEXT NOT NULL,
              created TIMESTAMP WITH TIME ZONE NOT NULL,
              completed TIMESTAMP WITH TIME ZONE,
              customer_id UUID,
              employee_id UUID NOT NULL,
              register_id UUID NOT NULL,
              location_id UUID NOT NULL,
              subtotal INTEGER NOT NULL,
              discount_total INTEGER NOT NULL,
              tax_total INTEGER NOT NULL,
              total INTEGER NOT NULL,
              transaction_type TEXT NOT NULL,
              is_voided BOOLEAN NOT NULL DEFAULT FALSE,
              void_reason TEXT,
              is_refunded BOOLEAN NOT NULL DEFAULT FALSE,
              refund_reason TEXT,
              reference_transaction_id UUID,
              notes TEXT
            )
          |]
      _ -> do
        hPutStrLn stderr "Transaction tables already exist"
        pure ()

getAllTransactions :: ConnectionPool -> IO [Transaction]
getAllTransactions pool = withConnection pool $ \conn ->
  Database.PostgreSQL.Simple.query_ conn
    [sql|
      SELECT
        t.id,
        t.status,
        t.created,
        t.completed,
        t.customer_id,
        t.employee_id,
        t.register_id,
        t.location_id,
        t.subtotal,
        t.discount_total,
        t.tax_total,
        t.total,
        t.transaction_type,
        t.is_voided,
        t.void_reason,
        t.is_refunded,
        t.refund_reason,
        t.reference_transaction_id,
        t.notes
      FROM transaction t
      ORDER BY t.created DESC
    |]

getTransactionById :: ConnectionPool -> UUID -> IO (Maybe Transaction)
getTransactionById pool transactionId = withConnection pool $ \conn -> do
  let query_str = [sql|
      SELECT
        t.id,
        t.status,
        t.created,
        t.completed,
        t.customer_id,
        t.employee_id,
        t.register_id,
        t.location_id,
        t.subtotal,
        t.discount_total,
        t.tax_total,
        t.total,
        t.transaction_type,
        t.is_voided,
        t.void_reason,
        t.is_refunded,
        t.refund_reason,
        t.reference_transaction_id,
        t.notes
      FROM transaction t
      WHERE t.id = ?
    |]

  results <- Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only transactionId)

  case results of
    [transaction] -> do
      items <- getTransactionItemsByTransactionId conn transactionId
      payments <- getPaymentsByTransactionId conn transactionId
      pure $ Just $ transaction { transactionItems = items, transactionPayments = payments }
    _ -> pure Nothing

getTransactionItemsByTransactionId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [TransactionItem]
getTransactionItemsByTransactionId conn transactionId = do
  let query_str = [sql|
      SELECT
        id,
        transaction_id,
        menu_item_sku,
        quantity,
        price_per_unit,
        subtotal,
        total
      FROM transaction_item
      WHERE transaction_id = ?
    |]

  items <- Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only transactionId)

  mapM (\item -> do
    discounts <- getDiscountsByTransactionItemId conn (transactionItemId item)
    taxes <- getTaxesByTransactionItemId conn (transactionItemId item)
    pure $ item { transactionItemDiscounts = discounts, transactionItemTaxes = taxes }
    ) items

getDiscountsByTransactionItemId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [DiscountRecord]
getDiscountsByTransactionItemId conn itemId = do
  let query_str = [sql|
      SELECT
        d.type,
        d.amount,
        d.percent,
        d.reason,
        d.approved_by
      FROM discount d
      WHERE d.transaction_item_id = ?
    |]

  Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only itemId)

getTaxesByTransactionItemId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [TaxRecord]
getTaxesByTransactionItemId conn itemId = do
  let query_str = [sql|
      SELECT
        t.category,
        t.rate,
        t.amount,
        t.description
      FROM transaction_tax t
      WHERE t.transaction_item_id = ?
    |]

  Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only itemId)

getPaymentsByTransactionId :: Database.PostgreSQL.Simple.Connection -> UUID -> IO [PaymentTransaction]
getPaymentsByTransactionId conn transactionId = do
  let query_str = [sql|
      SELECT
        id,
        transaction_id,
        method,
        amount,
        tendered,
        change_amount,
        reference,
        approved,
        authorization_code
      FROM payment_transaction
      WHERE transaction_id = ?
    |]

  Database.PostgreSQL.Simple.query conn query_str (Database.PostgreSQL.Simple.Only transactionId)

createTransaction :: ConnectionPool -> Transaction -> IO Transaction
createTransaction pool transaction = withConnection pool $ \conn -> do

  let insert_str = [sql|
      INSERT INTO transaction (
        id,
        status,
        created,
        completed,
        customer_id,
        employee_id,
        register_id,
        location_id,
        subtotal,
        discount_total,
        tax_total,
        total,
        transaction_type,
        is_voided,
        void_reason,
        is_refunded,
        refund_reason,
        reference_transaction_id,
        notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING
        id,
        status,
        created,
        completed,
        customer_id,
        employee_id,
        register_id,
        location_id,
        subtotal,
        discount_total,
        tax_total,
        total,
        transaction_type,
        is_voided,
        void_reason,
        is_refunded,
        refund_reason,
        reference_transaction_id,
        notes
    |]

  [newTransaction] <- Database.PostgreSQL.Simple.query conn insert_str (
    transactionId transaction,
    showStatus (transactionStatus transaction),
    transactionCreated transaction,
    transactionCompleted transaction,
    transactionCustomerId transaction,
    transactionEmployeeId transaction,
    transactionRegisterId transaction,
    transactionLocationId transaction,
    transactionSubtotal transaction,
    transactionDiscountTotal transaction,
    transactionTaxTotal transaction,
    transactionTotal transaction,
    showTransactionType (transactionType transaction),
    transactionIsVoided transaction,
    transactionVoidReason transaction,
    transactionIsRefunded transaction,
    transactionRefundReason transaction,
    transactionReferenceTransactionId transaction,
    transactionNotes transaction
   )

  newItems <- mapM (insertTransactionItem conn) (transactionItems transaction)
  newPayments <- mapM (insertPaymentTransaction conn) (transactionPayments transaction)
  pure $ newTransaction { transactionItems = newItems, transactionPayments = newPayments }

insertTransactionItem :: Database.PostgreSQL.Simple.Connection -> TransactionItem -> IO TransactionItem
insertTransactionItem conn item = do

  [newItem] <- Database.PostgreSQL.Simple.query conn [sql|
    INSERT INTO transaction_item (
      id,
      transaction_id,
      menu_item_sku,
      quantity,
      price_per_unit,
      subtotal,
      total
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    RETURNING
      id,
      transaction_id,
      menu_item_sku,
      quantity,
      price_per_unit,
      subtotal,
      total
  |] (
    transactionItemId item,
    transactionItemTransactionId item,
    transactionItemMenuItemSku item,
    transactionItemQuantity item,
    transactionItemPricePerUnit item,
    transactionItemSubtotal item,
    transactionItemTotal item
   )


  discounts <- mapM (insertDiscount conn (transactionItemId item) Nothing)
                   (transactionItemDiscounts item)


  taxes <- mapM (insertTax conn (transactionItemId item))
               (transactionItemTaxes item)


  pure $ newItem { transactionItemDiscounts = discounts, transactionItemTaxes = taxes }

insertDiscount :: Database.PostgreSQL.Simple.Connection -> UUID -> Maybe UUID -> DiscountRecord -> IO DiscountRecord
insertDiscount conn itemId transactionId discount = do
  discountId <- liftIO nextRandom
  Database.PostgreSQL.Simple.execute conn [sql|
    INSERT INTO discount (
      id,
      transaction_item_id,
      transaction_id,
      type,
      amount,
      percent,
      reason,
      approved_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  |] (
    discountId,
    itemId,
    transactionId,
    showDiscountType (discountType discount),
    discountAmount discount,
    getDiscountPercent (discountType discount),
    discountReason discount,
    discountApprovedBy discount
    )
  pure discount

getDiscountPercent :: DiscountType -> Maybe Data.Scientific.Scientific
getDiscountPercent (PercentOff percent) = Just percent
getDiscountPercent _ = Nothing

insertTax :: Database.PostgreSQL.Simple.Connection -> UUID -> TaxRecord -> IO TaxRecord
insertTax conn itemId tax = do
  taxId <- liftIO nextRandom
  Database.PostgreSQL.Simple.execute conn [sql|
    INSERT INTO transaction_tax (
      id,
      transaction_item_id,
      category,
      rate,
      amount,
      description
    ) VALUES (?, ?, ?, ?, ?, ?)
  |] (
    taxId,
    itemId,
    showTaxCategory (taxCategory tax),
    taxRate tax,
    taxAmount tax,
    taxDescription tax
    )
  pure tax

insertPaymentTransaction :: Database.PostgreSQL.Simple.Connection -> PaymentTransaction -> IO PaymentTransaction
insertPaymentTransaction conn payment = do
  [newPayment] <- Database.PostgreSQL.Simple.query conn [sql|
    INSERT INTO payment_transaction (
      id,
      transaction_id,
      method,
      amount,
      tendered,
      change_amount,
      reference,
      approved,
      authorization_code
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    RETURNING
      id,
      transaction_id,
      method,
      amount,
      tendered,
      change_amount,
      reference,
      approved,
      authorization_code
  |] (
    paymentId payment,
    paymentTransactionId payment,
    showPaymentMethod (paymentMethod payment),
    paymentAmount payment,
    paymentTendered payment,
    paymentChange payment,
    paymentReference payment,
    paymentApproved payment,
    paymentAuthorizationCode payment
   )
  pure newPayment

updateTransaction :: ConnectionPool -> UUID -> Transaction -> IO Transaction
updateTransaction pool transactionId transaction = withConnection pool $ \conn -> do

  Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = ?,
      completed = ?,
      customer_id = ?,
      employee_id = ?,
      register_id = ?,
      location_id = ?,
      subtotal = ?,
      discount_total = ?,
      tax_total = ?,
      total = ?,
      transaction_type = ?,
      is_voided = ?,
      void_reason = ?,
      is_refunded = ?,
      refund_reason = ?,
      reference_transaction_id = ?,
      notes = ?
    WHERE id = ?
  |] (
    showStatus (transactionStatus transaction),
    transactionCompleted transaction,
    transactionCustomerId transaction,
    transactionEmployeeId transaction,
    transactionRegisterId transaction,
    transactionLocationId transaction,
    transactionSubtotal transaction,
    transactionDiscountTotal transaction,
    transactionTaxTotal transaction,
    transactionTotal transaction,
    showTransactionType (transactionType transaction),
    transactionIsVoided transaction,
    transactionVoidReason transaction,
    transactionIsRefunded transaction,
    transactionRefundReason transaction,
    transactionReferenceTransactionId transaction,
    transactionNotes transaction,
    transactionId
   )


  maybeTransaction <- getTransactionById pool transactionId
  case maybeTransaction of
    Just updatedTransaction -> pure updatedTransaction
    Nothing -> error $ "Transaction not found after update: " ++ show transactionId

voidTransaction :: ConnectionPool -> UUID -> Text -> IO Transaction
voidTransaction pool transactionId reason = withConnection pool $ \conn -> do

  Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = 'VOIDED',
      is_voided = TRUE,
      void_reason = ?
    WHERE id = ?
  |] (reason, transactionId)


  maybeTransaction <- getTransactionById pool transactionId
  case maybeTransaction of
    Just updatedTransaction -> pure updatedTransaction
    Nothing -> error $ "Transaction not found after void: " ++ show transactionId

refundTransaction :: ConnectionPool -> UUID -> Text -> IO Transaction
refundTransaction pool transactionId reason = withConnection pool $ \conn -> do

  maybeOriginalTransaction <- getTransactionById pool transactionId
  case maybeOriginalTransaction of
    Nothing -> error $ "Original transaction not found for refund: " ++ show transactionId
    Just originalTransaction -> do

      refundId <- liftIO nextRandom
      now <- liftIO getCurrentTime

      let refundTransaction = Transaction {
        transactionId = refundId,
        transactionStatus = Completed,
        transactionCreated = now,
        transactionCompleted = Just now,
        transactionCustomerId = transactionCustomerId originalTransaction,
        transactionEmployeeId = transactionEmployeeId originalTransaction,
        transactionRegisterId = transactionRegisterId originalTransaction,
        transactionLocationId = transactionLocationId originalTransaction,

        transactionSubtotal = negate $ transactionSubtotal originalTransaction,
        transactionDiscountTotal = negate $ transactionDiscountTotal originalTransaction,
        transactionTaxTotal = negate $ transactionTaxTotal originalTransaction,
        transactionTotal = negate $ transactionTotal originalTransaction,
        transactionType = Return,
        transactionIsVoided = False,
        transactionVoidReason = Nothing,
        transactionIsRefunded = False,
        transactionRefundReason = Nothing,
        transactionReferenceTransactionId = Just transactionId,
        transactionNotes = Just $ "Refund for transaction " <> T.pack (toString transactionId) <> ": " <> reason,

        transactionItems = map negateTransactionItem $ transactionItems originalTransaction,
        transactionPayments = map negatePaymentTransaction $ transactionPayments originalTransaction
      }


      newRefundTransaction <- createTransaction pool refundTransaction


      Database.PostgreSQL.Simple.execute conn [sql|
        UPDATE transaction SET
          is_refunded = TRUE,
          refund_reason = ?
        WHERE id = ?
      |] (reason, transactionId)


      pure newRefundTransaction

negateTransactionItem :: TransactionItem -> TransactionItem
negateTransactionItem item = TransactionItem {
  transactionItemId = transactionItemId item,
  transactionItemTransactionId = transactionItemTransactionId item,
  transactionItemMenuItemSku = transactionItemMenuItemSku item,
  transactionItemQuantity = transactionItemQuantity item,
  transactionItemPricePerUnit = transactionItemPricePerUnit item,
  transactionItemDiscounts = map negateDiscountRecord (transactionItemDiscounts item),
  transactionItemTaxes = map negateTaxRecord (transactionItemTaxes item),
  transactionItemSubtotal = negate (transactionItemSubtotal item),
  transactionItemTotal = negate (transactionItemTotal item)
}

negateDiscountRecord :: DiscountRecord -> DiscountRecord
negateDiscountRecord discount = discount {
  discountAmount = negate $ discountAmount discount
}

negateTaxRecord :: TaxRecord -> TaxRecord
negateTaxRecord tax = tax {
  taxAmount = negate $ taxAmount tax
}

negatePaymentTransaction :: PaymentTransaction -> PaymentTransaction
negatePaymentTransaction payment = payment {
  paymentId = paymentId payment,
  paymentAmount = negate $ paymentAmount payment,
  paymentTendered = negate $ paymentTendered payment,
  paymentChange = negate $ paymentChange payment
}

finalizeTransaction :: ConnectionPool -> UUID -> IO Transaction
finalizeTransaction pool transactionId = withConnection pool $ \conn -> do

  now <- liftIO getCurrentTime
  Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = 'COMPLETED',
      completed = ?
    WHERE id = ?
  |] (now, transactionId)


  maybeTransaction <- getTransactionById pool transactionId
  case maybeTransaction of
    Just updatedTransaction -> pure updatedTransaction
    Nothing -> error $ "Transaction not found after finalization: " ++ show transactionId

addTransactionItem :: ConnectionPool -> TransactionItem -> IO TransactionItem
addTransactionItem pool item = withConnection pool $ \conn -> do

  newItem <- insertTransactionItem conn item


  updateTransactionTotals conn (transactionItemTransactionId item)


  pure newItem

deleteTransactionItem :: ConnectionPool -> UUID -> IO ()
deleteTransactionItem pool itemId = withConnection pool $ \conn -> do

  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT transaction_id FROM transaction_item WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only itemId)

  case results of
    [Database.PostgreSQL.Simple.Only transactionId] -> do

      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM discount WHERE transaction_item_id = ?
      |] (Database.PostgreSQL.Simple.Only itemId)


      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM transaction_tax WHERE transaction_item_id = ?
      |] (Database.PostgreSQL.Simple.Only itemId)


      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM transaction_item WHERE id = ?
      |] (Database.PostgreSQL.Simple.Only itemId)


      updateTransactionTotals conn transactionId

    _ -> pure ()

addPaymentTransaction :: ConnectionPool -> PaymentTransaction -> IO PaymentTransaction
addPaymentTransaction pool payment = withConnection pool $ \conn -> do

  newPayment <- insertPaymentTransaction conn payment


  updateTransactionPaymentStatus conn (paymentTransactionId payment)


  pure newPayment

deletePaymentTransaction :: ConnectionPool -> UUID -> IO ()
deletePaymentTransaction pool paymentId = withConnection pool $ \conn -> do

  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT transaction_id FROM payment_transaction WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only paymentId)

  case results of
    [Database.PostgreSQL.Simple.Only transactionId] -> do

      Database.PostgreSQL.Simple.execute conn [sql|
        DELETE FROM payment_transaction WHERE id = ?
      |] (Database.PostgreSQL.Simple.Only paymentId)


      updateTransactionPaymentStatus conn transactionId

    _ -> pure ()

updateTransactionTotals :: Database.PostgreSQL.Simple.Connection -> UUID -> IO ()
updateTransactionTotals conn transactionId = do
  [Database.PostgreSQL.Simple.Only subtotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(subtotal), 0) FROM transaction_item WHERE transaction_id = ?
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  [Database.PostgreSQL.Simple.Only discountTotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(amount), 0) FROM discount
    WHERE transaction_id = ? OR transaction_item_id IN (
      SELECT id FROM transaction_item WHERE transaction_id = ?
    )
  |] (transactionId, transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  [Database.PostgreSQL.Simple.Only taxTotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(amount), 0) FROM transaction_tax
    WHERE transaction_item_id IN (
      SELECT id FROM transaction_item WHERE transaction_id = ?
    )
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  let total = subtotal - discountTotal + taxTotal

  void $ Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      subtotal = ?,
      discount_total = ?,
      tax_total = ?,
      total = ?
    WHERE id = ?
  |] (subtotal, discountTotal, taxTotal, total, transactionId)

updateTransactionPaymentStatus :: Database.PostgreSQL.Simple.Connection -> UUID -> IO ()
updateTransactionPaymentStatus conn transactionId = do
  [Database.PostgreSQL.Simple.Only total] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT total FROM transaction WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  [Database.PostgreSQL.Simple.Only paymentTotal] <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT COALESCE(SUM(amount), 0) FROM payment_transaction
    WHERE transaction_id = ?
  |] (Database.PostgreSQL.Simple.Only transactionId) :: IO [Database.PostgreSQL.Simple.Only Scientific]

  let status = if paymentTotal >= total then "COMPLETED" else "IN_PROGRESS" :: Text

  void $ Database.PostgreSQL.Simple.execute conn [sql|
    UPDATE transaction SET
      status = ?
    WHERE id = ?
  |] (status, transactionId)

showStatus :: TransactionStatus -> Text
showStatus Created = "CREATED"
showStatus InProgress = "IN_PROGRESS"
showStatus Completed = "COMPLETED"
showStatus Voided = "VOIDED"
showStatus Refunded = "REFUNDED"

showTransactionType :: TransactionType -> Text
showTransactionType Sale = "SALE"
showTransactionType Return = "RETURN"
showTransactionType Exchange = "EXCHANGE"
showTransactionType InventoryAdjustment = "INVENTORY_ADJUSTMENT"
showTransactionType ManagerComp = "MANAGER_COMP"
showTransactionType Administrative = "ADMINISTRATIVE"

showPaymentMethod :: PaymentMethod -> Text
showPaymentMethod Cash = "CASH"
showPaymentMethod Debit = "DEBIT"
showPaymentMethod Credit = "CREDIT"
showPaymentMethod ACH = "ACH"
showPaymentMethod GiftCard = "GIFT_CARD"
showPaymentMethod StoredValue = "STORED_VALUE"
showPaymentMethod Mixed = "MIXED"
showPaymentMethod (Other text) = "OTHER"

showTaxCategory :: TaxCategory -> Text
showTaxCategory RegularSalesTax = "REGULAR_SALES_TAX"
showTaxCategory ExciseTax = "EXCISE_TAX"
showTaxCategory CannabisTax = "CANNABIS_TAX"
showTaxCategory LocalTax = "LOCAL_TAX"
showTaxCategory MedicalTax = "MEDICAL_TAX"
showTaxCategory NoTax = "NO_TAX"

showDiscountType :: DiscountType -> Text
showDiscountType (PercentOff _) = "PERCENT_OFF"
showDiscountType (AmountOff _) = "AMOUNT_OFF"
showDiscountType BuyOneGetOne = "BUY_ONE_GET_ONE"
showDiscountType (Custom _ _) = "CUSTOM"

getAllRegisters :: ConnectionPool -> IO [Register]
getAllRegisters pool = withConnection pool $ \conn ->
  Database.PostgreSQL.Simple.query_ conn [sql|
    SELECT
      id,
      name,
      location_id,
      is_open,
      current_drawer_amount,
      expected_drawer_amount,
      opened_at,
      opened_by,
      last_transaction_time
    FROM register
    ORDER BY name
  |]

instance FromRow Register where
  fromRow =
    Register
      <$> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field

getRegisterById :: ConnectionPool -> UUID -> IO (Maybe Register)
getRegisterById pool registerId = withConnection pool $ \conn -> do
  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT
      id,
      name,
      location_id,
      is_open,
      current_drawer_amount,
      expected_drawer_amount,
      opened_at,
      opened_by,
      last_transaction_time
    FROM register
    WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only registerId)

  case results of
    [register] -> pure $ Just register
    _ -> pure Nothing

createRegister :: ConnectionPool -> Register -> IO Register
createRegister pool register = withConnection pool $ \conn ->
  head <$> Database.PostgreSQL.Simple.query conn [sql|
    INSERT INTO register (
      id,
      name,
      location_id,
      is_open,
      current_drawer_amount,
      expected_drawer_amount,
      opened_at,
      opened_by,
      last_transaction_time
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    RETURNING
      id,
      name,
      location_id,
      is_open,
      current_drawer_amount,
      expected_drawer_amount,
      opened_at,
      opened_by,
      last_transaction_time
  |] (
    registerId register,
    registerName register,
    registerLocationId register,
    registerIsOpen register,
    registerCurrentDrawerAmount register,
    registerExpectedDrawerAmount register,
    registerOpenedAt register,
    registerOpenedBy register,
    registerLastTransactionTime register
  )

updateRegister :: ConnectionPool -> UUID -> Register -> IO Register
updateRegister pool registerId register = withConnection pool $ \conn -> do
  let update_str = [sql|
    UPDATE register SET
      name = ?,
      location_id = ?,
      is_open = ?,
      current_drawer_amount = ?,
      expected_drawer_amount = ?,
      opened_at = ?,
      opened_by = ?,
      last_transaction_time = ?
    WHERE id = ?
  |]

  Database.PostgreSQL.Simple.execute conn update_str (
    registerName register,
    registerLocationId register,
    registerIsOpen register,
    registerCurrentDrawerAmount register,
    registerExpectedDrawerAmount register,
    registerOpenedAt register,
    registerOpenedBy register,
    registerLastTransactionTime register,
    registerId
   )

  maybeRegister <- getRegisterById pool registerId
  case maybeRegister of
    Just updatedRegister -> pure updatedRegister
    Nothing -> error $ "Register not found after update: " ++ show registerId

openRegister :: ConnectionPool -> UUID -> OpenRegisterRequest -> IO Register
openRegister pool registerId request = withConnection pool $ \conn -> do
  now <- liftIO getCurrentTime

  let update_str = [sql|
    UPDATE register SET
      is_open = TRUE,
      current_drawer_amount = ?,
      expected_drawer_amount = ?,
      opened_at = ?,
      opened_by = ?
    WHERE id = ?
  |]

  Database.PostgreSQL.Simple.execute conn update_str (
    openRegisterStartingCash request,
    openRegisterStartingCash request,
    now,
    openRegisterEmployeeId request,
    registerId
    )

  maybeRegister <- getRegisterById pool registerId
  case maybeRegister of
    Just updatedRegister -> pure updatedRegister
    Nothing -> error $ "Register not found after opening: " ++ show registerId

closeRegister :: ConnectionPool -> UUID -> CloseRegisterRequest -> IO CloseRegisterResult
closeRegister pool registerId request = withConnection pool $ \conn -> do
  now <- liftIO getCurrentTime

  maybeRegister <- getRegisterById pool registerId
  case maybeRegister of
    Nothing -> error $ "Register not found: " ++ show registerId
    Just register -> do

      let variance = registerExpectedDrawerAmount register - closeRegisterCountedCash request

      let update_str = [sql|
        UPDATE register SET
          is_open = FALSE,
          current_drawer_amount = ?,
          last_transaction_time = ?
        WHERE id = ?
      |]

      Database.PostgreSQL.Simple.execute conn update_str (
        closeRegisterCountedCash request,
        now,
        registerId
        )

      maybeUpdatedRegister <- getRegisterById pool registerId
      case maybeUpdatedRegister of
        Nothing -> error $ "Register not found after closing: " ++ show registerId
        Just updatedRegister ->
          pure $ CloseRegisterResult {
            closeRegisterResultRegister = updatedRegister,
            closeRegisterResultVariance = variance
          }

getTransactionIdByItemId :: ConnectionPool -> UUID -> IO (Maybe UUID)
getTransactionIdByItemId pool itemId = withConnection pool $ \conn -> do
  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT transaction_id
    FROM transaction_item
    WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only itemId)

  case results of
    [Database.PostgreSQL.Simple.Only txId] -> return $ Just txId
    _ -> return Nothing

getTransactionIdByPaymentId :: ConnectionPool -> UUID -> IO (Maybe UUID)
getTransactionIdByPaymentId pool paymentId = withConnection pool $ \conn -> do
  results <- Database.PostgreSQL.Simple.query conn [sql|
    SELECT transaction_id
    FROM payment_transaction
    WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only paymentId)

  case results of
    [Database.PostgreSQL.Simple.Only txId] -> return $ Just txId
    _ -> return Nothing

updateTransactionItem :: ConnectionPool -> TransactionItem -> IO TransactionItem
updateTransactionItem pool item = withConnection pool $ \conn -> do

  Database.PostgreSQL.Simple.execute conn [sql|
    DELETE FROM transaction_item
    WHERE id = ?
  |] (Database.PostgreSQL.Simple.Only (transactionItemId item))


  insertTransactionItem conn item-- END OF: ./backend/src/DB/Transaction.hs

-- FILE: ./backend/src/Server.hs
{-# LANGUAGE ScopedTypeVariables #-}

module Server where

import API.Inventory
import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Database.PostgreSQL.Simple
import Data.Pool (Pool)
import Servant
import DB.Database (getAllMenuItems, insertMenuItem, updateExistingMenuItem, deleteMenuItem)
import Types.Inventory
import API.Transaction (PosAPI)
import Data.Text (pack)
import qualified Data.Pool as Pool
import Server.Transaction (posServerImpl)
import Server.TransactionStateMachine (posServerStateMachineImpl)

combinedServerWithStateMachine :: Pool Connection -> Server API
combinedServerWithStateMachine pool =
  inventoryServer pool
    :<|> posServerStateMachineImpl pool

inventoryServer :: Pool.Pool Connection -> Server InventoryAPI
inventoryServer pool =
  getInventory
    :<|> addMenuItem
    :<|> updateMenuItem
    :<|> deleteMenuItem pool
  where
    getInventory :: Handler InventoryResponse
    getInventory = do
      inventory <- liftIO $ getAllMenuItems pool
      liftIO $ putStrLn "Sending inventory response:"
      liftIO $ LBS.putStrLn $ encode $ InventoryData inventory
      return $ InventoryData inventory

    addMenuItem :: MenuItem -> Handler InventoryResponse
    addMenuItem item = do
      liftIO $ putStrLn "Received request to add menu item"
      liftIO $ print item
      result <- liftIO $ try $ do
        insertMenuItem pool item
        let response = Message (pack "Item added successfully")
        liftIO $ putStrLn $ "Sending response: " ++ show (encode response)
        return response
      case result of
        Right msg -> return msg
        Left (e :: SomeException) -> do
          let errMsg = pack $ "Error inserting item: " <> show e
          liftIO $ putStrLn $ "Error: " ++ show e
          let response = Message errMsg
          liftIO $ putStrLn $ "Sending error response: " ++ show (encode response)
          return response

    updateMenuItem :: MenuItem -> Handler InventoryResponse
    updateMenuItem item = do
      liftIO $ putStrLn "Received request to update menu item"
      liftIO $ print item
      result <- liftIO try

-- END OF: ./backend/src/Server.hs

-- FILE: ./backend/src/Server/Transaction.hs
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Redundant return" #-}

module Server.Transaction where

import API.Transaction
import Control.Monad.IO.Class (liftIO)
import Data.Pool (Pool)
import Data.UUID (UUID)
import Database.PostgreSQL.Simple (Connection)
import DB.Transaction
import Servant
import Types.Transaction
import Data.Text (Text, pack)
import qualified Data.ByteString.Lazy.Char8 as LBS

stringToLBS :: String -> LBS.ByteString
stringToLBS = LBS.pack

transactionServer :: Pool Connection -> Server TransactionAPI
transactionServer pool =
  getAllTransactionsHandler
    :<|> getTransactionHandler
    :<|> createTransactionHandler
    :<|> updateTransactionHandler
    :<|> voidTransactionHandler
    :<|> refundTransactionHandler
    :<|> addTransactionItemHandler
    :<|> removeTransactionItemHandler
    :<|> addPaymentTransactionHandler
    :<|> removePaymentTransactionHandler
    :<|> finalizeTransactionHandler
  where
    getAllTransactionsHandler :: Handler [Transaction]
    getAllTransactionsHandler = do
      liftIO $ putStrLn "Handling GET /transaction request"
      transactions <- liftIO $ getAllTransactions pool
      liftIO $ putStrLn $ "Returning " ++ show (length transactions) ++ " transactions"
      return transactions

    getTransactionHandler :: UUID -> Handler Transaction
    getTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling GET /transaction/" ++ show txId ++ " request"
      maybeTransaction <- liftIO $ getTransactionById pool txId
      case maybeTransaction of
        Just transaction -> return transaction
        Nothing -> throwError err404 { errBody = stringToLBS "Transaction not found" }

    createTransactionHandler :: Transaction -> Handler Transaction
    createTransactionHandler transaction = do
      liftIO $ putStrLn "Handling POST /transaction request"
      liftIO $ putStrLn $ "Creating transaction: " ++ show (transactionId transaction)
      createdTransaction <- liftIO $ createTransaction pool transaction
      liftIO $ putStrLn "Transaction created successfully"
      return createdTransaction

    updateTransactionHandler :: UUID -> Transaction -> Handler Transaction
    updateTransactionHandler txId transaction = do
      liftIO $ putStrLn $ "Handling PUT /transaction/" ++ show txId ++ " request"
      updatedTransaction <- liftIO $ updateTransaction pool txId transaction
      liftIO $ putStrLn "Transaction updated successfully"
      return updatedTransaction

    voidTransactionHandler :: UUID -> Text -> Handler Transaction
    voidTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/void/" ++ show txId ++ " request"
      voidedTransaction <- liftIO $ voidTransaction pool txId reason
      liftIO $ putStrLn "Transaction voided successfully"
      return voidedTransaction

    refundTransactionHandler :: UUID -> Text -> Handler Transaction
    refundTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/refund/" ++ show txId ++ " request"
      refundedTransaction <- liftIO $ refundTransaction pool txId reason
      liftIO $ putStrLn "Transaction refunded successfully"
      return refundedTransaction

    addTransactionItemHandler :: TransactionItem -> Handler TransactionItem
    addTransactionItemHandler item = do
      liftIO $ putStrLn "Handling POST /transaction/item request"
      addedItem <- liftIO $ addTransactionItem pool item
      liftIO $ putStrLn "Transaction item added successfully"
      return addedItem

    removeTransactionItemHandler :: UUID -> Handler NoContent
    removeTransactionItemHandler itemId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/item/" ++ show itemId ++ " request"
      liftIO $ deleteTransactionItem pool itemId
      liftIO $ putStrLn "Transaction item deleted successfully"
      return NoContent

    addPaymentTransactionHandler :: PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler payment = do
      liftIO $ putStrLn "Handling POST /transaction/payment request"
      addedPayment <- liftIO $ addPaymentTransaction pool payment
      liftIO $ putStrLn "Payment transaction added successfully"
      return addedPayment

    removePaymentTransactionHandler :: UUID -> Handler NoContent
    removePaymentTransactionHandler pymtId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/payment/" ++ show pymtId ++ " request"
      liftIO $ deletePaymentTransaction pool pymtId
      liftIO $ putStrLn "Payment transaction deleted successfully"
      return NoContent

    finalizeTransactionHandler :: UUID -> Handler Transaction
    finalizeTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling POST /transaction/finalize/" ++ show txId ++ " request"
      finalizedTransaction <- liftIO $ finalizeTransaction pool txId
      liftIO $ putStrLn "Transaction finalized successfully"
      return finalizedTransaction

registerServer :: Pool Connection -> Server RegisterAPI
registerServer pool =
  getAllRegistersHandler
    :<|> getRegisterHandler
    :<|> createRegisterHandler
    :<|> updateRegisterHandler
    :<|> openRegisterHandler
    :<|> closeRegisterHandler
  where
    getAllRegistersHandler :: Handler [Register]
    getAllRegistersHandler = do
      liftIO $ putStrLn "Handling GET /register request"
      registers <- liftIO $ getAllRegisters pool
      return registers

    getRegisterHandler :: UUID -> Handler Register
    getRegisterHandler regId = do
      liftIO $ putStrLn $ "Handling GET /register/" ++ show regId ++ " request"
      maybeRegister <- liftIO $ getRegisterById pool regId
      case maybeRegister of
        Just register -> return register
        Nothing -> throwError err404 { errBody = stringToLBS "Register not found" }

    createRegisterHandler :: Register -> Handler Register
    createRegisterHandler register = do
      liftIO $ putStrLn "Handling POST /register request"
      createdRegister <- liftIO $ createRegister pool register
      return createdRegister

    updateRegisterHandler :: UUID -> Register -> Handler Register
    updateRegisterHandler regId register = do
      liftIO $ putStrLn $ "Handling PUT /register/" ++ show regId ++ " request"
      updatedRegister <- liftIO $ updateRegister pool regId register
      return updatedRegister

    openRegisterHandler :: UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/open/" ++ show regId ++ " request"
      openedRegister <- liftIO $ openRegister pool regId request
      return openedRegister

    closeRegisterHandler :: UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/close/" ++ show regId ++ " request"
      closeResult <- liftIO $ closeRegister pool regId request
      return closeResult

ledgerServer :: Pool Connection -> Server LedgerAPI
ledgerServer _ =
  getEntriesHandler
    :<|> getEntryHandler
    :<|> getAccountsHandler
    :<|> getAccountHandler
    :<|> createAccountHandler
    :<|> dailyReportHandler
  where
    getEntriesHandler :: Handler [LedgerEntry]
    getEntriesHandler = do
      liftIO $ putStrLn "Handling GET /ledger/entry request"
      return []

    getEntryHandler :: UUID -> Handler LedgerEntry
    getEntryHandler entryId = do
      liftIO $ putStrLn $ "Handling GET /ledger/entry/" ++ show entryId ++ " request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    getAccountsHandler :: Handler [Account]
    getAccountsHandler = do
      liftIO $ putStrLn "Handling GET /ledger/account request"
      return []

    getAccountHandler :: UUID -> Handler Account
    getAccountHandler acctId = do
      liftIO $ putStrLn $ "Handling GET /ledger/account/" ++ show acctId ++ " request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    createAccountHandler :: Account -> Handler Account
    createAccountHandler _ = do
      liftIO $ putStrLn "Handling POST /ledger/account request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    dailyReportHandler :: DailyReportRequest -> Handler DailyReportResult
    dailyReportHandler _ = do
      liftIO $ putStrLn "Handling POST /ledger/report/daily request"
      return $ DailyReportResult 0 0 0 0 0

complianceServer :: Pool Connection -> Server ComplianceAPI
complianceServer _ =
  verificationHandler
    :<|> getRecordHandler
    :<|> reportHandler
  where
    verificationHandler :: CustomerVerification -> Handler CustomerVerification
    verificationHandler verification = do
      liftIO $ putStrLn "Handling POST /compliance/verification request"
      return verification

    getRecordHandler :: UUID -> Handler ComplianceRecord
    getRecordHandler txId = do
      liftIO $ putStrLn $ "Handling GET /compliance/record/" ++ show txId ++ " request"
      throwError err501 { errBody = stringToLBS "Not implemented yet" }

    reportHandler :: ComplianceReportRequest -> Handler ComplianceReportResult
    reportHandler _ = do
      liftIO $ putStrLn "Handling POST /compliance/report request"
      return $ ComplianceReportResult (pack "Report Not Implemented")

posServerImpl :: Pool Connection -> Server PosAPI
posServerImpl pool =
  transactionServer pool
    :<|> registerServer pool
    :<|> ledgerServer pool
    :<|> complianceServer pool-- END OF: ./backend/src/Server/Transaction.hs

-- FILE: ./backend/src/Server/TransactionStateMachine.hs
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DerivingStrategies #-}

module Server.TransactionStateMachine where

import Crem.BaseMachine ( BaseMachineT, InitialState(..), pureResult, ActionResult(..) )
import Crem.Render.RenderableVertices (RenderableVertices(..))
import Crem.StateMachine (StateMachineT, StateMachine, run)
import Crem.Topology (Topology(..))
import Data.UUID (UUID)
import Data.Text (Text)
import Data.Pool (Pool)
import Database.PostgreSQL.Simple (Connection)
import Servant hiding (STrue, SFalse)
import Types.Transaction
import DB.Transaction
import API.Transaction
import Control.Monad.IO.Class (liftIO)
import Data.Time (getCurrentTime)
import Service.Transaction (TransactionEvent(..))
import Crem.Render.Render (Mermaid(..), renderStateDiagram, getText)
import qualified Data.Text as Text
import qualified Data.Singletons.Base.TH as STH

$(STH.singletons [d|
  data TransactionStateVertex
    = NotStarted
    | TxCreated
    | TxInProgress
    | TxCompleted
    | TxVoided
    | TxRefunded
    deriving (Eq, Show, Enum, Bounded)

  transactionStateTopology :: Topology TransactionStateVertex
  transactionStateTopology = Topology
    [ (NotStarted, [TxCreated])
    , (TxCreated, [TxInProgress])
    , (TxInProgress, [TxCompleted, TxVoided])
    , (TxCompleted, [TxVoided, TxRefunded])
    , (TxVoided, [])
    , (TxRefunded, [])
    ]
  |])

deriving via AllVertices TransactionStateVertex instance RenderableVertices TransactionStateVertex

data TransactionState (vertex :: TransactionVertex) where
  CreatedState :: Transaction -> TransactionState 'Created
  InProgressState :: Transaction -> TransactionState 'InProgress
  CompletedState :: Transaction -> TransactionState 'Completed
  VoidedState :: Transaction -> TransactionState 'Voided
  RefundedState :: Transaction -> TransactionState 'Refunded

transactionBasic :: Pool Connection -> BaseMachine TransactionTopology TransactionCommand Transaction
transactionBasic pool =
  BaseMachineT
    { initialState = InitialState (CreatedState emptyTransaction)
    , action = handleCommand
    }
  where
    emptyTransaction :: Transaction
    emptyTransaction = undefined

    handleCommand :: TransactionState vertex -> TransactionCommand -> ActionResult IO TransactionTopology TransactionState vertex Transaction
    handleCommand (CreatedState tx) (AddItem item) = do
      updatedTx <- liftIO $ addTransactionItem pool item
      pureResult updatedTx (InProgressState updatedTx)

    handleCommand (InProgressState tx) (AddItem item) = do
      updatedTx <- liftIO $ addTransactionItem pool item
      pureResult updatedTx (InProgressState updatedTx)

    handleCommand (InProgressState tx) (RemoveItem itemId) = do
      liftIO $ deleteTransactionItem pool itemId

      updatedTx <- liftIO $ getTransactionById pool (transactionId tx)
      case updatedTx of
        Just tx' -> pureResult tx' (InProgressState tx')
        Nothing -> pureResult tx (InProgressState tx)

    handleCommand (InProgressState tx) (AddPayment payment) = do
      addedPayment <- liftIO $ addPaymentTransaction pool payment

      updatedTx <- liftIO $ getTransactionById pool (transactionId tx)
      case updatedTx of
        Just tx' ->

          if transactionTotal tx' <= sum (paymentAmount <$> transactionPayments tx')
          then pureResult tx' (CompletedState tx')
          else pureResult tx' (InProgressState tx')
        Nothing -> pureResult tx (InProgressState tx)

    handleCommand (InProgressState tx) FinalizeTransaction = do
      finalizedTx <- liftIO $ finalizeTransaction pool (transactionId tx)
      pureResult finalizedTx (CompletedState finalizedTx)

    handleCommand (CompletedState tx) (VoidTransaction reason) = do
      voidedTx <- liftIO $ voidTransaction pool (transactionId tx) reason
      pureResult voidedTx (VoidedState voidedTx)

    handleCommand (CompletedState tx) (RefundTransaction reason) = do
      refundedTx <- liftIO $ refundTransaction pool (transactionId tx) reason
      pureResult refundedTx (RefundedState refundedTx)

    handleCommand (VoidedState tx) _ =
      pureResult tx (VoidedState tx)

    handleCommand (RefundedState tx) _ =
      pureResult tx (RefundedState tx)

data TransactionCommand
  = AddItem TransactionItem
  | RemoveItem UUID
  | AddPayment PaymentTransaction
  | RemovePayment UUID
  | FinalizeTransaction
  | VoidTransaction Text
  | RefundTransaction Text

transaction :: Pool Connection -> StateMachine TransactionCommand Transaction
transaction pool = Basic (transactionBasic pool)

posServerStateMachineImpl :: Pool Connection -> Server PosAPI
posServerStateMachineImpl pool =
  transactionServerStateMachine pool
    :<|> registerServer pool
    :<|> ledgerServer pool
    :<|> complianceServer pool

transactionServerStateMachine :: Pool Connection -> Server TransactionAPI
transactionServerStateMachine pool =
  getAllTransactionsHandler
    :<|> getTransactionHandler
    :<|> createTransactionHandler
    :<|> updateTransactionHandler
    :<|> voidTransactionHandler
    :<|> refundTransactionHandler
    :<|> addTransactionItemHandler
    :<|> removeTransactionItemHandler
    :<|> addPaymentTransactionHandler
    :<|> removePaymentTransactionHandler
    :<|> finalizeTransactionHandler
  where
    getAllTransactionsHandler :: Handler [Transaction]
    getAllTransactionsHandler = do
      liftIO $ putStrLn "Handling GET /transaction request (StateMachine)"
      transactions <- liftIO $ getAllTransactions pool
      liftIO $ putStrLn $ "Returning " ++ show (length transactions) ++ " transactions"
      return transactions

    getTransactionHandler :: UUID -> Handler Transaction
    getTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling GET /transaction/" ++ show txId ++ " request (StateMachine)"
      maybeTransaction <- liftIO $ getTransactionById pool txId
      case maybeTransaction of
        Just transaction -> return transaction
        Nothing -> throwError err404 { errBody = "Transaction not found" }

    createTransactionHandler :: Transaction -> Handler Transaction
    createTransactionHandler transaction = do
      liftIO $ putStrLn "Handling POST /transaction request (StateMachine)"
      liftIO $ putStrLn $ "Creating transaction: " ++ show (transactionId transaction)
      createdTransaction <- liftIO $ createTransaction pool transaction
      liftIO $ putStrLn "Transaction created successfully"
      return createdTransaction

    updateTransactionHandler :: UUID -> Transaction -> Handler Transaction
    updateTransactionHandler txId transaction = do
      liftIO $ putStrLn $ "Handling PUT /transaction/" ++ show txId ++ " request (StateMachine)"
      updatedTransaction <- liftIO $ updateTransaction pool txId transaction
      liftIO $ putStrLn "Transaction updated successfully"
      return updatedTransaction

    voidTransactionHandler :: UUID -> Text -> Handler Transaction
    voidTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/void/" ++ show txId ++ " request (StateMachine)"

      maybeTransaction <- liftIO $ getTransactionById pool txId
      case maybeTransaction of
        Just tx -> do
          let command = VoidTransaction reason
          let stMachine =
                case transactionStatus tx of
                  Completed -> transaction pool
                  _ -> transaction pool
          (voidedTransaction, _) <- liftIO $ run stMachine command
          liftIO $ putStrLn "Transaction voided successfully"
          return voidedTransaction
        Nothing -> throwError err404 { errBody = "Transaction not found" }

    refundTransactionHandler :: UUID -> Text -> Handler Transaction
    refundTransactionHandler txId reason = do
      liftIO $ putStrLn $ "Handling POST /transaction/refund/" ++ show txId ++ " request (StateMachine)"

      maybeTransaction <- liftIO $ getTransactionById pool txId
      case maybeTransaction of
        Just tx -> do
          let command = RefundTransaction reason
          let stMachine =
                case transactionStatus tx of
                  Completed -> transaction pool
                  _ -> transaction pool
          (refundedTransaction, _) <- liftIO $ run stMachine command
          liftIO $ putStrLn "Transaction refunded successfully"
          return refundedTransaction
        Nothing -> throwError err404 { errBody = "Transaction not found" }

    addTransactionItemHandler :: TransactionItem -> Handler TransactionItem
    addTransactionItemHandler item = do
      liftIO $ putStrLn "Handling POST /transaction/item request (StateMachine)"

      txId <- liftIO $ getTransactionIdByItemId pool (transactionItemId item)
      case txId of
        Just transactionId -> do
          maybeTransaction <- liftIO $ getTransactionById pool transactionId
          case maybeTransaction of
            Just tx -> do
              let command = AddItem item
              let stMachine =
                    case transactionStatus tx of
                      Created -> transaction pool
                      InProgress -> transaction pool
                      _ -> transaction pool
              (_, _) <- liftIO $ run stMachine command

              return item
            Nothing -> throwError err404 { errBody = "Transaction not found" }
        Nothing -> do

          liftIO $ addTransactionItem pool item

    removeTransactionItemHandler :: UUID -> Handler NoContent
    removeTransactionItemHandler itemId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/item/" ++ show itemId ++ " request (StateMachine)"

      txId <- liftIO $ getTransactionIdByItemId pool itemId
      case txId of
        Just transactionId -> do
          maybeTransaction <- liftIO $ getTransactionById pool transactionId
          case maybeTransaction of
            Just tx -> do
              let command = RemoveItem itemId
              let stMachine =
                    case transactionStatus tx of
                      InProgress -> transaction pool
                      _ -> transaction pool
              (_, _) <- liftIO $ run stMachine command
              return NoContent
            Nothing -> throwError err404 { errBody = "Transaction not found" }
        Nothing -> throwError err404 { errBody = "Transaction item not found" }

    addPaymentTransactionHandler :: PaymentTransaction -> Handler PaymentTransaction
    addPaymentTransactionHandler payment = do
      liftIO $ putStrLn "Handling POST /transaction/payment request (StateMachine)"

      maybeTransaction <- liftIO $ getTransactionById pool (paymentTransactionId payment)
      case maybeTransaction of
        Just tx -> do
          let command = AddPayment payment
          let stMachine =
                case transactionStatus tx of
                  InProgress -> transaction pool
                  _ -> transaction pool
          (_, _) <- liftIO $ run stMachine command

          return payment
        Nothing -> throwError err404 { errBody = "Transaction not found" }

    removePaymentTransactionHandler :: UUID -> Handler NoContent
    removePaymentTransactionHandler pymtId = do
      liftIO $ putStrLn $ "Handling DELETE /transaction/payment/" ++ show pymtId ++ " request (StateMachine)"
      liftIO $ deletePaymentTransaction pool pymtId
      liftIO $ putStrLn "Payment transaction deleted successfully"
      return NoContent

    finalizeTransactionHandler :: UUID -> Handler Transaction
    finalizeTransactionHandler txId = do
      liftIO $ putStrLn $ "Handling POST /transaction/finalize/" ++ show txId ++ " request (StateMachine)"

      maybeTransaction <- liftIO $ getTransactionById pool txId
      case maybeTransaction of
        Just tx -> do
          let command = FinalizeTransaction
          let stMachine =
                case transactionStatus tx of
                  InProgress -> transaction pool
                  _ -> transaction pool
          (finalizedTransaction, _) <- liftIO $ run stMachine command
          liftIO $ putStrLn "Transaction finalized successfully"
          return finalizedTransaction
        Nothing -> throwError err404 { errBody = "Transaction not found" }

registerServer :: Pool Connection -> Server RegisterAPI
registerServer pool =
  getAllRegistersHandler
    :<|> getRegisterHandler
    :<|> createRegisterHandler
    :<|> updateRegisterHandler
    :<|> openRegisterHandler
    :<|> closeRegisterHandler
  where
    getAllRegistersHandler :: Handler [Register]
    getAllRegistersHandler = do
      liftIO $ putStrLn "Handling GET /register request"
      liftIO $ getAllRegisters pool

    getRegisterHandler :: UUID -> Handler Register
    getRegisterHandler regId = do
      liftIO $ putStrLn $ "Handling GET /register/" ++ show regId ++ " request"
      maybeRegister <- liftIO $ getRegisterById pool regId
      case maybeRegister of
        Just register -> return register
        Nothing -> throwError err404 { errBody = "Register not found" }

    createRegisterHandler :: Register -> Handler Register
    createRegisterHandler register = do
      liftIO $ putStrLn "Handling POST /register request"
      liftIO $ createRegister pool register

    updateRegisterHandler :: UUID -> Register -> Handler Register
    updateRegisterHandler regId register = do
      liftIO $ putStrLn $ "Handling PUT /register/" ++ show regId ++ " request"
      liftIO $ updateRegister pool regId register

    openRegisterHandler :: UUID -> OpenRegisterRequest -> Handler Register
    openRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/open/" ++ show regId ++ " request"
      liftIO $ openRegister pool regId request

    closeRegisterHandler :: UUID -> CloseRegisterRequest -> Handler CloseRegisterResult
    closeRegisterHandler regId request = do
      liftIO $ putStrLn $ "Handling POST /register/close/" ++ show regId ++ " request"
      liftIO $ closeRegister pool regId request

ledgerServer :: Pool Connection -> Server LedgerAPI
ledgerServer _ =
  getEntriesHandler
    :<|> getEntryHandler
    :<|> getAccountsHandler
    :<|> getAccountHandler
    :<|> createAccountHandler
    :<|> dailyReportHandler
  where
    getEntriesHandler :: Handler [LedgerEntry]
    getEntriesHandler = do
      liftIO $ putStrLn "Handling GET /ledger/entry request"
      return []

    getEntryHandler :: UUID -> Handler LedgerEntry
    getEntryHandler entryId = do
      liftIO $ putStrLn $ "Handling GET /ledger/entry/" ++ show entryId ++ " request"
      throwError err501 { errBody = "Not implemented yet" }

    getAccountsHandler :: Handler [Account]
    getAccountsHandler = do
      liftIO $ putStrLn "Handling GET /ledger/account request"
      return []

    getAccountHandler :: UUID -> Handler Account
    getAccountHandler acctId = do
      liftIO $ putStrLn $ "Handling GET /ledger/account/" ++ show acctId ++ " request"
      throwError err501 { errBody = "Not implemented yet" }

    createAccountHandler :: Account -> Handler Account
    createAccountHandler _ = do
      liftIO $ putStrLn "Handling POST /ledger/account request"
      throwError err501 { errBody = "Not implemented yet" }

    dailyReportHandler :: DailyReportRequest -> Handler DailyReportResult
    dailyReportHandler _ = do
      liftIO $ putStrLn "Handling POST /ledger/report/daily request"
      return $ DailyReportResult 0 0 0 0 0

complianceServer :: Pool Connection -> Server ComplianceAPI
complianceServer _ =
  verificationHandler
    :<|> getRecordHandler
    :<|> reportHandler
  where
    verificationHandler :: CustomerVerification -> Handler CustomerVerification
    verificationHandler verification = do
      liftIO $ putStrLn "Handling POST /compliance/verification request"
      return verification

    getRecordHandler :: UUID -> Handler ComplianceRecord
    getRecordHandler txId = do
      liftIO $ putStrLn $ "Handling GET /compliance/record/" ++ show txId ++ " request"
      throwError err501 { errBody = "Not implemented yet" }

    reportHandler :: ComplianceReportRequest -> Handler ComplianceReportResult
    reportHandler _ = do
      liftIO $ putStrLn "Handling POST /compliance/report request"
      return $ ComplianceReportResult "Report Not Implemented"-- END OF: ./backend/src/Server/TransactionStateMachine.hs

-- FILE: ./backend/src/Service/Transaction.hs
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ImpredicativeTypes #-}

module Service.Transaction where

import qualified State.Transaction as State
import Control.Monad.Except (ExceptT, throwError, runExceptT)
import Control.Monad.Trans (lift)
import Control.Monad.IO.Class (liftIO)
import Data.Pool (Pool)
import Data.UUID (UUID)
import Data.UUID.V4 (nextRandom)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import qualified Data.Foldable as Foldable
import Database.PostgreSQL.Simple (Connection)
import Types.Transaction
import qualified DB.Transaction as DB
import Crem.BaseMachine (BaseMachineT, InitialState(..), pureResult)
import Crem.StateMachine (StateMachineT, StateMachine, run, runMultiple)
import Crem.Topology (Topology)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Servant (Handler, err400, errBody, NoContent(..))
import Data.Functor.Identity (Identity, runIdentity)

data TransactionEvent
  = TransactionCreated UUID
  | ItemAdded TransactionItem
  | ItemUpdated TransactionItem
  | ItemRemoved UUID
  | PaymentAdded PaymentTransaction
  | PaymentRemoved UUID
  | TransactionFinalized UTCTime
  | TransactionVoided Text UTCTime
  | TransactionRefunded Text UTCTime UUID
  | IllegalStateTransition Text

data TransactionCommand
  = InitTransaction UUID UTCTime UUID UUID UUID
  | AddItem TransactionItem
  | RemoveItem UUID
  | AddPayment PaymentTransaction
  | RemovePayment UUID
  | FinalizeTransaction UTCTime
  | VoidTransaction Text UTCTime
  | RefundTransaction Text UTCTime UUID

type TransactionOperation a = ExceptT Text IO a

errorMsg :: Text -> LBS.ByteString
errorMsg = LBS.pack . T.unpack

runTransactionOp :: TransactionOperation a -> Handler a
runTransactionOp op = do
  result <- liftIO $ runExceptT op
  case result of
    Left err -> throwError $ err400 { errBody = errorMsg err }
    Right val -> return val

createNewTransaction :: Pool Connection -> Transaction -> Handler Transaction
createNewTransaction pool transaction = runTransactionOp $ do

  let transId = transactionId transaction
      employeeId = transactionEmployeeId transaction
      registerId = transactionRegisterId transaction
      locationId = transactionLocationId transaction


  now <- liftIO getCurrentTime


  let machine = State.createTransaction transId now employeeId registerId locationId


  (event, updatedMachine) <- lift $ return $
    runIdentity $ run machine (InitTransaction transId now employeeId registerId locationId)


  case event of
    TransactionCreated _ -> do

      createdTx <- liftIO $ DB.createTransaction pool transaction
      return createdTx

    IllegalStateTransition reason ->
      throwError $ "Failed to create transaction: " <> reason

    _ -> throwError "Unexpected event during transaction creation"

loadTransactionMachine :: Pool Connection -> UUID -> TransactionOperation (StateMachine TransactionCommand State.TransactionEvent, Transaction)
loadTransactionMachine pool txId = do

  maybeTx <- liftIO $ DB.getTransactionById pool txId

  case maybeTx of
    Nothing -> throwError $ "Transaction not found: " <> T.pack (show txId)
    Just tx -> do

      case State.fromTransaction tx of
        Left err -> throwError $ "Invalid transaction state: " <> err
        Right (sing, state) -> do

          let machine = State.transactionMachine sing state
          return (machine, tx)

addTransactionItem :: Pool Connection -> TransactionItem -> Handler TransactionItem
addTransactionItem pool item = runTransactionOp $ do
  let txId = transactionItemTransactionId item


  (machine, _) <- loadTransactionMachine pool txId


  (event, _) <- lift $ return $ runIdentity $ run machine (AddItem item)

  case event of
    State.ItemAdded _ -> do

      addedItem <- liftIO $ DB.addTransactionItem pool item
      return addedItem

    State.IllegalStateTransition reason ->
      throwError $ "Failed to add item: " <> reason

    _ -> throwError "Unexpected event when adding item"

removeTransactionItem :: Pool Connection -> UUID -> Handler NoContent
removeTransactionItem pool itemId = runTransactionOp $ do

  txIdResult <- liftIO $ DB.getTransactionIdByItemId pool itemId

  case txIdResult of
    Nothing -> throwError $ "Item not found: " <> T.pack (show itemId)
    Just txId -> do

      (machine, _) <- loadTransactionMachine pool txId


      (event, _) <- lift $ return $ runIdentity $ run machine (RemoveItem itemId)

      case event of
        State.ItemRemoved _ -> do

          liftIO $ DB.deleteTransactionItem pool itemId
          return NoContent

        State.IllegalStateTransition reason ->
          throwError $ "Failed to remove item: " <> reason

        _ -> throwError "Unexpected event when removing item"

addPaymentTransaction :: Pool Connection -> PaymentTransaction -> Handler PaymentTransaction
addPaymentTransaction pool payment = runTransactionOp $ do
  let txId = paymentTransactionId payment


  (machine, _) <- loadTransactionMachine pool txId


  (event, _) <- lift $ return $ runIdentity $ run machine (AddPayment payment)

  case event of
    State.PaymentAdded _ -> do

      addedPayment <- liftIO $ DB.addPaymentTransaction pool payment
      return addedPayment

    State.IllegalStateTransition reason ->
      throwError $ "Failed to add payment: " <> reason

    _ -> throwError "Unexpected event when adding payment"

removePaymentTransaction :: Pool Connection -> UUID -> Handler NoContent
removePaymentTransaction pool paymentId = runTransactionOp $ do

  txIdResult <- liftIO $ DB.getTransactionIdByPaymentId pool paymentId

  case txIdResult of
    Nothing -> throwError $ "Payment not found: " <> T.pack (show paymentId)
    Just txId -> do

      (machine, _) <- loadTransactionMachine pool txId


      (event, _) <- lift $ return $ runIdentity $ run machine (RemovePayment paymentId)

      case event of
        State.PaymentRemoved _ -> do

          liftIO $ DB.deletePaymentTransaction pool paymentId
          return NoContent

        State.IllegalStateTransition reason ->
          throwError $ "Failed to remove payment: " <> reason

        _ -> throwError "Unexpected event when removing payment"

finalizeTransaction :: Pool Connection -> UUID -> Handler Transaction
finalizeTransaction pool txId = runTransactionOp $ do

  (machine, tx) <- loadTransactionMachine pool txId


  now <- liftIO getCurrentTime


  (event, updatedMachine) <- lift $ return $ runIdentity $ run machine (FinalizeTransaction now)


  case event of
    State.TransactionFinalized timestamp -> do

      finalizedTx <- liftIO $ DB.finalizeTransaction pool txId
      return finalizedTx

    State.IllegalStateTransition reason ->
      throwError $ "Failed to finalize transaction: " <> reason

    _ -> throwError "Unexpected event when finalizing transaction"

voidTransaction :: Pool Connection -> UUID -> Text -> Handler Transaction
voidTransaction pool txId reason = runTransactionOp $ do

  (machine, tx) <- loadTransactionMachine pool txId


  now <- liftIO getCurrentTime


  (event, updatedMachine) <- lift $ return $ runIdentity $ run machine (VoidTransaction reason now)


  case event of
    State.TransactionVoided _ timestamp -> do

      voidedTx <- liftIO $ DB.voidTransaction pool txId reason
      return voidedTx

    State.IllegalStateTransition reason' ->
      throwError $ "Failed to void transaction: " <> reason'

    _ -> throwError "Unexpected event when voiding transaction"

refundTransaction :: Pool Connection -> UUID -> Text -> Handler Transaction
refundTransaction pool txId reason = runTransactionOp $ do

  (machine, tx) <- loadTransactionMachine pool txId


  now <- liftIO getCurrentTime


  refundId <- liftIO nextRandom


  (event, updatedMachine) <- lift $ return $
    runIdentity $ run machine (RefundTransaction reason now refundId)


  case event of
    State.TransactionRefunded _ timestamp refTxId -> do

      refundedTx <- liftIO $ DB.refundTransaction pool txId reason
      return refundedTx

    State.IllegalStateTransition reason' ->
      throwError $ "Failed to refund transaction: " <> reason'

    _ -> throwError "Unexpected event when refunding transaction"

getAllTransactions :: Pool Connection -> Handler [Transaction]
getAllTransactions pool = liftIO $ DB.getAllTransactions pool

getTransaction :: Pool Connection -> UUID -> Handler Transaction
getTransaction pool txId = runTransactionOp $ do
  maybeTx <- liftIO $ DB.getTransactionById pool txId
  case maybeTx of
    Nothing -> throwError $ "Transaction not found: " <> T.pack (show txId)
    Just tx -> return tx

updateTransaction :: Pool Connection -> UUID -> Transaction -> Handler Transaction
updateTransaction pool txId transaction = runTransactionOp $ do

  let commands = transactionToCommands transaction


  updateTransactionWithCommands pool txId commands

transactionToCommands :: Transaction -> [TransactionCommand]
transactionToCommands tx =

  (map AddItem (transactionItems tx)) ++


  (map AddPayment (transactionPayments tx)) ++


  (if transactionStatus tx == Completed && transactionCompleted tx /= Nothing
   then [FinalizeTransaction (maybe (transactionCreated tx) id (transactionCompleted tx))]
   else []) ++


  (if transactionIsVoided tx
   then [VoidTransaction
          (maybe "No reason provided" id (transactionVoidReason tx))
          (maybe (transactionCreated tx) id (transactionCompleted tx))]
   else []) ++


  (if transactionIsRefunded tx
   then case transactionReferenceTransactionId tx of
          Just refTxId -> [RefundTransaction
                            (maybe "No reason provided" id (transactionRefundReason tx))
                            (maybe (transactionCreated tx) id (transactionCompleted tx))
                            refTxId]
          Nothing -> []
   else [])

updateTransactionWithCommands :: Pool Connection -> UUID -> [TransactionCommand] -> TransactionOperation Transaction
updateTransactionWithCommands pool txId commands = do

  (machine, tx) <- loadTransactionMachine pool txId


  (events, updatedMachine) <- lift $ return $ runIdentity $ runMultiple machine commands


  let illegalEvents = [reason | State.IllegalStateTransition reason <- Foldable.toList events]
  if not (null illegalEvents)
    then throwError $ "Failed to update transaction: " <> T.unlines illegalEvents
    else do

      processEvents pool txId (Foldable.toList events)


      updatedTx <- liftIO $ DB.getTransactionById pool txId
      case updatedTx of
        Nothing -> throwError "Transaction disappeared after update"
        Just tx' -> return tx'

processEvents :: Pool Connection -> UUID -> [State.TransactionEvent] -> TransactionOperation ()
processEvents pool txId events = do
  mapM_ (processEvent pool txId) events

processEvent :: Pool Connection -> UUID -> State.TransactionEvent -> TransactionOperation ()
processEvent pool txId event = case event of
  State.TransactionCreated _ ->
    return ()

  State.ItemAdded item ->
    void $ liftIO $ DB.addTransactionItem pool item

  State.ItemUpdated item ->
    void $ liftIO $ updateTransactionItem pool item

  State.ItemRemoved itemId ->
    liftIO $ DB.deleteTransactionItem pool itemId

  State.PaymentAdded payment ->
    void $ liftIO $ DB.addPaymentTransaction pool payment

  State.PaymentRemoved paymentId ->
    liftIO $ DB.deletePaymentTransaction pool paymentId

  State.TransactionFinalized _ ->
    void $ liftIO $ DB.finalizeTransaction pool txId

  State.TransactionVoided reason _ ->
    void $ liftIO $ DB.voidTransaction pool txId reason

  State.TransactionRefunded reason _ refTxId ->
    void $ liftIO $ DB.refundTransaction pool txId reason

  State.IllegalStateTransition _ ->
    return ()
  where
    void :: Monad m => m a -> m ()
    void action = action >> return ()

updateTransactionItem :: Pool Connection -> TransactionItem -> IO TransactionItem
updateTransactionItem pool item = do

  DB.deleteTransactionItem pool (transactionItemId item)
  DB.addTransactionItem pool item-- END OF: ./backend/src/Service/Transaction.hs

-- FILE: ./backend/src/State/Topology.hs
{-# LANGUAGE TypeFamilies #-}

module State.Topology where

import Data.Aeson (ToJSON(..), FromJSON(..))
import GHC.Generics (Generic)
import Data.Kind (Type)
import State.Transaction (TransactionVertex(..))
import Crem.Topology (Topology)

type TransactionTopology = 'Topology '[ '(TxCreated, '[TxInProgress, TxVoided])
                                       , '(TxInProgress, '[TxCompleted, TxVoided])
                                       , '(TxCompleted, '[TxRefunded])
                                       , '(TxVoided, '[])
                                       , '(TxRefunded, '[])
                                       ]

type family AllowedTransition (from :: TransactionVertex) (to :: TransactionVertex) :: Bool where

  AllowedTransition 'TxCreated 'TxInProgress = 'True
  AllowedTransition 'TxCreated 'TxVoided = 'True


  AllowedTransition 'TxInProgress 'TxCompleted = 'True
  AllowedTransition 'TxInProgress 'TxVoided = 'True


  AllowedTransition 'TxCompleted 'TxRefunded = 'True


  AllowedTransition _ _ = 'False

class ValidTransition (from :: TransactionVertex) (to :: TransactionVertex) where
  validateTransition :: proxy from -> proxy to -> Bool
  validateTransition _ _ = True

instance (AllowedTransition from to ~ 'True) => ValidTransition from to-- END OF: ./backend/src/State/Topology.hs

-- FILE: ./backend/src/Types/Inventory.hs
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Types.Inventory where

import Data.Aeson
    ( ToJSON(toJSON), FromJSON(parseJSON), object, KeyValue((.=)) )
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID ( UUID )
import qualified Data.Vector as V
import Database.PostgreSQL.Simple.FromRow (FromRow (..), field)
import Database.PostgreSQL.Simple.ToField (ToField (..))
import Database.PostgreSQL.Simple.ToRow (ToRow (..))
import Database.PostgreSQL.Simple.Types (PGArray (..))
import GHC.Generics ( Generic )

data Species
  = Indica
  | IndicaDominantHybrid
  | Hybrid
  | SativaDominantHybrid
  | Sativa
  deriving (Show, Eq, Ord, Generic, FromJSON, ToJSON, Read)

data ItemCategory
  = Flower
  | PreRolls
  | Vaporizers
  | Edibles
  | Drinks
  | Concentrates
  | Topicals
  | Tinctures
  | Accessories
  deriving (Show, Eq, Ord, Generic, FromJSON, ToJSON, Read)

data StrainLineage = StrainLineage
  { thc :: Text
  , cbg :: Text
  , strain :: Text
  , creator :: Text
  , species :: Species
  , dominant_terpene :: Text
  , terpenes :: V.Vector Text
  , lineage :: V.Vector Text
  , leafly_url :: Text
  , img :: Text
  }
  deriving (Show, Generic)

instance ToJSON StrainLineage
instance FromJSON StrainLineage

data MenuItem = MenuItem
  { sort :: Int
  , sku :: UUID
  , brand :: Text
  , name :: Text
  , price :: Int
  , measure_unit :: Text
  , per_package :: Text
  , quantity :: Int
  , category :: ItemCategory
  , subcategory :: Text
  , description :: Text
  , tags :: V.Vector Text
  , effects :: V.Vector Text
  , strain_lineage :: StrainLineage
  }
  deriving (Show, Generic)

instance ToJSON MenuItem
instance FromJSON MenuItem

instance ToRow MenuItem where
  toRow MenuItem {..} =
    [ toField sort
    , toField sku
    , toField brand
    , toField name
    , toField price
    , toField measure_unit
    , toField per_package
    , toField quantity
    , toField (show category)
    , toField subcategory
    , toField description
    , toField (PGArray $ V.toList tags)
    , toField (PGArray $ V.toList effects)
    ]

instance FromRow MenuItem where
  fromRow =
    MenuItem
      <$> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> (read <$> field)
      <*> field
      <*> field
      <*> (V.fromList . fromPGArray <$> field)
      <*> (V.fromList . fromPGArray <$> field)
      <*> ( StrainLineage
              <$> field
              <*> field
              <*> field
              <*> field
              <*> (read <$> field)
              <*> field
              <*> (V.fromList . fromPGArray <$> field)
              <*> (V.fromList . fromPGArray <$> field)
              <*> field
              <*> field
          )

newtype Inventory = Inventory
  { items :: V.Vector MenuItem
  }
  deriving (Show, Generic)

instance ToJSON Inventory where
  toJSON (Inventory {items = items}) = toJSON items

instance FromJSON Inventory where
  parseJSON v = Inventory <$> parseJSON v

data InventoryResponse
  = InventoryData Inventory
  | Message Text
  deriving (Show, Generic)

instance ToJSON InventoryResponse where
  toJSON (InventoryData inv) =
    object
      [ "type" .= T.pack "data"
      , "value" .= toJSON inv
      ]
  toJSON (Message msg) =
    object
      [ "type" .= T.pack "message"
      , "value" .= msg
      ]

instance FromJSON InventoryResponse
-- END OF: ./backend/src/Types/Inventory.hs

-- FILE: ./backend/src/Types/Transaction.hs
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Types.Transaction where

import Data.UUID (UUID)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Scientific (Scientific)
import Data.Aeson (ToJSON(..), FromJSON(..))
import GHC.Generics
import Database.PostgreSQL.Simple.FromRow (FromRow(..), field)

data TransactionStatus
  = Created
  | InProgress
  | Completed
  | Voided
  | Refunded
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON TransactionStatus
instance FromJSON TransactionStatus

data TransactionType
  = Sale
  | Return
  | Exchange
  | InventoryAdjustment
  | ManagerComp
  | Administrative
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON TransactionType
instance FromJSON TransactionType

data PaymentMethod
  = Cash
  | Debit
  | Credit
  | ACH
  | GiftCard
  | StoredValue
  | Mixed
  | Other Text
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON PaymentMethod
instance FromJSON PaymentMethod

data TaxCategory
  = RegularSalesTax
  | ExciseTax
  | CannabisTax
  | LocalTax
  | MedicalTax
  | NoTax
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON TaxCategory
instance FromJSON TaxCategory

data DiscountType
  = PercentOff Scientific
  | AmountOff Int
  | BuyOneGetOne
  | Custom Text Int
  deriving (Show, Eq, Ord, Generic)

instance ToJSON DiscountType
instance FromJSON DiscountType

data TaxRecord = TaxRecord
  { taxCategory :: TaxCategory
  , taxRate :: Scientific
  , taxAmount :: Int
  , taxDescription :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON TaxRecord
instance FromJSON TaxRecord

data DiscountRecord = DiscountRecord
  { discountType :: DiscountType
  , discountAmount :: Int
  , discountReason :: Text
  , discountApprovedBy :: Maybe UUID
  } deriving (Show, Eq, Generic)

instance ToJSON DiscountRecord
instance FromJSON DiscountRecord

data TransactionItem = TransactionItem
  { transactionItemId :: UUID
  , transactionItemTransactionId :: UUID
  , transactionItemMenuItemSku :: UUID
  , transactionItemQuantity :: Int
  , transactionItemPricePerUnit :: Int
  , transactionItemDiscounts :: [DiscountRecord]
  , transactionItemTaxes :: [TaxRecord]
  , transactionItemSubtotal :: Int
  , transactionItemTotal :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON TransactionItem
instance FromJSON TransactionItem

data PaymentTransaction = PaymentTransaction
  { paymentId :: UUID
  , paymentTransactionId :: UUID
  , paymentMethod :: PaymentMethod
  , paymentAmount :: Int
  , paymentTendered :: Int
  , paymentChange :: Int
  , paymentReference :: Maybe Text
  , paymentApproved :: Bool
  , paymentAuthorizationCode :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON PaymentTransaction
instance FromJSON PaymentTransaction

data Transaction = Transaction
  { transactionId :: UUID
  , transactionStatus :: TransactionStatus
  , transactionCreated :: UTCTime
  , transactionCompleted :: Maybe UTCTime
  , transactionCustomerId :: Maybe UUID
  , transactionEmployeeId :: UUID
  , transactionRegisterId :: UUID
  , transactionLocationId :: UUID
  , transactionItems :: [TransactionItem]
  , transactionPayments :: [PaymentTransaction]
  , transactionSubtotal :: Int
  , transactionDiscountTotal :: Int
  , transactionTaxTotal :: Int
  , transactionTotal :: Int
  , transactionType :: TransactionType
  , transactionIsVoided :: Bool
  , transactionVoidReason :: Maybe Text
  , transactionIsRefunded :: Bool
  , transactionRefundReason :: Maybe Text
  , transactionReferenceTransactionId :: Maybe UUID
  , transactionNotes :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON Transaction
instance FromJSON Transaction

data LedgerEntryType
  = SaleEntry
  | Tax
  | Discount
  | Payment
  | Refund
  | Void
  | Adjustment
  | Fee
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON LedgerEntryType
instance FromJSON LedgerEntryType

data AccountType
  = Asset
  | Liability
  | Equity
  | Revenue
  | Expense
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON AccountType
instance FromJSON AccountType

data Account = Account
  { accountId :: UUID
  , accountCode :: Text
  , accountName :: Text
  , accountIsDebitNormal :: Bool
  , accountParentAccountId :: Maybe UUID
  , accountType :: AccountType
  } deriving (Show, Eq, Generic)

instance ToJSON Account
instance FromJSON Account

data LedgerEntry = LedgerEntry
  { ledgerEntryId :: UUID
  , ledgerEntryTransactionId :: UUID
  , ledgerEntryAccountId :: UUID
  , ledgerEntryAmount :: Int
  , ledgerEntryIsDebit :: Bool
  , ledgerEntryTimestamp :: UTCTime
  , ledgerEntryType :: LedgerEntryType
  , ledgerEntryDescription :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON LedgerEntry
instance FromJSON LedgerEntry

data VerificationType
  = AgeVerification
  | MedicalCardVerification
  | IDScan
  | VisualInspection
  | PatientRegistration
  | PurchaseLimitCheck
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON VerificationType
instance FromJSON VerificationType

data VerificationStatus
  = VerifiedStatus
  | FailedStatus
  | ExpiredStatus
  | NotRequiredStatus
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON VerificationStatus
instance FromJSON VerificationStatus

data CustomerVerification = CustomerVerification
  { customerVerificationId :: UUID
  , customerVerificationCustomerId :: UUID
  , customerVerificationType :: VerificationType
  , customerVerificationStatus :: VerificationStatus
  , customerVerificationVerifiedBy :: UUID
  , customerVerificationVerifiedAt :: UTCTime
  , customerVerificationExpiresAt :: Maybe UTCTime
  , customerVerificationNotes :: Maybe Text
  , customerVerificationDocumentId :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON CustomerVerification
instance FromJSON CustomerVerification

data ReportingStatus
  = NotRequired
  | Pending
  | Submitted
  | Acknowledged
  | Failed
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON ReportingStatus
instance FromJSON ReportingStatus

data ComplianceRecord = ComplianceRecord
  { complianceRecordId :: UUID
  , complianceRecordTransactionId :: UUID
  , complianceRecordVerifications :: [CustomerVerification]
  , complianceRecordIsCompliant :: Bool
  , complianceRecordRequiresStateReporting :: Bool
  , complianceRecordReportingStatus :: ReportingStatus
  , complianceRecordReportedAt :: Maybe UTCTime
  , complianceRecordReferenceId :: Maybe Text
  , complianceRecordNotes :: Maybe Text
  } deriving (Show, Eq, Generic)

instance ToJSON ComplianceRecord
instance FromJSON ComplianceRecord

data InventoryStatus
  = Available
  | OnHold
  | Reserved
  | Sold
  | Damaged
  | Expired
  | InTransit
  | UnderReview
  | Recalled
  deriving (Show, Eq, Ord, Generic, Read)

instance ToJSON InventoryStatus
instance FromJSON InventoryStatus

instance FromRow Transaction where
  fromRow =
    Transaction
      <$> field
      <*> (read <$> field)
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> pure []
      <*> pure []
      <*> field
      <*> field
      <*> field
      <*> field
      <*> (read <$> field)
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field

instance FromRow TransactionItem where
  fromRow =
    TransactionItem
      <$> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> pure []
      <*> pure []
      <*> field
      <*> field

instance FromRow DiscountRecord where
  fromRow =
    DiscountRecord
      <$> (parseDiscountType <$> field <*> field)
      <*> field
      <*> field
      <*> field

parseDiscountType :: Text -> Maybe Int -> DiscountType
parseDiscountType typ (Just val)
  | typ == "PERCENT_OFF" = PercentOff (fromIntegral val / 100)
  | typ == "AMOUNT_OFF" = AmountOff val
  | typ == "BUY_ONE_GET_ONE" = BuyOneGetOne
  | otherwise = Custom typ val
parseDiscountType typ _
  | typ == "BUY_ONE_GET_ONE" = BuyOneGetOne
  | otherwise = AmountOff 0

instance FromRow TaxRecord where
  fromRow =
    TaxRecord
      <$> (read <$> field)
      <*> field
      <*> field
      <*> field

instance FromRow PaymentTransaction where
  fromRow =
    PaymentTransaction
      <$> field
      <*> field
      <*> (read <$> field)
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field
      <*> field-- END OF: ./backend/src/Types/Transaction.hs

