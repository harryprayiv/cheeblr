-- src/State/SaleTransactionMachine.hs

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
{-# OPTIONS_GHC -Wno-star-is-type -Wno-unused-top-binds #-}

-- | Sale-side transaction lifecycle, typed against 'Sale.SaleTransaction'.
--
-- Parallel to 'State.TransactionMachine' during the migration window. The
-- legacy machine still exists and still operates on the untyped
-- 'Legacy.Transaction'; this one operates on the typed 'Sale.SaleTransaction'.
-- 2E-5 switches the service layer over; once nothing imports the legacy
-- machine, it gets deleted in cleanup, and the vertex / state / function
-- names here can drop the 'Sale' prefix.
--
-- Topology is identical to the legacy machine.
module State.SaleTransactionMachine (
  SaleTxVertex (..),
  SSaleTxVertex (..),
  SaleTxTopology,
  SaleTxState (..),
  SomeSaleTxState (..),
  fromSaleTransaction,
  toSomeSaleTxState,
  someTxStatus,
  SaleTxCommand (..),
  SaleTxEvent (..),
  runTxCommand,
) where

import Crem.BaseMachine (ActionResult (..), pureResult)
import Crem.Render.RenderableVertices (RenderableVertices (..))
import Crem.Topology (Topology (..))
import Data.Functor.Identity (Identity, runIdentity)
import Data.Singletons.Base.TH
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import qualified Types.Transaction as Legacy
import qualified Types.Transaction.Sale as Sale

$( singletons
     [d|
       data SaleTxVertex
         = SaleCreated
         | SaleInProgress
         | SaleCompleted
         | SaleVoided
         | SaleRefunded
         deriving (Eq, Show)
       |]
 )

deriving instance Enum SaleTxVertex
deriving instance Bounded SaleTxVertex

instance RenderableVertices SaleTxVertex where
  vertices = [minBound .. maxBound]

type SaleTxTopology =
  'Topology
    '[ '( 'SaleCreated, '[ 'SaleCreated, 'SaleInProgress, 'SaleVoided])
     , '( 'SaleInProgress, '[ 'SaleInProgress, 'SaleCompleted, 'SaleVoided])
     , '( 'SaleCompleted, '[ 'SaleCompleted, 'SaleVoided, 'SaleRefunded])
     , '( 'SaleVoided, '[ 'SaleVoided])
     , '( 'SaleRefunded, '[ 'SaleRefunded])
     ]

data SaleTxState (v :: SaleTxVertex) where
  CreatedState :: Sale.SaleTransaction -> SaleTxState 'SaleCreated
  InProgressState :: Sale.SaleTransaction -> SaleTxState 'SaleInProgress
  CompletedState :: Sale.SaleTransaction -> SaleTxState 'SaleCompleted
  VoidedState :: Sale.SaleTransaction -> SaleTxState 'SaleVoided
  RefundedState :: Sale.SaleTransaction -> SaleTxState 'SaleRefunded

data SomeSaleTxState = forall v. SomeSaleTxState (SSaleTxVertex v) (SaleTxState v)

fromSaleTransaction :: Sale.SaleTransaction -> SomeSaleTxState
fromSaleTransaction sale = case Sale.saleStatus sale of
  Legacy.Created -> SomeSaleTxState SSaleCreated (CreatedState sale)
  Legacy.InProgress -> SomeSaleTxState SSaleInProgress (InProgressState sale)
  Legacy.Completed -> SomeSaleTxState SSaleCompleted (CompletedState sale)
  Legacy.Voided -> SomeSaleTxState SSaleVoided (VoidedState sale)
  Legacy.Refunded -> SomeSaleTxState SSaleRefunded (RefundedState sale)

toSomeSaleTxState :: SaleTxState v -> SomeSaleTxState
toSomeSaleTxState = \case
  st@(CreatedState _) -> SomeSaleTxState SSaleCreated st
  st@(InProgressState _) -> SomeSaleTxState SSaleInProgress st
  st@(CompletedState _) -> SomeSaleTxState SSaleCompleted st
  st@(VoidedState _) -> SomeSaleTxState SSaleVoided st
  st@(RefundedState _) -> SomeSaleTxState SSaleRefunded st

data SaleTxCommand
  = AddItemCmd Sale.Item
  | RemoveItemCmd UUID
  | AddPaymentCmd Sale.Payment
  | RemovePaymentCmd UUID
  | FinalizeCmd
  | VoidCmd Text
  | RefundCmd Text UUID
  deriving (Show, Eq, Generic)

