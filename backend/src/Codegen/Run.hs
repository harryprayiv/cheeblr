{-# LANGUAGE OverloadedStrings #-}

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
import Data.Text (Text)
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

-- | Run codegen and write files to disk
runCodegen :: DomainSchema -> IO ()
runCodegen schema = do
  let modules = generateAll schema
  
  putStrLn "=== Haskell Domain Codegen ==="
  putStrLn $ "Generating " ++ show (length modules) ++ " modules...\n"
  
  forM_ modules $ \GeneratedModule{..} -> do
    -- Create directory if needed
    createDirectoryIfMissing True (takeDirectory modulePath)
    
    -- Write the file
    TIO.writeFile modulePath moduleContent
    putStrLn $ "Generated: " ++ modulePath
  
  putStrLn "\n=== Done! ==="