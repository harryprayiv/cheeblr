module Main (main) where

import Test.Hspec
import qualified Test.Integration.JsonContractSpec

main :: IO ()
main = hspec $ do
  Test.Integration.JsonContractSpec.spec