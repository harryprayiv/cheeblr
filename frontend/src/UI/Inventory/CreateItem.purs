module CreateItem where

import Prelude

import API.Inventory (writeInventory)
import Config.InventoryFields (brandConfig, categoryConfig, cbgConfig, creatorConfig, dominantTerpeneConfig, effectsConfig, imgConfig, leaflyUrlConfig, lineageConfig, measureUnitConfig, nameConfig, perPackageConfig, priceConfig, quantityConfig, skuConfig, sortConfig, speciesConfig, strainConfig, subcategoryConfig, tagsConfig, terpenesConfig, thcConfig)
import Data.Array (all, null)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple.Nested ((/\))
import Deku.Control (text, text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect.Aff (launchAff)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Services.AuthService (AuthContext)
import Types.Inventory (InventoryResponse(..))
import Components.Form (makeDescriptionField, makeDropdown, makeTextField)
import Utils.Formatting (ensureInt, ensureNumber)
import Utils.UUIDGen (genUUID)
import Utils.Validation (validateMenuItem)

createItem :: Ref AuthContext -> String -> Nut
createItem authRef initialUUID = Deku.do

  setSku /\ skuValue <- useState initialUUID
  setName /\ nameValue <- useState ""
  setBrand /\ brandValue <- useState ""
  setPrice /\ priceValue <- useState ""
  setQuantity /\ quantityValue <- useState ""
  setCategory /\ categoryValue <- useState ""
  setDescription /\ descriptionValue <- useState ""
  setTags /\ tagsValue <- useState ""
  setEffects /\ effectsValue <- useState ""
  setThc /\ thcValue <- useState ""
  setCbg /\ cbgValue <- useState ""
  setStrain /\ strainValue <- useState ""
  setCreator /\ creatorValue <- useState ""
  setSpecies /\ speciesValue <- useState ""
  setDominantTerpene /\ dominantTerpeneValue <- useState ""
  setTerpenes /\ terpenesValue <- useState ""
  setLineage /\ lineageValue <- useState ""
  setSort /\ sortValue <- useState ""
  setMeasureUnit /\ measureUnitValue <- useState ""
  setPerPackage /\ perPackageValue <- useState ""
  setSubcategory /\ subcategoryValue <- useState ""
  setLeaflyUrl /\ leaflyUrlValue <- useState ""
  setImg /\ imgValue <- useState ""

  setValidName /\ validNameEvent <- useState (Just false)
  setValidSku /\ validSkuEvent <- useState (Just true)
  setValidBrand /\ validBrandEvent <- useState (Just false)
  setValidPrice /\ validPriceEvent <- useState (Just false)
  setValidQuantity /\ validQuantityEvent <- useState (Just false)
  setValidCategory /\ validCategoryEvent <- useState (Just false)
  setValidThc /\ validThcEvent <- useState (Just false)
  setValidCbg /\ validCbgEvent <- useState (Just false)
  setValidStrain /\ validStrainEvent <- useState (Just false)
  setValidCreator /\ validCreatorEvent <- useState (Just false)
  setValidSpecies /\ validSpeciesEvent <- useState (Just false)
  setValidDominantTerpene /\ validDominantTerpeneEvent <- useState (Just false)
  setValidTerpenes /\ validTerpenesEvent <- useState (Just true)
  setValidLineage /\ validLineageEvent <- useState (Just true)
  setValidSort /\ validSortEvent <- useState (Just false)
  setValidMeasureUnit /\ validMeasureUnitEvent <- useState (Just false)
  setValidPerPackage /\ validPerPackageEvent <- useState (Just false)
  setValidSubcategory /\ validSubcategoryEvent <- useState (Just false)
  setValidLeaflyUrl /\ validLeaflyUrlEvent <- useState (Just false)
  setValidImg /\ validImgEvent <- useState (Just false)
  setValidDescription /\ validDescriptionEvent <- useState (Just true)
  setValidTags /\ validTagsEvent <- useState (Just true)
  setValidEffects /\ validEffectsEvent <- useState (Just true)

  setStatusMessage /\ statusMessageEvent <- useState ""
  setSubmitting /\ submittingEvent <- useState false
  setErrors /\ errorsValue <- useState []
  setFiber /\ _ <- useState (pure unit)

  let
    isFormValid = ado
      vName <- validNameEvent
      vSku <- validSkuEvent
      vBrand <- validBrandEvent
      vPrice <- validPriceEvent
      vQuantity <- validQuantityEvent
      vCategory <- validCategoryEvent
      vThc <- validThcEvent
      vCbg <- validCbgEvent
      vStrain <- validStrainEvent
      vCreator <- validCreatorEvent
      vSpecies <- validSpeciesEvent
      vDominantTerpene <- validDominantTerpeneEvent
      vSort <- validSortEvent
      vMeasureUnit <- validMeasureUnitEvent
      vPerPackage <- validPerPackageEvent
      vSubcategory <- validSubcategoryEvent
      vLeaflyUrl <- validLeaflyUrlEvent
      vImg <- validImgEvent
      vDescription <- validDescriptionEvent
      vTags <- validTagsEvent
      vEffects <- validEffectsEvent
      vTerpenes <- validTerpenesEvent
      vLineage <- validLineageEvent
      in
        all (fromMaybe false)
          [ vName
          , vSku
          , vBrand
          , vPrice
          , vQuantity
          , vCategory
          , vThc
          , vCbg
          , vStrain
          , vCreator
          , vSpecies
          , vDominantTerpene
          , vSort
          , vMeasureUnit
          , vPerPackage
          , vSubcategory
          , vLeaflyUrl
          , vImg
          , vDescription
          , vTags
          , vEffects
          , vTerpenes
          , vLineage
          ]

  let
    resetForm = do
      newUUID <- genUUID
      setSku (show newUUID)
      setValidSku (Just true)
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
      setDescription ""
      setValidDescription (Just true)
      setTags ""
      setValidTags (Just true)
      setEffects ""
      setValidEffects (Just true)
      setThc ""
      setValidThc (Just false)
      setCbg ""
      setValidCbg (Just false)
      setStrain ""
      setValidStrain (Just false)
      setCreator ""
      setValidCreator (Just false)
      setSpecies ""
      setValidSpecies (Just false)
      setDominantTerpene ""
      setValidDominantTerpene (Just false)
      setTerpenes ""
      setValidTerpenes (Just true)
      setLineage ""
      setValidLineage (Just true)
      setSort ""
      setValidSort (Just false)
      setMeasureUnit ""
      setValidMeasureUnit (Just false)
      setPerPackage ""
      setValidPerPackage (Just false)
      setSubcategory ""
      setValidSubcategory (Just false)
      setLeaflyUrl ""
      setValidLeaflyUrl (Just false)
      setImg ""
      setValidImg (Just false)
      setStatusMessage "Form reset successfully"
      setErrors []

  D.div_
    [ D.div
        [ DA.klass_ "component-loading-debug"
        , DL.load_ \_ -> do
            liftEffect $ Console.log "CreateItem component loading"
            liftEffect $ Console.log $ "Using initialUUID: " <> initialUUID
            setCategory ""
            setValidCategory (Just false)
            setSpecies ""
            setValidSpecies (Just false)

            liftEffect $ Console.log "Forcing initialization of dropdown values"
        ]
        []

    , D.div
        [ DA.klass_ "space-y-4 max-w-2xl mx-auto p-6" ]
        [ D.h2
            [ DA.klass_ "text-2xl font-bold mb-6" ]
            [ text_ "Add New Menu Item" ]

        , D.div
            [ DA.klass_ "error-container mb-4" ]
            [ errorsValue <#~> \errs ->
                if null errs then
                  D.span [] []
                else
                  D.ul
                    [ DA.klass_ "text-red-500 text-sm bg-red-50 p-4 rounded" ]
                    (map (\err -> D.li_ [ text_ err ]) errs)
            ]
        , makeTextField (brandConfig "") setBrand setValidBrand validBrandEvent
            false
        , makeTextField (nameConfig "") setName setValidName validNameEvent
            false
        , makeTextField (skuConfig initialUUID) setSku setValidSku validSkuEvent
            false
        , makeTextField (sortConfig "") setSort setValidSort validSortEvent
            false
        , makeTextField (priceConfig "") setPrice setValidPrice validPriceEvent
            false
        , makeTextField (quantityConfig "") setQuantity setValidQuantity
            validQuantityEvent
            false
        , makeTextField (perPackageConfig "") setPerPackage setValidPerPackage
            validPerPackageEvent
            false
        , makeTextField (measureUnitConfig "") setMeasureUnit
            setValidMeasureUnit
            validMeasureUnitEvent
            false
        , makeTextField (subcategoryConfig "") setSubcategory
            setValidSubcategory
            validSubcategoryEvent
            false
        , makeDropdown
            (categoryConfig { defaultValue: "", forNewItem: false })
            setCategory
            setValidCategory
            validCategoryEvent
        , makeDescriptionField "" setDescription
            setValidDescription
            validDescriptionEvent
        , makeTextField (tagsConfig "") setTags setValidTags validTagsEvent
            false
        , makeTextField (effectsConfig "") setEffects setValidEffects
            validEffectsEvent
            false
        , makeTextField (thcConfig "") setThc setValidThc validThcEvent false
        , makeTextField (cbgConfig "") setCbg setValidCbg validCbgEvent false
        , makeDropdown
            (speciesConfig { defaultValue: "", forNewItem: false })
            setSpecies
            setValidSpecies
            validSpeciesEvent
        , makeTextField (strainConfig "") setStrain setValidStrain
            validStrainEvent
            false
        , makeTextField (dominantTerpeneConfig "") setDominantTerpene
            setValidDominantTerpene
            validDominantTerpeneEvent
            false
        , makeTextField (terpenesConfig "") setTerpenes setValidTerpenes
            validTerpenesEvent
            false
        , makeTextField (lineageConfig "") setLineage setValidLineage
            validLineageEvent
            false
        , makeTextField (creatorConfig "") setCreator setValidCreator
            validCreatorEvent
            false
        , makeTextField (leaflyUrlConfig "") setLeaflyUrl setValidLeaflyUrl
            validLeaflyUrlEvent
            false
        , makeTextField (imgConfig "") setImg setValidImg validImgEvent false
        ]
    , D.button
        [ DA.klass_ "form-button form-button-green"
        , DA.disabled $ map show $ (||) <$> submittingEvent <*> map not
            isFormValid
        , DL.runOn DL.click $
            ( { sort: _
              , name: _
              , sku: _
              , brand: _
              , price: _
              , measureUnit: _
              , perPackage: _
              , quantity: _
              , category: _
              , subcategory: _
              , description: _
              , tags: _
              , effects: _
              , thc: _
              , cbg: _
              , strain: _
              , creator: _
              , species: _
              , dominantTerpene: _
              , terpenes: _
              , lineage: _
              , leaflyUrl: _
              , img: _
              }
                <$> sortValue
                <*> nameValue
                <*> skuValue
                <*> brandValue
                <*> priceValue
                <*> measureUnitValue
                <*> perPackageValue
                <*> quantityValue
                <*> categoryValue
                <*> subcategoryValue
                <*> descriptionValue
                <*> tagsValue
                <*> effectsValue
                <*> thcValue
                <*> cbgValue
                <*> strainValue
                <*> creatorValue
                <*> speciesValue
                <*> dominantTerpeneValue
                <*> terpenesValue
                <*> lineageValue
                <*> leaflyUrlValue
                <*> imgValue
            ) <#> \values -> do
              setSubmitting true
              setErrors []
              setStatusMessage "Processing form submission..."

              -- debug for description field specifically
              liftEffect $ Console.log $ "Description before submission: '"
                <> values.description
                <> "'"

              void $ setFiber =<< launchAff do
                let
                  formInput =
                    { sort: ensureInt values.sort
                    , name: values.name
                    , sku: values.sku
                    , brand: values.brand
                    , price: ensureNumber values.price
                    , measure_unit: values.measureUnit
                    , per_package: values.perPackage
                    , quantity: ensureInt values.quantity
                    , category: values.category
                    , subcategory: values.subcategory
                    , description: values.description
                    , tags: values.tags
                    , effects: values.effects
                    , strain_lineage:
                        { thc: values.thc
                        , cbg: values.cbg
                        , strain: values.strain
                        , creator: values.creator
                        , species: values.species
                        , dominant_terpene: values.dominantTerpene
                        , terpenes: values.terpenes
                        , lineage: values.lineage
                        , leafly_url: values.leaflyUrl
                        , img: values.img
                        }
                    }

                liftEffect $ Console.group "Form Submission"
                liftEffect $ Console.log "Form data:"
                liftEffect $ Console.logShow formInput

                case validateMenuItem formInput of
                  Left err -> liftEffect do
                    Console.error "Form validation failed:"
                    Console.errorShow err
                    Console.groupEnd
                    setStatusMessage $ "Validation error: " <> err
                    setSubmitting false
                    setErrors [ err ]

                  Right menuItem -> do
                    liftEffect $ Console.info "Form validated successfully:"
                    liftEffect $ Console.logShow menuItem
                    result <- writeInventory authRef menuItem
                    liftEffect case result of
                      Right (Message msg) -> do
                        Console.info "Submission successful"
                        setStatusMessage msg
                        resetForm
                      Right (InventoryData _) -> do
                        Console.info "Item added to inventory"
                        setStatusMessage "Item successfully added to inventory!"
                        resetForm
                      Left err -> do
                        Console.error "API Error:"
                        Console.errorShow err
                        setStatusMessage $ "Error saving item: " <> err
                        setErrors [ err ]

                    liftEffect $ Console.groupEnd
                    liftEffect $ setSubmitting false
        ]
        [ text $ map
            ( \isSubmitting ->
                if isSubmitting then "Submitting..." else "Submit"
            )
            submittingEvent
        ]

    , D.div
        [ DA.klass_ "mt-8 p-4 border rounded bg-gray-50" ]
        [ D.h3
            [ DA.klass_ "text-lg font-semibold mb-2" ]
            [ text_ "Debug Information" ]
        , D.div
            [ DA.klass_ "debug-status mb-2 text-sm" ]
            [ D.strong_ [ text_ "Status: " ]
            , text statusMessageEvent
            ]
        , D.div
            [ DA.klass_ "debug-form-state mb-2 text-sm" ]
            [ D.strong_ [ text_ "Form valid: " ]
            , text $ map show isFormValid
            ]
        ]
    ]