data SaleTxEvent
  = ItemAdded Sale.Item
  | ItemRemoved UUID
  | PaymentAdded Sale.Payment
  | PaymentRemoved UUID
  | TxFinalized
  | TxWasVoided Text
  | TxWasRefunded Text UUID
  | InvalidTxCommand Text
  deriving (Show, Eq, Generic)

txAction :: SaleTxState v -> SaleTxCommand -> ActionResult Identity SaleTxTopology SaleTxState v SaleTxEvent
txAction (CreatedState sale) (AddItemCmd item) =
  pureResult
    (ItemAdded item)
    (InProgressState sale {Sale.saleStatus = Legacy.InProgress})
txAction (CreatedState sale) (VoidCmd reason) =
  pureResult
    (TxWasVoided reason)
    ( VoidedState
        sale
          { Sale.saleStatus = Legacy.Voided
          , Sale.saleIsVoided = True
          , Sale.saleVoidReason = Just reason
          }
    )
txAction (CreatedState sale) cmd =
  pureResult
    (InvalidTxCommand $ "Cannot " <> cmdLabel cmd <> " from Created")
    (CreatedState sale)
txAction (InProgressState sale) (AddItemCmd item) =
  pureResult (ItemAdded item) (InProgressState sale)
txAction (InProgressState sale) (RemoveItemCmd iid) =
  pureResult (ItemRemoved iid) (InProgressState sale)
txAction (InProgressState sale) (AddPaymentCmd payment) =
  pureResult (PaymentAdded payment) (InProgressState sale)
txAction (InProgressState sale) (RemovePaymentCmd pid) =
  pureResult (PaymentRemoved pid) (InProgressState sale)
txAction (InProgressState sale) FinalizeCmd =
  pureResult
    TxFinalized
    (CompletedState sale {Sale.saleStatus = Legacy.Completed})
txAction (InProgressState sale) (VoidCmd reason) =
  pureResult
    (TxWasVoided reason)
    ( VoidedState
        sale
          { Sale.saleStatus = Legacy.Voided
          , Sale.saleIsVoided = True
          , Sale.saleVoidReason = Just reason
          }
    )
txAction (InProgressState sale) cmd =
  pureResult
    (InvalidTxCommand $ "Cannot " <> cmdLabel cmd <> " from InProgress")
    (InProgressState sale)
txAction (CompletedState sale) (VoidCmd reason) =
  pureResult
    (TxWasVoided reason)
    ( VoidedState
        sale
          { Sale.saleStatus = Legacy.Voided
          , Sale.saleIsVoided = True
          , Sale.saleVoidReason = Just reason
          }
    )
txAction (CompletedState sale) (RefundCmd reason refundId) =
  pureResult
    (TxWasRefunded reason refundId)
    ( RefundedState
        sale
          { Sale.saleStatus = Legacy.Refunded
          , Sale.saleIsRefunded = True
          , Sale.saleRefundReason = Just reason
          }
    )
txAction (CompletedState sale) cmd =
  pureResult
    (InvalidTxCommand $ "Cannot " <> cmdLabel cmd <> " from Completed")
    (CompletedState sale)
txAction (VoidedState sale) _ = pureResult (InvalidTxCommand "Sale transaction is voided") (VoidedState sale)
txAction (RefundedState sale) _ = pureResult (InvalidTxCommand "Sale transaction is refunded") (RefundedState sale)

runTxCommand :: SomeSaleTxState -> SaleTxCommand -> (SaleTxEvent, SomeSaleTxState)
runTxCommand (SomeSaleTxState _ st) cmd =
  case txAction st cmd of
    ActionResult m ->
      let (evt, nextSt) = runIdentity m
       in (evt, toSomeSaleTxState nextSt)

cmdLabel :: SaleTxCommand -> Text
cmdLabel = \case
  AddItemCmd _ -> "AddItem"
  RemoveItemCmd _ -> "RemoveItem"
  AddPaymentCmd _ -> "AddPayment"
  RemovePaymentCmd _ -> "RemovePayment"
  FinalizeCmd -> "Finalize"
  VoidCmd _ -> "Void"
  RefundCmd _ _ -> "Refund"

someTxStatus :: SomeSaleTxState -> Legacy.TransactionStatus
someTxStatus (SomeSaleTxState sv _) = case sv of
  SSaleCreated -> Legacy.Created
  SSaleInProgress -> Legacy.InProgress
  SSaleCompleted -> Legacy.Completed
  SSaleVoided -> Legacy.Voided
  SSaleRefunded -> Legacy.Refunded