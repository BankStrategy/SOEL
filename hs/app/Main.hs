{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Main (main) where

import Control.Monad (when)
import Data.Text (Text)
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (hFlush, stderr)

import Soel.Config (loadConfig, requireApiKey)
import Soel.Pipeline
import Soel.Types (App, runApp, SoelError(..))
import Soel.Utils.Errors (soelErrorCode)
import Soel.Utils.Logger (setLogLevel, LogLevel(..), logError)

-- ─── CLI Types ──────────────────────────────────────────────────────

data Command
  = CmdCompile !CompileCmd
  | CmdRun     !RunCmd
  | CmdCheck   !CheckCmd
  | CmdRepair  !RepairCmd
  deriving (Show)

data CompileCmd = CompileCmd
  { ccFile    :: !FilePath
  , ccOutput  :: !(Maybe FilePath)
  , ccIrOnly  :: !Bool
  , ccFast    :: !Bool
  , ccDialog  :: !Bool
  , ccLenient :: !Bool
  , ccVerbose :: !Bool
  } deriving (Show)

data RunCmd = RunCmd
  { rcFile    :: !FilePath
  , rcFast    :: !Bool
  , rcDialog  :: !Bool
  , rcLenient :: !Bool
  , rcVerbose :: !Bool
  } deriving (Show)

data CheckCmd = CheckCmd
  { ckFile    :: !FilePath
  , ckFast    :: !Bool
  , ckVerbose :: !Bool
  } deriving (Show)

data RepairCmd = RepairCmd
  { rpFile    :: !FilePath
  , rpVerbose :: !Bool
  } deriving (Show)

-- ─── Parsers ────────────────────────────────────────────────────────

compileParser :: Parser Command
compileParser = CmdCompile <$> (CompileCmd
  <$> argument str (metavar "FILE" <> help "Path to .soel source file")
  <*> optional (strOption
        (short 'o' <> long "output" <> metavar "PATH" <> help "Output .hs file path"))
  <*> switch (long "ir-only" <> help "Output semantic IR JSON instead of Haskell")
  <*> switch (long "fast" <> help "Use fast encoder (less detail)")
  <*> switch (long "dialog" <> help "Interactively resolve semantic ambiguities")
  <*> switch (long "lenient" <> help "Auto-resolve ambiguities instead of failing")
  <*> switch (long "verbose" <> help "Verbose output"))

runParser :: Parser Command
runParser = CmdRun <$> (RunCmd
  <$> argument str (metavar "FILE" <> help "Path to .soel source file")
  <*> switch (long "fast" <> help "Use fast encoder")
  <*> switch (long "dialog" <> help "Interactively resolve semantic ambiguities")
  <*> switch (long "lenient" <> help "Auto-resolve ambiguities instead of failing")
  <*> switch (long "verbose" <> help "Verbose output"))

checkParser :: Parser Command
checkParser = CmdCheck <$> (CheckCmd
  <$> argument str (metavar "FILE" <> help "Path to .soel source file")
  <*> switch (long "fast" <> help "Use fast encoder")
  <*> switch (long "verbose" <> help "Verbose output"))

repairParser :: Parser Command
repairParser = CmdRepair <$> (RepairCmd
  <$> argument str (metavar "FILE" <> help "Path to .soel source file")
  <*> switch (long "verbose" <> help "Verbose output"))

commandParser :: Parser Command
commandParser = subparser
  ( command "compile" (info compileParser (progDesc "Compile a .soel file to Haskell"))
 <> command "run"     (info runParser     (progDesc "Compile .soel -> Haskell, then GHC compile + execute"))
 <> command "check"   (info checkParser   (progDesc "Analyze .soel file and report semantic errors/warnings"))
 <> command "repair"  (info repairParser  (progDesc "Conversational debugging loop for a .soel program"))
  )

opts :: ParserInfo Command
opts = info (commandParser <**> helper)
  ( fullDesc
 <> header "soel - Semantic Open-Ended Language compiler"
 <> progDesc "Compile natural language narratives to executable Haskell"
  )

-- ─── Ambiguity mode resolution ──────────────────────────────────────

resolveAmbiguityMode :: Bool -> Bool -> AmbiguityMode
resolveAmbiguityMode dialog lenient
  | dialog  = Dialog
  | lenient = Lenient
  | otherwise = Strict

-- ─── Command runner ─────────────────────────────────────────────────

-- | Load config, check API key, run an App action, handle errors.
runCommand :: Bool -> Bool -> App () -> IO ()
runCommand verbose fast appAction = do
  when verbose $ setLogLevel LevelDebug
  eCfg <- loadConfig fast
  case eCfg of
    Left err -> handleError err
    Right cfg -> do
      case requireApiKey cfg of
        Left err -> handleError err
        Right _  -> do
          result <- runApp cfg appAction
          handleResult result

-- ─── Main ───────────────────────────────────────────────────────────

main :: IO ()
main = do
  cmd <- execParser opts
  case cmd of
    CmdCompile CompileCmd{..} ->
      runCommand ccVerbose ccFast $ runCompile ccFile CompileOptions
        { coOutput        = ccOutput
        , coIrOnly        = ccIrOnly
        , coAmbiguityMode = resolveAmbiguityMode ccDialog ccLenient
        }

    CmdRun RunCmd{..} ->
      runCommand rcVerbose rcFast $ runRun rcFile RunOptions
        { roAmbiguityMode = resolveAmbiguityMode rcDialog rcLenient
        }

    CmdCheck CheckCmd{..} ->
      runCommand ckVerbose ckFast $ runCheck ckFile CheckOptions

    CmdRepair RepairCmd{..} ->
      runCommand rpVerbose False $ runRepair rpFile

handleResult :: Either SoelError () -> IO ()
handleResult (Right ()) = pure ()
handleResult (Left err) = handleError err

handleError :: SoelError -> IO ()
handleError err = do
  case err of
    SemanticAmbiguityError msg ->
      -- Diagnostics already printed; just emit the summary
      logError msg
    _ ->
      logError $ "[" <> soelErrorCode err <> "] " <> errorMessage err
  hFlush stderr
  exitFailure

errorMessage :: SoelError -> Text
errorMessage (SemanticEncodingError msg)   = msg
errorMessage (IRValidationError msg _)     = msg
errorMessage (CodegenError msg)            = msg
errorMessage (GHCError msg _ _)            = msg
errorMessage (OpenRouterError msg _ _)     = msg
errorMessage (ConfigError msg)             = msg
errorMessage (SemanticAmbiguityError msg)  = msg
