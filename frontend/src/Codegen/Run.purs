module Codegen.Run where

import Prelude
import Codegen.Main (runCodegen)
import Effect (Effect)
import Schemas.Dispensary (dispensarySchema)

main :: Effect Unit
main = runCodegen dispensarySchema