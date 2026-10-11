module Pages.Registers where

import Prelude

import API.Register as RegisterApi
import API.Request (ApiError)
import API.Request as Request
import Config.Entity (dummyLocationId)
import Data.Array (null)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Data.Validation.Semigroup (toEither)
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import FRP.Poll (Poll)
import Services.RegisterService as RegisterService
import Types.RemoteData (RemoteData(..))
import Types.Session (SessionResponse)
import Types.UUID (UUID)
import UI.Form (Built, Form, Style, defaultStyle, runFormWith)
import UI.Form (text) as F
import UI.Form.Parser (cents, required)
import UI.Remote (onMount, standardView, useRemote, viewRemote)
import Utils.Formatting (formatCentsToDollars)

-- Registers are created, opened and closed here and nowhere else.
--
--   Create: shown with capCanManageRegisters. Owner decision: only a
--           manager or an admin creates a register. A new register is
--           closed.
--   Open:   shown with capCanOpenRegister, on a closed register, with the
--           starting cash in the drawer.
--   Close:  shown with capCanCloseRegister, on an open register, with the
--           counted cash. The backend answers with the variance.
--   Use on this device: remembers the register in this browser. The sale
--           page sells on the remembered register.
--
-- Every register is filed under the one configured location
-- (Config.Entity.dummyLocationId). The session carries no location.

formStyle :: Style
formStyle = defaultStyle { field = "", hint = "text-red-500 text-xs" }

nameForm :: Form String
nameForm = F.text
  { label: "Name:", placeholder: "Front counter", initial: "" }
  required

cashForm :: String -> Form Int
cashForm label = F.text
  { label, placeholder: "0.00", initial: "" }
  cents

-- Expected minus counted, in cents, as the backend computes it.
describeVariance :: Int -> String
describeVariance variance
  | variance == 0 = "The drawer matches the expected amount."
  | variance > 0 = "The drawer is short by $" <> formatCentsToDollars variance <> "."
  | otherwise =
      "The drawer is over by $" <> formatCentsToDollars (negate variance) <> "."

page :: SessionResponse -> Nut
page user = Deku.do
  registers <- useRemote Loading RegisterApi.getRegisters
  setChosen /\ chosenV <- useHot (Nothing :: Maybe UUID)
  setMessage /\ messageV <- useHot ""
  setBusy /\ busyV <- useHot false

  let
    caps = user.sessionCapabilities

    -- Runs one request, shows its outcome and reads the list again. The
    -- list is read again after a refusal too, because a 409 means the list
    -- on screen is out of date.
    run :: forall a. Aff (Either ApiError a) -> (a -> Effect String) -> Effect Unit
    run request done = do
      setBusy true
      setMessage ""
      launchAff_ do
        result <- request
        liftEffect do
          case result of
            Right value -> done value >>= setMessage
            Left err -> setMessage ("Error: " <> Request.describe err)
          setBusy false
          registers.refresh

    create name = run
      (liftEffect (RegisterService.newRegister name dummyLocationId)
         >>= RegisterApi.createRegister)
      (\register -> pure ("Created register " <> register.registerName <> "."))

    open register startingCash = run
      ( RegisterApi.openRegister register.registerId
          { openRegisterStartingCash: startingCash }
      )
      (\opened -> pure ("Opened register " <> opened.registerName <> "."))

    close register countedCash = run
      ( RegisterApi.closeRegister register.registerId
          { closeRegisterCountedCash: countedCash }
      )
      ( \result -> pure
          ( "Closed register "
              <> result.closeRegisterResultRegister.registerName
              <> ". "
              <> describeVariance result.closeRegisterResultVariance
          )
      )

    choose register = do
      RegisterService.chooseRegister register.registerId
      setChosen (Just register.registerId)
      setMessage ("This device now sells on " <> register.registerName <> ".")

    row register =
      D.div [ DA.klass_ "register-row stat-card" ]
        ( [ D.div [ DA.klass_ "register-name" ] [ text_ register.registerName ]
          , D.div [ DA.klass_ "register-state" ]
              [ text_ (if register.registerIsOpen then "Open" else "Closed") ]
          , D.div [ DA.klass_ "register-device" ]
              [ text $ chosenV <#> \chosen ->
                  if chosen == Just register.registerId then
                    "This device sells on this register"
                  else ""
              ]
          , D.button
              [ DA.klass_ "btn btn-sm"
              , DL.click_ \_ -> choose register
              ]
              [ text_ "Use on this device" ]
          ]
            <> drawer register
            <> openControls register
            <> closeControls register
        )

    drawer register =
      if register.registerIsOpen && caps.capCanCloseRegister then
        [ D.div [ DA.klass_ "register-drawer" ]
            [ text_
                ( "Expected in drawer: $"
                    <> formatCentsToDollars register.registerExpectedDrawerAmount
                )
            ]
        ]
      else []

    openControls register =
      if not register.registerIsOpen && caps.capCanOpenRegister then
        [ runFormWith formStyle (cashForm "Starting cash:") \form ->
            D.div [ DA.klass_ "register-action" ]
              (form.view <> [ submit busyV "Open" form (open register) ])
        ]
      else []

    closeControls register =
      if register.registerIsOpen && caps.capCanCloseRegister then
        [ runFormWith formStyle (cashForm "Counted cash:") \form ->
            D.div [ DA.klass_ "register-action" ]
              (form.view <> [ submit busyV "Close" form (close register) ])
        ]
      else []

    createControls =
      if caps.capCanManageRegisters then
        runFormWith formStyle nameForm \form ->
          D.div [ DA.klass_ "register-create" ]
            ( [ D.h3_ [ text_ "New register" ] ]
                <> form.view
                <>
                  [ submit busyV "Create register" form \name -> do
                      create name
                      form.reset
                  ]
            )
      else D.div_ []

    list found =
      if null found then
        D.div [ DA.klass_ "empty-result" ]
          [ text_
              ( if caps.capCanManageRegisters then
                  "There are no registers yet. Create one above."
                else
                  "There are no registers yet. Ask a manager to create one."
              )
          ]
      else D.div [ DA.klass_ "register-list" ] (map row found)

  D.div
    [ DA.klass_ "registers-page"
    , onMount do
        RegisterService.chosenRegisterId >>= setChosen
        registers.reload
    ]
    [ D.h1_ [ text_ "Registers" ]
    , D.div [ DA.klass_ "status-message" ] [ text messageV ]
    , createControls
    , viewRemote (standardView "Loading registers...") list registers.value
    ]

-- A button that submits a form's value when the form is valid and no
-- request is running.
submit
  :: forall a
   . Poll Boolean
  -> String
  -> Built a
  -> (a -> Effect Unit)
  -> Nut
submit busyV label form action =
  D.button
    [ DA.klass_ "btn btn-primary"
    , DA.disabled $ ready <#> \ok -> if ok then "" else "true"
    , DL.runOn DL.click $
        ( \result busy ->
            case toEither result of
              Right value | not busy -> action value
              _ -> pure unit
        )
          <$> form.result
          <*> busyV
    ]
    [ text_ label ]
  where
  ready =
    ( \result busy ->
        case toEither result of
          Right _ -> not busy
          Left _ -> false
    )
      <$> form.result
      <*> busyV
