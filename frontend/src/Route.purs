module Route where

import Prelude hiding ((/))

import API.Auth (logout)
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..))
import Data.Show.Generic (genericShow)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks ((<#~>))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import FRP.Poll (Poll)
import Routing.Duplex (RouteDuplex', root, segment, string)
import Routing.Duplex.Generic as G
import Routing.Duplex.Generic.Syntax ((/))
import Services.AuthService (AuthState(..), clearToken, loadToken)

data Route
  = Login
  | LiveView
  | Create
  | Delete String
  | CreateTransaction
  | TransactionHistory
  | Edit String
  | Admin
  | Manager

derive instance Eq Route
derive instance Ord Route
derive instance genericRoute :: Generic Route _

instance Show Route where
  show = genericShow

route :: RouteDuplex' Route
route = root $ G.sum
  { "Login":              "login"       / G.noArgs
  , "LiveView":           G.noArgs
  , "Create":             "create"      / G.noArgs
  , "Edit":               "edit"        / (string segment)
  , "Delete":             "delete"      / (string segment)
  , "CreateTransaction":  "transaction" / "create"  / G.noArgs
  , "TransactionHistory": "transaction" / "history" / G.noArgs
  , "Admin": "admin" / G.noArgs
  , "Manager": "manager" / G.noArgs
  }

nav
  :: Poll Route
  -> Poll AuthState
  -> (AuthState -> Effect Unit)
  -> Nut
nav currentRoute authPoll pushAuth =
  D.nav [ DA.klass_ "navbar" ]
    [ D.div [ DA.klass_ "container" ]
        [ D.div
            [ DA.klass_ "nav" ]
            [ navItem LiveView          "/#/"                   "LiveView"        currentRoute
            , navItem Create            "/#/create"             "Create Item"     currentRoute
            , navItem CreateTransaction "/#/transaction/create" "New Transaction" currentRoute
            , authPoll <#~> authButton
            , navItem Admin "/#/admin" "Admin" currentRoute
            , navItem Manager "/#/manager" "Manager" currentRoute
            ]
        ]
    ]
  where
  authButton :: AuthState -> Nut
  authButton SignedOut =
    D.a
      [ DA.href_  "/#/login"
      , DA.klass_ "nav-link nav-auth-link"
      ]
      [ text_ "Login" ]
  -- The second field is the session token; we don't need it here.
  authButton (SignedIn _ _) =
    D.button
      [ DA.klass_ "nav-link nav-auth-link nav-logout-btn"
      , DL.click_ \_ ->
          launchAff_ do
            mToken <- liftEffect loadToken
            case mToken of
              Just token -> void $ logout token
              Nothing    -> pure unit
            liftEffect do
              clearToken
              pushAuth SignedOut
      ]
      [ text_ "Logout" ]

navItem :: Route -> String -> String -> Poll Route -> Nut
navItem thisRoute href label currentRoute =
  D.div
    [ DA.klass_ "nav-item mx-2" ]
    [ D.a
        [ DA.href_ href
        , DA.klass $ currentRoute <#> \r ->
            "nav-link" <> if r == thisRoute then " active" else ""
        ]
        [ text_ label ]
    ]