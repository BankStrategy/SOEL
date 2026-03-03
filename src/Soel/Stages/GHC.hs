{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Soel.Stages.GHC
  ( GHCResult(..)
  , ghcCompile
  , ghcRun
  ) where

import Control.Exception (catch, IOException)
import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import System.Directory (doesFileExist, makeAbsolute, removeFile)
import System.Exit (ExitCode(..))
import System.FilePath (takeBaseName, takeDirectory, (</>), replaceExtension)
import System.IO (stderr, hFlush)
import System.Process.Typed
  ( proc, readProcess, runProcess, setWorkingDir, setStdin, setStdout, setStderr, inherit )

import Soel.Config (SoelConfig(..), HaskellConfig(..))
import Soel.Types (App, SoelError(..))
import Soel.Utils.Logger (logStage, logSuccess, withSpinner, spinnerSuccess, spinnerFail)

-- | Result of GHC compilation.
data GHCResult = GHCResult
  { grExecutablePath :: !FilePath
  , grStdout         :: !Text
  , grStderr         :: !Text
  } deriving (Show)

-- | Compile a .hs file with GHC.
ghcCompile :: FilePath -> App GHCResult
ghcCompile hsPath = do
  cfg <- ask
  let hsCfg = cfgHaskell cfg

  liftIO $ logStage "Compiling with GHC"

  absPath <- liftIO $ makeAbsolute hsPath
  let dir      = takeDirectory absPath
      name     = takeBaseName absPath
      execPath = dir </> name
      ghc      = hsGhcPath hsCfg

  -- Build flags: configured flags + language extensions + output
  let extFlags = map (\ext -> "-X" <> T.unpack ext) (hsExtensions hsCfg)
      allFlags = map T.unpack (hsGhcFlags hsCfg)
              ++ extFlags
              ++ [absPath, "-o", execPath]

  (exitCode, stdoutBs, stderrBs) <- liftIO $
    withSpinner ("Compiling " <> T.pack name <> ".hs...") $
      readProcess
        $ setWorkingDir dir
        $ proc ghc allFlags

  let stdoutText = decodeLBS stdoutBs
      stderrText = decodeLBS stderrBs

  case exitCode of
    ExitFailure code -> do
      liftIO $ spinnerFail "GHC compilation failed"
      throwError $ GHCError
        ("GHC compilation failed for " <> T.pack absPath)
        stderrText
        code
    ExitSuccess -> do
      liftIO $ spinnerSuccess $ "Compiled \x2192 " <> T.pack execPath

      -- Clean up .o and .hi artifacts
      liftIO $ do
        cleanupFile (replaceExtension absPath ".o")
        cleanupFile (replaceExtension absPath ".hi")

      pure GHCResult
        { grExecutablePath = execPath
        , grStdout         = stdoutText
        , grStderr         = stderrText
        }

-- | Run a compiled Haskell executable with inherited stdio.
ghcRun :: FilePath -> App ()
ghcRun execPath = do
  liftIO $ logStage "Running program"
  liftIO $ TIO.hPutStr stderr "\n" >> hFlush stderr

  exitCode <- liftIO $ runProcess
    $ setStdin inherit
    $ setStdout inherit
    $ setStderr inherit
    $ setWorkingDir (takeDirectory execPath)
    $ proc execPath []

  liftIO $ TIO.hPutStr stderr "\n" >> hFlush stderr

  case exitCode of
    ExitSuccess -> liftIO $ logSuccess "Program finished"
    ExitFailure code ->
      throwError $ GHCError
        ("Program exited with code " <> T.pack (show code))
        ""
        code

-- | Decode lazy ByteString to Text (UTF-8, lenient).
decodeLBS :: BL.ByteString -> Text
decodeLBS = TE.decodeUtf8With (\_ _ -> Just '?') . BL.toStrict

-- | Try to remove a file, ignoring errors.
cleanupFile :: FilePath -> IO ()
cleanupFile path = do
  exists <- doesFileExist path
  if exists
    then removeFile path `catch` (\(_ :: IOException) -> pure ())
    else pure ()
