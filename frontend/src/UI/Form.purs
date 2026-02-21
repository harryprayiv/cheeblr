module Cheeblr.UI.Form where

import Prelude

import Cheeblr.Core.Schema (FieldDescriptor, FieldType(..), FormSchema)
import Cheeblr.Core.Validation (runValidation)
import Cheeblr.UI.FormHelpers (getInputValue, getSelectValue)
import Data.Array (filter)
import Data.Array as Data.Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
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
import Effect.Ref as Ref
import FRP.Poll (Poll)

type FormFieldState =
  { key :: String
  , descriptor :: FieldDescriptor
  , value :: Poll String
  , setValue :: String -> Effect Unit
  , isValid :: Poll (Maybe Boolean)
  , setValid :: Maybe Boolean -> Effect Unit
  , touched :: Poll Boolean
  , setTouched :: Boolean -> Effect Unit
  }

type FormState =
  { fields :: Array FormFieldState
  , fieldMap :: Map String FormFieldState
  , isFormValid :: Poll Boolean
  , valuesRef :: Ref (Map String String)
  }

readValues :: FormState -> Effect (Map String String)
readValues form = Ref.read form.valuesRef

readValue :: FormState -> String -> Effect (Maybe String)
readValue form key = do
  vals <- Ref.read form.valuesRef
  pure $ Map.lookup key vals

buildForm
  :: FormSchema
  -> Array { key :: String, value :: String }
  -> Ref (Map String String)
  -> (FormState -> Nut)
  -> Nut
buildForm schema initialValues valuesRef renderFn =
  buildFields schema initialValues valuesRef [] renderFn

buildFields
  :: Array FieldDescriptor
  -> Array { key :: String, value :: String }
  -> Ref (Map String String)
  -> Array FormFieldState
  -> (FormState -> Nut)
  -> Nut
buildFields descriptors initVals valuesRef accumulated renderFn =
  case Data.Array.uncons descriptors of
    Nothing ->
      let
        fieldMap = Map.fromFoldable $
          accumulated <#> \fs -> fs.key /\ fs
        isFormValid = computeFormValidity accumulated
        formState = { fields: accumulated, fieldMap, isFormValid, valuesRef }
      in
        renderFn formState

    Just { head: desc, tail: rest } ->
      let
        initVal = lookupInitial desc.key initVals
        -- Pre-validate non-empty initial values (edit mode)
        initValid =
          if initVal == "" then Nothing
          else Just (runValidation desc.validation (desc.formatInput initVal))
        initTouched = initVal /= ""
      in
        Deku.do
          setValue /\ valuePoll <- useState initVal
          setValid /\ validPoll <- useState initValid
          setTouched /\ touchedPoll <- useState initTouched

          let
            fieldState =
              { key: desc.key
              , descriptor: desc
              , value: valuePoll
              , setValue
              , isValid: validPoll
              , setValid
              , touched: touchedPoll
              , setTouched
              }

          buildFields rest initVals valuesRef
            (accumulated <> [ fieldState ]) renderFn

renderField :: Ref (Map String String) -> FormFieldState -> Nut
renderField valuesRef fs =
  let
    validate str = do
      let formatted = fs.descriptor.formatInput str
      fs.setTouched true
      if formatted == "" then
        fs.setValid Nothing
      else
        fs.setValid (Just (runValidation fs.descriptor.validation formatted))

    handleInput str = do
      fs.setValue str
      Ref.modify_ (Map.insert fs.key str) valuesRef
      validate str
  in
    D.div
      [ DA.klass_ "form-field" ]
      [
        D.label
          [ DA.klass_ "form-field-label" ]
          [ text_ fs.descriptor.label ]

      , renderInputElement fs.descriptor.fieldType handleInput fs.value

      , validationIndicator fs
      ]

