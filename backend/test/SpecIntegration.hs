module Main where

import Test.Hspec

import qualified Test.Integration.JsonContractSpec
import qualified Test.GraphQL.IntegrationSpec

main :: IO ()
main = hspec $ do
  describe "Cheeblr Integration" $ do
    Test.Integration.JsonContractSpec.spec
    Test.GraphQL.IntegrationSpec.spec