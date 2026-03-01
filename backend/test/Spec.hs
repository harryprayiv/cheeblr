module Main where

import Test.Hspec

import qualified Test.Types.AuthSpec
import qualified Test.Types.TransactionSpec
import qualified Test.Types.InventorySpec
import qualified Test.Auth.SimpleSpec
import qualified Test.API.TransactionSpec
import qualified Test.DB.PureFunctionsSpec

main :: IO ()
main = hspec $ do
  describe "Cheeblr Backend" $ do
    Test.Types.AuthSpec.spec
    Test.Types.TransactionSpec.spec
    Test.Types.InventorySpec.spec
    Test.Auth.SimpleSpec.spec
    Test.API.TransactionSpec.spec
    Test.DB.PureFunctionsSpec.spec