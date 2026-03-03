{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Stages.Repair
  ( repairLoop
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Aeson ((.:), (.:?), withObject, eitherDecode)
import qualified Data.Aeson as Aeson
import Data.Aeson.Types (parseEither)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import System.Console.ANSI (SGR(..), Color(..), ColorIntensity(..), ConsoleLayer(..))
import System.Console.Haskeline (InputT, runInputT, defaultSettings, getInputLine)
import System.FilePath (replaceExtension)

import Soel.Types (App, SoelError(..), SoelConfig(..), runApp, requireApiKeyM)
import Soel.Config (OpenRouterConfig(..))
import Soel.IR.Types (SourceFile(..), CodeIR, AmbiguityResult(..))
import Soel.IR.Transform (transformToCodeIR)
import Soel.Stages.Reader (readSource)
import Soel.Stages.SemanticEncoder (semanticEncode)
import Soel.Stages.AmbiguityDetector (detectAmbiguities)
import Soel.Stages.Dialog (autoResolveAll)
import Soel.Stages.Codegen (generateHaskell, CodegenResult(..))
import Soel.Stages.Writer (writeHaskell, WriteOptions(..))
import Soel.Stages.GHC (ghcCompile, ghcRun, GHCResult(..))
import Soel.LLM.OpenRouter
  ( llmRequest, extractJSON
  , LLMRequestOptions(..), LLMMessage(..), LLMRole(..) )
import Soel.LLM.Prompts (getPrompt)
import Soel.Utils.Logger
  ( logStage, logInfo, logSuccess, logWarn, logError
  , spinnerSuccess, spinnerFail, coloredStderr )

--------------------------------------------------------------------------------
-- Repair result from LLM
--------------------------------------------------------------------------------

data RepairResult = RepairResult
  { rrDiagnosis      :: !Text
  , rrRootCause      :: !Text
  , rrFixType        :: !Text
  , rrFixedCode      :: !Text
  , rrExplanation    :: !Text
  , rrSoelSuggestion :: !(Maybe Text)
  } deriving (Show)

parseRepairResult :: Text -> Either String RepairResult
parseRepairResult txt =
  case eitherDecode (TLE.encodeUtf8 (TL.fromStrict txt)) of
    Left err  -> Left err
    Right val -> parseEither parser val
  where
    parser = withObject "RepairResult" $ \v -> do
      rrDiagnosis      <- v .:  "diagnosis"
      rrRootCause      <- v .:  "root_cause"
      rrFixType        <- v .:  "fix_type"
      rrFixedCode      <- v .:  "fixed_code"
      rrExplanation    <- v .:  "explanation"
      rrSoelSuggestion <- v .:? "soel_suggestion"
      pure RepairResult{..}

--------------------------------------------------------------------------------
-- Main entry point
--------------------------------------------------------------------------------

-- | Interactive repair loop: compiles a .soel file, then iteratively fixes
-- GHC errors by consulting the LLM. Up to 5 rounds.
repairLoop :: FilePath -> App ()
repairLoop filePath = do
  cfg <- ask
  liftIO $ logStage "Pragmatic repair mode"

  -- Step 1: Read source
  source <- readSource filePath
  let hsPath = replaceExtension (sfPath source) ".hs"

  liftIO $ coloredStderr [SetColor Foreground Dull White] "\n  Performing initial compilation..."

  -- Step 2: Full compile pipeline
  narrativeIR <- semanticEncode (sfContent source)
  codeIR      <- transformToCodeIR narrativeIR (sfContent source)
  ambResult   <- detectAmbiguities narrativeIR codeIR
  let resolved = autoResolveAll (arAll ambResult)
  CodegenResult{..} <- generateHaskell codeIR resolved (sfContent source)

  _ <- writeHaskell crHaskellSource WriteOptions
    { woSourcePath = sfPath source
    , woOutputPath = Just hsPath
    }

  -- Step 3: Enter interactive repair loop (runs in Haskeline for readline)
  liftIO $ runInputT defaultSettings $
    repairRounds cfg source codeIR hsPath crHaskellSource 1 maxRounds
  where
    maxRounds :: Int
    maxRounds = 5

--------------------------------------------------------------------------------
-- Repair rounds (runs inside Haskeline's InputT IO)
--------------------------------------------------------------------------------

repairRounds
  :: SoelConfig
  -> SourceFile
  -> CodeIR
  -> FilePath       -- ^ .hs output path
  -> Text           -- ^ current Haskell source
  -> Int            -- ^ current round (1-based)
  -> Int            -- ^ max rounds
  -> InputT IO ()
repairRounds cfg source codeIR hsPath haskellSrc rnd maxR
  | rnd > maxR = liftIO $ logWarn $
      "Max repair rounds (" <> T.pack (show maxR) <> ") reached"
  | otherwise = do
      liftIO $ coloredStderr [SetColor Foreground Vivid Cyan] $
        "\n\x2500\x2500\x2500 Repair round "
        <> T.pack (show rnd) <> "/" <> T.pack (show maxR)
        <> " \x2500\x2500\x2500"

      -- Try ghcCompile + ghcRun
      compileResult <- liftIO $ runApp cfg $ do
        result <- ghcCompile hsPath
        ghcRun (grExecutablePath result)

      case compileResult of
        Right () ->
          liftIO $ logSuccess "Program compiled and ran successfully!"

        Left (GHCError _msg ghcStderr _exitCode) -> do
          -- Show the GHC error
          liftIO $ do
            coloredStderr [SetColor Foreground Vivid Red] "\n  GHC Error:"
            coloredStderr [SetColor Foreground Dull White] $
              T.unlines $ map ("    " <>) (T.lines ghcStderr)

          -- Ask LLM to diagnose and fix
          repairResult <- liftIO $ runApp cfg $
            repairWithLLM source codeIR haskellSrc ghcStderr

          case repairResult of
            Left err -> do
              liftIO $ do
                spinnerFail "Repair analysis failed"
                logError $ T.pack (show err)
              repairRounds cfg source codeIR hsPath haskellSrc (rnd + 1) maxR

            Right repair -> do
              liftIO $ do
                spinnerSuccess "Fix generated"
                coloredStderr [SetColor Foreground Vivid Yellow] $
                  "\n  Diagnosis: " <> rrDiagnosis repair
                coloredStderr [SetColor Foreground Vivid White] $
                  "  Fix: " <> rrExplanation repair
                case rrSoelSuggestion repair of
                  Just sug -> coloredStderr [SetColor Foreground Dull White] $
                    "\n  SOEL suggestion: " <> sug
                  Nothing  -> pure ()

              -- Prompt user
              mAnswer <- getInputLine "\n  Apply fix? [Y/n] "
              let answer = T.strip $ T.pack $ maybe "" id mAnswer

              if T.toLower answer == "n"
                then do
                  liftIO $ logInfo "Fix skipped"
                  mCustom <- getInputLine
                    "  Describe the issue or press Enter to retry: "
                  case mCustom of
                    Just c | not (T.null (T.strip (T.pack c))) ->
                      liftIO $ coloredStderr [SetColor Foreground Dull White] $
                        "  Will incorporate: \"" <> T.pack c <> "\""
                    _ -> pure ()
                  repairRounds cfg source codeIR hsPath haskellSrc (rnd + 1) maxR
                else do
                  let newSrc = rrFixedCode repair
                  _ <- liftIO $ runApp cfg $
                    writeHaskell newSrc WriteOptions
                      { woSourcePath = sfPath source
                      , woOutputPath = Just hsPath
                      }
                  liftIO $ logInfo "Fix applied, retrying..."
                  repairRounds cfg source codeIR hsPath newSrc (rnd + 1) maxR

        Left otherErr -> do
          -- Non-GHC error
          liftIO $ logError $ "Unexpected error: " <> T.pack (show otherErr)

--------------------------------------------------------------------------------
-- LLM repair call
--------------------------------------------------------------------------------

repairWithLLM :: SourceFile -> CodeIR -> Text -> Text -> App RepairResult
repairWithLLM source codeIR haskellSrc ghcStderr = do
  cfg <- ask
  apiKey <- requireApiKeyM

  let systemPrompt = getPrompt "pragmatic-repair"
      userPayload  = Aeson.encode $ Aeson.object
        [ ("soel_source",  Aeson.String (sfContent source))
        , ("haskell_code", Aeson.String haskellSrc)
        , ("ghc_error",    Aeson.String ghcStderr)
        , ("code_ir",      Aeson.toJSON codeIR)
        ]

  raw <- llmRequest LLMRequestOptions
    { lroApiKey      = apiKey
    , lroModel       = orModel (cfgOpenRouter cfg)
    , lroMessages    =
        [ LLMMessage RoleSystem systemPrompt
        , LLMMessage RoleUser (TL.toStrict $ TLE.decodeUtf8 userPayload)
        ]
    , lroTemperature = 0.2
    , lroMaxTokens   = Nothing
    , lroJsonMode    = False
    }

  let jsonText = extractJSON raw
  case parseRepairResult jsonText of
    Left err -> throwError $ CodegenError $
      "Failed to parse repair response: " <> T.pack err
    Right repair -> pure repair
