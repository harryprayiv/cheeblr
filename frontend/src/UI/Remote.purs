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

import Data.Either (Either)
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
import Types.RemoteData (RemoteData(..), fromEither)

-- What useRemote hands to a page.
--   value:  the current state of the request
--   reload: sets the state to Loading and runs the request again
type Remote a =
  { value :: Poll (RemoteData a)
  , reload :: Effect Unit
  }

-- A hook that owns one backend request. The first argument is the state
-- before anything has run: Loading for data fetched when the page opens
-- (pair it with onMount), NotAsked for data fetched on a button press.
useRemote
  :: forall a
   . RemoteData a
  -> Aff (Either String a)
  -> (Remote a -> Nut)
  -> Nut
useRemote initial request cont = Deku.do
  setValue /\ value <- useHot initial
  let
    reload = do
      setValue Loading
      launchAff_ do
        result <- request
        liftEffect $ setValue (fromEither result)
  cont { value, reload }

-- Runs an effect once when the element it is attached to is created. The
-- DOM load event does not fire on a div, so DL.load_ cannot be used for this.
onMount :: forall r. Effect Unit -> Poll (Attribute r)
onMount effect = Self.self_ \_ -> effect

-- How to draw the three states that carry no data.
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

-- A loading line with the given text, and the error message on failure.
standardView :: String -> RemoteView
standardView loadingText =
  { notAsked: D.div_ []
  , loading: D.div [ DA.klass_ "loading-indicator" ] [ text_ loadingText ]
  , failure: \err -> D.div [ DA.klass_ "error-message" ] [ text_ err ]
  }

-- Empty placeholders, for panels that sit beside one that already reports
-- the loading state and the error.
quietView :: RemoteView
quietView =
  { notAsked: D.div_ []
  , loading: D.div [ DA.klass_ "loading-indicator" ] []
  , failure: \_ -> D.div [ DA.klass_ "error-message" ] []
  }
