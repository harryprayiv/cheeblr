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

module State.RegisterMachine
  (
    RegVertex (..)
  , SRegVertex (..)
  , RegTopology

  , RegState (..)
  , SomeRegState (..)
  , fromRegister
  , toSomeRegState

  , RegCommand (..)
  , RegEvent (..)

  , runRegCommand
  ) where

import Crem.BaseMachine (ActionResult (..), pureResult)
import Crem.Render.RenderableVertices (RenderableVertices (..))
import Crem.Topology (Topology (..))
import Data.Functor.Identity (Identity, runIdentity)
import Data.Singletons.Base.TH
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import API.Transaction (Register (..))

$(singletons [d|
  data RegVertex = RegClosed | RegOpen
    deriving (Eq, Show)
  |])

deriving instance Enum RegVertex
deriving instance Bounded RegVertex

instance RenderableVertices RegVertex where
  vertices = [minBound .. maxBound]

type RegTopology = 'Topology
  '[ '( 'RegClosed, '[ 'RegClosed, 'RegOpen])
   , '( 'RegOpen,   '[ 'RegOpen,   'RegClosed])
   ]

data RegState (v :: RegVertex) where
  ClosedState :: Register -> RegState 'RegClosed
  OpenState   :: Register -> RegState 'RegOpen

data SomeRegState = forall v. SomeRegState (SRegVertex v) (RegState v)

fromRegister :: Register -> SomeRegState
fromRegister reg
  | registerIsOpen reg = SomeRegState SRegOpen   (OpenState   reg)
  | otherwise          = SomeRegState SRegClosed (ClosedState reg)

toSomeRegState :: RegState v -> SomeRegState
toSomeRegState = \case
  st@(ClosedState _) -> SomeRegState SRegClosed st
  st@(OpenState   _) -> SomeRegState SRegOpen   st

data RegCommand
  = OpenRegCmd  UUID Int
  | CloseRegCmd UUID Int
  deriving (Show, Eq, Generic)

data RegEvent
  = RegOpened         Register
  | RegWasClosed      Register Int
  | InvalidRegCommand Text
  deriving (Show, Eq, Generic)

regAction :: RegState v -> RegCommand -> ActionResult Identity RegTopology RegState v RegEvent

regAction (ClosedState reg) (OpenRegCmd empId startCash) =
  let opened = reg
        { registerIsOpen               = True
        , registerCurrentDrawerAmount  = startCash
        , registerExpectedDrawerAmount = startCash
        , registerOpenedBy             = Just empId
        }
  in pureResult (RegOpened opened) (OpenState opened)

regAction (ClosedState reg) _ =
  pureResult (InvalidRegCommand "Register is already closed") (ClosedState reg)

regAction (OpenState reg) (CloseRegCmd _ countedCash) =
  let variance = registerExpectedDrawerAmount reg - countedCash
      closed   = reg
        { registerIsOpen              = False
        , registerCurrentDrawerAmount = countedCash
        }
  in pureResult (RegWasClosed closed variance) (ClosedState closed)

regAction (OpenState reg) _ =
  pureResult (InvalidRegCommand "Register is already open") (OpenState reg)

runRegCommand :: SomeRegState -> RegCommand -> (RegEvent, SomeRegState)
runRegCommand (SomeRegState _ st) cmd =
  case regAction st cmd of
    ActionResult m ->
      let (evt, nextSt) = runIdentity m
      in  (evt, toSomeRegState nextSt)