module UI.Inventory.ItemForm where

import Prelude

import API.Inventory (writeInventory, updateInventory)
import Data.Array (all, filter)
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap)
import Data.String (joinWith, trim)
import Data.String.Common (split) as String
import Data.String.Pattern (Pattern(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useHot)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import FRP.Poll (Poll)
import Services.AuthService (UserId)
import Types.Formatting (ValidationRule)
import Types.Inventory (MenuItem(..), StrainLineage(..), InventoryResponse(..), validateMenuItem)
import Utils.Formatting (formatCentsToDecimal)
import Utils.Validation (allOf, alphanumeric, dollarAmount, nonEmpty, nonNegativeInteger, percentage, runValidation, validMeasurementUnit, validUrl)
import Web.Event.Event (target)
import Web.HTML.HTMLInputElement (fromEventTarget, value) as Input
import Web.HTML.HTMLSelectElement (fromEventTarget, value) as Select
import Web.HTML.HTMLTextAreaElement (fromEventTarget, value) as TextArea

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

type FormInit =
  { name :: String
  , sku :: String
  , brand :: String
  , price :: String
  , quantity :: String
  , category :: String
  , subcategory :: String
  , sort :: String
  , measureUnit :: String
  , perPackage :: String
  , description :: String
  , tags :: String
  , effects :: String
  , strain :: String
  , species :: String
  , creator :: String
  , lineage :: String
  , thc :: String
  , cbg :: String
  , dominantTerpene :: String
  , terpenes :: String
  , leaflyUrl :: String
  , img :: String
  }

initValues :: FormMode -> FormInit
initValues (CreateMode uuid) =
  { name: ""
  , sku: uuid
  , brand: ""
  , price: ""
  , quantity: ""
  , category: ""
  , subcategory: ""
  , sort: ""
  , measureUnit: ""
  , perPackage: ""
  , description: ""
  , tags: ""
  , effects: ""
  , strain: ""
  , species: ""
  , creator: ""
  , lineage: ""
  , thc: ""
  , cbg: ""
  , dominantTerpene: ""
  , terpenes: ""
  , leaflyUrl: ""
  , img: ""
  }
initValues (EditMode (MenuItem i)) =
  let
    (StrainLineage sl) = i.strain_lineage
  in
    { name: i.name
    , sku: show i.sku
    , brand: i.brand
    , price: formatCentsToDecimal (unwrap i.price)
    , quantity: show i.quantity
    , category: show i.category
    , subcategory: i.subcategory
    , sort: show i.sort
    , measureUnit: i.measure_unit
    , perPackage: i.per_package
    , description: i.description
    , tags: joinWith ", " i.tags
    , effects: joinWith ", " i.effects
    , strain: sl.strain
    , species: show sl.species
    , creator: sl.creator
    , lineage: joinWith ", " sl.lineage
    , thc: sl.thc
    , cbg: sl.cbg
    , dominantTerpene: sl.dominant_terpene
    , terpenes: joinWith ", " sl.terpenes
    , leaflyUrl: sl.leafly_url
    , img: sl.img
    }

inputKls :: String
inputKls =
  """rounded-md border-gray-300 shadow-sm
     border-2 mr-2 border-solid
     focus:border-indigo-500 focus:ring-indigo-500"""

vTextField
  :: String
  -> String
  -> (String -> Effect Unit)
  -> Poll String
  -> ValidationRule
  -> String
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Nut
vTextField label placeholder setValue valuePoll rule errMsg setValid validPoll =
  D.div [ DA.klass_ "mb-3" ]
    [ D.div [ DA.klass_ "flex items-center gap-2" ]
        [ D.label [ DA.klass_ "w-36 text-sm font-medium" ] [ text_ label ]
        , D.input
            [ DA.placeholder_ placeholder
            , DA.value valuePoll
            , DL.input_ \evt ->
                for_ (target evt >>= Input.fromEventTarget) \el -> do
                  v <- Input.value el
                  let trimmed = trim v
                  setValue trimmed
                  setValid (Just (runValidation rule trimmed))
            , DA.klass_ inputKls
            ]
            []
        , D.span [ DA.klass_ "text-red-500 text-xs" ]
            [ text $ validPoll <#> case _ of
                Just false -> errMsg
                _ -> ""
            ]
        ]
    ]

plainTextField
  :: String -> String -> (String -> Effect Unit) -> Poll String -> Nut
plainTextField label placeholder setValue valuePoll =
  D.div [ DA.klass_ "mb-3" ]
    [ D.div [ DA.klass_ "flex items-center gap-2" ]
        [ D.label [ DA.klass_ "w-36 text-sm font-medium" ] [ text_ label ]
        , D.input
            [ DA.placeholder_ placeholder
            , DA.value valuePoll
            , DL.input_ \evt ->
                for_ (target evt >>= Input.fromEventTarget) \el -> do
                  v <- Input.value el
                  setValue (trim v)
            , DA.klass_ inputKls
            ]
            []
        ]
    ]

readOnlyField :: String -> Poll String -> Nut
readOnlyField label valuePoll =
  D.div [ DA.klass_ "mb-3" ]
    [ D.div [ DA.klass_ "flex items-center gap-2" ]
        [ D.label [ DA.klass_ "w-36 text-sm font-medium" ] [ text_ label ]
        , D.input
            [ DA.klass_ (inputKls <> " bg-gray-100")
            , DA.value valuePoll
            , DA.disabled_ "true"
            ]
            []
        ]
    ]

textAreaField
  :: String -> String -> String -> (String -> Effect Unit) -> Nut
textAreaField label placeholder initialValue setValue =
  D.div [ DA.klass_ "mb-3" ]
    [ D.div [ DA.klass_ "flex items-start gap-2" ]
        [ D.label [ DA.klass_ "w-36 text-sm font-medium pt-2" ] [ text_ label ]
        , D.textarea
            [ DA.placeholder_ placeholder
            , DA.cols_ "40"
            , DA.rows_ "4"
            , DL.input_ \evt ->
                for_ (target evt >>= TextArea.fromEventTarget) \el -> do
                  v <- TextArea.value el
                  setValue v
            , DA.klass_ (inputKls <> " resize-y")
            ]
            [ text_ initialValue ]
        ]
    ]

selectField
  :: String
  -> Array { value :: String, label :: String }
  -> String
  -> (String -> Effect Unit)
  -> ValidationRule
  -> String
  -> (Maybe Boolean -> Effect Unit)
  -> Poll (Maybe Boolean)
  -> Nut
selectField label options initialValue setValue rule errMsg setValid validPoll =
  D.div [ DA.klass_ "mb-3" ]
    [ D.div [ DA.klass_ "flex items-center gap-2" ]
        [ D.label [ DA.klass_ "w-36 text-sm font-medium" ] [ text_ label ]
        , D.select
            [ DA.klass_ inputKls
            , DL.change_ \evt ->
                for_ (target evt >>= Select.fromEventTarget) \el -> do
                  v <- Select.value el
                  setValue v
                  setValid (Just (runValidation rule v))
            ]
            ( map
                ( \opt ->
                    D.option
                      ( [ DA.value_ opt.value ] <>
                          if opt.value == initialValue && initialValue /= ""
                            then [ DA.selected_ "selected" ]
                            else []
                      )
                      [ text_ opt.label ]
                )
                options
            )
        , D.span [ DA.klass_ "text-red-500 text-xs" ]
            [ text $ validPoll <#> case _ of
                Just false -> errMsg
                _ -> ""
            ]
        ]
    ]

sectionHeading :: String -> Nut
sectionHeading title =
  D.h3 [ DA.klass_ "text-lg font-semibold mb-3 border-b pb-1" ]
    [ text_ title ]

categoryOptions :: Array { value :: String, label :: String }
categoryOptions =
  [ { value: "", label: "Select category..." }
  , { value: "Flower", label: "Flower" }
  , { value: "PreRolls", label: "Pre-Rolls" }
  , { value: "Vaporizers", label: "Vaporizers" }
  , { value: "Edibles", label: "Edibles" }
  , { value: "Drinks", label: "Drinks" }
  , { value: "Concentrates", label: "Concentrates" }
  , { value: "Topicals", label: "Topicals" }
  , { value: "Tinctures", label: "Tinctures" }
  , { value: "Accessories", label: "Accessories" }
  ]

speciesOptions :: Array { value :: String, label :: String }
speciesOptions =
  [ { value: "", label: "Select species..." }
  , { value: "Indica", label: "Indica" }
  , { value: "IndicaDominantHybrid", label: "Indica-Dominant Hybrid" }
  , { value: "Hybrid", label: "Hybrid" }
  , { value: "SativaDominantHybrid", label: "Sativa-Dominant Hybrid" }
  , { value: "Sativa", label: "Sativa" }
  ]

splitCommas :: String -> Array String
splitCommas s = filter (_ /= "") $ map trim $ String.split (Pattern ",") s

itemForm :: UserId -> FormMode -> Nut
itemForm userId mode =
  let
    init = initValues mode
    isEdit = case mode of
      EditMode _ -> true
      _ -> false
    v0 = if isEdit then Just true else Just false
  in
    Deku.do

      setName /\ nameV <- useHot init.name
      setValidName /\ validNameV <- useHot v0

      _setSku /\ skuV <- useHot init.sku

      setBrand /\ brandV <- useHot init.brand
      setValidBrand /\ validBrandV <- useHot v0

      setPrice /\ priceV <- useHot init.price
      setValidPrice /\ validPriceV <- useHot v0

      setQuantity /\ quantityV <- useHot init.quantity
      setValidQuantity /\ validQuantityV <- useHot v0

      setCategory /\ categoryV <- useHot init.category
      setValidCategory /\ validCategoryV <- useHot v0

      setSubcategory /\ subcategoryV <- useHot init.subcategory
      setValidSubcategory /\ validSubcategoryV <- useHot v0

      setSort /\ sortV <- useHot init.sort
      setValidSort /\ validSortV <- useHot v0

      setMeasureUnit /\ measureUnitV <- useHot init.measureUnit
      setValidMeasureUnit /\ validMeasureUnitV <- useHot v0

      setPerPackage /\ perPackageV <- useHot init.perPackage
      setValidPerPackage /\ validPerPackageV <- useHot v0

      setDescription /\ descriptionV <- useHot init.description
      setTags /\ tagsV <- useHot init.tags
      setEffects /\ effectsV <- useHot init.effects

      setStrain /\ strainV <- useHot init.strain
      setValidStrain /\ validStrainV <- useHot v0

      setSpecies /\ speciesV <- useHot init.species
      setValidSpecies /\ validSpeciesV <- useHot v0

      setCreator /\ creatorV <- useHot init.creator
      setValidCreator /\ validCreatorV <- useHot v0

      setLineage /\ lineageV <- useHot init.lineage

      setThc /\ thcV <- useHot init.thc
      setValidThc /\ validThcV <- useHot v0

      setCbg /\ cbgV <- useHot init.cbg
      setValidCbg /\ validCbgV <- useHot v0

      setDominantTerpene /\ dominantTerpeneV <- useHot init.dominantTerpene
      setValidDominantTerpene /\ validDominantTerpeneV <- useHot v0

      setTerpenes /\ terpenesV <- useHot init.terpenes

      setLeaflyUrl /\ leaflyUrlV <- useHot init.leaflyUrl
      setValidLeaflyUrl /\ validLeaflyUrlV <- useHot v0

      setImg /\ imgV <- useHot init.img
      setValidImg /\ validImgV <- useHot v0

      setStatusMessage /\ statusMessageV <- useHot ""
      setSubmitting /\ submittingV <- useHot false

      let
        isFormValid = ado
          vN <- validNameV
          vB <- validBrandV
          vP <- validPriceV
          vQ <- validQuantityV
          vC <- validCategoryV
          vSub <- validSubcategoryV
          vS <- validSortV
          vMU <- validMeasureUnitV
          vPP <- validPerPackageV
          vSt <- validStrainV
          vSp <- validSpeciesV
          vCr <- validCreatorV
          vTh <- validThcV
          vCb <- validCbgV
          vDT <- validDominantTerpeneV
          vLU <- validLeaflyUrlV
          vIm <- validImgV
          in all (fromMaybe false)
            [ vN, vB, vP, vQ, vC, vSub, vS, vMU, vPP
            , vSt, vSp, vCr, vTh, vCb, vDT, vLU, vIm
            ]

        formTitle =
          if isEdit then "Edit Menu Item" else "Create Menu Item"

        submitLabel =
          if isEdit then "Update" else "Create"

        resetForm = do
          setName ""
          setValidName (Just false)
          setBrand ""
          setValidBrand (Just false)
          setPrice ""
          setValidPrice (Just false)
          setQuantity ""
          setValidQuantity (Just false)
          setCategory ""
          setValidCategory (Just false)
          setSubcategory ""
          setValidSubcategory (Just false)
          setSort ""
          setValidSort (Just false)
          setMeasureUnit ""
          setValidMeasureUnit (Just false)
          setPerPackage ""
          setValidPerPackage (Just false)
          setDescription ""
          setTags ""
          setEffects ""
          setStrain ""
          setValidStrain (Just false)
          setSpecies ""
          setValidSpecies (Just false)
          setCreator ""
          setValidCreator (Just false)
          setLineage ""
          setThc ""
          setValidThc (Just false)
          setCbg ""
          setValidCbg (Just false)
          setDominantTerpene ""
          setValidDominantTerpene (Just false)
          setTerpenes ""
          setLeaflyUrl ""
          setValidLeaflyUrl (Just false)
          setImg ""
          setValidImg (Just false)

      D.div [ DA.klass_ "space-y-4 max-w-2xl mx-auto p-6" ]
        [ D.h2 [ DA.klass_ "text-2xl font-bold mb-6" ] [ text_ formTitle ]

        , D.div [ DA.klass_ "mb-6" ]
            [ sectionHeading "Basic Info"
            , vTextField "Name" "Item name"
                setName nameV
                (allOf [ nonEmpty, alphanumeric ]) "Name required (text only)"
                setValidName validNameV
            , readOnlyField "SKU" skuV
            , vTextField "Brand" "Brand name"
                setBrand brandV
                (allOf [ nonEmpty, alphanumeric ]) "Brand required"
                setValidBrand validBrandV
            , vTextField "Price" "0.00"
                setPrice priceV
                dollarAmount "Valid price required (e.g. 29.99)"
                setValidPrice validPriceV
            , vTextField "Quantity" "0"
                setQuantity quantityV
                nonNegativeInteger "Whole number required"
                setValidQuantity validQuantityV
            , selectField "Category" categoryOptions init.category
                setCategory
                nonEmpty "Category is required"
                setValidCategory validCategoryV
            , vTextField "Subcategory" "e.g. Gummies, Cartridge"
                setSubcategory subcategoryV
                (allOf [ nonEmpty, alphanumeric ]) "Subcategory required"
                setValidSubcategory validSubcategoryV
            , vTextField "Sort Order" "0"
                setSort sortV
                nonNegativeInteger "Whole number required"
                setValidSort validSortV
            , vTextField "Measure Unit" "g, oz, ml"
                setMeasureUnit measureUnitV
                validMeasurementUnit "Valid unit required"
                setValidMeasureUnit validMeasureUnitV
            , vTextField "Per Package" "e.g. 3.5g, 1oz"
                setPerPackage perPackageV
                (allOf [ nonEmpty ]) "Per-package amount required"
                setValidPerPackage validPerPackageV
            , textAreaField "Description" "Item description"
                init.description setDescription
            , plainTextField "Tags" "tag1, tag2, tag3"
                setTags tagsV
            , plainTextField "Effects" "relaxed, happy, creative"
                setEffects effectsV
            ]

        , D.div [ DA.klass_ "mb-6" ]
            [ sectionHeading "Strain & Lineage"
            , vTextField "Strain" "Strain name"
                setStrain strainV
                (allOf [ nonEmpty, alphanumeric ]) "Strain required"
                setValidStrain validStrainV
            , selectField "Species" speciesOptions init.species
                setSpecies
                nonEmpty "Species is required"
                setValidSpecies validSpeciesV
            , vTextField "Creator" "Breeder/creator name"
                setCreator creatorV
                (allOf [ nonEmpty, alphanumeric ]) "Creator required"
                setValidCreator validCreatorV
            , plainTextField "Lineage" "Parent strain 1, Parent strain 2"
                setLineage lineageV
            ]

        , D.div [ DA.klass_ "mb-6" ]
            [ sectionHeading "Compliance"
            , vTextField "THC %" "e.g. 25.5"
                setThc thcV
                percentage "Format: XX.XX"
                setValidThc validThcV
            , vTextField "CBG %" "e.g. 0.8"
                setCbg cbgV
                percentage "Format: XX.XX"
                setValidCbg validCbgV
            , vTextField "Dominant Terpene" "e.g. Myrcene"
                setDominantTerpene dominantTerpeneV
                (allOf [ nonEmpty, alphanumeric ]) "Required"
                setValidDominantTerpene validDominantTerpeneV
            , plainTextField "Terpenes" "Myrcene, Limonene, Caryophyllene"
                setTerpenes terpenesV
            ]

        , D.div [ DA.klass_ "mb-6" ]
            [ sectionHeading "Media & Links"
            , vTextField "Leafly URL" "https://leafly.com/..."
                setLeaflyUrl leaflyUrlV
                validUrl "Valid URL required"
                setValidLeaflyUrl validLeaflyUrlV
            , vTextField "Image URL" "https://..."
                setImg imgV
                validUrl "Valid URL required"
                setValidImg validImgV
            ]

        , D.div [ DA.klass_ "mt-6 flex items-center gap-4" ]
            [ D.button
                [ DA.klass $ isFormValid <#> \v ->
                    "px-6 py-2 rounded-md text-white font-medium " <>
                      if v then "bg-indigo-600 hover:bg-indigo-700"
                      else "bg-gray-400 cursor-not-allowed"
                , DL.runOn DL.click $ ado
                    name <- nameV
                    sku <- skuV
                    brand <- brandV
                    price <- priceV
                    quantity <- quantityV
                    category <- categoryV
                    subcategory <- subcategoryV
                    sort' <- sortV
                    measureUnit <- measureUnitV
                    perPackage <- perPackageV
                    description <- descriptionV
                    tags <- tagsV
                    effects <- effectsV
                    strain <- strainV
                    species <- speciesV
                    creator <- creatorV
                    lineage <- lineageV
                    thc <- thcV
                    cbg <- cbgV
                    dominantTerpene <- dominantTerpeneV
                    terpenes <- terpenesV
                    leaflyUrl <- leaflyUrlV
                    img <- imgV
                    valid <- isFormValid
                    submitting <- submittingV
                    in when (valid && not submitting) do
                      setSubmitting true
                      setStatusMessage "Submitting..."

                      let
                        formInput =
                          { sort: sort'
                          , name
                          , sku
                          , brand
                          , price
                          , measure_unit: measureUnit
                          , per_package: perPackage
                          , quantity
                          , category
                          , subcategory
                          , description
                          , tags
                          , effects
                          , strain_lineage:
                              { thc
                              , cbg
                              , strain
                              , creator
                              , species
                              , dominant_terpene: dominantTerpene
                              , terpenes
                              , lineage
                              , leafly_url: leaflyUrl
                              , img
                              }
                          }

                      case validateMenuItem formInput of
                        Left parseErr -> do
                          setStatusMessage $ "Validation error: " <> parseErr
                          setSubmitting false

                        Right menuItem ->
                          launchAff_ do
                            result <- case mode of
                              CreateMode _ -> writeInventory userId menuItem
                              EditMode _   -> updateInventory userId menuItem

                            liftEffect $ case result of
                              Right (Message msg) -> do
                                setStatusMessage $ "Success: " <> msg
                                setSubmitting false
                                case mode of
                                  CreateMode _ -> resetForm
                                  EditMode _   -> pure unit

                              Right (InventoryData _) -> do
                                setStatusMessage "Success"
                                setSubmitting false

                              Left err -> do
                                setStatusMessage $ "Error: " <> err
                                setSubmitting false
                ]
                [ text $ ado
                    sub <- submittingV
                    valid <- isFormValid
                    in
                      if sub then "Submitting..."
                      else if valid then submitLabel
                      else submitLabel <> " (fix errors)"
                ]
            ]

        , D.div [ DA.klass_ "mt-4 text-center" ] [ text statusMessageV ]
        ]