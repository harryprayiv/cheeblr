module Main where

import Test.Hspec

import qualified Test.Types.AuthSpec
import qualified Test.Types.TransactionSpec
import qualified Test.Types.InventorySpec
import qualified Test.Auth.SimpleSpec
import qualified Test.API.TransactionSpec
import qualified Test.DB.PureFunctionsSpec
import qualified Test.GraphQL.SchemaSpec
import qualified Test.GraphQL.ResolversSpec
import qualified Test.State.TransactionMachineSpec
import qualified Test.State.RegisterMachineSpec

main :: IO ()
main = hspec $ do
  describe "Cheeblr Backend" $ do
    Test.Types.AuthSpec.spec
    Test.Types.TransactionSpec.spec
    Test.Types.InventorySpec.spec
    Test.Auth.SimpleSpec.spec
    Test.API.TransactionSpec.spec
    Test.DB.PureFunctionsSpec.spec
    Test.GraphQL.SchemaSpec.spec
    Test.GraphQL.ResolversSpec.spec
    Test.State.TransactionMachineSpec.spec
    Test.State.RegisterMachineSpec.spec