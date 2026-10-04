module UI.Inventory.ItemForm
  ( FormMode(..)
  , itemForm
  , menuItemForm
  , renderError
  ) where

import Prelude

import API.Inventory (writeInventory, updateInventory)
import Data.Either (Either(..))
import Data.Finance.Money (Discrete(..))
import Data.Maybe (Maybe(..), maybe)
import Data.Newtype (unwrap)
import Data.String (joinWith)
import Data.Tuple.Nested ((/\))
import Data.Validation.Semigroup (toEither)
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Services.AuthService (UserId)
import Types.Inventory (ItemCategory(..), MenuItem(..), Species(..), StrainLineage(..))
import UI.Form (Form, isValid, readOnly, runForm, section, select)
import UI.Form (text, textArea) as F
import UI.Form.Parser (alphanumeric, anyText, cents, commaList, measurementUnit, nonNegativeInt, percentage, required, url, uuid)
import Utils.Formatting (formatCentsToDecimal)

renderError :: String -> Nut
renderError message =
  D.div
    [ DA.klass_ "error-container max-w-2xl mx-auto p-6" ]
    [ D.div
        [ DA.klass_ "bg-red-100 border-l-4 border-red-500 text-red-700 p-4" ]
        [ D.h2
            [ DA.klass_ "text-lg font-medium mb-2" ]
            [ text_ "Error Loading Item" ]
        , D.p_
            [ text_ message ]
        , D.div
            [ DA.klass_ "mt-4" ]
            [ D.a
                [ DA.href_ "/#/"
                , DA.klass_ "text-blue-600 hover:underline"
                ]
                [ text_ "Return to Inventory" ]
            ]
        ]
    ]

data FormMode = CreateMode String | EditMode MenuItem

categoryLabel :: ItemCategory -> String
categoryLabel = case _ of
  PreRolls -> "Pre-Rolls"
  other -> show other

speciesLabel :: Species -> String
speciesLabel = case _ of
  Indica -> "Indica"
  IndicaDominantHybrid -> "Indica-Dominant Hybrid"
  Hybrid -> "Hybrid"
  SativaDominantHybrid -> "Sativa-Dominant Hybrid"
  Sativa -> "Sativa"

