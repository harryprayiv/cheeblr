{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Codegen.Run
  ( runCodegen
  , generateAll
  ) where

import Codegen.Schema (DomainSchema(..))
import Codegen.Generate.Common (GeneratedModule(..))
import Codegen.Generate.Types (generateTypesModule)
import Codegen.Generate.Database (generateDbModule)
import Codegen.Generate.API (generateApiModule)
import Codegen.Generate.Server (generateServerModule)

import Control.Monad (forM_)
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)

-- | Generate all modules from a schema
generateAll :: DomainSchema -> [GeneratedModule]
generateAll schema =
  [ generateTypesModule schema
  , generateDbModule schema
  , generateApiModule schema
  , generateServerModule schema
  ]

-- | Run the code generator
runCodegen :: DomainSchema -> IO ()
runCodegen schema = do
  let modules = generateAll schema

  putStrLn "=== Haskell Domain Codegen ==="
  putStrLn $ "Schema: " ++ show (schemaName schema)
  putStrLn $ "Generating " ++ show (length modules) ++ " modules...\n"

  forM_ modules $ \GeneratedModule{..} -> do
    -- Ensure directory exists
    createDirectoryIfMissing True (takeDirectory modulePath)

    -- Write the file
    TIO.writeFile modulePath moduleContent
    putStrLn $ "  ✓ " ++ modulePath

  putStrLn "\n=== Done! ==="
  putStrLn "\nGenerated modules:"
  putStrLn "  - Generated/Types/<Domain>.hs"
  putStrLn "  - Generated/DB/<Domain>.hs"
  putStrLn "  - Generated/API/<Domain>.hs"
  putStrLn "  - Generated/Server/<Domain>.hs"