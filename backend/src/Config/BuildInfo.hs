{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Config.BuildInfo (
  BuildInfo (..),
  currentBuildInfo,
) where

import Data.Aeson (ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

data BuildInfo = BuildInfo
  { biGitSha :: Text
  , biBuildTime :: Text
  , biVersion :: Text
  }
  deriving (Show, Eq, Generic)

instance ToJSON BuildInfo

-- To embed real values at build time set GIT_SHA / BUILD_TIME as
-- passthruVars in the haskell.nix derivation and splice via gitrev + CPP.
-- "dev" / "unknown" are safe compile-time defaults.
currentBuildInfo :: BuildInfo
currentBuildInfo =
  BuildInfo
    { biGitSha = "dev"
    , biBuildTime = "unknown"
    , biVersion = "0.1.0"
    }
