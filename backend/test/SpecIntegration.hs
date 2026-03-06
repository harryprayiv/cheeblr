module Main (main) where

import Test.Hspec
import Test.Integration.JsonContractSpec (spec)

main :: IO ()
main = hspec spec