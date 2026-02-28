module UI.Inventory.DeleteItem where

import Prelude

import API.Inventory (deleteInventory)
import Data.Either (Either(..))
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
import Services.AuthService (UserId)
import Types.Inventory (InventoryResponse(..))

deleteItem :: UserId -> String -> String -> Nut
deleteItem userId itemId itemName = Deku.do
  setStatusMessage /\ statusMessageEvent <- useState ""
  setSubmitting /\ submittingEvent <- useState false
  setSuccess /\ successEvent <- useState false
  setFiber /\ _ <- useState (pure unit)

  D.div
    [ DA.klass_ "space-y-4 max-w-2xl mx-auto p-6" ]
    [ D.h2
        [ DA.klass_ "text-2xl font-bold mb-6" ]
        [ text_ "Delete Menu Item" ]

    , D.div
        [ DA.klass_ "bg-red-50 p-4 rounded mb-4" ]
        [ D.p
            [ DA.klass_ "text-red-700 font-medium" ]
            [ text_ "Warning: This action cannot be undone." ]
        , D.p
            [ DA.klass_ "text-red-600 mt-2" ]
            [ text_ $ "Are you sure you want to delete '" <> itemName <> "'?" ]
        ]

    , D.div
        [ DA.klass_ "flex space-x-4" ]
        [ D.button
            [ DA.klass_ "form-button form-button-red"
            , DA.disabled $ map show submittingEvent
            , DL.click_ \_ -> do
                setSubmitting true
                void $ setFiber =<< launchAff do
                  result <- deleteInventory userId itemId
                  liftEffect $ case result of
                    Right (Message msg) -> do
                      Console.log $ "Deletion successful: " <> msg
                      setStatusMessage msg
                      setSuccess true
                      setSubmitting false
                    Right (InventoryData _) -> do
                      Console.log "Item deleted successfully"
                      setStatusMessage "Item successfully deleted!"
                      setSuccess true
                      setSubmitting false
                    Left err -> do
                      Console.error $ "Failed to delete item: " <> err
                      setStatusMessage $ "Error: " <> err
                      setSubmitting false
            ]
            [ text $ map
                ( \isSubmitting ->
                    if isSubmitting then "Deleting..." else "Confirm Delete"
                )
                submittingEvent
            ]
        , D.a
            [ DA.klass_ $
                "inline-flex items-center rounded-md border border-gray-300 px-3 py-2 text-sm font-medium leading-4 text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
            , DA.href_ "/#/"
            ]
            [ text_ "Cancel" ]
        ]

    , D.div
        [ DA.klass_ "mt-4" ]
        [ successEvent <#~> \success ->
            if success then
              D.div
                [ DA.klass_ "bg-green-50 p-4 rounded" ]
                [ D.p
                    [ DA.klass_ "text-green-700" ]
                    [ text statusMessageEvent ]
                , D.p
                    [ DA.klass_ "mt-2" ]
                    [ D.a
                        [ DA.klass_ "text-green-600 underline"
                        , DA.href_ "/#/"
                        ]
                        [ text_ "Return to Inventory" ]
                    ]
                ]
            else
              D.div
                [ DA.klass_ "text-red-600" ]
                [ text statusMessageEvent ]
        ]
    ]

renderDeleteConfirmation :: UserId -> String -> String -> Nut
renderDeleteConfirmation userId itemId itemName =
  deleteItem userId itemId itemName