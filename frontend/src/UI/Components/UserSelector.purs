module Components.UserSelector where

import Prelude

import Config.Auth (DevUser, allDevUsers)
import Data.Array (mapWithIndex)
import Deku.Attribute ((!:=))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Hooks (useState)
import Effect (Effect)
import Effect.Ref (Ref)
import FRP.Poll (Poll)
import Services.AuthService (AuthContext, getCurrentUser, setCurrentUser)
import Types.Auth (UserRole(..))

-- | User selector component props
type UserSelectorProps =
  { authRef :: Ref AuthContext
  , onUserChange :: DevUser -> Effect Unit
  , currentUser :: Poll DevUser
  }

-- | Color badge for each role
roleBadgeColor :: UserRole -> String
roleBadgeColor = case _ of
  Customer -> "bg-blue-100 text-blue-800"
  Cashier -> "bg-green-100 text-green-800"
  Manager -> "bg-yellow-100 text-yellow-800"
  Admin -> "bg-red-100 text-red-800"

-- | Human-readable role label
roleLabel :: UserRole -> String
roleLabel = case _ of
  Customer -> "Customer"
  Cashier -> "Cashier"
  Manager -> "Manager"
  Admin -> "Admin"

-- | Role icon (emoji for simplicity)
roleIcon :: UserRole -> String
roleIcon = case _ of
  Customer -> "👤"
  Cashier -> "💵"
  Manager -> "👔"
  Admin -> "🔑"

-- | Single user option button
userOption :: DevUser -> Boolean -> (DevUser -> Effect Unit) -> Nut
userOption user isSelected onClick =
  D.button
    [ DA.klass_ $ "flex items-center gap-2 px-3 py-2 rounded-lg border transition-all "
        <> if isSelected 
           then "border-blue-500 bg-blue-50 shadow-md"
           else "border-gray-200 hover:border-gray-300 hover:bg-gray-50"
    , DL.click_ \_ -> onClick user
    ]
    [ D.span [ DA.klass_ "text-lg" ] [ text_ (roleIcon user.role) ]
    , D.div [ DA.klass_ "text-left" ]
        [ D.div [ DA.klass_ "font-medium text-sm" ] [ text_ user.userName ]
        , D.span 
            [ DA.klass_ $ "inline-block px-2 py-0.5 rounded text-xs font-medium " 
                <> roleBadgeColor user.role
            ] 
            [ text_ (roleLabel user.role) ]
        ]
    ]

-- | Main user selector component
userSelector :: UserSelectorProps -> Nut
userSelector props =
  D.div [ DA.klass_ "bg-amber-50 border border-amber-200 rounded-lg p-4 mb-4" ]
    [ D.div [ DA.klass_ "flex items-center gap-2 mb-3" ]
        [ D.span [ DA.klass_ "text-amber-600 text-lg" ] [ text_ "⚠️" ]
        , D.span [ DA.klass_ "font-medium text-amber-800" ] [ text_ "Dev Mode: User Selector" ]
        ]
    , D.div [ DA.klass_ "flex flex-wrap gap-2" ] $
        map (\user -> 
          D.div [] 
            [ props.currentUser <#> \currentUser ->
                userOption user (currentUser.userId == user.userId) props.onUserChange
            ]
        ) allDevUsers
    , D.div [ DA.klass_ "mt-3 text-xs text-amber-700" ]
        [ text_ "Current user: "
        , D.span [ DA.klass_ "font-mono" ] 
            [ text $ props.currentUser <#> _.userName ]
        , text_ " ("
        , text $ props.currentUser <#> (_.role >>> roleLabel)
        , text_ ")"
        ]
    ]

-- | Compact user selector for header/navbar
compactUserSelector :: UserSelectorProps -> Nut
compactUserSelector props =
  D.div [ DA.klass_ "relative" ]
    [ D.div [ DA.klass_ "flex items-center gap-2" ]
        [ D.span [ DA.klass_ "text-sm text-gray-600" ] [ text_ "Dev:" ]
        , D.select
            [ DA.klass_ "border border-gray-300 rounded px-2 py-1 text-sm bg-white"
            , DL.change_ \evt -> do
                -- Get selected index and look up user
                -- For simplicity, using role as value
                pure unit -- TODO: implement select handler
            ]
            (mapWithIndex (\idx user -> 
              D.option 
                [ DA.value_ user.userId ]
                [ text_ $ user.userName <> " (" <> roleLabel user.role <> ")" ]
            ) allDevUsers)
        ]
    ]

-- | Capability indicator (shows current user's permissions)
capabilityIndicator :: UserSelectorProps -> Nut
capabilityIndicator props =
  D.div [ DA.klass_ "bg-gray-50 border border-gray-200 rounded-lg p-3 text-xs" ]
    [ D.div [ DA.klass_ "font-medium text-gray-700 mb-2" ] [ text_ "Capabilities:" ]
    , props.currentUser <#> \user ->
        let caps = capabilitiesForRoleUI user.role
        in D.div [ DA.klass_ "flex flex-wrap gap-1" ] $
             map (\cap -> 
               D.span 
                 [ DA.klass_ "inline-block px-2 py-0.5 rounded bg-green-100 text-green-800" ]
                 [ text_ cap ]
             ) caps
    ]

-- | Get human-readable capability list for a role (for UI display)
capabilitiesForRoleUI :: UserRole -> Array String
capabilitiesForRoleUI = case _ of
  Customer -> ["View Inventory"]
  Cashier -> ["View Inventory", "Edit Item", "Process Transaction", "Open/Close Register", "View Compliance"]
  Manager -> ["View Inventory", "Create/Edit/Delete Items", "All Transactions", "Manage Registers", "View Reports", "View Compliance"]
  Admin -> ["Full Access"]