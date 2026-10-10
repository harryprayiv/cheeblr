module Pages.Login where

import Prelude

import API.Auth (login)
import API.Request as Request
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
import Deku.Hooks (useState)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Types.Session (SessionResponse)
import UI.Form (Form, Style, defaultStyle, isValid, password, runFormWith, textAutofocus)
import UI.Form.Parser (Parser, required)

type Credentials =
  { username :: String
  , password :: String
  }

loginStyle :: Style
loginStyle = defaultStyle
  { field = "form-group"
  , line = ""
  , label = "form-label"
  , input = "form-input-field"
  , hint = "hidden"
  }

anyPassword :: Parser String
anyPassword raw = if raw == "" then Left "Required" else Right raw

credentialsForm :: Form Credentials
credentialsForm = ado
  username <- textAutofocus
    { label: "Username", placeholder: "Enter username", initial: "" }
    required
  password' <- password
    { label: "Password", placeholder: "Enter password", initial: "" }
    anyPassword
  in { username, password: password' }

-- A successful login hands the session the backend returned to onSignedIn.
-- A response that does not decode (an unknown role, for example) is an
-- error on this page and the browser stays signed out. Main decides where
-- to go after signing in.
page :: (SessionResponse -> Effect Unit) -> Nut
page onSignedIn = runFormWith loginStyle credentialsForm \form -> Deku.do
  setErrorMessage /\ errorMessageValue <- useState ""
  setSubmitting   /\ submittingValue   <- useState false

  let
    valid = isValid form

    submit credentials = do
      setSubmitting true
      setErrorMessage ""
      launchAff_ do
        result <- login
          { loginUsername: credentials.username
          , loginPassword: credentials.password
          , loginRegisterId: Nothing
          }
        liftEffect $ case result of
          Left err -> do
            setErrorMessage $ "Login failed: " <> Request.describe err
            setSubmitting false
          Right resp -> do
            setSubmitting false
            onSignedIn resp.loginUser

  D.div
    [ DA.klass_ "login-container" ]
    [ D.div
        [ DA.klass_ "login-card" ]
        [ D.h1
            [ DA.klass_ "login-title" ]
            [ text_ "Cheeblr POS" ]

        , D.div
            [ DA.klass_ "login-form" ]
            ( form.view <>
                [ D.div
                    [ DA.klass_ "error-message" ]
                    [ text errorMessageValue ]

                , D.button
                    [ DA.klass $
                        ( \submitting v ->
                            "login-button" <>
                              if submitting || not v then " disabled" else ""
                        )
                          <$> submittingValue
                          <*> valid
                    , DA.disabled $
                        ( \submitting v ->
                            if submitting || not v then "true" else ""
                        )
                          <$> submittingValue
                          <*> valid
                    , DL.runOn DL.click $
                        ( \result submitting ->
                            case toEither result of
                              Right credentials | not submitting ->
                                submit credentials
                              _ -> pure unit
                        )
                          <$> form.result
                          <*> submittingValue
                    ]
                    [ text $ submittingValue <#> \s ->
                        if s then "Signing in..." else "Sign In"
                    ]
                ]
            )
        ]
    ]
