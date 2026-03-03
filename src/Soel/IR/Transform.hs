{-# LANGUAGE OverloadedStrings #-}

module Soel.IR.Transform
  ( transformToCodeIR
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Aeson (eitherDecode, encode)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE

import Soel.Types (App, SoelError(..), SoelConfig(..), requireApiKeyM)
import Soel.Config (OpenRouterConfig(..))
import Soel.IR.Types (NarrativeIR, CodeIR)
import Soel.IR.Validate (validateCodeIR)
import Soel.LLM.OpenRouter (LLMRole(..), LLMMessage(..), LLMRequestOptions(..), llmRequest, extractJSON)
import Soel.LLM.Prompts (getPromptWithVars)
import Soel.Utils.Logger (logStage, spinnerSuccess, spinnerFail)

-- | Transform a NarrativeIR into a CodeIR by calling the LLM with the
-- ir-transform prompt. The source text is included for context.
transformToCodeIR :: NarrativeIR -> Text -> App CodeIR
transformToCodeIR narrativeIR sourceText = do
  cfg <- ask
  liftIO $ logStage "Transforming narrative IR \x2192 code IR"

  apiKey <- requireApiKeyM

  -- Load the ir-transform prompt with substitutions
  let prompt = getPromptWithVars "ir-transform"
        [ ("SOURCE_TEXT", sourceText)
        , ("NARRATIVE_IR", nirJson)
        ]

  -- Call the LLM
  raw <- llmRequest LLMRequestOptions
    { lroApiKey      = apiKey
    , lroModel       = orModel (cfgOpenRouter cfg)
    , lroMessages    = [LLMMessage RoleSystem prompt]
    , lroTemperature = 0.2
    , lroMaxTokens   = Nothing
    , lroJsonMode    = True
    }

  -- Extract JSON from response
  let jsonText = extractJSON raw

  -- Parse the JSON string into a Value
  let jsonBs = TLE.encodeUtf8 (TL.fromStrict jsonText)
  case eitherDecode jsonBs of
    Left err -> throwError $ SemanticEncodingError $
      "Failed to parse transform response as JSON: " <> T.pack err
    Right val -> case validateCodeIR val of
      Left err  -> throwError err
      Right cir -> pure cir
  where
    nirJson :: Text
    nirJson = TL.toStrict $ TLE.decodeUtf8 $ encode narrativeIR
