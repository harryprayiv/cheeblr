module Route where

import Prelude hiding ((/))

import Data.Array (filter)
import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks ((<#~>))
import Effect (Effect)
import FRP.Poll (Poll)
import Routing.Duplex (RouteDuplex', root, segment, string)
import Routing.Duplex.Generic as G
import Routing.Duplex.Generic.Syntax ((/))
import Services.AuthService (AuthState(..))
import Types.Auth (UserCapabilities)

data Route
  = Login
  | LiveView
  | Create
  | Delete String
  | CreateTransaction
  | TransactionHistory
  | Registers
  | Edit String
  | Admin
  | Manager
  | Stock
  | Feed

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
  , "Registers":          "register"    / G.noArgs
  , "Admin":              "admin"       / G.noArgs
  , "Manager":            "manager"     / G.noArgs
  , "Stock":              "stock"       / G.noArgs
  , "Feed":               "feed"        / G.noArgs
  }

type NavLink =
  { route :: Route
  , href :: String
  , label :: String
  , allowed :: UserCapabilities -> Boolean
  }

-- Each link is shown only to a user whose capabilities, as the backend sent
-- them, pass the same check the backend applies to that area. This decides
-- what is shown. The backend decides every request.
navLinks :: Array NavLink
navLinks =
  [ { route: LiveView
    , href: "/#/"
    , label: "LiveView"
    , allowed: _.capCanViewInventory
    }
  , { route: Create
    , href: "/#/create"
    , label: "Create Item"
    , allowed: _.capCanCreateItem
    }
  , { route: CreateTransaction
    , href: "/#/transaction/create"
    , label: "New Transaction"
    , allowed: _.capCanProcessTransaction
    }
  , { route: TransactionHistory
    , href: "/#/transaction/history"
    , label: "Sales"
    , allowed: _.capCanProcessTransaction
    }
  , { route: Registers
    , href: "/#/register"
    , label: "Registers"
    , allowed: \caps -> caps.capCanOpenRegister || caps.capCanManageRegisters
    }
  , { route: Admin
    , href: "/#/admin"
    , label: "Admin"
    , allowed: _.capCanViewAdminDashboard
    }
  , { route: Manager
    , href: "/#/manager"
    , label: "Manager"
    , allowed: _.capCanViewReports
    }
  , { route: Stock
    , href: "/#/stock"
    , label: "Stock Room"
    , allowed: _.capCanFulfillOrders
    }
  , { route: Feed
    , href: "/#/feed"
    , label: "Feed"
    , allowed: const true
    }
  ]

visibleLinks :: UserCapabilities -> Array NavLink
visibleLinks caps = filter (\link -> link.allowed caps) navLinks

nav :: Poll Route -> Poll AuthState -> Effect Unit -> Nut
nav currentRoute authPoll signOut =
  D.nav [ DA.klass_ "navbar" ]
    [ D.div [ DA.klass_ "container" ]
        [ authPoll <#~> \auth ->
            D.div [ DA.klass_ "nav" ] case auth of
              SignedOut ->
                [ D.a
                    [ DA.href_ "/#/login"
                    , DA.klass_ "nav-link nav-auth-link"
                    ]
                    [ text_ "Login" ]
                ]
              SignedIn user ->
                ( visibleLinks user.sessionCapabilities <#> \link ->
                    navItem link.route link.href link.label currentRoute
                )
                  <>
                    [ D.span [ DA.klass_ "nav-user" ]
                        [ text_ user.sessionUserName ]
                    , D.button
                        [ DA.klass_ "nav-link nav-auth-link nav-logout-btn"
                        , DL.click_ \_ -> signOut
                        ]
                        [ text_ "Logout" ]
                    ]
        ]
    ]

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
