module Pages.Login where

import Prelude

import API.Auth (login)
import Config.Auth (defaultDevUser, findDevUserByRole)
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
import Effect.Class.Console as Console
import Services.AuthService (AuthState(..))
import UI.Form (Form, Style, defaultStyle, isValid, password, runFormWith, textAutofocus)
import UI.Form.Parser (Parser, required)
import Web.HTML (window)
import Web.HTML.Location (setHref)
import Web.HTML.Window (location)

type Credentials =
  { username :: String
  , password :: String
  }

-- The login card has its own stylesheet classes. The hint is hidden because
-- the disabled Sign In button already tells the user both fields are needed.
loginStyle :: Style
loginStyle = defaultStyle
  { field = "form-group"
  , line = ""
  , label = "form-label"
  , input = "form-input-field"
  , hint = "hidden"
  }

-- Passwords are not trimmed. Leading and trailing spaces can be part of one.
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

page
  :: (AuthState -> Effect Unit)
  -> Effect Unit
  -> Nut
page pushAuth _ = runFormWith loginStyle credentialsForm \form -> Deku.do
  setErrorMessage /\ errorMessageValue <- useState ""
  setSubmitting   /\ submittingValue   <- useState false

  let
    valid = isValid form

    submit credentials = do
      setSubmitting true
      setErrorMessage ""
      launchAff_ do
        result <- login credentials.username credentials.password Nothing
        liftEffect $ case result of
          Left err -> do
            setErrorMessage $ "Login failed: " <> err
            setSubmitting false
          Right resp -> do
            -- An unrecognised role falls back to defaultDevUser. This is the
            -- open issue AdminFallbackOnUnknownRole and is unchanged here.
            let devUser = case findDevUserByRole resp.loginUser.sessionRole of
                  Just u  -> u
                  Nothing -> defaultDevUser
            pushAuth (SignedIn devUser (show devUser.userId))
            Console.log $ "Logged in as: " <> resp.loginUser.sessionUserName
            setSubmitting false
            w <- window
            loc <- location w
            setHref "/#/" loc

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