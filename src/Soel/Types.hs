{-# LANGUAGE OverloadedStrings #-}

module Soel.Types
  ( -- * App monad
    App
  , runApp
  , requireApiKeyM
    -- * Re-exports
  , module Soel.Utils.Errors
  , module Soel.Config
  ) where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Reader (ReaderT, runReaderT, asks)
import Data.Text (Text)

import Soel.Config
import Soel.Utils.Errors

-- | The main application monad. Config available via 'ask', errors via 'throwError'.
type App a = ReaderT SoelConfig (ExceptT SoelError IO) a

-- | Run an App action with the given config.
runApp :: SoelConfig -> App a -> IO (Either SoelError a)
runApp cfg = runExceptT . flip runReaderT cfg

-- | Extract the API key from config or throw a 'ConfigError'.
requireApiKeyM :: App Text
requireApiKeyM = do
  mKey <- asks (orApiKey . cfgOpenRouter)
  case mKey of
    Just k  -> pure k
    Nothing -> throwError $ ConfigError
      "OpenRouter API key required. Set OPENROUTER_API_KEY env var or add to .soelrc"
