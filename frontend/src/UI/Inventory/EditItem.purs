module EditItem where

import Prelude

import API.Inventory (updateInventory)
import Config.InventoryFields (brandConfig, categoryConfig, cbgConfig, creatorConfig, dominantTerpeneConfig, effectsConfig, imgConfig, leaflyUrlConfig, lineageConfig, measureUnitConfig, nameConfig, perPackageConfig, priceConfig, quantityConfig, skuConfig, sortConfig, speciesConfig, strainConfig, subcategoryConfig, tagsConfig, terpenesConfig, thcConfig)
import Data.Array (all)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap)
import Data.String (joinWith)
import Data.String.CodeUnits (length)
import Data.Tuple.Nested ((/\))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners (runOn)
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState)
import Effect.Aff (launchAff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Types.Inventory (InventoryResponse(..), MenuItem(..), StrainLineage(..))
import Components.Form (makeDescriptionField, makeDropdown, makeTextField)
import Utils.Formatting (ensureInt, ensureNumber, formatCentsToDecimal)
import Utils.Validation (validateMenuItem)

editItem :: MenuItem -> Nut
editItem (MenuItem item) = Deku.do
  let (StrainLineage lineage) = item.strain_lineage
  let categoryValue = show item.category
  let speciesValue = show lineage.species

  setStatusMessage /\ statusMessageEvent <- useState ""
  setSubmitting /\ submittingEvent <- useState false
  setFiber /\ _ <- useState (pure unit)

  setName /\ nameEvent <- useState item.name
  setValidName /\ validNameEvent <- useState (Just true)

  setSku /\ skuEvent <- useState (show item.sku)
  setValidSku /\ validSkuEvent <- useState (Just true)

  setBrand /\ brandEvent <- useState item.brand
  setValidBrand /\ validBrandEvent <- useState (Just true)

  setPrice /\ priceEvent <- useState (formatCentsToDecimal (unwrap item.price))
  setValidPrice /\ validPriceEvent <- useState (Just true)
  setQuantity /\ quantityEvent <- useState (show item.quantity)
  setValidQuantity /\ validQuantityEvent <- useState (Just true)

  setSort /\ sortEvent <- useState (show item.sort)
  setValidSort /\ validSortEvent <- useState (Just true)

  setMeasureUnit /\ measureUnitEvent <- useState item.measure_unit
  setValidMeasureUnit /\ validMeasureUnitEvent <- useState (Just true)

  setPerPackage /\ perPackageEvent <- useState item.per_package
  setValidPerPackage /\ validPerPackageEvent <- useState (Just true)

  setCategory /\ categoryEvent <- useState categoryValue
  setValidCategory /\ validCategoryEvent <- useState (Just true)

  setSubcategory /\ subcategoryEvent <- useState item.subcategory
  setValidSubcategory /\ validSubcategoryEvent <- useState (Just true)

  setDescription /\ descriptionEvent <- useState item.description
  setValidDescription /\ validDescriptionEvent <- useState (Just true)

  setTags /\ tagsEvent <- useState (joinWith ", " item.tags)
  setValidTags /\ validTagsEvent <- useState (Just true)

  setEffects /\ effectsEvent <- useState (joinWith ", " item.effects)
  setValidEffects /\ validEffectsEvent <- useState (Just true)

  setThc /\ thcEvent <- useState lineage.thc
  setValidThc /\ validThcEvent <- useState (Just true)

  setCbg /\ cbgEvent <- useState lineage.cbg
  setValidCbg /\ validCbgEvent <- useState (Just true)

  setStrain /\ strainEvent <- useState lineage.strain
  setValidStrain /\ validStrainEvent <- useState (Just true)

  setCreator /\ creatorEvent <- useState lineage.creator
  setValidCreator /\ validCreatorEvent <- useState (Just true)

  setSpecies /\ speciesEvent <- useState speciesValue
  setValidSpecies /\ validSpeciesEvent <- useState (Just true)

  setDominantTerpene /\ dominantTerpeneEvent <- useState
    lineage.dominant_terpene
  setValidDominantTerpene /\ validDominantTerpeneEvent <- useState (Just true)

  setTerpenes /\ terpenesEvent <- useState (joinWith ", " lineage.terpenes)
  setValidTerpenes /\ validTerpenesEvent <- useState (Just true)

  setLineage /\ lineageEvent <- useState (joinWith ", " lineage.lineage)
  setValidLineage /\ validLineageEvent <- useState (Just true)

  setLeaflyUrl /\ leaflyUrlEvent <- useState lineage.leafly_url
  setValidLeaflyUrl /\ validLeaflyUrlEvent <- useState (Just true)

  setImg /\ imgEvent <- useState lineage.img
  setValidImg /\ validImgEvent <- useState (Just true)

  let
    customCategoryConfig = categoryConfig
      { defaultValue: categoryValue, forNewItem: false }
  let
    customSpeciesConfig = speciesConfig
      { defaultValue: speciesValue, forNewItem: false }
  let
    isFormValid = ado
      vName <- validNameEvent
      vSku <- validSkuEvent
      vBrand <- validBrandEvent
      vPrice <- validPriceEvent
      vQuantity <- validQuantityEvent
      vSort <- validSortEvent
      vMeasureUnit <- validMeasureUnitEvent
      vPerPackage <- validPerPackageEvent
      vCategory <- validCategoryEvent
      vSubcategory <- validSubcategoryEvent
      vThc <- validThcEvent
      vCbg <- validCbgEvent
      vStrain <- validStrainEvent
      vCreator <- validCreatorEvent
      vSpecies <- validSpeciesEvent
      vDominantTerpene <- validDominantTerpeneEvent
      vLeaflyUrl <- validLeaflyUrlEvent
      vImg <- validImgEvent
      in
        all (fromMaybe false)
          [ vName
          , vSku
          , vBrand
          , vPrice
          , vQuantity
          , vSort
          , vMeasureUnit
          , vPerPackage
          , vCategory
          , vSubcategory
          , vThc
          , vCbg
          , vStrain
          , vCreator
          , vSpecies
          , vDominantTerpene
          , vLeaflyUrl
          , vImg
          ]

  D.div
    [ DA.klass_ "space-y-4 max-w-2xl mx-auto p-6"
    , DL.load_ \_ -> do
        liftEffect $ Console.log $ "EditItem component loaded"
        liftEffect $ Console.log $ "Current category value: " <> categoryValue
        liftEffect $ Console.log $ "Current species value: " <> speciesValue

        liftEffect $ Console.log $ "Description value from backend: '"
          <> item.description
          <> "'"
        liftEffect $ Console.log $ "Description length: " <> show
          (length item.description)

        setCategory categoryValue
        setValidCategory (Just true)

        setSpecies speciesValue
        setValidSpecies (Just true)
    ]
    [ D.h2
        [ DA.klass_ "text-2xl font-bold mb-6" ]
        [ text_ "Edit Menu Item" ]
    , makeTextField (nameConfig item.name) setName setValidName validNameEvent
        false
    , makeTextField (skuConfig (show item.sku)) setSku setValidSku validSkuEvent
        false
    , makeTextField (brandConfig item.brand) setBrand setValidBrand
        validBrandEvent
        false
    , makeTextField (priceConfig (show item.price)) setPrice setValidPrice
        validPriceEvent
        false
    , makeTextField (quantityConfig (show item.quantity)) setQuantity
        setValidQuantity
        validQuantityEvent
        false
    , makeTextField (sortConfig (show item.sort)) setSort setValidSort
        validSortEvent
        false
    , makeTextField (measureUnitConfig item.measure_unit) setMeasureUnit
        setValidMeasureUnit
        validMeasureUnitEvent
        false
    , makeTextField (perPackageConfig item.per_package) setPerPackage
        setValidPerPackage
        validPerPackageEvent
        false
    , makeTextField (subcategoryConfig item.subcategory) setSubcategory
        setValidSubcategory
        validSubcategoryEvent
        false
    , makeDropdown customCategoryConfig setCategory setValidCategory
        validCategoryEvent
    , makeDescriptionField item.description setDescription
        setValidDescription
        validDescriptionEvent
    , makeTextField (tagsConfig (joinWith ", " item.tags)) setTags setValidTags
        validTagsEvent
        false
    , makeTextField (effectsConfig (joinWith ", " item.effects)) setEffects
        setValidEffects
        validEffectsEvent
        false
    , makeTextField (thcConfig lineage.thc) setThc setValidThc validThcEvent
        false
    , makeTextField (cbgConfig lineage.cbg) setCbg setValidCbg validCbgEvent
        false
    , makeTextField (strainConfig lineage.strain) setStrain setValidStrain
        validStrainEvent
        false
    , makeTextField (creatorConfig lineage.creator) setCreator setValidCreator
        validCreatorEvent
        false
    , makeDropdown customSpeciesConfig setSpecies setValidSpecies
        validSpeciesEvent
    , makeTextField (dominantTerpeneConfig lineage.dominant_terpene)
        setDominantTerpene
        setValidDominantTerpene
        validDominantTerpeneEvent
        false
    , makeTextField (terpenesConfig (joinWith ", " lineage.terpenes))
        setTerpenes
        setValidTerpenes
        validTerpenesEvent
        false
    , makeTextField (lineageConfig (joinWith ", " lineage.lineage)) setLineage
        setValidLineage
        validLineageEvent
        false
    , makeTextField (leaflyUrlConfig lineage.leafly_url) setLeaflyUrl
        setValidLeaflyUrl
        validLeaflyUrlEvent
        false
    , makeTextField (imgConfig lineage.img) setImg setValidImg validImgEvent
        false

    , D.button
        [ DA.klass_ "form-button form-button-green"
        , DA.disabled $ map show $ (||) <$> submittingEvent <*> map not
            isFormValid
        , runOn DL.click $
            ( \sort
               name
               sku
               brand
               price
               measureUnit
               perPackage
               quantity
               category
               subcategory
               description
               tags
               effects
               thc
               cbg
               strain
               creator
               species
               dominantTerpene
               terpenes
               lineage
               leaflyUrl
               img -> do

                liftEffect $ Console.log $
                  "Description value before submission: '" <> description <> "'"

                setSubmitting true
                void $ setFiber =<< launchAff do
                  let
                    formInput =
                      { sort: ensureInt sort
                      , name
                      , sku
                      , brand
                      , price: ensureNumber price
                      , measure_unit: measureUnit
                      , per_package: perPackage
                      , quantity: ensureInt quantity
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

                  liftEffect $ Console.group "Form Submission"
                  liftEffect $ Console.log "Form data:"
                  liftEffect $ Console.logShow formInput
                  liftEffect $ Console.log $ "Description in form submission: '"
                    <> description
                    <> "'"

                  case validateMenuItem formInput of
                    Left err -> liftEffect do
                      Console.error "Form validation failed:"
                      Console.errorShow err
                      Console.groupEnd
                      setStatusMessage $ "Validation error: " <> err
                      setSubmitting false

                    Right menuItem -> do
                      liftEffect $ Console.info "Form validated successfully:"
                      liftEffect $ Console.logShow menuItem
                      liftEffect $ Console.log $
                        "Description after validation: '" <> description <> "'"

                      result <- updateInventory menuItem
                      liftEffect case result of
                        Right (Message msg) -> do
                          Console.info "Submission successful"
                          Console.log $ "Description after submission: '"
                            <> description
                            <> "'"
                          setStatusMessage msg
                        Right (InventoryData _) -> do
                          Console.info "Item updated in inventory"
                          Console.log $ "Description after successful update: '"
                            <> description
                            <> "'"
                          setStatusMessage "Item successfully updated!"
                        Left err -> do
                          Console.error "API Error:"
                          Console.errorShow err
                          setStatusMessage $ "Error saving item: " <> err
                      liftEffect $ Console.groupEnd
                      liftEffect $ setSubmitting false
            ) <$> sortEvent
              <*> nameEvent
              <*> skuEvent
              <*> brandEvent
              <*> priceEvent
              <*> measureUnitEvent
              <*> perPackageEvent
              <*> quantityEvent
              <*> categoryEvent
              <*> subcategoryEvent
              <*> descriptionEvent
              <*> tagsEvent
              <*> effectsEvent
              <*> thcEvent
              <*> cbgEvent
              <*> strainEvent
              <*> creatorEvent
              <*> speciesEvent
              <*> dominantTerpeneEvent
              <*> terpenesEvent
              <*> lineageEvent
              <*> leaflyUrlEvent
              <*> imgEvent
        ]
        [ text $ map
            ( \isSubmitting ->
                if isSubmitting then "Submitting..." else "Submit"
            )
            submittingEvent
        ]

    , D.div
        [ DA.klass_ "mt-4 text-center" ]
        [ text statusMessageEvent ]

    -- debug
    -- , D.div
    --     [ DA.klass_ "mt-4 p-4 border rounded bg-gray-50" ]
    --     [ D.h3 [ DA.klass_ "text-lg font-bold" ] [ text_ "Debug Info" ]
    --     , D.div [ DA.klass_ "text-sm" ]
    --         [ D.div_ [ text_ "Current description value: " ]
    --         , D.pre [ DA.klass_ "bg-gray-100 p-2 rounded" ]
    --             [ text descriptionEvent ]
    --         ]
    --     ]
    ]

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