validationIndicator :: FormFieldState -> Nut
validationIndicator fs =
  ((/\) <$> fs.isValid <*> fs.touched) <#~> \(valid /\ wasTouched) ->
    case valid, wasTouched of
      Just false, true ->
        D.span
          [ DA.klass_ "form-field-error" ]
          [ text_ fs.descriptor.errorMessage ]
      Just true, true ->
        D.span
          [ DA.klass_ "form-field-valid" ]
          [ text_ "✓" ]
      _, _ ->
        D.span_ []

renderInputElement :: FieldType -> (String -> Effect Unit) -> Poll String -> Nut
renderInputElement fieldType handleInput valuePoll = case fieldType of

  TextField ->
    D.input
      [ DA.klass_ "form-input"
      , DA.xtype_ "text"
      , DA.value valuePoll
      , DL.input_ \evt -> do
          val <- getInputValue evt
          handleInput val
      ] []

  NumberField ->
    D.input
      [ DA.klass_ "form-input"
      , DA.xtype_ "number"
      , DA.value valuePoll
      , DL.input_ \evt -> do
          val <- getInputValue evt
          handleInput val
      ] []

  PasswordField ->
    D.input
      [ DA.klass_ "form-input"
      , DA.xtype_ "password"
      , DA.value valuePoll
      , DL.input_ \evt -> do
          val <- getInputValue evt
          handleInput val
      ] []

  TextArea _ ->
    D.textarea
      [ DA.klass_ "form-input form-textarea"
      , DL.input_ \evt -> do
          val <- getInputValue evt
          handleInput val
      ] []

  Dropdown options ->
    D.select
      [ DA.klass_ "form-select"
      , DL.change_ \evt -> do
          val <- getSelectValue evt
          handleInput val
      ]
      (options <#> \opt ->
        D.option
          [ DA.value_ opt.value ]
          [ text_ opt.label ]
      )

  TagDropdown { options, emptyOption } ->
    D.select
      [ DA.klass_ "form-select"
      , DL.change_ \evt -> do
          val <- getSelectValue evt
          handleInput val
      ]
      ( case emptyOption of
          Just empty ->
            [ D.option [ DA.value_ empty.value ] [ text_ empty.label ] ]
              <> (options <#> mkOpt)
          Nothing ->
            options <#> mkOpt
      )
    where
    mkOpt opt = D.option [ DA.value_ opt.value ] [ text_ opt.label ]

renderForm
  :: FormState
  -> { title :: String
     , submitLabel :: String
     , onSubmit :: Map String String -> Effect Unit
     , statusMessage :: Poll String
     }
  -> Nut
renderForm formState opts =
  D.div
    [ DA.klass_ "product-form" ]
    [ D.h2 [ DA.klass_ "form-title" ] [ text_ opts.title ]

    , D.div
        [ DA.klass_ "form-fields" ]
        (formState.fields <#> renderField formState.valuesRef)

    , opts.statusMessage <#~> \msg ->
        if msg == "" then D.span_ []
        else D.div [ DA.klass_ "form-status" ] [ text_ msg ]

    , formState.isFormValid <#~> \valid ->
        D.button
          [ DA.klass_ $
              if valid then "form-submit" else "form-submit disabled"
          , DL.click_ \_ -> do
              when valid do
                values <- readValues formState
                opts.onSubmit values
          ]
          [ text_ opts.submitLabel ]
    ]

lookupInitial :: String -> Array { key :: String, value :: String } -> String
lookupInitial key initVals =
  case Data.Array.find (\iv -> iv.key == key) initVals of
    Just iv -> iv.value
    Nothing -> ""

computeFormValidity :: Array FormFieldState -> Poll Boolean
computeFormValidity fields =
  let
    validatable = filter (\fs -> fs.descriptor.errorMessage /= "") fields
  in
    case validatable of
      [] -> pure true
      _ ->
        Data.Array.foldl
          (\accPoll fs ->
            (/\) <$> accPoll <*> fs.isValid <#> \(acc /\ fieldValid) ->
              acc && fromMaybe false fieldValid
          )
          (pure true)
          validatable