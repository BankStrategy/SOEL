{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Pipeline
  ( AmbiguityMode(..)
  , CompileOptions(..)
  , RunOptions(..)
  , CheckOptions(..)
  , runCompile
  , runRun
  , runCheck
  , runRepair
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.FilePath (replaceExtension)
import System.IO (stderr)

import Soel.Types (App, SoelError(..))
import Soel.IR.Types
import Soel.IR.Transform (transformToCodeIR)
import Soel.Stages.Reader (readSource)
import Soel.Stages.SemanticEncoder (semanticEncode)
import Soel.Stages.AmbiguityDetector (detectAmbiguities, emitDiagnostics)
import Soel.Stages.Dialog (resolveAmbiguities, autoResolveAll)
import Soel.Stages.Codegen (generateHaskell, CodegenResult(..))
import Soel.Stages.Writer (writeHaskell, writeIR, WriteOptions(..))
import Soel.Stages.GHC (ghcCompile, ghcRun, GHCResult(..))
import Soel.Stages.Repair (repairLoop)
import Soel.Cache.Store (getCached, setCache)
import Soel.Utils.Logger

-- | How to handle semantic ambiguities.
data AmbiguityMode = Strict | Dialog | Lenient
  deriving (Show, Eq)

-- | Options for the compile command.
data CompileOptions = CompileOptions
  { coOutput       :: !(Maybe FilePath)
  , coIrOnly       :: !Bool
  , coAmbiguityMode :: !AmbiguityMode
  } deriving (Show)

-- | Options for the run command.
data RunOptions = RunOptions
  { roAmbiguityMode :: !AmbiguityMode
  } deriving (Show)

-- | Options for the check command.
data CheckOptions = CheckOptions
  deriving (Show)

-- ─── Compile ────────────────────────────────────────────────────────

runCompile :: FilePath -> CompileOptions -> App ()
runCompile filePath CompileOptions{..} = do
  -- Stage 1: Read
  liftIO $ logStage "Reading source"
  source <- readSource filePath

  -- Stage 2: Semantic Encode (with cache)
  let narrativeCacheKey = "narrative-" <> sfName source
  mCachedNarrative <- getCached narrativeCacheKey (sfHash source)
  narrativeIR <- case (mCachedNarrative :: Maybe NarrativeIR) of
    Just nir -> do
      liftIO $ logInfo "Using cached narrative IR"
      pure nir
    Nothing -> do
      nir <- semanticEncode (sfContent source)
      setCache narrativeCacheKey (sfHash source) nir
      pure nir

  -- Stage 2b: Transform to Code IR (with cache)
  let codeCacheKey = "code-" <> sfName source
  mCachedCode <- getCached codeCacheKey (sfHash source)
  codeIR <- case (mCachedCode :: Maybe CodeIR) of
    Just cir -> do
      liftIO $ logInfo "Using cached code IR"
      pure cir
    Nothing -> do
      cir <- transformToCodeIR narrativeIR (sfContent source)
      setCache codeCacheKey (sfHash source) cir
      pure cir

  -- If --ir-only, output the IR and stop
  if coIrOnly
    then do
      let irVal = object
                    [ "narrative" .= narrativeIR
                    , "code"      .= codeIR
                    ]
      _ <- writeIR irVal (sfPath source)
      liftIO $ BL8.putStrLn (encode irVal)
      pure ()
    else do
      -- Stage 3: Detect Ambiguities
      ambResult <- detectAmbiguities narrativeIR codeIR

      -- Stage 4: Resolve based on mode
      resolved <- case coAmbiguityMode of
        Strict -> do
          emitDiagnostics ambResult (sfPath source) (sfContent source)
          -- If we get here, only warnings remain
          pure $ autoResolveAll (arWarnings ambResult)

        Dialog -> do
          -- Print warnings first
          liftIO $ mapM_ (TIO.hPutStr stderr . formatDiagnostic . ambiguityDiag (sfPath source) (sfContent source))
            (arWarnings ambResult)
          resolveAmbiguities (arAll ambResult) (sfContent source)

        Lenient -> do
          let allAmbs = arAll ambResult
          if not (null allAmbs)
            then do
              liftIO $ mapM_ (TIO.hPutStr stderr . formatDiagnostic . ambiguityDiag (sfPath source) (sfContent source))
                allAmbs
              let e = length (arErrors ambResult)
                  w = length (arWarnings ambResult)
              liftIO $ logWarn $ "Auto-resolving " <> T.pack (show e) <> " error(s) and "
                              <> T.pack (show w) <> " warning(s) in lenient mode"
            else pure ()
          pure $ autoResolveAll allAmbs

      -- Stage 5: Generate Haskell
      CodegenResult{..} <- generateHaskell codeIR resolved (sfContent source)

      -- Stage 6: Write
      hsPath <- writeHaskell crHaskellSource WriteOptions
        { woSourcePath = sfPath source
        , woOutputPath = coOutput
        }

      liftIO $ logSuccess $ "Compilation complete: " <> T.pack hsPath

-- ─── Run ────────────────────────────────────────────────────────────

runRun :: FilePath -> RunOptions -> App ()
runRun filePath RunOptions{..} = do
  let hsPath = replaceExtension filePath ".hs"

  runCompile filePath CompileOptions
    { coOutput        = Just hsPath
    , coIrOnly        = False
    , coAmbiguityMode = roAmbiguityMode
    }

  -- Stage 7: GHC compile + run
  result <- ghcCompile hsPath
  ghcRun (grExecutablePath result)

-- ─── Check ──────────────────────────────────────────────────────────

runCheck :: FilePath -> CheckOptions -> App ()
runCheck filePath _ = do
  liftIO $ logStage "Reading source"
  source <- readSource filePath

  narrativeIR <- semanticEncode (sfContent source)
  codeIR <- transformToCodeIR narrativeIR (sfContent source)
  ambResult <- detectAmbiguities narrativeIR codeIR

  if null (arAll ambResult)
    then liftIO $ logSuccess "No semantic issues detected"
    else do
      liftIO $ mapM_ (TIO.hPutStr stderr . formatDiagnostic . ambiguityDiag (sfPath source) (sfContent source))
        (arAll ambResult)

      let e = length (arErrors ambResult)
          w = length (arWarnings ambResult)
      liftIO $ logError $ T.pack (show e) <> " error(s), " <> T.pack (show w) <> " warning(s)"

      if e > 0
        then throwError $ SemanticAmbiguityError $
               T.pack (show e) <> " semantic error(s), " <> T.pack (show w) <> " warning(s)"
        else pure ()

-- ─── Repair ─────────────────────────────────────────────────────────

runRepair :: FilePath -> App ()
runRepair filePath = repairLoop filePath

-- ─── Helpers ────────────────────────────────────────────────────────

-- | Build diagnostic options from an ambiguity.
ambiguityDiag :: FilePath -> Text -> Ambiguity -> DiagnosticOpts
ambiguityDiag fp sourceText amb = DiagnosticOpts
  { diagFile       = fp
  , diagSeverity   = severityText (ambSeverity amb)
  , diagId         = ambId amb
  , diagCategory   = categoryText (ambCategory amb)
  , diagMessage    = ambDescription amb
  , diagSpan       = ambSourceSpan amb
  , diagSourceText = Just sourceText
  , diagOptions    = map (\o -> (aoLabel o, aoConfidence o)) (ambOptions amb)
  }

