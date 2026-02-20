module Cheeblr.UI.Route where

import Prelude

import Cheeblr.API.Auth (AuthContext)
import Cheeblr.API.Inventory as InventoryAPI
import Cheeblr.UI.Auth.UserSwitcher (userSwitcher)
import Cheeblr.UI.Navigation (Page(..), navBar)
import Cheeblr.UI.Transaction.TransactionPage (transactionPage)
import Cheeblr.Core.Product (Product(..), ProductList(..), ProductResponse(..))
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
import FRP.Poll (Poll)

----------------------------------------------------------------------
-- App Shell
----------------------------------------------------------------------

-- | Top-level application component.
-- | Manages navigation state and renders the current page.
appShell :: Ref AuthContext -> Nut
appShell authRef = Deku.do
  setPage /\ currentPage <- useState InventoryPage
  setInventory /\ inventoryPoll <- useState (ProductList [])
  setStatus /\ statusPoll <- useState ""

  let
    loadInventory = launchAff_ do
      result <- InventoryAPI.read authRef
      liftEffect case result of
        Right (ProductData list) -> setInventory list
        Right (ProductMessage msg) -> setStatus msg
        Left err -> do
          Console.error err
          setStatus ("Failed to load inventory: " <> err)

    onUserSwitch _ = loadInventory

  D.div
    [ DA.klass_ "app-shell"
    -- Load inventory on mount
    , DL.load_ \_ -> loadInventory
    ]
    [ -- Dev toolbar
      D.div
        [ DA.klass_ "dev-toolbar" ]
        [ userSwitcher authRef onUserSwitch ]

    -- Navigation
    , navBar currentPage setPage

    -- Status
    , statusPoll <#~> \msg ->
        if msg == "" then D.span_ []
        else D.div [ DA.klass_ "app-status" ] [ text_ msg ]

    -- Page content (reactive)
    , currentPage <#~> \page ->
        D.div
          [ DA.klass_ "page-content" ]
          [ renderPage authRef page inventoryPoll setPage setStatus ]
    ]

----------------------------------------------------------------------
-- Page Router
----------------------------------------------------------------------

renderPage
  :: Ref AuthContext
  -> Page
  -> Poll ProductList
  -> (Page -> Effect Unit)
  -> (String -> Effect Unit)
  -> Nut
renderPage authRef page inventoryPoll setPage setStatus =
  case page of
    InventoryPage ->
      D.div
        [ DA.klass_ "inventory-page" ]
        [ D.h2_ [ text_ "Inventory" ]
        , D.button
            [ DA.klass_ "btn-primary"
            , DL.click_ \_ -> setPage CreateItemPage
            ]
            [ text_ "Add Product" ]
        , inventoryPoll <#~> \(ProductList items) ->
            D.div
              [ DA.klass_ "inventory-list" ]
              (items <#> \product ->
                inventoryRow product (setPage EditItemPage)
              )
        ]

    CreateItemPage ->
      D.div_
        [ D.h2_ [ text_ "Create Item" ]
        , text_ "TODO: wire mkProductForm CreateMode"
        , D.button
            [ DL.click_ \_ -> setPage InventoryPage ]
            [ text_ "← Back" ]
        ]

    EditItemPage ->
      D.div_
        [ D.h2_ [ text_ "Edit Item" ]
        , text_ "TODO: wire mkProductForm (EditMode product)"
        , D.button
            [ DL.click_ \_ -> setPage InventoryPage ]
            [ text_ "← Back" ]
        ]

    TransactionPage ->
      transactionPage authRef inventoryPoll

    RegisterPage ->
      D.div_
        [ D.h2_ [ text_ "Register Management" ]
        , text_ "TODO: register open/close UI"
        ]

    ReportsPage ->
      D.div_
        [ D.h2_ [ text_ "Reports" ]
        , text_ "TODO: reports UI"
        ]

----------------------------------------------------------------------
-- Inventory Row (simple list item)
----------------------------------------------------------------------

inventoryRow :: Product -> Effect Unit -> Nut
inventoryRow (Product p) onEdit =
  D.div
    [ DA.klass_ "inventory-row"
    , DL.click_ \_ -> onEdit
    ]
    [ D.span [ DA.klass_ "inv-name" ] [ text_ p.name ]
    , D.span [ DA.klass_ "inv-brand" ] [ text_ p.brand ]
    , D.span [ DA.klass_ "inv-qty" ] [ text_ (show p.quantity) ]
    ]
