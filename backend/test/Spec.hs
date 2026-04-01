module Main where

import Test.Hspec

import qualified Test.Types.AuthSpec
import qualified Test.Types.TransactionSpec
import qualified Test.Types.InventorySpec
import qualified Test.Auth.SimpleSpec
import qualified Test.API.TransactionSpec
import qualified Test.API.OpenApiSpec
import qualified Test.DB.PureFunctionsSpec
import qualified Test.GraphQL.SchemaSpec
import qualified Test.GraphQL.ResolversSpec
import qualified Test.State.TransactionMachineSpec
import qualified Test.State.RegisterMachineSpec
import qualified Test.Effect.InventoryDbSpec
import qualified Test.Effect.EventEmitterSpec
import qualified Test.Service.TransactionSpec
import qualified Test.Service.RegisterSpec
import qualified Test.Props.JsonRoundtripSpec
import qualified Test.Props.ParseShowSpec
import qualified Test.Props.NegateSpec
import qualified Test.Props.StateMachineSpec

main :: IO ()
main = hspec $ do
  describe "Cheeblr Backend" $ do
    Test.Types.AuthSpec.spec
    Test.Types.TransactionSpec.spec
    Test.Types.InventorySpec.spec
    Test.Auth.SimpleSpec.spec
    Test.API.TransactionSpec.spec
    Test.API.OpenApiSpec.spec
    Test.DB.PureFunctionsSpec.spec
    Test.GraphQL.SchemaSpec.spec
    Test.GraphQL.ResolversSpec.spec
    Test.State.TransactionMachineSpec.spec
    Test.State.RegisterMachineSpec.spec
    Test.Effect.InventoryDbSpec.spec
    Test.Effect.EventEmitterSpec.spec
    Test.Service.TransactionSpec.spec
    Test.Service.RegisterSpec.spec
    Test.Props.JsonRoundtripSpec.spec
    Test.Props.ParseShowSpec.spec
    Test.Props.NegateSpec.spec
    Test.Props.StateMachineSpec.spec