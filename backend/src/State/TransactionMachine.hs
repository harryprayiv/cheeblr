{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-star-is-type #-}
{-# OPTIONS_GHC -Wno-star-is-type -Wno-unused-top-binds #-}

module State.TransactionMachine
  (
    TxVertex (..)
  , STxVertex (..)
  , TxTopology

  , TxState (..)
  , SomeTxState (..)
  , fromTransaction
  , toSomeTxState

  , TxCommand (..)
  , TxEvent (..)

  , runTxCommand
  ) where

import Crem.BaseMachine (ActionResult (..), pureResult)
import Crem.Render.RenderableVertices (RenderableVertices (..))
import Crem.Topology (Topology (..))
import Data.Functor.Identity (Identity, runIdentity)
import Data.Singletons.Base.TH
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import qualified Types.Transaction as T

$(singletons [d|
  data TxVertex
    = TxCreated
    | TxInProgress
    | TxCompleted
    | TxVoided
    | TxRefunded
    deriving (Eq, Show)
  |])

deriving instance Enum TxVertex
deriving instance Bounded TxVertex

instance RenderableVertices TxVertex where
  vertices = [minBound .. maxBound]

type TxTopology = 'Topology
  '[ '( 'TxCreated,    '[ 'TxCreated,    'TxInProgress, 'TxVoided])
   , '( 'TxInProgress, '[ 'TxInProgress, 'TxCompleted,  'TxVoided])
   , '( 'TxCompleted,  '[ 'TxCompleted,  'TxVoided,     'TxRefunded])
   , '( 'TxVoided,     '[ 'TxVoided])
   , '( 'TxRefunded,   '[ 'TxRefunded])
   ]

data TxState (v :: TxVertex) where
  CreatedState    :: T.Transaction -> TxState 'TxCreated
  InProgressState :: T.Transaction -> TxState 'TxInProgress
  CompletedState  :: T.Transaction -> TxState 'TxCompleted
  VoidedState     :: T.Transaction -> TxState 'TxVoided
  RefundedState   :: T.Transaction -> TxState 'TxRefunded

data SomeTxState = forall v. SomeTxState (STxVertex v) (TxState v)

fromTransaction :: T.Transaction -> SomeTxState
fromTransaction tx = case T.transactionStatus tx of
  T.Created    -> SomeTxState STxCreated    (CreatedState    tx)
  T.InProgress -> SomeTxState STxInProgress (InProgressState tx)
  T.Completed  -> SomeTxState STxCompleted  (CompletedState  tx)
  T.Voided     -> SomeTxState STxVoided     (VoidedState     tx)
  T.Refunded   -> SomeTxState STxRefunded   (RefundedState   tx)

toSomeTxState :: TxState v -> SomeTxState
toSomeTxState = \case
  st@(CreatedState    _) -> SomeTxState STxCreated    st
  st@(InProgressState _) -> SomeTxState STxInProgress st
  st@(CompletedState  _) -> SomeTxState STxCompleted  st
  st@(VoidedState     _) -> SomeTxState STxVoided     st
  st@(RefundedState   _) -> SomeTxState STxRefunded   st

data TxCommand
  = AddItemCmd       T.TransactionItem
  | RemoveItemCmd    UUID
  | AddPaymentCmd    T.PaymentTransaction
  | RemovePaymentCmd UUID
  | FinalizeCmd
  | VoidCmd          Text
  | RefundCmd        Text UUID
  deriving (Show, Generic)

data TxEvent
  = ItemAdded        T.TransactionItem
  | ItemRemoved      UUID
  | PaymentAdded     T.PaymentTransaction
  | PaymentRemoved   UUID
  | TxFinalized
  | TxWasVoided      Text
  | TxWasRefunded    Text UUID
  | InvalidTxCommand Text
  deriving (Show, Generic)

txAction :: TxState v -> TxCommand -> ActionResult Identity TxTopology TxState v TxEvent

txAction (CreatedState tx) (AddItemCmd item) =
  pureResult (ItemAdded item)
    (InProgressState tx { T.transactionStatus = T.InProgress })

txAction (CreatedState tx) (VoidCmd reason) =
  pureResult (TxWasVoided reason)
    (VoidedState tx { T.transactionStatus = T.Voided
                    , T.transactionIsVoided = True
                    , T.transactionVoidReason = Just reason })

txAction (CreatedState tx) cmd =
  pureResult (InvalidTxCommand $ "Cannot " <> cmdLabel cmd <> " from Created")
    (CreatedState tx)

txAction (InProgressState tx) (AddItemCmd item) =
  pureResult (ItemAdded item) (InProgressState tx)

txAction (InProgressState tx) (RemoveItemCmd iid) =
  pureResult (ItemRemoved iid) (InProgressState tx)

txAction (InProgressState tx) (AddPaymentCmd payment) =
  pureResult (PaymentAdded payment) (InProgressState tx)

txAction (InProgressState tx) (RemovePaymentCmd pid) =
  pureResult (PaymentRemoved pid) (InProgressState tx)

txAction (InProgressState tx) FinalizeCmd =
  pureResult TxFinalized
    (CompletedState tx { T.transactionStatus = T.Completed })

txAction (InProgressState tx) (VoidCmd reason) =
  pureResult (TxWasVoided reason)
    (VoidedState tx { T.transactionStatus = T.Voided
                    , T.transactionIsVoided = True
                    , T.transactionVoidReason = Just reason })

txAction (InProgressState tx) cmd =
  pureResult (InvalidTxCommand $ "Cannot " <> cmdLabel cmd <> " from InProgress")
    (InProgressState tx)

txAction (CompletedState tx) (VoidCmd reason) =
  pureResult (TxWasVoided reason)
    (VoidedState tx { T.transactionStatus = T.Voided
                    , T.transactionIsVoided = True
                    , T.transactionVoidReason = Just reason })

txAction (CompletedState tx) (RefundCmd reason refundId) =
  pureResult (TxWasRefunded reason refundId)
    (RefundedState tx { T.transactionStatus = T.Refunded
                      , T.transactionIsRefunded = True
                      , T.transactionRefundReason = Just reason })

txAction (CompletedState tx) cmd =
  pureResult (InvalidTxCommand $ "Cannot " <> cmdLabel cmd <> " from Completed")
    (CompletedState tx)

txAction (VoidedState   tx) _ = pureResult (InvalidTxCommand "Transaction is voided")   (VoidedState   tx)
txAction (RefundedState tx) _ = pureResult (InvalidTxCommand "Transaction is refunded") (RefundedState tx)

runTxCommand :: SomeTxState -> TxCommand -> (TxEvent, SomeTxState)
runTxCommand (SomeTxState _ st) cmd =
  case txAction st cmd of
    ActionResult m ->
      let (evt, nextSt) = runIdentity m
      in  (evt, toSomeTxState nextSt)

cmdLabel :: TxCommand -> Text
cmdLabel = \case
  AddItemCmd       _ -> "AddItem"
  RemoveItemCmd    _ -> "RemoveItem"
  AddPaymentCmd    _ -> "AddPayment"
  RemovePaymentCmd _ -> "RemovePayment"
  FinalizeCmd        -> "Finalize"
  VoidCmd          _ -> "Void"
  RefundCmd        _ _ -> "Refund"