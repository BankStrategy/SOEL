{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE OverloadedStrings #-}

module Soel.LLM.Prompts
  ( getPrompt
  , getPromptWithVars
  ) where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedFile)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

--------------------------------------------------------------------------------
-- Embedded prompt templates (resolved relative to project root, i.e. hs/)
--------------------------------------------------------------------------------

semanticEncoderFullBS :: ByteString
semanticEncoderFullBS = $(embedFile "../prompts/semantic-encoder-full.md")

semanticEncoderFastBS :: ByteString
semanticEncoderFastBS = $(embedFile "../prompts/semantic-encoder-fast.md")

irTransformBS :: ByteString
irTransformBS = $(embedFile "../prompts/ir-transform.md")

codegenHaskellBS :: ByteString
codegenHaskellBS = $(embedFile "../prompts/codegen-haskell.md")

ambiguityResolverBS :: ByteString
ambiguityResolverBS = $(embedFile "../prompts/ambiguity-resolver.md")

pragmaticRepairBS :: ByteString
pragmaticRepairBS = $(embedFile "../prompts/pragmatic-repair.md")

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- | Look up a prompt template by name and return its content as Text.
getPrompt :: Text -> Text
getPrompt name = case name of
  "semantic-encoder-full" -> TE.decodeUtf8 semanticEncoderFullBS
  "semantic-encoder-fast" -> TE.decodeUtf8 semanticEncoderFastBS
  "ir-transform"          -> TE.decodeUtf8 irTransformBS
  "codegen-haskell"       -> TE.decodeUtf8 codegenHaskellBS
  "ambiguity-resolver"    -> TE.decodeUtf8 ambiguityResolverBS
  "pragmatic-repair"      -> TE.decodeUtf8 pragmaticRepairBS
  other                   -> error $ "Unknown prompt template: " <> T.unpack other

-- | Load a prompt template and replace all @{{KEY}}@ placeholders with
-- the corresponding values from the provided association list.
getPromptWithVars :: Text -> [(Text, Text)] -> Text
getPromptWithVars name vars =
  foldl applyVar (getPrompt name) vars
  where
    applyVar content (key, value) =
      T.replace ("{{" <> key <> "}}") value content
