module Form where

import Prelude

import Data.Enum (class BoundedEnum)
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), Replacement(..), trim, replaceAll)
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import FRP.Poll (Poll)
import Types (DropdownConfig, ItemCategory, Species, ValidationRule(..), runValidation)
import Utils (getAllEnumValues)
import Validation (allOf, alphanumeric, anyOf, commaList, dollarAmount, extendedAlphanumeric, fraction, maxLength, nonEmpty, nonNegativeInteger, percentage, validMeasurementUnit, validUrl)
import Web.Event.Event (target)
import Web.HTML.HTMLInputElement (fromEventTarget, value) as Input
import Web.HTML.HTMLSelectElement (fromEventTarget, value) as Select
import Web.UIEvent.KeyboardEvent (toEvent)
import Web.HTML.HTMLTextAreaElement (fromEventTarget, value) as TextArea

type FieldConfig =
  { label :: String
  , placeholder :: String
  , defaultValue :: String
  , validation :: ValidationRule
  , errorMessage :: String
  , formatInput :: String -> String
  }

type TextAreaConfig =
  { label :: String
  , placeholder :: String
  , defaultValue :: String
  , rows :: String
  , cols :: String
  , errorMessage :: String
  }

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
            , DA.klass_ inputKls
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

-- Modified makeTextField to include a password option
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
              , DA.klass_ (inputKls <> " resize-y")
              ]
              [ text_ config.defaultValue ]
          else
            D.input
              [ DA.placeholder_ config.placeholder
              , DA.value_ config.defaultValue
              , DA.xtype_ (if isPw then "password" else "text") -- Use password type if isPw is true
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
              , DA.klass_ inputKls
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

-- defaults to a non-password field
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
            [ DA.klass_ inputKls
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

-- Field config builders that include validation
nameConfig :: String -> FieldConfig
nameConfig defaultValue =
  { label: "Name"
  , placeholder: "Enter product name"
  , defaultValue
  , validation: allOf [ nonEmpty, extendedAlphanumeric, maxLength 50 ]
  , errorMessage: "Name is required and must be less than 50 characters"
  , formatInput: trim
  }

passwordConfig :: String -> FieldConfig
passwordConfig defaultValue =
  { label: "Password"
  , placeholder: "Enter password"
  , defaultValue
  , validation: nonEmpty
  , errorMessage: "Password is required"
  , formatInput: identity
  }

skuConfig :: String -> FieldConfig
skuConfig defaultValue =
  { label: "SKU"
  , placeholder: "Enter UUID"
  , defaultValue
  , validation: ValidationRule \_ -> true
  , errorMessage: "Required, must be a valid UUID"
  , formatInput: trim
  }

brandConfig :: String -> FieldConfig
brandConfig defaultValue =
  { label: "Brand"
  , placeholder: "Enter brand name"
  , defaultValue
  , validation: allOf [ nonEmpty, extendedAlphanumeric ]
  , errorMessage: "Brand name is required"
  , formatInput: trim
  }

priceConfig :: String -> FieldConfig
priceConfig defaultValue =
  { label: "Price"
  , placeholder: "Enter price"
  , defaultValue
  , validation: dollarAmount
  , errorMessage: "Price must be a valid number"
  , formatInput: trim
  }

quantityConfig :: String -> FieldConfig
quantityConfig defaultValue =
  { label: "Quantity"
  , placeholder: "Enter quantity"
  , defaultValue
  , validation: nonNegativeInteger
  , errorMessage: "Quantity must be a non-negative number"
  , formatInput: trim
  }

sortConfig :: String -> FieldConfig
sortConfig defaultValue =
  { label: "Sort Order"
  , placeholder: "Enter sort position"
  , defaultValue
  , validation: nonNegativeInteger
  , errorMessage: "Sort order must be a number"
  , formatInput: trim
  }

measureUnitConfig :: String -> FieldConfig
measureUnitConfig defaultValue =
  { label: "Measure Unit"
  , placeholder: "Enter unit (g, mg, etc)"
  , defaultValue
  , validation: validMeasurementUnit
  , errorMessage: "Measure unit is required"
  , formatInput: trim
  }

perPackageConfig :: String -> FieldConfig
perPackageConfig defaultValue =
  { label: "Per Package"
  , placeholder: "Enter amount per package"
  , defaultValue
  , validation: anyOf [ nonNegativeInteger, fraction ]
  , errorMessage: "Per package must be a whole number or fraction"
  , formatInput: trim
  }

subcategoryConfig :: String -> FieldConfig
subcategoryConfig defaultValue =
  { label: "Subcategory"
  , placeholder: "Enter subcategory"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Subcategory is required"
  , formatInput: trim
  }

descriptionConfig :: String -> FieldConfig
descriptionConfig defaultValue =
  { label: "Description"
  , placeholder: "Enter description"
  , defaultValue: defaultValue
  , validation: ValidationRule \_ -> true -- Always valid for testing
  , errorMessage: "Description is required"
  , formatInput: identity -- Don't trim or modify the input
  }

tagsConfig :: String -> FieldConfig
tagsConfig defaultValue =
  { label: "Tags"
  , placeholder: "Enter tags (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

effectsConfig :: String -> FieldConfig
effectsConfig defaultValue =
  { label: "Effects"
  , placeholder: "Enter effects (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

thcConfig :: String -> FieldConfig
thcConfig defaultValue =
  { label: "THC %"
  , placeholder: "Enter THC percentage"
  , defaultValue
  , validation: percentage
  , errorMessage: "THC % must be in format XX.XX%"
  , formatInput: trim
  }

cbgConfig :: String -> FieldConfig
cbgConfig defaultValue =
  { label: "CBG %"
  , placeholder: "Enter CBG percentage"
  , defaultValue
  , validation: percentage
  , errorMessage: "CBG % must be in format XX.XX%"
  , formatInput: trim
  }

strainConfig :: String -> FieldConfig
strainConfig defaultValue =
  { label: "Strain"
  , placeholder: "Enter strain name"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Strain name is required"
  , formatInput: trim
  }

creatorConfig :: String -> FieldConfig
creatorConfig defaultValue =
  { label: "Creator"
  , placeholder: "Enter creator name"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Creator name is required"
  , formatInput: trim
  }

dominantTerpeneConfig :: String -> FieldConfig
dominantTerpeneConfig defaultValue =
  { label: "Dominant Terpene"
  , placeholder: "Enter dominant terpene"
  , defaultValue
  , validation: allOf [ nonEmpty, alphanumeric ]
  , errorMessage: "Dominant terpene is required"
  , formatInput: trim
  }

terpenesConfig :: String -> FieldConfig
terpenesConfig defaultValue =
  { label: "Terpenes"
  , placeholder: "Enter terpenes (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

lineageConfig :: String -> FieldConfig
lineageConfig defaultValue =
  { label: "Lineage"
  , placeholder: "Enter lineage (comma-separated)"
  , defaultValue
  , validation: commaList
  , errorMessage: "Invalid format"
  , formatInput: trim
  }

leaflyUrlConfig :: String -> FieldConfig
leaflyUrlConfig defaultValue =
  { label: "Leafly URL"
  , placeholder: "Enter Leafly URL"
  , defaultValue
  , validation: validUrl
  , errorMessage: "URL must be valid"
  , formatInput: trim
  }

imgConfig :: String -> FieldConfig
imgConfig defaultValue =
  { label: "Image URL"
  , placeholder: "Enter image URL"
  , defaultValue
  , validation: validUrl
  , errorMessage: "URL must be valid"
  , formatInput: trim
  }

categoryConfig
  :: { defaultValue :: String, forNewItem :: Boolean } -> DropdownConfig
categoryConfig { defaultValue, forNewItem } =
  { label: "Category"
  , options: map (\val -> { value: show val, label: show val })
      (getAllEnumValues :: Array ItemCategory)
  , defaultValue
  , emptyOption:
      if forNewItem then Just { value: "", label: "Select..." }
      else Nothing
  }

speciesConfig
  :: { defaultValue :: String, forNewItem :: Boolean } -> DropdownConfig
speciesConfig { defaultValue, forNewItem } =
  { label: "Species"
  , options: map (\val -> { value: show val, label: show val })
      (getAllEnumValues :: Array Species)
  , defaultValue
  , emptyOption:
      if forNewItem then Just { value: "", label: "Select..." }
      else Nothing
  }

-- Style classes
inputKls :: String
inputKls =
  """
  rounded-md border-gray-300 shadow-sm
  border-2 mr-2 border-solid
  focus:border-indigo-500 focus:ring-indigo-500
  sm:text-sm
"""

buttonClass :: String -> String
buttonClass color =
  replaceAll (Pattern "COLOR") (Replacement color)
    """
    mb-3 inline-flex items-center rounded-md
    border border-transparent bg-COLOR-600 px-3 py-2
    text-sm font-medium leading-4 text-white shadow-sm
    hover:bg-COLOR-700 focus:outline-none focus:ring-2
    focus:ring-COLOR-500 focus:ring-offset-2
"""