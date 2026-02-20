module Cheeblr.UI.Auth.UserSwitcher where

import Prelude

import Cheeblr.API.Auth (AuthContext, DevUser, allDevUsers, setCurrentUser)
import Cheeblr.Core.Auth (roleLabel, roleIcon, roleBadgeClass)
import Cheeblr.UI.FormHelpers (getSelectValue)
import Data.Array as Data.Array
import Data.Maybe (Maybe(..))
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

----------------------------------------------------------------------
-- User Switcher (dev toolbar)
----------------------------------------------------------------------

userSwitcher
  :: Ref AuthContext
  -> (DevUser -> Effect Unit)   -- callback after user switch
  -> Nut
userSwitcher authRef onSwitch = Deku.do
  setCurrentName /\ currentNamePoll <- useState ""

  -- Initialize with current user
  -- (would be done via DL.load_ in practice)

  D.div
    [ DA.klass_ "user-switcher" ]
    [ D.label [ DA.klass_ "user-switcher-label" ] [ text_ "User: " ]
    , D.select
        [ DA.klass_ "user-switcher-select"
        , DL.change_ \evt -> do
            val <- getSelectValue evt
            case findUserByName val of
              Just user -> do
                setCurrentUser authRef user
                setCurrentName user.userName
                onSwitch user
              Nothing -> pure unit
        ]
        (allDevUsers <#> \user ->
          D.option
            [ DA.value_ user.userName ]
            [ text_ (user.userName <> " (" <> roleLabel user.role <> ")") ]
        )

    -- Show current role badge
    , currentNamePoll <#~> \name ->
        case findUserByName name of
          Just user ->
            D.span
              [ DA.klass_ ("user-badge " <> roleBadgeClass user.role) ]
              [ text_ (roleIcon user.role <> " " <> roleLabel user.role) ]
          Nothing ->
            D.span_ []
    ]

findUserByName :: String -> Maybe DevUser
findUserByName name =
  Data.Array.find (\u -> u.userName == name) allDevUsers
