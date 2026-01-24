module Main where

import Codegen.Run (runCodegen)
import Schemas.Dispensary (dispensarySchema)

main :: IO ()
main = runCodegen dispensarySchema