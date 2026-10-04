module UI.Form
  ( Form
  , Built
  , TextSpec
  , runForm
  , isValid
  , text
  , password
  , textArea
  , readOnly
  , select
  , section
  , visibleWhen
  , dependent
  ) where

import Prelude

import Data.Either (Either(..), either, hush)
import Data.Enum (class BoundedEnum, enumFromTo, fromEnum, toEnum)
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..), maybe)
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Data.Validation.Semigroup (V, invalid, isValid) as V
import Data.Validation.Semigroup (toEither)
import Deku.Control (text_)
import Deku.Core (Nut, attributeAtYourOwnRisk)
import Deku.Control (text) as DC
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot)
import Effect (Effect)
import FRP.Poll (Poll)
import UI.Form.Parser (Parser)
import Web.Event.Event (target)
import Web.HTML.HTMLInputElement (fromEventTarget, value) as Input
import Web.HTML.HTMLSelectElement (fromEventTarget, value) as Select
import Web.HTML.HTMLTextAreaElement (fromEventTarget, value) as TextArea

-- What a form yields once its state cells exist.
--   view:   the rendered fields, in composition order
--   result: the parsed value, or every current error prefixed with its label
--   reset:  puts every field back to its initial text
type Built a =
  { view :: Array Nut
  , result :: Poll (V.V (Array String) a)
  , reset :: Effect Unit
  }

-- A form is a Deku hook in continuation form. Each field allocates one cell
-- holding its raw text. Validity is never stored; it is the field's parser
-- mapped over that cell. Composition is applicative only, so the set of
-- fields is static and errors from all fields accumulate.
newtype Form a = Form ((Built a -> Nut) -> Nut)

instance Functor Form where
  map f (Form k) = Form \cont -> k \b ->
    cont { view: b.view, result: map (map f) b.result, reset: b.reset }

instance Apply Form where
  apply (Form kf) (Form ka) = Form \cont -> kf \bf -> ka \ba ->
    cont
      { view: bf.view <> ba.view
      , result: (<*>) <$> bf.result <*> ba.result
      , reset: bf.reset *> ba.reset
      }

instance Applicative Form where
  pure a = Form \cont ->
    cont { view: [], result: pure (pure a), reset: pure unit }

runForm :: forall a. Form a -> (Built a -> Nut) -> Nut
runForm (Form k) = k

isValid :: forall a. Built a -> Poll Boolean
isValid b = V.isValid <$> b.result

type TextSpec =
  { label :: String
  , placeholder :: String
  , initial :: String
  }

inputKls :: String
inputKls =
  "rounded-md border-gray-300 shadow-sm border-2 mr-2 border-solid focus:border-indigo-500 focus:ring-indigo-500"

toV :: forall a. String -> Either String a -> V.V (Array String) a
toV label = either (\e -> V.invalid [ label <> ": " <> e ]) pure

