module Cheeblr.UI.Route where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.Inventory as InventoryAPI
import Cheeblr.Core.Money (formatCurrency)
import Cheeblr.Core.Product (Product(..), ProductList(..), ProductResponse(..))
import Cheeblr.Core.Tag (unTag)
import Cheeblr.UI.Auth.UserSwitcher (userSwitcher)
import Cheeblr.UI.Inventory.ProductForm (FormMode(..), mkProductForm)
import Cheeblr.UI.Navigation (Page(..), navBar)
import Cheeblr.UI.Register.RegisterPage (registerPage)
import Cheeblr.UI.Register.RegisterService as RS
import Cheeblr.UI.Transaction.TransactionPage (transactionPage)
import Data.Either (Either(..))
import Data.Tuple.Nested ((/\))
import Deku.Control (text_)
import Deku.Core (Nut)
import Deku.DOM as D
import Deku.DOM.Attributes as DA
import Deku.DOM.Listeners as DL
import Deku.Do as Deku
import Deku.Hooks (useState, (<#~>))
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Effect.Ref (Ref)
import Effect.Unsafe (unsafePerformEffect)
import FRP.Poll (Poll)
import Types.UUID (UUID(..))

-- | Default location ID for register initialization
defaultLocationId :: UUID
defaultLocationId = UUID "b2bd4b3a-d50f-4c04-90b1-01266735876b"

appShell :: Ref AuthContext -> Nut
appShell authRef =
  let
    registerHandle :: RS.RegisterHandle
    registerHandle = unsafePerformEffect RS.newRegisterHandle
  in
    appShellInner authRef registerHandle

appShellInner :: Ref AuthContext -> RS.RegisterHandle -> Nut
appShellInner authRef registerHandle = Deku.do
  setPage /\ currentPage <- useState InventoryPage
  setInventory /\ inventoryPoll <- useState (ProductList [])
  setStatus /\ statusPoll <- useState ""

  let
    loadInventory :: Effect Unit
    loadInventory = launchAff_ do
      result <- InventoryAPI.read authRef
      liftEffect case result of
        Right (ProductData list) -> setInventory list
        Right (ProductMessage msg) -> setStatus msg
        Left err -> do
          Console.error err
          setStatus ("Failed to load inventory: " <> err)

    initRegister :: Effect Unit
    initRegister =
      RS.initRegister authRef registerHandle defaultLocationId
        (\_ -> Console.log "Register initialized")
        (\err -> Console.error $ "Register init failed: " <> err)

    onUserSwitch _ = loadInventory

  D.div
    [ DA.klass_ "app-shell"
    , DL.load_ \_ -> do
        loadInventory
        initRegister
    ]
    [
      D.div
        [ DA.klass_ "dev-toolbar" ]
        [ userSwitcher authRef onUserSwitch ]

    , navBar currentPage setPage

    , statusPoll <#~> \msg ->
        if msg == "" then D.span_ []
        else D.div [ DA.klass_ "app-status" ] [ text_ msg ]

    , currentPage <#~> \page ->
        D.div
          [ DA.klass_ "page-content" ]
          [ renderPage authRef page inventoryPoll setPage setStatus loadInventory registerHandle ]
    ]

renderPage
  :: Ref AuthContext
  -> Page
  -> Poll ProductList
  -> (Page -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit
  -> RS.RegisterHandle
  -> Nut
renderPage authRef page inventoryPoll setPage setStatus loadInventory registerHandle =
  case page of
    InventoryPage ->
      D.div
        [ DA.klass_ "inventory-page" ]
        [ D.div
            [ DA.klass_ "inventory-header" ]
            [ D.h2_ [ text_ "Inventory" ]
            , D.button
                [ DA.klass_ "btn-primary"
                , DL.click_ \_ -> setPage CreateItemPage
                ]
                [ text_ "Add Product" ]
            ]
        , inventoryPoll <#~> \(ProductList items) ->
            D.div
              [ DA.klass_ "inventory-list" ]
              (items <#> \product ->
                inventoryRow product
                  (\p -> setPage (EditItemPage p))
                  (\p -> setPage (DeleteConfirmPage p))
              )
        ]

    CreateItemPage ->
      D.div
        [ DA.klass_ "create-item-page" ]
        [ D.button
            [ DA.klass_ "btn-back"
            , DL.click_ \_ -> setPage InventoryPage
            ]
            [ text_ "← Back to Inventory" ]
        , unsafePerformEffect $ mkProductForm authRef CreateMode \_ -> do
            loadInventory
            setPage InventoryPage
        ]

    EditItemPage product ->
      D.div
        [ DA.klass_ "edit-item-page" ]
        [ D.button
            [ DA.klass_ "btn-back"
            , DL.click_ \_ -> setPage InventoryPage
            ]
            [ text_ "← Back to Inventory" ]
        , unsafePerformEffect $ mkProductForm authRef (EditMode product) \_ -> do
            loadInventory
            setPage InventoryPage
        ]

    DeleteConfirmPage product@(Product p) ->
      D.div
        [ DA.klass_ "delete-confirm-page" ]
        [ D.h2_ [ text_ "Delete Product" ]
        , D.div
            [ DA.klass_ "delete-confirm-details" ]
            [ D.p_ [ text_ ("Are you sure you want to delete " <> p.name <> "?") ]
            , D.div
                [ DA.klass_ "delete-product-summary" ]
                [ D.span_ [ text_ (p.brand <> " — " <> p.name) ]
                , D.span_ [ text_ (unTag p.category <> " · " <> formatCurrency p.price) ]
                , D.span_ [ text_ (show p.quantity <> " in stock") ]
                ]
            ]
        , D.div
            [ DA.klass_ "delete-confirm-actions" ]
            [ D.button
                [ DA.klass_ "btn-danger"
                , DL.click_ \_ -> do
                    setStatus "Deleting..."
                    launchAff_ do
                      result <- InventoryAPI.remove authRef (show p.sku)
                      liftEffect case result of
                        Right _ -> do
                          setStatus ""
                          loadInventory
                          setPage InventoryPage
                        Left err -> do
                          Console.error err
                          setStatus ("Delete failed: " <> err)
                ]
                [ text_ "Confirm Delete" ]
            , D.button
                [ DA.klass_ "btn-secondary"
                , DL.click_ \_ -> setPage InventoryPage
                ]
                [ text_ "Cancel" ]
            ]
        ]

    TransactionPage ->
      transactionPage authRef inventoryPoll

    RegisterPage ->
      registerPage authRef registerHandle

    ReportsPage ->
      D.div_
        [ D.h2_ [ text_ "Reports" ]
        , text_ "TODO: reports UI"
        ]

inventoryRow :: Product -> (Product -> Effect Unit) -> (Product -> Effect Unit) -> Nut
inventoryRow product@(Product p) onEdit onDelete =
  D.div
    [ DA.klass_ "inventory-row" ]
    [ D.div
        [ DA.klass_ "inv-info"
        , DL.click_ \_ -> onEdit product
        ]
        [ D.span [ DA.klass_ "inv-name" ] [ text_ p.name ]
        , D.span [ DA.klass_ "inv-brand" ] [ text_ p.brand ]
        , D.span [ DA.klass_ "inv-category" ] [ text_ (unTag p.category) ]
        , D.span [ DA.klass_ "inv-qty" ] [ text_ (show p.quantity) ]
        , D.span [ DA.klass_ "inv-price" ] [ text_ (formatCurrency p.price) ]
        ]
    , D.div
        [ DA.klass_ "inv-actions" ]
        [ D.button
            [ DA.klass_ "btn-edit"
            , DL.click_ \_ -> onEdit product
            ]
            [ text_ "Edit" ]
        , D.button
            [ DA.klass_ "btn-delete"
            , DL.click_ \_ -> onDelete product
            ]
            [ text_ "Delete" ]
        ]
    ]