module Codegen.Main where

import Prelude

import Codegen.Generate (generateAll)
import Codegen.Schema (DomainSchema)
import Data.Array (length)
import Data.Traversable (for_)
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Class.Console as Console
import Node.Encoding (Encoding(..))
import Node.FS.Aff (mkdir', writeTextFile)
import Node.FS.Perms (mkPerms, all)
import Node.Path as Path

runCodegen :: DomainSchema -> Effect Unit
runCodegen schema = launchAff_ do
  let modules = generateAll schema
  
  for_ modules \mod -> do
    let dir = Path.dirname mod.path
    mkdir' dir { recursive: true, mode: mkPerms all all all }
    writeTextFile UTF8 mod.path mod.content
    liftEffect $ Console.log $ "Generated: " <> mod.path
  
  liftEffect $ Console.log $ "Done! Generated " <> show (length modules) <> " modules."