row :: forall a. String -> String -> Nut -> Poll (Either String a) -> Nut
row align label control parsed =
  D.div [ DA.klass_ "mb-3" ]
    [ D.div [ DA.klass_ ("flex gap-2 " <> align) ]
        [ D.label [ DA.klass_ "w-36 text-sm font-medium" ] [ text_ label ]
        , control
        , D.span [ DA.klass_ "text-red-500 text-xs" ]
            [ DC.text (parsed <#> either identity (const "")) ]
        ]
    ]

inputField :: forall a. String -> TextSpec -> Parser a -> Form a
inputField inputType spec parse = Form \cont -> Deku.do
  setRaw /\ raw <- useHot spec.initial
  let
    parsed = parse <$> raw
    control =
      D.input
        [ DA.xtype_ inputType
        , DA.placeholder_ spec.placeholder
        , DA.value raw
        , DA.klass_ inputKls
        , DL.input_ \evt ->
            for_ (target evt >>= Input.fromEventTarget) \el ->
              Input.value el >>= setRaw
        ]
        []
  cont
    { view: [ row "items-center" spec.label control parsed ]
    , result: toV spec.label <$> parsed
    , reset: setRaw spec.initial
    }

text :: forall a. TextSpec -> Parser a -> Form a
text = inputField "text"

password :: forall a. TextSpec -> Parser a -> Form a
password = inputField "password"

textArea :: forall a. TextSpec -> Parser a -> Form a
textArea spec parse = Form \cont -> Deku.do
  setRaw /\ raw <- useHot spec.initial
  let
    parsed = parse <$> raw
    control =
      D.textarea
        [ DA.placeholder_ spec.placeholder
        , DA.cols_ "40"
        , DA.rows_ "4"
        , attributeAtYourOwnRisk "value" <$> raw
        , DA.klass_ (inputKls <> " resize-y")
        , DL.input_ \evt ->
            for_ (target evt >>= TextArea.fromEventTarget) \el ->
              TextArea.value el >>= setRaw
        ]
        []
  cont
    { view: [ row "items-start" spec.label control parsed ]
    , result: toV spec.label <$> parsed
    , reset: setRaw spec.initial
    }

-- A value the user can see but not change, such as a generated SKU. It still
-- goes through a parser so the form result carries the typed value.
readOnly :: forall a. { label :: String, value :: String } -> Parser a -> Form a
readOnly spec parse = Form \cont ->
  let
    parsed = parse spec.value
    control =
      D.input
        [ DA.klass_ (inputKls <> " bg-gray-100")
        , DA.value_ spec.value
        , DA.disabled_ "true"
        ]
        []
  in
    cont
      { view: [ row "items-center" spec.label control (pure parsed) ]
      , result: pure (toV spec.label parsed)
      , reset: pure unit
      }

-- A dropdown over every constructor of a BoundedEnum. Option values are the
-- enum indices, so there is no string-to-constructor table to keep in sync
-- and no dependence on Show.
select
  :: forall a
   . BoundedEnum a
  => { label :: String
     , prompt :: String
     , initial :: Maybe a
     , display :: a -> String
     }
  -> Form a
select spec = Form \cont -> Deku.do
  let
    key :: a -> String
    key = show <<< fromEnum

    initialKey = maybe "" key spec.initial

    parse :: String -> Either String a
    parse s = case Int.fromString s >>= toEnum of
      Just a -> Right a
      Nothing -> Left "Select an option"

    choices :: Array a
    choices = enumFromTo bottom top
  setRaw /\ raw <- useHot initialKey
  let
    parsed = parse <$> raw
    option k label =
      D.option
        [ DA.value_ k
        , DA.selected (raw <#> \r -> if r == k then "selected" else "")
        ]
        [ text_ label ]
    control =
      D.select
        [ DA.klass_ inputKls
        , DL.change_ \evt ->
            for_ (target evt >>= Select.fromEventTarget) \el ->
              Select.value el >>= setRaw
        ]
        ( [ option "" spec.prompt ]
            <> map (\a -> option (key a) (spec.display a)) choices
        )
  cont
    { view: [ row "items-center" spec.label control parsed ]
    , result: toV spec.label <$> parsed
    , reset: setRaw initialKey
    }

-- Groups the fields of a sub-form under a heading. Purely a layout wrapper.
section :: forall a. String -> Form a -> Form a
section title (Form k) = Form \cont -> k \b ->
  cont
    { view:
        [ D.div [ DA.klass_ "mb-6" ]
            ( [ D.h3 [ DA.klass_ "text-lg font-semibold mb-3 border-b pb-1" ]
                  [ text_ title ]
              ]
                <> b.view
            )
        ]
    , result: b.result
    , reset: b.reset
    }

-- Shows or hides a sub-form. The sub-form stays mounted, so its text survives
-- being hidden. While hidden it yields Nothing and its errors do not count
-- against the form.
visibleWhen :: forall a. Poll Boolean -> Form a -> Form (Maybe a)
visibleWhen visible (Form k) = Form \cont -> k \b ->
  cont
    { view:
        [ D.div
            [ DA.klass (visible <#> if _ then "" else "hidden") ]
            b.view
        ]
    , result:
        (\vis r -> if vis then Just <$> r else pure Nothing)
          <$> visible
          <*> b.result
    , reset: b.reset
    }

-- The escape hatch for dependent fields. The second form is built once and
-- receives the first form's parsed value as a Poll (Nothing while the first
-- form is invalid). It can react to that Poll, usually through visibleWhen,
-- but it cannot change which fields exist. That restriction is what keeps
-- reset and error accumulation working without a Monad instance.
dependent
  :: forall k a
   . Form k
  -> (Poll (Maybe k) -> Form a)
  -> Form (Tuple k a)
dependent (Form kk) f = Form \cont -> kk \bk ->
  let
    Form ka = f (hush <<< toEither <$> bk.result)
  in
    ka \ba ->
      cont
        { view: bk.view <> ba.view
        , result: (\rk ra -> Tuple <$> rk <*> ra) <$> bk.result <*> ba.result
        , reset: bk.reset *> ba.reset
        }
