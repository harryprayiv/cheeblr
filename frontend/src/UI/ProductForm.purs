module Cheeblr.UI.Inventory.ProductForm where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.Inventory as InventoryAPI
import Cheeblr.Core.Product (Product, ProductResponse)
import Cheeblr.Core.Schema (defaults, extractAll, productSchema)
import Cheeblr.Core.Validation (validateProduct)
import Cheeblr.UI.Form (buildForm, renderForm)
import Data.Either (Either(..))
import Data.Map as Map
import Data.Maybe (fromMaybe)
import Data.Tuple.Nested ((/\))
import Deku.Core (Nut)
import Deku.Do as Deku
import Deku.Hooks (useState)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Effect.Ref as Ref

----------------------------------------------------------------------
-- Form Mode
----------------------------------------------------------------------

data FormMode
  = CreateMode
  | EditMode Product

----------------------------------------------------------------------
-- Component
----------------------------------------------------------------------

-- | The practical entry point. Creates the Ref in Effect,
-- | then builds the form.
mkProductForm
  :: Ref AuthContext
  -> FormMode
  -> (ProductResponse -> Effect Unit)
  -> Effect Nut
mkProductForm authRef mode onSuccess = do
  let
    initialValues = case mode of
      CreateMode -> defaults productSchema
      EditMode product -> extractAll productSchema product

    initMap = Map.fromFoldable $
      initialValues <#> \{ key, value } -> key /\ value

  valuesRef <- Ref.new initMap
  pure $ productFormInner authRef mode onSuccess valuesRef initialValues

-- | Internal: the actual form component with Ref already created.
productFormInner
  :: Ref AuthContext
  -> FormMode
  -> (ProductResponse -> Effect Unit)
  -> Ref (Map.Map String String)
  -> Array { key :: String, value :: String }
  -> Nut
productFormInner authRef mode onSuccess valuesRef initialValues = Deku.do
  setStatus /\ statusPoll <- useState ""

  let
    title = case mode of
      CreateMode -> "Create Product"
      EditMode _ -> "Edit Product"

    submitLabel = case mode of
      CreateMode -> "Create"
      EditMode _ -> "Save Changes"

    handleSubmit :: Map.Map String String -> Effect Unit
    handleSubmit values = do
      setStatus "Submitting..."

      -- Build the form input record from collected values
      let
        get key = fromMaybe "" (Map.lookup key values)

        formInput =
          { sort: get "sort"
          , sku: get "sku"
          , brand: get "brand"
          , name: get "name"
          , price: get "price"
          , measureUnit: get "measureUnit"
          , perPackage: get "perPackage"
          , quantity: get "quantity"
          , category: get "category"
          , subcategory: get "subcategory"
          , description: get "description"
          , tags: get "tags"
          , effects: get "effects"
          , meta:
              { thc: get "meta.thc"
              , cbg: get "meta.cbg"
              , strain: get "meta.strain"
              , creator: get "meta.creator"
              , species: get "meta.species"
              , dominantTerpene: get "meta.dominantTerpene"
              , terpenes: get "meta.terpenes"
              , lineage: get "meta.lineage"
              , leaflyUrl: get "meta.leaflyUrl"
              , img: get "meta.img"
              }
          }

      case validateProduct formInput of
        Left err -> setStatus ("Validation failed: " <> err)
        Right product -> do
          launchAff_ do
            result <- case mode of
              CreateMode -> InventoryAPI.create authRef product
              EditMode _ -> InventoryAPI.update authRef product
            liftEffect case result of
              Right response -> do
                setStatus "Success!"
                onSuccess response
              Left err -> do
                Console.error err
                setStatus ("Error: " <> err)

  buildForm productSchema initialValues valuesRef \formState ->
    renderForm formState
      { title
      , submitLabel
      , onSubmit: handleSubmit
      , statusMessage: statusPoll
      }
