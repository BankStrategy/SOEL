{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Stages.Codegen
  ( CodegenResult(..)
  , generateHaskell
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (isJust)

import Soel.Types (App, SoelError(..), SoelConfig(..), requireApiKeyM)
import Soel.Config (OpenRouterConfig(..), HaskellConfig(..))
import Soel.IR.Types (CodeIR(..), ModuleDecl(..), Ambiguity(..), AmbiguityResolution(..))
import Soel.IR.Validate ()  -- import ToJSON/FromJSON orphan instances
import Soel.LLM.OpenRouter (llmRequest, LLMRequestOptions(..), LLMMessage(..), LLMRole(..))
import Soel.LLM.Prompts (getPromptWithVars)
import Soel.Utils.Logger (logStage, spinnerSuccess, spinnerFail)

-- | Result of Haskell code generation.
data CodegenResult = CodegenResult
  { crHaskellSource :: !Text
  , crModuleName    :: !Text
  } deriving (Show, Eq)

-- | Generate Haskell source code from a Code IR and resolved ambiguities.
generateHaskell :: CodeIR -> [Ambiguity] -> Text -> App CodegenResult
generateHaskell codeIR resolvedAmbiguities sourceText = do
  cfg <- ask
  liftIO $ logStage "Generating Haskell code"

  apiKey <- requireApiKeyM

  let resolutions = formatResolutions resolvedAmbiguities
      codeIRJson  = T.pack $ BLC.unpack $ encode codeIR
      extensions  = T.intercalate ", " (hsExtensions (cfgHaskell cfg))

      prompt = getPromptWithVars "codegen-haskell"
        [ ("CODE_IR",     codeIRJson)
        , ("RESOLUTIONS", resolutions)
        , ("SOURCE_TEXT", sourceText)
        , ("EXTENSIONS",  extensions)
        ]

  raw <- llmRequest LLMRequestOptions
    { lroApiKey      = apiKey
    , lroModel       = orModel (cfgOpenRouter cfg)
    , lroMessages    = [ LLMMessage RoleSystem prompt ]
    , lroTemperature = 0.2
    , lroMaxTokens   = Nothing
    , lroJsonMode    = False
    }

  liftIO $ spinnerSuccess "Haskell code generated"

  let haskellSource = ensureModuleMain (extractHaskell raw)

  if not (T.isInfixOf "module " haskellSource) && not (T.isInfixOf "main " haskellSource)
    then do
      liftIO $ spinnerFail "Code generation failed"
      throwError $ CodegenError "Generated code does not contain a valid Haskell module"
    else pure CodegenResult
      { crHaskellSource = haskellSource
      , crModuleName    = mdName (cirModule codeIR)
      }

-- | Format resolved ambiguities as a bullet list for the LLM prompt.
formatResolutions :: [Ambiguity] -> Text
formatResolutions ambs =
  let resolved = filter (isJust . ambResolution) ambs
      lines_   = map formatOne resolved
  in  if null lines_
      then "No ambiguities to resolve."
      else T.intercalate "\n" lines_
  where
    formatOne a = case ambResolution a of
      Just res -> "- " <> ambDescription a <> ": " <> arChosen res
               <> " (" <> arRationale res <> ")"
      Nothing  -> "- " <> ambDescription a <> ": unresolved"

-- | Extract Haskell code from the LLM response.
-- Tries code fences first, then module declaration, then falls back to raw text.
extractHaskell :: Text -> Text
extractHaskell text =
  case extractFenced text of
    Just code -> T.strip code
    Nothing   -> case extractFromModule text of
      Just code -> T.strip code
      Nothing   -> T.strip text

-- | Try to find Haskell in ```haskell ... ``` or ``` ... ``` fences.
extractFenced :: Text -> Maybe Text
extractFenced s =
  -- Find first line starting with ``` and last line that is exactly ```
  let ls = T.lines s
      isOpenFence l = let t = T.stripStart l
                      in T.isPrefixOf "```" t
      isCloseFence l = T.strip l == "```"
  in case break isOpenFence ls of
       (_, [])       -> Nothing
       (_, _open:rest) ->
         case break isCloseFence (reverse rest) of
           (_, [])     -> Nothing
           (after, _)  -> let body = T.unlines (reverse after)
                          in if T.null (T.strip body) then Nothing else Just body

-- | Look for module declaration (possibly preceded by pragmas) and take everything from there.
-- Scans lines for the first pragma or module declaration and returns from there.
extractFromModule :: Text -> Maybe Text
extractFromModule s =
  let ls = T.lines s
      isModuleLine l = T.isPrefixOf "module " (T.stripStart l)
      isPragmaLine l = T.isPrefixOf "{-#" (T.stripStart l)
      -- Find the first line that starts a Haskell module (pragma or module decl)
      startIdx = findStart 0 ls
      findStart _ [] = Nothing
      findStart i (l:rest)
        | isPragmaLine l = Just i
        | isModuleLine l = Just i
        | otherwise      = findStart (i + 1) rest
  in case startIdx of
       Just idx -> let result = T.unlines (drop idx ls)
                   in if T.null (T.strip result) then Nothing else Just result
       Nothing  -> Nothing

-- | GHC requires @module Main where@ for executables.
-- Replace whatever module name the LLM chose with Main.
ensureModuleMain :: Text -> Text
ensureModuleMain source =
  let ls = T.lines source
  in T.unlines (map replaceModuleLine ls)

-- | Replace "module SomeName where" with "module Main where" on a single line.
replaceModuleLine :: Text -> Text
replaceModuleLine line =
  let stripped = T.stripStart line
  in if T.isPrefixOf "module " stripped
     then let afterModule = T.drop 7 stripped  -- drop "module "
              -- Skip the module name (non-space chars)
              rest = T.dropWhile (/= ' ') (T.stripStart afterModule)
          in "module Main" <> rest
     else line
