module Pages.Login where

import Prelude

import API.Auth (login)
import Config.Auth (defaultDevUser, findDevUserByRole)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
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
import Services.AuthService (AuthState(..), persistToken)
import Web.Event.Event (target)
import Web.HTML (window)
import Web.HTML.HTMLInputElement (fromEventTarget, value) as Input
import Web.HTML.Location (setHref)
import Web.HTML.Window (location)

------------------------------------------------------------------------
-- Login page
--
-- On success:
--   1. Persist the token to localStorage.
--   2. Push SignedIn to the auth poll.
--   3. Navigate to /#/ which triggers the LiveView route via matchesWith.
------------------------------------------------------------------------

page
  :: (AuthState -> Effect Unit)  -- push to authState poll
  -> Effect Unit                 -- ignored; navigation done via hash
  -> Nut
page pushAuth _ = Deku.do
  setUsername     /\ usernameValue     <- useState ""
  setPassword     /\ passwordValue     <- useState ""
  setErrorMessage /\ errorMessageValue <- useState ""
  setSubmitting   /\ submittingValue   <- useState false

  D.div
    [ DA.klass_ "login-container" ]
    [ D.div
        [ DA.klass_ "login-card" ]
        [ D.h1
            [ DA.klass_ "login-title" ]
            [ text_ "Cheeblr POS" ]

        , D.div
            [ DA.klass_ "login-form" ]
            [ D.div
                [ DA.klass_ "form-group" ]
                [ D.label [ DA.klass_ "form-label" ] [ text_ "Username" ]
                , D.input
                    [ DA.klass_       "form-input-field"
                    , DA.xtype_       "text"
                    , DA.placeholder_ "Enter username"
                    , DA.autofocus_   "true"
                    , DL.input_ \evt ->
                        case target evt >>= Input.fromEventTarget of
                          Nothing -> pure unit
                          Just el -> Input.value el >>= setUsername
                    ]
                    []
                ]

            , D.div
                [ DA.klass_ "form-group" ]
                [ D.label [ DA.klass_ "form-label" ] [ text_ "Password" ]
                , D.input
                    [ DA.klass_       "form-input-field"
                    , DA.xtype_       "password"
                    , DA.placeholder_ "Enter password"
                    , DL.input_ \evt ->
                        case target evt >>= Input.fromEventTarget of
                          Nothing -> pure unit
                          Just el -> Input.value el >>= setPassword
                    ]
                    []
                ]

            , D.div
                [ DA.klass_ "error-message" ]
                [ text errorMessageValue ]

            , D.button
                [ DA.klass $ submittingValue <#> \submitting ->
                    "login-button" <> if submitting then " disabled" else ""
                , DA.disabled $ submittingValue <#> \s -> if s then "true" else ""
                , DL.runOn DL.click $
                    ( \username password submitting ->
                        when (not submitting) do
                          setSubmitting true
                          setErrorMessage ""
                          launchAff_ do
                            result <- login username password Nothing
                            liftEffect $ case result of
                              Left err -> do
                                setErrorMessage $ "Login failed: " <> err
                                setSubmitting false
                              Right resp -> do
                                persistToken resp.loginToken
                                let devUser = case findDevUserByRole resp.loginUser.sessionRole of
                                      Just u  -> u
                                      Nothing -> defaultDevUser
                                pushAuth (SignedIn devUser)
                                Console.log $ "Logged in as: " <> resp.loginUser.sessionUserName
                                setSubmitting false
                                -- Navigate to LiveView via hash change.
                                -- matchesWith in Main.purs picks this up.
                                w <- window
                                loc <- location w
                                setHref "/#/" loc
                    ) <$> usernameValue
                      <*> passwordValue
                      <*> submittingValue
                ]
                [ text $ submittingValue <#> \s ->
                    if s then "Signing in..." else "Sign In"
                ]
            ]
        ]
    ]