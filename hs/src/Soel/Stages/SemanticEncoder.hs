{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Stages.SemanticEncoder
  ( semanticEncode
  ) where

import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Aeson (Value(..), eitherDecode')
import Data.Aeson.Key (fromText)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V

import Soel.Types (App, SoelError(..), SoelConfig(..), requireApiKeyM)
import Soel.Config (CompilerConfig(..), OpenRouterConfig(..))
import Soel.IR.Types (NarrativeIR)
import Soel.IR.Validate (validateNarrativeIR)
import Soel.LLM.OpenRouter (llmRequest, extractJSON, LLMRequestOptions(..), LLMMessage(..), LLMRole(..))
import Soel.LLM.Prompts (getPrompt)
import Soel.Utils.Logger (logStage, spinnerSuccess, spinnerFail)

-- | Semantically encode source text into a NarrativeIR using the LLM.
semanticEncode :: Text -> App NarrativeIR
semanticEncode source = do
  cfg <- ask
  let mode = ccEncoderMode (cfgCompiler cfg)
      promptName = if mode == "fast"
                   then "semantic-encoder-fast"
                   else "semantic-encoder-full"
      systemPrompt = T.replace "<NARRATIVE_SCRIPT>" "" (getPrompt promptName)

  liftIO $ logStage $ "Semantic encoding (" <> mode <> " mode)"

  apiKey <- requireApiKeyM

  raw <- llmRequest LLMRequestOptions
    { lroApiKey      = apiKey
    , lroModel       = orModel (cfgOpenRouter cfg)
    , lroMessages    =
        [ LLMMessage RoleSystem systemPrompt
        , LLMMessage RoleUser source
        ]
    , lroTemperature = 0.2
    , lroMaxTokens   = Nothing
    , lroJsonMode    = True
    }

  liftIO $ spinnerSuccess "Semantic encoding complete"

  let jsonText = extractJSON raw
  case eitherDecode' (BL.fromStrict $ TE.encodeUtf8 jsonText) :: Either String Value of
    Left err -> do
      liftIO $ spinnerFail "Semantic encoding failed"
      throwError $ SemanticEncodingError $
        "Failed to parse encoder response as JSON: " <> T.pack err
    Right val -> do
      let normalized = if mode == "fast"
                       then normalizeFastIR val
                       else val
      case validateNarrativeIR normalized of
        Left err -> do
          liftIO $ spinnerFail "Semantic encoding failed"
          throwError err
        Right nir -> pure nir

-- | Normalize the fast encoder's compact JSON format to the full NarrativeIR shape.
-- The fast encoder returns a different schema with shorter field names;
-- this function restructures the JSON Value before validation.
normalizeFastIR :: Value -> Value
normalizeFastIR (Object top) = Object $ KM.fromList
  [ ("meta",          normalizeMeta   (lookupVal "meta" top))
  , ("entities",      normalizeEntities (lookupArr "entities" top))
  , ("events",        normalizeEvents (lookupArr "events" top))
  , ("relationships", normalizeRelationships (lookupVal "relations" top))
  , ("themes",        normalizeThemes (lookupArr "themes" top))
  , ("ambiguities",   normalizeAmbiguities top)
  , ("segments",      Array V.empty)
  ]
normalizeFastIR v = v

-- ─── Meta normalization ──────────────────────────────────────────

normalizeMeta :: Value -> Value
normalizeMeta (Object m) = Object $ KM.fromList
  [ ("language",          fromMaybe (String "en") (km "language" m))
  , ("genre_guess",       String "unknown")
  , ("narrative_pov",     fromMaybe (String "unknown") (km "pov" m))
  , ("timeframe",         String "unknown")
  , ("global_confidence", extractGlobalConf m)
  ]
normalizeMeta _ = Object $ KM.fromList
  [ ("language",          String "en")
  , ("genre_guess",       String "unknown")
  , ("narrative_pov",     String "unknown")
  , ("timeframe",         String "unknown")
  , ("global_confidence", Number 0.5)
  ]

extractGlobalConf :: KM.KeyMap Value -> Value
extractGlobalConf m = case km "global_sentiment" m of
  Just (Object gs) -> fromMaybe (Number 0.5) (km "confidence" gs)
  _                -> Number 0.5

-- ─── Entity normalization ────────────────────────────────────────

normalizeEntities :: [Value] -> Value
normalizeEntities = Array . V.fromList . map normalizeEntity

normalizeEntity :: Value -> Value
normalizeEntity (Object e) = Object $ KM.fromList
  [ ("id",             fromMaybe Null (km "id" e))
  , ("type",           fromMaybe Null (km "type" e))
  , ("canonical_name", fromMaybe (fromMaybe Null (km "name" e)) (km "canonical_name" e))
  , ("aliases",        fromMaybe (Array V.empty) (km "aliases" e))
  , ("mentions",       Array V.empty)
  , ("attributes",     Object $ KM.fromList
      [ ("stable", Array V.empty), ("temporary", Array V.empty) ])
  ]
normalizeEntity v = v

-- ─── Event normalization ─────────────────────────────────────────

normalizeEvents :: [Value] -> Value
normalizeEvents = Array . V.fromList . map normalizeEvent

normalizeEvent :: Value -> Value
normalizeEvent (Object ev) = Object $ KM.fromList
  [ ("id",           fromMaybe Null (km "id" ev))
  , ("event_type",   String "action")
  , ("predicate",    fromMaybe (fromMaybe Null (km "pred" ev)) (km "predicate" ev))
  , ("tense_aspect", fromMaybe (fromMaybe (String "unknown") (km "time" ev)) (km "tense_aspect" ev))
  , ("polarity",     fromMaybe (String "affirmed") (km "polarity" ev))
  , ("trigger",      normalizeTrigger ev)
  , ("participants", normalizeParticipants ev)
  , ("relations",    normalizeEventRelations ev)
  , ("modality",     Object $ KM.fromList
      [ ("certainty", Number 0.5), ("source", String "unknown")
      , ("evidence_span", Array (V.fromList [Number (-1), Number (-1)])) ])
  ]
normalizeEvent v = v

normalizeTrigger :: KM.KeyMap Value -> Value
normalizeTrigger ev = case km "trigger_span" ev of
  Just span_ -> Object $ KM.fromList
    [ ("span", span_), ("text", String "") ]
  Nothing -> case km "trigger" ev of
    Just t  -> t
    Nothing -> Object $ KM.fromList
      [ ("span", Array (V.fromList [Number (-1), Number (-1)])), ("text", String "") ]

normalizeParticipants :: KM.KeyMap Value -> Value
normalizeParticipants ev =
  let raw = case km "roles" ev of
              Just (Array arr) -> V.toList arr
              _ -> case km "participants" ev of
                     Just (Array arr) -> V.toList arr
                     _ -> []
  in Array $ V.fromList $ map normalizeParticipant raw

normalizeParticipant :: Value -> Value
normalizeParticipant (Object r) = Object $ KM.fromList
  [ ("role",       fromMaybe Null (km "role" r))
  , ("entity_id",  fromMaybe (fromMaybe Null (km "entity" r)) (km "entity_id" r))
  , ("span",       fromMaybe (fromMaybe defSpan (km "evidence_span" r)) (km "span" r))
  , ("confidence", fromMaybe (Number 0.5) (km "confidence" r))
  ]
  where defSpan = Array (V.fromList [Number (-1), Number (-1)])
normalizeParticipant v = v

normalizeEventRelations :: KM.KeyMap Value -> Value
normalizeEventRelations ev =
  let raw = case km "links" ev of
              Just (Array arr) -> V.toList arr
              _ -> case km "relations" ev of
                     Just (Array arr) -> V.toList arr
                     _ -> []
  in Array $ V.fromList $ map normalizeEventRel raw

normalizeEventRel :: Value -> Value
normalizeEventRel (Object l) = Object $ KM.fromList
  [ ("type",            fromMaybe Null (km "type" l))
  , ("target_event_id", fromMaybe (fromMaybe Null (km "target" l)) (km "target_event_id" l))
  , ("evidence_span",   fromMaybe defSpan (km "evidence_span" l))
  , ("confidence",      fromMaybe (Number 0.5) (km "confidence" l))
  ]
  where defSpan = Array (V.fromList [Number (-1), Number (-1)])
normalizeEventRel v = v

-- ─── Relationship normalization ──────────────────────────────────

normalizeRelationships :: Value -> Value
normalizeRelationships (Object rels) =
  let social = case km "social" rels of
        Just (Array arr) -> V.toList arr
        _                -> []
  in Array $ V.fromList $ zipWith normalizeRel [1..] social
normalizeRelationships _ = Array V.empty

normalizeRel :: Int -> Value -> Value
normalizeRel i (Object r) = Object $ KM.fromList
  [ ("id",               String $ "R" <> T.pack (show i))
  , ("source_entity_id", fromMaybe Null (km "a" r))
  , ("target_entity_id", fromMaybe Null (km "b" r))
  , ("relation",         fromMaybe Null (km "type" r))
  , ("directional",      Bool True)
  , ("status",           String "active")
  , ("evidence_span",    fromMaybe defSpan (km "evidence_span" r))
  , ("confidence",       fromMaybe (Number 0.5) (km "confidence" r))
  ]
  where defSpan = Array (V.fromList [Number (-1), Number (-1)])
normalizeRel _ v = v

-- ─── Theme normalization ─────────────────────────────────────────

normalizeThemes :: [Value] -> Value
normalizeThemes = Array . V.fromList . map normalizeTheme

normalizeTheme :: Value -> Value
normalizeTheme (Object t) =
  let conf = fromMaybe (Number 0.5) (km "confidence" t)
      evidenceSpans = case km "evidence_spans" t of
        Just (Array arr) -> V.toList arr
        _                -> []
      support = Array $ V.fromList $ map (mkSupport conf) evidenceSpans
  in Object $ KM.fromList
    [ ("theme",      fromMaybe (fromMaybe Null (km "label" t)) (km "theme" t))
    , ("support",    support)
    , ("confidence", conf)
    ]
normalizeTheme v = v

mkSupport :: Value -> Value -> Value
mkSupport conf span_ = Object $ KM.fromList
  [ ("evidence_span", span_)
  , ("note",          String "")
  , ("confidence",    conf)
  ]

-- ─── Ambiguity normalization ─────────────────────────────────────

normalizeAmbiguities :: KM.KeyMap Value -> Value
normalizeAmbiguities top =
  let raw = case km "high_uncertainty" top of
              Just (Array arr) -> V.toList arr
              _ -> case km "ambiguities" top of
                     Just (Array arr) -> V.toList arr
                     _ -> []
  in Array $ V.fromList $ zipWith normalizeAmb [1..] raw

normalizeAmb :: Int -> Value -> Value
normalizeAmb i (Object a) = Object $ KM.fromList
  [ ("id",              fromMaybe (String $ "A" <> T.pack (show i)) (km "id" a))
  , ("issue",           fromMaybe (String "other") (km "issue" a))
  , ("span",            fromMaybe defSpan (km "span" a))
  , ("interpretations", normalizeInterpretations a)
  ]
  where defSpan = Array (V.fromList [Number (-1), Number (-1)])
normalizeAmb _ v = v

normalizeInterpretations :: KM.KeyMap Value -> Value
normalizeInterpretations a = case km "options" a of
  Just (Array arr) -> Array arr
  _ -> case km "interpretations" a of
    Just (Array arr) -> Array arr
    _                -> Array V.empty

-- ─── Helpers ─────────────────────────────────────────────────────

-- | Look up a key in a KeyMap.
km :: Text -> KM.KeyMap Value -> Maybe Value
km k = KM.lookup (fromText k)

-- | Look up a key and return the value, or Null.
lookupVal :: Text -> KM.KeyMap Value -> Value
lookupVal k m = fromMaybe Null (km k m)

-- | Look up a key expected to be an array; return the elements as a list.
lookupArr :: Text -> KM.KeyMap Value -> [Value]
lookupArr k m = case km k m of
  Just (Array arr) -> V.toList arr
  _                -> []
