module UI.Components.Form where

import Prelude

import Data.Enum (class BoundedEnum)
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Deku.Attribute (Attribute)
import Deku.Control (text, text_, elementify)
import Deku.Core (Nut, attributeAtYourOwnRisk)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import Types.Common (DropdownConfig, FieldConfig, TextAreaConfig, ValidationRule, HTMLFormField)
import Utils.Formatting (getAllEnumValues)
import Utils.Validation (runValidation)
import Web.Event.Event (target)
import Web.HTML.HTMLInputElement (fromEventTarget, value) as Input
import Web.HTML.HTMLSelectElement (fromEventTarget, value) as Select
import Web.HTML.HTMLTextAreaElement (fromEventTarget, value) as TextArea
import Web.UIEvent.KeyboardEvent (toEvent)

formField
  :: forall r
   . Array (Poll (Attribute (HTMLFormField r)))
  -> Array Nut
  -> Nut
formField = elementify Nothing "div"

formFieldValue
  :: forall r
   . Poll String
  -> Poll (Attribute (value :: String | r))
formFieldValue = map (attributeAtYourOwnRisk "value")

formFieldValidation
  :: forall r
   . Poll ValidationRule
  -> Poll (Attribute (validation :: ValidationRule | r))
formFieldValidation = map \rule ->
  attributeAtYourOwnRisk "data-validation" (show rule)

makePasswordField
  :: FieldConfig
  -> (String -> Effect Unit)
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Nut
makePasswordField config setValue setValid validEvent =
  D.div_
    [ D.div
        [ DA.klass_ "flex items-center gap-2" ]
        [ D.label_
            [ text_ config.label ]
        , D.input
            [ DA.placeholder_ config.placeholder
            , DA.value_ config.defaultValue
            , DA.xtype_ "password"
            , DL.keyup_ \evt -> do
                let targetEvent = toEvent evt
                for_ (target targetEvent >>= Input.fromEventTarget)
                  \inputElement -> do
                    v <- Input.value inputElement
                    let formatted = config.formatInput v
                    setValue formatted
                    setValid
                      (Just (runValidation config.validation formatted))
            , DL.input_ \evt -> do
                for_ (target evt >>= Input.fromEventTarget) \inputElement ->
                  do
                    v <- Input.value inputElement
                    let formatted = config.formatInput v
                    setValue formatted
                    setValid
                      (Just (runValidation config.validation formatted))
            , DA.klass_ "form-input-field"
            ]
            []
        , D.span
            [ DA.klass_ "text-red-500 text-xs" ]
            [ text
                ( map
                    ( \mValid -> case mValid of
                        Just false -> config.errorMessage
                        _ -> ""
                    )
                    validEvent
                )
            ]
        ]
    ]

makeTextArea
  :: TextAreaConfig
  -> (String -> Effect Unit)
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Nut
makeTextArea config setValue setValid validEvent =
  D.div_
    [ D.div
        [ DA.klass_ "flex items-center gap-2" ]
        [ D.label_
            [ text_ config.label ]
        , D.textarea
            [ DA.placeholder_ config.placeholder
            , DA.cols_ config.cols
            , DA.rows_ config.rows
            , DA.klass_
                "rounded-md border-gray-300 shadow-sm border-2 mr-2 border-solid focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm resize-y"
            , DL.keyup_ \evt -> do
                let targetEvent = toEvent evt
                for_ (target targetEvent >>= TextArea.fromEventTarget)
                  \textareaElement -> do
                    v <- TextArea.value textareaElement
                    setValue v
                    setValid (Just true)
                    Console.log $ "TextArea keyup: '" <> v <> "'"
            , DL.input_ \evt -> do
                for_ (target evt >>= TextArea.fromEventTarget)
                  \textareaElement -> do
                    v <- TextArea.value textareaElement
                    setValue v
                    setValid (Just true)
                    Console.log $ "TextArea input: '" <> v <> "'"
            ]
            [ text_ config.defaultValue ]
        , D.span
            [ DA.klass_ "text-red-500 text-xs" ]
            [ text
                ( map
                    ( \mValid -> case mValid of
                        Just false -> config.errorMessage
                        _ -> ""
                    )
                    validEvent
                )
            ]
        ]
    ]

makeTextField
  :: FieldConfig
  -> (String -> Effect Unit)
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Boolean
  -> Nut
