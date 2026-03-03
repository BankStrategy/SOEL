{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Config
  ( SoelConfig(..)
  , OpenRouterConfig(..)
  , HaskellConfig(..)
  , CompilerConfig(..)
  , loadConfig
  , requireApiKey
  , defaultConfig
  ) where

import Control.Monad (filterM)
import Data.Aeson
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BL
import GHC.Generics (Generic)
import System.Directory (doesFileExist, getCurrentDirectory, getHomeDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>), takeDirectory)

import Soel.Utils.Errors (SoelError(..))

-- | OpenRouter API configuration.
data OpenRouterConfig = OpenRouterConfig
  { orApiKey :: !(Maybe Text)
  , orModel  :: !Text
  } deriving (Show, Eq, Generic)

-- | GHC / Haskell toolchain configuration.
data HaskellConfig = HaskellConfig
  { hsGhcPath    :: !FilePath
  , hsGhcFlags   :: ![Text]
  , hsExtensions :: ![Text]
  } deriving (Show, Eq, Generic)

-- | Compiler behavior configuration.
data CompilerConfig = CompilerConfig
  { ccEncoderMode        :: !Text
  , ccAmbiguityThreshold :: !Double
  , ccMaxDialogRounds    :: !Int
  } deriving (Show, Eq, Generic)

-- | Top-level SOEL configuration.
data SoelConfig = SoelConfig
  { cfgOpenRouter :: !OpenRouterConfig
  , cfgHaskell    :: !HaskellConfig
  , cfgCompiler   :: !CompilerConfig
  } deriving (Show, Eq)

-- | Default configuration matching TypeScript defaults.
defaultConfig :: SoelConfig
defaultConfig = SoelConfig
  { cfgOpenRouter = OpenRouterConfig
      { orApiKey = Nothing
      , orModel  = "anthropic/claude-opus-4.6"
      }
  , cfgHaskell = HaskellConfig
      { hsGhcPath    = "ghc"
      , hsGhcFlags   = ["-O2", "-Wall"]
      , hsExtensions = ["OverloadedStrings", "DeriveGeneric"]
      }
  , cfgCompiler = CompilerConfig
      { ccEncoderMode        = "full"
      , ccAmbiguityThreshold = 0.7
      , ccMaxDialogRounds    = 5
      }
  }

-- JSON parsing: we parse the .soelrc format which has different field names

instance FromJSON OpenRouterConfig where
  parseJSON = withObject "OpenRouterConfig" $ \v -> do
    orApiKey <- v .:? "apiKey"
    orModel  <- v .:? "model" .!= "anthropic/claude-opus-4.6"
    pure OpenRouterConfig{..}

instance FromJSON HaskellConfig where
  parseJSON = withObject "HaskellConfig" $ \v -> do
    hsGhcPath    <- v .:? "ghcPath"    .!= "ghc"
    hsGhcFlags   <- v .:? "ghcFlags"   .!= ["-O2", "-Wall"]
    hsExtensions <- v .:? "extensions" .!= ["OverloadedStrings", "DeriveGeneric"]
    pure HaskellConfig{..}

instance FromJSON CompilerConfig where
  parseJSON = withObject "CompilerConfig" $ \v -> do
    ccEncoderMode        <- v .:? "encoderMode"        .!= "full"
    ccAmbiguityThreshold <- v .:? "ambiguityThreshold" .!= 0.7
    ccMaxDialogRounds    <- v .:? "maxDialogRounds"    .!= 5
    pure CompilerConfig{..}

instance FromJSON SoelConfig where
  parseJSON = withObject "SoelConfig" $ \v -> do
    cfgOpenRouter <- v .:? "openrouter" .!= orDefault
    cfgHaskell    <- v .:? "haskell"    .!= hsDefault
    cfgCompiler   <- v .:? "compiler"   .!= ccDefault
    pure SoelConfig{..}
    where
      orDefault = OpenRouterConfig Nothing "anthropic/claude-opus-4.6"
      hsDefault = HaskellConfig "ghc" ["-O2", "-Wall"] ["OverloadedStrings", "DeriveGeneric"]
      ccDefault = CompilerConfig "full" 0.7 5

-- | Load config by walking up from cwd looking for .soelrc or .soelrc.json,
-- then apply env var overrides and ghcup auto-detection.
loadConfig :: Bool -> IO (Either SoelError SoelConfig)
loadConfig fastMode = do
  cwd <- getCurrentDirectory
  mRaw <- findConfigFile cwd
  case mRaw of
    Left err -> pure (Left err)
    Right cfg0 -> do
      -- Env var override for API key
      mEnvKey <- lookupEnv "OPENROUTER_API_KEY"
      let cfg1 = case mEnvKey of
            Just k  -> cfg0 { cfgOpenRouter = (cfgOpenRouter cfg0) { orApiKey = Just (T.pack k) } }
            Nothing -> cfg0

      -- Fast mode override
      let cfg2 = if fastMode
            then cfg1 { cfgCompiler = (cfgCompiler cfg1) { ccEncoderMode = "fast" } }
            else cfg1

      -- Auto-detect ghcup GHC
      cfg3 <- autoDetectGhcup cfg2

      pure (Right cfg3)

-- | Search upward from a directory for .soelrc or .soelrc.json.
findConfigFile :: FilePath -> IO (Either SoelError SoelConfig)
findConfigFile dir = do
  let candidates = [dir </> ".soelrc", dir </> ".soelrc.json"]
  found <- findFirst candidates
  case found of
    Just path -> do
      bs <- BL.readFile path
      case eitherDecode bs of
        Left err -> pure $ Left $ ConfigError $ T.pack $ "Invalid JSON in " <> path <> ": " <> err
        Right cfg -> pure $ Right cfg
    Nothing -> do
      let parent = takeDirectory dir
      if parent == dir
        then pure (Right defaultConfig)  -- Reached filesystem root, use defaults
        else findConfigFile parent

findFirst :: [FilePath] -> IO (Maybe FilePath)
findFirst paths = listToMaybe <$> filterM doesFileExist paths

-- | Auto-detect GHC installed via ghcup.
autoDetectGhcup :: SoelConfig -> IO SoelConfig
autoDetectGhcup cfg = do
  home <- getHomeDirectory
  let ghcupGhc = home </> ".ghcup" </> "bin" </> "ghc"
  exists <- doesFileExist ghcupGhc
  pure $ if exists && hsGhcPath (cfgHaskell cfg) == "ghc"
    then cfg { cfgHaskell = (cfgHaskell cfg) { hsGhcPath = ghcupGhc } }
    else cfg

-- | Require that an API key is configured. Throws ConfigError if missing.
requireApiKey :: SoelConfig -> Either SoelError Text
requireApiKey cfg = case orApiKey (cfgOpenRouter cfg) of
  Just k  -> Right k
  Nothing -> Left $ ConfigError
    "OpenRouter API key required. Set OPENROUTER_API_KEY env var or add to .soelrc"
