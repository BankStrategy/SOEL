{-# LANGUAGE OverloadedStrings #-}

module Soel.Stages.Reader
  ( readSource
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Numeric (showHex)
import System.Directory (makeAbsolute)
import System.FilePath (takeBaseName, takeExtension)

import Soel.IR.Types (SourceFile(..))
import Soel.Types (App, SoelError(..))
import Soel.Utils.Logger (logDebug)

-- | Read a .soel source file, validate it, and compute its SHA256 hash.
readSource :: FilePath -> App SourceFile
readSource filePath = do
  absPath <- liftIO $ makeAbsolute filePath

  -- Validate extension
  let ext = takeExtension absPath
  if ext /= ".soel"
    then throwError $ ConfigError $ "Expected .soel file, got: " <> T.pack ext
    else pure ()

  -- Read file
  content <- liftIO $ do
    bs <- BS.readFile absPath
    pure (TE.decodeUtf8 bs)

  -- Validate non-empty
  if T.null (T.strip content)
    then throwError $ ConfigError "Source file is empty"
    else pure ()

  -- Compute SHA256 hash (zero-padded hex)
  let hashBytes = SHA256.hash (TE.encodeUtf8 content)
      hashHex   = T.pack $ BS.unpack hashBytes >>= \b ->
        let h = showHex b "" in replicate (2 - length h) '0' ++ h
      name      = T.pack (takeBaseName absPath)

  liftIO $ logDebug $
    "Read " <> T.pack absPath <> " (" <> T.pack (show (T.length content))
    <> " chars, hash: " <> T.take 12 hashHex <> "...)"

  pure SourceFile
    { sfPath    = absPath
    , sfName    = name
    , sfContent = content
    , sfHash    = hashHex
    }