-- The whole item form. Adding a field means adding one line to the section
-- it belongs in and one name to that section's result record.
menuItemForm :: FormMode -> Form MenuItem
menuItemForm mode = ado
  basic <- section "Basic Info" basicInfo
  strain <- section "Strain & Lineage" strainInfo
  compliance <- section "Compliance" complianceInfo
  media <- section "Media & Links" mediaInfo
  in
    basic $ StrainLineage
      { thc: compliance.thc
      , cbg: compliance.cbg
      , strain: strain.strain
      , creator: strain.creator
      , species: strain.species
      , dominant_terpene: compliance.dominant_terpene
      , terpenes: compliance.terpenes
      , lineage: strain.lineage
      , leafly_url: media.leafly_url
      , img: media.img
      }
  where
  existing = case mode of
    EditMode (MenuItem i) -> Just i
    CreateMode _ -> Nothing

  existingStrain = existing <#> \i ->
    let
      StrainLineage sl = i.strain_lineage
    in
      sl

  -- Initial text for a field: read from the item being edited, or blank.
  item :: forall r. (_ -> r) -> (r -> String) -> String
  item get render = maybe "" (render <<< get) existing

  lineage :: forall r. (_ -> r) -> (r -> String) -> String
  lineage get render = maybe "" (render <<< get) existingStrain

  list = joinWith ", "

  skuText = case mode of
    CreateMode generated -> generated
    EditMode (MenuItem i) -> show i.sku

  requiredName = required >=> alphanumeric

  basicInfo = ado
    name <- F.text
      { label: "Name", placeholder: "Item name", initial: item _.name identity }
      requiredName
    sku <- readOnly { label: "SKU", value: skuText } uuid
    brand <- F.text
      { label: "Brand", placeholder: "Brand name", initial: item _.brand identity }
      requiredName
    price <- Discrete <$> F.text
      { label: "Price"
      , placeholder: "0.00"
      , initial: item _.price (formatCentsToDecimal <<< unwrap)
      }
      cents
    quantity <- F.text
      { label: "Quantity", placeholder: "0", initial: item _.quantity show }
      nonNegativeInt
    category <- select
      { label: "Category"
      , prompt: "Select category..."
      , initial: _.category <$> existing
      , display: categoryLabel
      }
    subcategory <- F.text
      { label: "Subcategory"
      , placeholder: "e.g. Gummies, Cartridge"
      , initial: item _.subcategory identity
      }
      requiredName
    sort <- F.text
      { label: "Sort Order", placeholder: "0", initial: item _.sort show }
      nonNegativeInt
    measure_unit <- F.text
      { label: "Measure Unit"
      , placeholder: "g, oz, ml"
      , initial: item _.measure_unit identity
      }
      measurementUnit
    per_package <- F.text
      { label: "Per Package"
      , placeholder: "e.g. 3.5g, 1oz"
      , initial: item _.per_package identity
      }
      required
    description <- F.textArea
      { label: "Description"
      , placeholder: "Item description"
      , initial: item _.description identity
      }
      anyText
    tags <- F.text
      { label: "Tags", placeholder: "tag1, tag2, tag3", initial: item _.tags list }
      commaList
    effects <- F.text
      { label: "Effects"
      , placeholder: "relaxed, happy, creative"
      , initial: item _.effects list
      }
      commaList
    in
      \strain_lineage -> MenuItem
        { sort
        , sku
        , brand
        , name
        , price
        , measure_unit
        , per_package
        , quantity
        , category
        , subcategory
        , description
        , tags
        , effects
        , strain_lineage
        }

  strainInfo = ado
    strain <- F.text
      { label: "Strain", placeholder: "Strain name", initial: lineage _.strain identity }
      requiredName
    species <- select
      { label: "Species"
      , prompt: "Select species..."
      , initial: _.species <$> existingStrain
      , display: speciesLabel
      }
    creator <- F.text
      { label: "Creator"
      , placeholder: "Breeder/creator name"
      , initial: lineage _.creator identity
      }
      requiredName
    lineage' <- F.text
      { label: "Lineage"
      , placeholder: "Parent strain 1, Parent strain 2"
      , initial: lineage _.lineage list
      }
      commaList
    in { strain, species, creator, lineage: lineage' }

  complianceInfo = ado
    thc <- F.text
      { label: "THC %", placeholder: "e.g. 25.5%", initial: lineage _.thc identity }
      percentage
    cbg <- F.text
      { label: "CBG %", placeholder: "e.g. 0.8%", initial: lineage _.cbg identity }
      percentage
    dominant_terpene <- F.text
      { label: "Dominant Terpene"
      , placeholder: "e.g. Myrcene"
      , initial: lineage _.dominant_terpene identity
      }
      requiredName
    terpenes <- F.text
      { label: "Terpenes"
      , placeholder: "Myrcene, Limonene, Caryophyllene"
      , initial: lineage _.terpenes list
      }
      commaList
    in { thc, cbg, dominant_terpene, terpenes }

  mediaInfo = ado
    leafly_url <- F.text
      { label: "Leafly URL"
      , placeholder: "https://leafly.com/..."
      , initial: lineage _.leafly_url identity
      }
      url
    img <- F.text
      { label: "Image URL", placeholder: "https://...", initial: lineage _.img identity }
      url
    in { leafly_url, img }

itemForm :: UserId -> FormMode -> Nut
itemForm userId mode = runForm (menuItemForm mode) \form -> Deku.do
  setStatusMessage /\ statusMessageV <- useHot ""
  setSubmitting /\ submittingV <- useHot false

  let
    valid = isValid form

    isEdit = case mode of
      EditMode _ -> true
      CreateMode _ -> false

    formTitle = if isEdit then "Edit Menu Item" else "Create Menu Item"

    submitLabel = if isEdit then "Update" else "Create"

    submit menuItem = do
      setSubmitting true
      setStatusMessage "Submitting..."
      launchAff_ do
        result <-
          if isEdit then updateInventory userId menuItem
          else writeInventory userId menuItem
        liftEffect do
          setSubmitting false
          case result of
            Right { success: true, message: msg } -> do
              setStatusMessage $ "Success: " <> msg
              unless isEdit form.reset
            Right { success: false, message: msg } ->
              setStatusMessage $ "Error: " <> msg
            Left err ->
              setStatusMessage $ "Error: " <> err

  D.div [ DA.klass_ "space-y-4 max-w-2xl mx-auto p-6" ]
    ( [ D.h2 [ DA.klass_ "text-2xl font-bold mb-6" ] [ text_ formTitle ] ]
        <> form.view
        <>
          [ D.div [ DA.klass_ "mt-6 flex items-center gap-4" ]
              [ D.button
                  [ DA.klass $ valid <#> \v ->
                      "px-6 py-2 rounded-md text-white font-medium " <>
                        if v then "bg-indigo-600 hover:bg-indigo-700"
                        else "bg-gray-400 cursor-not-allowed"
                  , DL.runOn DL.click $
                      ( \result submitting ->
                          case toEither result of
                            Right menuItem | not submitting -> submit menuItem
                            _ -> pure unit
                      )
                        <$> form.result
                        <*> submittingV
                  ]
                  [ text $
                      ( \sub v ->
                          if sub then "Submitting..."
                          else if v then submitLabel
                          else submitLabel <> " (fix errors)"
                      )
                        <$> submittingV
                        <*> valid
                  ]
              ]
          , D.div [ DA.klass_ "mt-4 text-center" ] [ text statusMessageV ]
          ]
    )