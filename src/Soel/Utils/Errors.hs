{-# LANGUAGE OverloadedStrings #-}

module Soel.Utils.Errors
  ( SoelError(..)
  , soelErrorCode
  ) where

import Data.Text (Text)

-- | All possible errors in the SOEL compiler pipeline.
data SoelError
  = SemanticEncodingError Text
  | IRValidationError Text [Text]      -- message + issues
  | CodegenError Text
  | GHCError Text Text Int             -- message, stderr, exit code
  | OpenRouterError Text Int Text      -- message, status, body
  | ConfigError Text
  | SemanticAmbiguityError Text
  deriving (Show, Eq)

-- | Get the error code string for a SoelError.
soelErrorCode :: SoelError -> Text
soelErrorCode (SemanticEncodingError _)   = "SEMANTIC_ENCODING_ERROR"
soelErrorCode (IRValidationError _ _)     = "IR_VALIDATION_ERROR"
soelErrorCode (CodegenError _)            = "CODEGEN_ERROR"
soelErrorCode (GHCError _ _ _)            = "GHC_ERROR"
soelErrorCode (OpenRouterError _ _ _)     = "OPENROUTER_ERROR"
soelErrorCode (ConfigError _)             = "CONFIG_ERROR"
soelErrorCode (SemanticAmbiguityError _)  = "SEMANTIC_AMBIGUITY"
