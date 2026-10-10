module UI.Remote
  ( Remote
  , RemoteView
  , useRemote
  , onMount
  , viewRemote
  , standardView
  , quietView
  ) where

import Prelude

import API.Request (ApiError)
import API.Request as Request
import Data.Either (Either(..))
import Data.Tuple.Nested ((/\))
import Deku.Attribute (Attribute)
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Self as Self
import Deku.Do as Deku
import Deku.Hooks (useHot, (<#~>))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import FRP.Poll (Poll)
import Types.RemoteData (RemoteData(..))

type Remote a =
  { value :: Poll (RemoteData a)
  , reload :: Effect Unit
  , refresh :: Effect Unit
  }

useRemote
  :: forall a
   . RemoteData a
  -> Aff (Either ApiError a)
  -> (Remote a -> Nut)
  -> Nut
useRemote initial request cont = Deku.do
  setValue /\ value <- useHot initial
  let
    refresh = launchAff_ do
      result <- request
      liftEffect $ setValue case result of
        Left err -> Failure (Request.describe err)
        Right a -> Success a

    reload = do
      setValue Loading
      refresh
  cont { value, reload, refresh }

onMount :: forall r. Effect Unit -> Poll (Attribute r)
onMount effect = Self.self_ \_ -> effect

type RemoteView =
  { notAsked :: Nut
  , loading :: Nut
  , failure :: String -> Nut
  }

viewRemote
  :: forall a
   . RemoteView
  -> (a -> Nut)
  -> Poll (RemoteData a)
  -> Nut
viewRemote view success value =
  value <#~> case _ of
    NotAsked -> view.notAsked
    Loading -> view.loading
    Failure err -> view.failure err
    Success a -> success a

standardView :: String -> RemoteView
standardView loadingText =
  { notAsked: D.div_ []
  , loading: D.div [ DA.klass_ "loading-indicator" ] [ text_ loadingText ]
  , failure: \err -> D.div [ DA.klass_ "error-message" ] [ text_ err ]
  }

quietView :: RemoteView
quietView =
  { notAsked: D.div_ []
  , loading: D.div [ DA.klass_ "loading-indicator" ] []
  , failure: \_ -> D.div [ DA.klass_ "error-message" ] []
  }

