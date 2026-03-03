{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Utils.Logger
  ( -- * Log levels
    LogLevel(..)
  , setLogLevel
  , getLogLevel
    -- * Logging functions
  , logDebug
  , logInfo
  , logSuccess
  , logWarn
  , logError
  , logStage
    -- * Spinner
  , withSpinner
  , spinnerSuccess
  , spinnerFail
    -- * Colored output
  , coloredStderr
    -- * Diagnostic formatting
  , DiagnosticOpts(..)
  , formatDiagnostic
  ) where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.IO (hFlush, stderr, hPutStr)
import System.IO.Unsafe (unsafePerformIO)
import System.Console.ANSI

-- | Log levels ordered by severity.
data LogLevel = LevelDebug | LevelInfo | LevelWarn | LevelError
  deriving (Show, Eq, Ord)

-- | Global mutable log level.
{-# NOINLINE currentLogLevel #-}
currentLogLevel :: IORef LogLevel
currentLogLevel = unsafePerformIO (newIORef LevelInfo)

setLogLevel :: LogLevel -> IO ()
setLogLevel = writeIORef currentLogLevel

getLogLevel :: IO LogLevel
getLogLevel = readIORef currentLogLevel

shouldLog :: LogLevel -> IO Bool
shouldLog level = do
  current <- readIORef currentLogLevel
  pure (level >= current)

-- | Write colored text to stderr.
coloredStderr :: [SGR] -> Text -> IO ()
coloredStderr sgrs msg = do
  hSetSGR stderr sgrs
  TIO.hPutStr stderr msg
  hSetSGR stderr [Reset]
  TIO.hPutStr stderr "\n"
  hFlush stderr

logDebug :: Text -> IO ()
logDebug msg = do
  ok <- shouldLog LevelDebug
  if ok then coloredStderr [SetColor Foreground Dull White] ("[debug] " <> msg)
        else pure ()

logInfo :: Text -> IO ()
logInfo msg = do
  ok <- shouldLog LevelInfo
  if ok then coloredStderr [SetColor Foreground Vivid Blue] ("\x2139 " <> msg)
        else pure ()

logSuccess :: Text -> IO ()
logSuccess msg = do
  ok <- shouldLog LevelInfo
  if ok then coloredStderr [SetColor Foreground Vivid Green] ("\x2713 " <> msg)
        else pure ()

logWarn :: Text -> IO ()
logWarn msg = do
  ok <- shouldLog LevelWarn
  if ok then coloredStderr [SetColor Foreground Vivid Yellow] ("\x26A0 " <> msg)
        else pure ()

logError :: Text -> IO ()
logError msg = do
  ok <- shouldLog LevelError
  if ok then coloredStderr [SetColor Foreground Vivid Red] ("\x2717 " <> msg)
        else pure ()

logStage :: Text -> IO ()
logStage name = do
  ok <- shouldLog LevelInfo
  if ok then coloredStderr [SetColor Foreground Vivid Cyan] ("\n\x25B8 " <> name)
        else pure ()

-- | Simple ANSI spinner. Shows message, runs action, shows result.
withSpinner :: Text -> IO a -> IO a
withSpinner msg action = do
  hPutStr stderr "\r"
  hSetSGR stderr [SetColor Foreground Vivid Cyan]
  TIO.hPutStr stderr ("  \x25CB " <> msg)
  hSetSGR stderr [Reset]
  hFlush stderr
  result <- action
  hPutStr stderr "\r"
  hSetSGR stderr [SetConsoleIntensity BoldIntensity]
  hPutStr stderr "                                                                          \r"
  hSetSGR stderr [Reset]
  hFlush stderr
  pure result

spinnerSuccess :: Text -> IO ()
spinnerSuccess msg = coloredStderr [SetColor Foreground Vivid Green] ("\x2713 " <> msg)

spinnerFail :: Text -> IO ()
spinnerFail msg = coloredStderr [SetColor Foreground Vivid Red] ("\x2717 " <> msg)

-- | Options for formatting a diagnostic message.
data DiagnosticOpts = DiagnosticOpts
  { diagFile       :: !FilePath
  , diagSeverity   :: !Text         -- "error" or "warning"
  , diagId         :: !Text         -- e.g. "S001"
  , diagCategory   :: !Text
  , diagMessage    :: !Text
  , diagSpan       :: !(Maybe (Int, Int))
  , diagSourceText :: !(Maybe Text)
  , diagOptions    :: ![(Text, Double)]  -- (label, confidence)
  } deriving (Show)

-- | Format a compiler diagnostic in GCC/GHC style.
formatDiagnostic :: DiagnosticOpts -> Text
formatDiagnostic DiagnosticOpts{..} =
  let
    -- Compute line/col from span
    (locStr, mLineNum, mColNum) = case (diagSpan, diagSourceText) of
      (Just (start, _), Just src) | start >= 0 ->
        let before = T.take start src
            lineNum = T.count "\n" before + 1
            colNum  = start - maybe 0 (\i -> i + 1) (T.findIndex (== '\n') (T.reverse before))
        in  (T.pack diagFile <> ":" <> T.pack (show lineNum) <> ":" <> T.pack (show colNum), Just lineNum, Just colNum)
      _ -> (T.pack diagFile, Nothing, Nothing)

    -- Header line
    header = locStr <> ": " <> diagSeverity <> " [" <> diagId <> "]: " <> diagMessage

    -- Category
    catLine = "  \x251C\x2500 category: " <> diagCategory

    -- Source context
    srcLines = case (diagSpan, diagSourceText, mLineNum, mColNum) of
      (Just (start, end), Just src, Just lineNum, Just colNum) | start >= 0 ->
        let allLines = T.lines src
            contextStart = max 0 (lineNum - 2)
            contextEnd   = min (length allLines) (lineNum + 1)
            contextSlice = zip [contextStart..] (take (contextEnd - contextStart) (drop contextStart allLines))
            formatLine (i, line) =
              let ln = T.justifyRight 4 ' ' (T.pack (show (i + 1)))
                  marker = if i == lineNum - 1 then "\x25B8" else " "
              in  "  " <> marker <> " " <> ln <> " \x2502 " <> line
            underlineLine = case find (\(i, _) -> i == lineNum - 1) contextSlice of
              Just (_, line) ->
                let underLen = min (end - start) (T.length line - colNum + 1)
                    pad = T.replicate (colNum - 1) " "
                    underline = T.replicate (max 1 underLen) "~"
                in  Just $ "       \x2502 " <> pad <> underline
              Nothing -> Nothing
        in  ["  \x2502"] ++ map formatLine contextSlice ++ maybe [] (:[]) underlineLine
      _ -> []

    -- Options
    optLines = if null diagOptions then []
      else ["  \x2502", "  \x251C\x2500 possible interpretations:"]
        ++ map (\(lbl, conf) ->
            let pct = T.pack (show (round (conf * 100) :: Int)) <> "%"
            in  "  \x2502   \x2022 " <> lbl <> " (" <> pct <> ")"
          ) diagOptions

    closing = ["  \x2502"]
  in
    T.unlines ([header, catLine] ++ srcLines ++ optLines ++ closing)