makeTextField config setValue setValid validEvent isPw =
  D.div_
    [ D.div
        [ DA.klass_ "flex items-center gap-2" ]
        [ D.label_
            [ text_ config.label ]
        , if config.label == "Description" then
            D.textarea
              [ DA.placeholder_ config.placeholder
              , DA.cols_ "40"
              , DA.rows_ "4"
              , DL.keyup_ \evt -> do
                  let targetEvent = toEvent evt
                  for_ (target targetEvent >>= TextArea.fromEventTarget)
                    \textareaElement -> do
                      v <- TextArea.value textareaElement
                      let formatted = config.formatInput v
                      setValue formatted
                      setValid
                        (Just (runValidation config.validation formatted))
                      liftEffect $ Console.log $ "Description keyup: '"
                        <> formatted
                        <> "'"
              , DL.input_ \evt -> do
                  for_ (target evt >>= TextArea.fromEventTarget)
                    \textareaElement ->
                      do
                        v <- TextArea.value textareaElement
                        let formatted = config.formatInput v
                        setValue formatted
                        setValid
                          (Just (runValidation config.validation formatted))
                        liftEffect $ Console.log $ "Description input: '"
                          <> formatted
                          <> "'"
              , DA.klass_ "form-textarea"
              ]
              [ text_ config.defaultValue ]
          else
            D.input
              [ DA.placeholder_ config.placeholder
              , DA.value_ config.defaultValue
              , DA.xtype_ (if isPw then "password" else "text")
              , DL.keyup_ \evt -> do
                  let targetEvent = toEvent evt
                  for_ (target targetEvent >>= Input.fromEventTarget)
                    \inputElement -> do
                      v <- Input.value inputElement
                      let formatted = config.formatInput v
                      setValue formatted
                      setValid
                        (Just (runValidation config.validation formatted))
              , DL.input_ \evt -> do
                  for_ (target evt >>= Input.fromEventTarget) \inputElement ->
                    do
                      v <- Input.value inputElement
                      let formatted = config.formatInput v
                      setValue formatted
                      setValid
                        (Just (runValidation config.validation formatted))
              , DA.klass_ "form-input-field"
              ]
              []
        , D.span
            [ DA.klass_ "text-red-500 text-xs" ]
            [ text
                ( map
                    ( \mValid -> case mValid of
                        Just false -> config.errorMessage
                        _ -> ""
                    )
                    validEvent
                )
            ]
        ]
    ]

makeNormalField
  :: FieldConfig
  -> (String -> Effect Unit)
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Nut
makeNormalField config setValue setValid validEvent =
  makeTextField config setValue setValid validEvent false

makeDescriptionField
  :: String
  -> (String -> Effect Unit)
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Nut
makeDescriptionField defaultValue setValue setValid validEvent =
  makeTextArea
    { label: "Description"
    , placeholder: "Enter description"
    , defaultValue: defaultValue
    , rows: "4"
    , cols: "40"
    , errorMessage: "Description is required"
    }
    setValue
    setValid
    validEvent

makeDropdown
  :: DropdownConfig
  -> (String -> Effect Unit)
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Nut
makeDropdown config setValue setValid validEvent =
  D.div_
    [ D.div
        [ DA.klass_ "flex items-center gap-2" ]
        [ D.label_
            [ text_ config.label ]
        , D.select
            [ DA.klass_ "form-input-field"
            , DL.load_ \_ -> do
                setValue config.defaultValue
                let
                  isEmpty = case config.emptyOption of
                    Just emptyOpt -> config.defaultValue == emptyOpt.value
                    Nothing -> config.defaultValue == ""
                setValid (Just (not isEmpty))
                liftEffect $ Console.log $
                  "Dropdown " <> config.label
                    <> " initialized with: "
                    <> config.defaultValue
                    <> ", valid: "
                    <> show (not isEmpty)
            , DL.change_ \evt -> do
                for_ (target evt >>= Select.fromEventTarget) \selectElement ->
                  do
                    v <- Select.value selectElement
                    setValue v
                    let
                      isEmpty = case config.emptyOption of
                        Just emptyOpt -> v == emptyOpt.value
                        Nothing -> v == ""
                    setValid (Just (not isEmpty))
                    liftEffect $ Console.log $
                      "Dropdown " <> config.label
                        <> " changed to: "
                        <> v
                        <> ", valid: "
                        <> show (not isEmpty)
            ]
            ( let
                emptyOptions = case config.emptyOption of
                  Just emptyOpt -> [ emptyOpt ]
                  Nothing -> []
                allOptions = emptyOptions <> config.options
              in
                allOptions <#> \opt ->
                  let
                    isSelected = opt.value == config.defaultValue
                  in
                    D.option
                      [ DA.value_ opt.value
                      , if isSelected then DA.selected_ "selected"
                        else DA.klass_ ""
                      ]
                      [ text_ opt.label ]
            )
        , D.span
            [ DA.klass_ "text-red-500 text-xs" ]
            [ text
                ( map
                    ( \mValid -> case mValid of
                        Just false -> "Please select an option"
                        _ -> ""
                    )
                    validEvent
                )
            ]
        ]
    ]

makeEnumDropdown
  :: ∀ a
   . BoundedEnum a
  => Bounded a
  => Show a
  => { label :: String, defaultValue :: String, includeEmptyOption :: Boolean }
  -> DropdownConfig
makeEnumDropdown { label, defaultValue, includeEmptyOption } =
  { label
  , options: map (\val -> { value: show val, label: show val })
      (getAllEnumValues :: Array a)
  , defaultValue
  , emptyOption:
      if includeEmptyOption then Just { value: "", label: "Select..." }
      else Nothing
  }