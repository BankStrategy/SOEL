{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Stages.Writer
  ( WriteOptions(..)
  , writeHaskell
  , writeIR
  ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value, encode)
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>), takeDirectory, takeBaseName, replaceExtension)

import Soel.Types (App)
import Soel.Utils.Logger (logSuccess)

-- | Options for writing Haskell output.
data WriteOptions = WriteOptions
  { woSourcePath :: !FilePath
  , woOutputPath :: !(Maybe FilePath)
  } deriving (Show)

-- | Write Haskell source to a .hs file. Returns the output path.
writeHaskell :: Text -> WriteOptions -> App FilePath
writeHaskell haskellSource WriteOptions{..} = liftIO $ do
  let outPath = case woOutputPath of
        Just p  -> p
        Nothing -> replaceExtension woSourcePath ".hs"

  createDirectoryIfMissing True (takeDirectory outPath)
  TIO.writeFile outPath (haskellSource <> "\n")

  logSuccess $ "Wrote " <> T.pack outPath
  pure outPath

-- | Write IR JSON to a file. Returns the output path.
writeIR :: Value -> FilePath -> App FilePath
writeIR ir sourcePath = liftIO $ do
  let outPath = replaceExtension sourcePath ".ir.json"

  createDirectoryIfMissing True (takeDirectory outPath)
  BL.writeFile outPath (encode ir)

  logSuccess $ "Wrote " <> T.pack outPath
  pure outPath
