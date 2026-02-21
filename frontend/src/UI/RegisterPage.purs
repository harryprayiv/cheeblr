module Cheeblr.UI.Register.RegisterPage where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.Core.Register (Register, formatDrawerAmount)
import Cheeblr.UI.Register.RegisterService as RS
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import FRP.Poll (Poll)

----------------------------------------------------------------------
-- Register page
----------------------------------------------------------------------

registerPage :: Ref AuthContext -> RS.RegisterHandle -> Nut
registerPage authRef handle = Deku.do
  setRegister /\ registerPoll <- useState (Nothing :: Maybe Register)
  setStatus /\ statusPoll <- useState ""
  setCashInput /\ cashInputPoll <- useState ""

  let
    syncFromHandle :: Effect Unit
    syncFromHandle = do
      mReg <- Ref.read handle
      setRegister mReg

    onOpen :: String -> Effect Unit
    onOpen cashStr = do
      let startingCash = parseCents cashStr
      mReg <- Ref.read handle
      case mReg of
        Nothing -> setStatus "No register loaded"
        Just reg ->
          RS.openRegister authRef handle reg.registerId startingCash
            (\opened -> do
              setRegister (Just opened)
              setCashInput ""
              setStatus "Register opened")
            (\err -> setStatus err)

    onClose :: String -> Effect Unit
    onClose cashStr = do
      let countedCash = parseCents cashStr
      mReg <- Ref.read handle
      case mReg of
        Nothing -> setStatus "No register loaded"
        Just reg ->
          RS.closeRegister authRef handle reg.registerId countedCash
            (\msg -> do
              syncFromHandle
              setCashInput ""
              setStatus msg)

  D.div
    [ DA.klass_ "register-page"
    , DL.load_ \_ -> syncFromHandle
    ]
    [
      D.h2_ [ text_ "Register" ]

    , statusPoll <#~> \msg ->
        if msg == "" then D.span_ []
        else D.div [ DA.klass_ "register-status" ] [ text_ msg ]

    , registerPoll <#~> \mReg ->
        case mReg of
          Nothing ->
            D.div
              [ DA.klass_ "register-empty" ]
              [ text_ "No register loaded. Initializing..." ]

          Just reg ->
            D.div
              [ DA.klass_ "register-detail" ]
              [ registerInfo reg
              , if reg.registerIsOpen
                  then closeForm cashInputPoll setCashInput onClose
                  else openForm cashInputPoll setCashInput onOpen
              ]
    ]

----------------------------------------------------------------------
-- Sub-components
----------------------------------------------------------------------

registerInfo :: Register -> Nut
registerInfo reg =
  D.div
    [ DA.klass_ "register-info" ]
    [ D.div [ DA.klass_ "register-info-row" ]
        [ D.span [ DA.klass_ "register-label" ] [ text_ "Name" ]
        , D.span_ [ text_ reg.registerName ]
        ]
    , D.div [ DA.klass_ "register-info-row" ]
        [ D.span [ DA.klass_ "register-label" ] [ text_ "Status" ]
        , D.span
            [ DA.klass_ (if reg.registerIsOpen then "status-open" else "status-closed") ]
            [ text_ (if reg.registerIsOpen then "Open" else "Closed") ]
        ]
    , D.div [ DA.klass_ "register-info-row" ]
        [ D.span [ DA.klass_ "register-label" ] [ text_ "Drawer" ]
        , D.span_ [ text_ (formatDrawerAmount reg.registerCurrentDrawerAmount) ]
        ]
    , D.div [ DA.klass_ "register-info-row" ]
        [ D.span [ DA.klass_ "register-label" ] [ text_ "Expected" ]
        , D.span_ [ text_ (formatDrawerAmount reg.registerExpectedDrawerAmount) ]
        ]
    ]

openForm :: Poll String -> (String -> Effect Unit) -> (String -> Effect Unit) -> Nut
openForm cashInputPoll setCashInput onOpen =
  D.div
    [ DA.klass_ "register-form" ]
    [ D.h3_ [ text_ "Open Register" ]
    , D.label_ [ text_ "Starting cash ($)" ]
    , D.input
        [ DA.klass_ "register-cash-input"
        , DA.xtype_ "number"
        , DA.placeholder_ "0.00"
        , DL.valueOn_ DL.input setCashInput
        ]
        []
    , cashInputPoll <#~> \cashStr ->
        D.button
          [ DA.klass_ "btn-primary"
          , DL.click_ \_ -> onOpen cashStr
          ]
          [ text_ "Open Register" ]
    ]

closeForm :: Poll String -> (String -> Effect Unit) -> (String -> Effect Unit) -> Nut
closeForm cashInputPoll setCashInput onClose =
  D.div
    [ DA.klass_ "register-form" ]
    [ D.h3_ [ text_ "Close Register" ]
    , D.label_ [ text_ "Counted cash ($)" ]
    , D.input
        [ DA.klass_ "register-cash-input"
        , DA.xtype_ "number"
        , DA.placeholder_ "0.00"
        , DL.valueOn_ DL.input setCashInput
        ]
        []
    , cashInputPoll <#~> \cashStr ->
        D.button
          [ DA.klass_ "btn-danger"
          , DL.click_ \_ -> onClose cashStr
          ]
          [ text_ "Close Register" ]
    ]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- | Parse a dollar string ("150.00") into cents (15000).
-- | Falls back to 0 on bad input.
parseCents :: String -> Int
parseCents str =
  case Number.fromString str of
    Just n -> Int.floor (n * 100.0)
    Nothing -> 0