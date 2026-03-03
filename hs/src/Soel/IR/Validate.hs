{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.IR.Validate
  ( validateNarrativeIR
  , validateCodeIR
  , sanitizeLLMJson
  ) where

import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import Data.Aeson.Types (Parser, parseMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as V

import Soel.IR.Types
import Soel.Utils.Errors (SoelError(..))

-- | Sanitize JSON from LLM output by stripping null values from objects.
-- LLMs sometimes return null for fields that should be strings, numbers, or
-- arrays. Removing null-keyed entries lets .:? defaults handle those fields
-- while .: catches truly absent required fields with a clear "key not found".
sanitizeLLMJson :: Value -> Value
sanitizeLLMJson (Object obj) = Object (KM.map sanitizeLLMJson (KM.filter (/= Null) obj))
sanitizeLLMJson (Array arr)  = Array (V.map sanitizeLLMJson arr)
sanitizeLLMJson v            = v

-- ─── Span parsing helper ──────────────────────────────────────────

parseSpan :: Value -> Parser (Int, Int)
parseSpan = withArray "span" $ \arr ->
  if V.length arr >= 2
    then (,) <$> parseJSON (arr V.! 0) <*> parseJSON (arr V.! 1)
    else fail "span must be a 2-element array"

-- ─── Narrative IR instances ────────────────────────────────────────

instance FromJSON NarrativeMeta where
  parseJSON = withObject "NarrativeMeta" $ \v -> do
    nmLanguage         <- v .:? "language"          .!= "en"
    nmGenreGuess       <- v .:? "genre_guess"       .!= "unknown"
    nmNarrativePov     <- v .:? "narrative_pov"     .!= "unknown"
    nmTimeframe        <- v .:? "timeframe"         .!= "unknown"
    nmGlobalConfidence <- v .:? "global_confidence" .!= 0.5
    pure NarrativeMeta{..}

instance ToJSON NarrativeMeta where
  toJSON NarrativeMeta{..} = object
    [ "language"          .= nmLanguage
    , "genre_guess"       .= nmGenreGuess
    , "narrative_pov"     .= nmNarrativePov
    , "timeframe"         .= nmTimeframe
    , "global_confidence" .= nmGlobalConfidence
    ]

instance FromJSON Mention where
  parseJSON = withObject "Mention" $ \v -> do
    mSpan         <- v .:? "span"
    menSpan       <- case mSpan of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    menSurface    <- v .:? "surface"    .!= ""
    menConfidence <- v .:? "confidence" .!= 0.5
    pure Mention{..}

instance ToJSON Mention where
  toJSON Mention{..} = object
    [ "span"       .= [fst menSpan, snd menSpan]
    , "surface"    .= menSurface
    , "confidence" .= menConfidence
    ]

instance FromJSON Attribute where
  parseJSON = withObject "Attribute" $ \v -> do
    attrKey          <- v .:? "key"   .!= ""
    attrValue        <- v .:? "value" .!= ""
    mSpan            <- v .:? "evidence_span"
    attrEvidenceSpan <- case mSpan of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    attrConfidence   <- v .:? "confidence" .!= 0.5
    pure Attribute{..}

instance ToJSON Attribute where
  toJSON Attribute{..} = object
    [ "key"           .= attrKey
    , "value"         .= attrValue
    , "evidence_span" .= [fst attrEvidenceSpan, snd attrEvidenceSpan]
    , "confidence"    .= attrConfidence
    ]

instance FromJSON EntityAttributes where
  parseJSON = withObject "EntityAttributes" $ \v -> do
    eaStable    <- v .:? "stable"    .!= []
    eaTemporary <- v .:? "temporary" .!= []
    pure EntityAttributes{..}

instance ToJSON EntityAttributes where
  toJSON EntityAttributes{..} = object
    [ "stable"    .= eaStable
    , "temporary" .= eaTemporary
    ]

instance FromJSON NarrativeEntity where
  parseJSON = withObject "NarrativeEntity" $ \v -> do
    neId            <- v .:  "id"
    neType          <- v .:  "type"
    neCanonicalName <- v .:  "canonical_name"
    neAliases       <- v .:? "aliases"    .!= []
    neMentions      <- v .:? "mentions"   .!= []
    neAttributes    <- v .:? "attributes" .!= EntityAttributes [] []
    pure NarrativeEntity{..}

instance ToJSON NarrativeEntity where
  toJSON NarrativeEntity{..} = object
    [ "id"             .= neId
    , "type"           .= neType
    , "canonical_name" .= neCanonicalName
    , "aliases"        .= neAliases
    , "mentions"       .= neMentions
    , "attributes"     .= neAttributes
    ]

instance FromJSON EventTrigger where
  parseJSON = withObject "EventTrigger" $ \v -> do
    mSpan <- v .:? "span"
    etSpan <- case mSpan of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    etText <- v .:? "text" .!= ""
    pure EventTrigger{..}

instance ToJSON EventTrigger where
  toJSON EventTrigger{..} = object
    [ "span" .= [fst etSpan, snd etSpan]
    , "text" .= etText
    ]

instance FromJSON Participant where
  parseJSON = withObject "Participant" $ \v -> do
    partRole       <- v .:? "role"       .!= ""
    partEntityId   <- v .:? "entity_id"  .!= ""
    mSpan          <- v .:? "span"
    partSpan       <- case mSpan of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    partConfidence <- v .:? "confidence" .!= 0.5
    pure Participant{..}

instance ToJSON Participant where
  toJSON Participant{..} = object
    [ "role"       .= partRole
    , "entity_id"  .= partEntityId
    , "span"       .= [fst partSpan, snd partSpan]
    , "confidence" .= partConfidence
    ]

instance FromJSON EventRelation where
  parseJSON = withObject "EventRelation" $ \v -> do
    erType          <- v .:? "type"            .!= ""
    erTargetEventId <- v .:? "target_event_id" .!= ""
    mSpan           <- v .:? "evidence_span"
    erEvidenceSpan  <- case mSpan of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    erConfidence    <- v .:? "confidence"      .!= 0.5
    pure EventRelation{..}

instance ToJSON EventRelation where
  toJSON EventRelation{..} = object
    [ "type"            .= erType
    , "target_event_id" .= erTargetEventId
    , "evidence_span"   .= [fst erEvidenceSpan, snd erEvidenceSpan]
    , "confidence"      .= erConfidence
    ]

instance FromJSON Modality where
  parseJSON = withObject "Modality" $ \v -> do
    modCertainty    <- v .:? "certainty"      .!= 0.5
    modSource       <- v .:? "source"         .!= "unknown"
    modEvidenceSpan <- case parseMaybe (.: "evidence_span") v of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    pure Modality{..}

instance ToJSON Modality where
  toJSON Modality{..} = object
    [ "certainty"      .= modCertainty
    , "source"         .= modSource
    , "evidence_span"  .= [fst modEvidenceSpan, snd modEvidenceSpan]
    ]

instance FromJSON NarrativeEvent where
  parseJSON = withObject "NarrativeEvent" $ \v -> do
    nevId           <- v .:  "id"
    nevEventType    <- v .:  "event_type"
    nevPredicate    <- v .:  "predicate"
    nevTenseAspect  <- v .:? "tense_aspect"  .!= "unknown"
    nevPolarity     <- v .:? "polarity"      .!= "affirmed"
    nevTrigger      <- v .: "trigger"
    nevParticipants <- v .:? "participants"  .!= []
    nevRelations    <- v .:? "relations"     .!= []
    nevModality     <- v .:? "modality"      .!= Modality 0.5 "unknown" (-1, -1)
    pure NarrativeEvent{..}

instance ToJSON NarrativeEvent where
  toJSON NarrativeEvent{..} = object
    [ "id"           .= nevId
    , "event_type"   .= nevEventType
    , "predicate"    .= nevPredicate
    , "tense_aspect" .= nevTenseAspect
    , "polarity"     .= nevPolarity
    , "trigger"      .= nevTrigger
    , "participants" .= nevParticipants
    , "relations"    .= nevRelations
    , "modality"     .= nevModality
    ]

instance FromJSON NarrativeRelationship where
  parseJSON = withObject "NarrativeRelationship" $ \v -> do
    nrId             <- v .:  "id"
    nrSourceEntityId <- v .:  "source_entity_id"
    nrTargetEntityId <- v .:  "target_entity_id"
    nrRelation       <- v .:  "relation"
    nrDirectional    <- v .:? "directional"      .!= True
    nrStatus         <- v .:? "status"           .!= "active"
    mSpan            <- v .:? "evidence_span"
    nrEvidenceSpan   <- case mSpan of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    nrConfidence     <- v .:? "confidence"       .!= 0.5
    pure NarrativeRelationship{..}

instance ToJSON NarrativeRelationship where
  toJSON NarrativeRelationship{..} = object
    [ "id"               .= nrId
    , "source_entity_id" .= nrSourceEntityId
    , "target_entity_id" .= nrTargetEntityId
    , "relation"         .= nrRelation
    , "directional"      .= nrDirectional
    , "status"           .= nrStatus
    , "evidence_span"    .= [fst nrEvidenceSpan, snd nrEvidenceSpan]
    , "confidence"       .= nrConfidence
    ]

instance FromJSON ThemeSupport where
  parseJSON = withObject "ThemeSupport" $ \v -> do
    mSpan          <- v .:? "evidence_span"
    tsEvidenceSpan <- case mSpan of
      Just s  -> parseSpan s
      Nothing -> pure (-1, -1)
    tsNote         <- v .:? "note"       .!= ""
    tsConfidence   <- v .:? "confidence" .!= 0.5
    pure ThemeSupport{..}

instance ToJSON ThemeSupport where
  toJSON ThemeSupport{..} = object
    [ "evidence_span" .= [fst tsEvidenceSpan, snd tsEvidenceSpan]
    , "note"          .= tsNote
    , "confidence"    .= tsConfidence
    ]

instance FromJSON NarrativeTheme where
  parseJSON = withObject "NarrativeTheme" $ \v -> do
    ntTheme      <- v .: "theme"
    ntSupport    <- v .:? "support" .!= []
    ntConfidence <- v .: "confidence"
    pure NarrativeTheme{..}

instance ToJSON NarrativeTheme where
  toJSON NarrativeTheme{..} = object
    [ "theme"      .= ntTheme
    , "support"    .= ntSupport
    , "confidence" .= ntConfidence
    ]

instance FromJSON Interpretation where
  parseJSON = withObject "Interpretation" $ \v -> do
    intReading    <- v .: "reading"
    intConfidence <- v .: "confidence"
    pure Interpretation{..}

instance ToJSON Interpretation where
  toJSON Interpretation{..} = object
    [ "reading"    .= intReading
    , "confidence" .= intConfidence
    ]

instance FromJSON NarrativeAmbiguity where
  parseJSON = withObject "NarrativeAmbiguity" $ \v -> do
    naId              <- v .: "id"
    naIssue           <- v .: "issue"
    naSpan            <- v .: "span" >>= parseSpan
    naInterpretations <- v .:? "interpretations" .!= []
    pure NarrativeAmbiguity{..}

instance ToJSON NarrativeAmbiguity where
  toJSON NarrativeAmbiguity{..} = object
    [ "id"              .= naId
    , "issue"           .= naIssue
    , "span"            .= [fst naSpan, snd naSpan]
    , "interpretations" .= naInterpretations
    ]

instance FromJSON NarrativeSegment where
  parseJSON = withObject "NarrativeSegment" $ \v -> do
    nsId        <- v .: "id"
    nsSpan      <- v .: "span" >>= parseSpan
    nsSummary   <- v .: "summary"
    nsKeyEvents <- v .:? "key_events" .!= []
    nsNotes     <- v .:? "notes"      .!= []
    pure NarrativeSegment{..}

instance ToJSON NarrativeSegment where
  toJSON NarrativeSegment{..} = object
    [ "id"         .= nsId
    , "span"       .= [fst nsSpan, snd nsSpan]
    , "summary"    .= nsSummary
    , "key_events" .= nsKeyEvents
    , "notes"      .= nsNotes
    ]

instance FromJSON NarrativeIR where
  parseJSON = withObject "NarrativeIR" $ \v -> do
    nirMeta          <- v .: "meta"
    nirEntities      <- v .:? "entities"      .!= []
    nirEvents        <- v .:? "events"        .!= []
    nirRelationships <- v .:? "relationships" .!= []
    nirThemes        <- v .:? "themes"        .!= []
    nirAmbiguities   <- v .:? "ambiguities"   .!= []
    nirSegments      <- v .:? "segments"      .!= []
    pure NarrativeIR{..}

instance ToJSON NarrativeIR where
  toJSON NarrativeIR{..} = object
    [ "meta"          .= nirMeta
    , "entities"      .= nirEntities
    , "events"        .= nirEvents
    , "relationships" .= nirRelationships
    , "themes"        .= nirThemes
    , "ambiguities"   .= nirAmbiguities
    , "segments"      .= nirSegments
    ]

-- ─── Code IR instances ─────────────────────────────────────────────

instance FromJSON ModuleDecl where
  parseJSON = withObject "ModuleDecl" $ \v -> do
    mdName        <- v .: "name"
    mdDescription <- v .:? "description" .!= ""
    mdExtensions  <- v .:? "extensions"  .!= []
    pure ModuleDecl{..}

instance ToJSON ModuleDecl where
  toJSON ModuleDecl{..} = object
    [ "name"        .= mdName
    , "description" .= mdDescription
    , "extensions"  .= mdExtensions
    ]

instance FromJSON ImportDecl where
  parseJSON = withObject "ImportDecl" $ \v -> do
    idModule    <- v .: "module"
    idQualified <- v .:? "qualified"
    idAlias     <- v .:? "alias"
    idItems     <- v .:? "items"
    pure ImportDecl{..}

instance ToJSON ImportDecl where
  toJSON ImportDecl{..} = object
    [ "module"    .= idModule
    , "qualified" .= idQualified
    , "alias"     .= idAlias
    , "items"     .= idItems
    ]

instance FromJSON TypeKind where
  parseJSON = withText "TypeKind" $ \t -> case t of
    "record"  -> pure KindRecord
    "sum"     -> pure KindSum
    "newtype" -> pure KindNewtype
    "alias"   -> pure KindAlias
    _         -> fail $ "Unknown TypeKind: " <> T.unpack t

instance ToJSON TypeKind where
  toJSON KindRecord  = String "record"
  toJSON KindSum     = String "sum"
  toJSON KindNewtype = String "newtype"
  toJSON KindAlias   = String "alias"

instance FromJSON FieldDecl where
  parseJSON = withObject "FieldDecl" $ \v -> do
    fdName        <- v .: "name"
    fdType        <- v .: "type"
    fdDescription <- v .:? "description" .!= ""
    fdOptional    <- v .:? "optional"    .!= False
    pure FieldDecl{..}

instance ToJSON FieldDecl where
  toJSON FieldDecl{..} = object
    [ "name"        .= fdName
    , "type"        .= fdType
    , "description" .= fdDescription
    , "optional"    .= fdOptional
    ]

instance FromJSON ConstructorDecl where
  parseJSON = withObject "ConstructorDecl" $ \v -> do
    cdName   <- v .: "name"
    cdFields <- v .:? "fields"
    pure ConstructorDecl{..}

instance ToJSON ConstructorDecl where
  toJSON ConstructorDecl{..} = object
    [ "name"   .= cdName
    , "fields" .= cdFields
    ]

instance FromJSON TypeDecl where
  parseJSON = withObject "TypeDecl" $ \v -> do
    tdName         <- v .: "name"
    tdKind         <- v .: "kind"
    tdDescription  <- v .:? "description"  .!= ""
    tdDeriving     <- v .:? "deriving"     .!= []
    tdFields       <- v .:? "fields"
    tdConstructors <- v .:? "constructors"
    tdWrappedType  <- v .:? "wrappedType"
    tdAliasTarget  <- v .:? "aliasTarget"
    pure TypeDecl{..}

instance ToJSON TypeDecl where
  toJSON TypeDecl{..} = object
    [ "name"         .= tdName
    , "kind"         .= tdKind
    , "description"  .= tdDescription
    , "deriving"     .= tdDeriving
    , "fields"       .= tdFields
    , "constructors" .= tdConstructors
    , "wrappedType"  .= tdWrappedType
    , "aliasTarget"  .= tdAliasTarget
    ]

instance FromJSON FunctionDecl where
  parseJSON = withObject "FunctionDecl" $ \v -> do
    fnName        <- v .: "name"
    fnSignature   <- v .: "signature"
    fnDescription <- v .:? "description" .!= ""
    fnPure        <- v .:? "pure"        .!= True
    fnBody        <- v .:? "body"
    pure FunctionDecl{..}

instance ToJSON FunctionDecl where
  toJSON FunctionDecl{..} = object
    [ "name"        .= fnName
    , "signature"   .= fnSignature
    , "description" .= fnDescription
    , "pure"        .= fnPure
    , "body"        .= fnBody
    ]

instance FromJSON IOType where
  parseJSON = withText "IOType" $ \t -> case t of
    "IO"   -> pure IOTypeIO
    "pure" -> pure IOTypePure
    _      -> fail $ "Unknown IOType: " <> T.unpack t

instance ToJSON IOType where
  toJSON IOTypeIO   = String "IO"
  toJSON IOTypePure = String "pure"

instance FromJSON ActionDecl where
  parseJSON = withObject "ActionDecl" $ \v -> do
    adName        <- v .: "name"
    adSignature   <- v .: "signature"
    adDescription <- v .:? "description" .!= ""
    adIoType      <- v .:? "ioType"      .!= IOTypeIO
    adBody        <- v .:? "body"
    pure ActionDecl{..}

instance ToJSON ActionDecl where
  toJSON ActionDecl{..} = object
    [ "name"        .= adName
    , "signature"   .= adSignature
    , "description" .= adDescription
    , "ioType"      .= adIoType
    , "body"        .= adBody
    ]

instance FromJSON ConstraintDecl where
  parseJSON = withObject "ConstraintDecl" $ \v -> do
    conName               <- v .: "name"
    conTargetType         <- v .: "targetType"
    conDescription        <- v .:? "description"        .!= ""
    conPredicateSignature <- v .: "predicateSignature"
    pure ConstraintDecl{..}

instance ToJSON ConstraintDecl where
  toJSON ConstraintDecl{..} = object
    [ "name"               .= conName
    , "targetType"         .= conTargetType
    , "description"        .= conDescription
    , "predicateSignature" .= conPredicateSignature
    ]

instance FromJSON EntryPointDecl where
  parseJSON = withObject "EntryPointDecl" $ \v -> do
    epDescription <- v .:? "description" .!= ""
    epSteps       <- v .:? "steps"       .!= []
    pure EntryPointDecl{..}

instance ToJSON EntryPointDecl where
  toJSON EntryPointDecl{..} = object
    [ "description" .= epDescription
    , "steps"       .= epSteps
    ]

instance FromJSON CodeIR where
  parseJSON = withObject "CodeIR" $ \v -> do
    cirModule      <- v .: "module"
    cirImports     <- v .:? "imports"     .!= []
    cirTypes       <- v .:? "types"       .!= []
    cirFunctions   <- v .:? "functions"   .!= []
    cirActions     <- v .:? "actions"     .!= []
    cirConstraints <- v .:? "constraints" .!= []
    cirEntryPoint  <- v .:? "entryPoint"
    pure CodeIR{..}

instance ToJSON CodeIR where
  toJSON CodeIR{..} = object
    [ "module"      .= cirModule
    , "imports"     .= cirImports
    , "types"       .= cirTypes
    , "functions"   .= cirFunctions
    , "actions"     .= cirActions
    , "constraints" .= cirConstraints
    , "entryPoint"  .= cirEntryPoint
    ]

-- ─── Ambiguity JSON instances ──────────────────────────────────────

instance FromJSON Severity where
  parseJSON = withText "Severity" $ \t -> case t of
    "error"   -> pure SevError
    "warning" -> pure SevWarning
    _         -> fail $ "Unknown Severity: " <> T.unpack t

instance ToJSON Severity where
  toJSON SevError   = String "error"
  toJSON SevWarning = String "warning"

instance FromJSON AmbiguityCategory where
  parseJSON = withText "AmbiguityCategory" $ \t -> case t of
    "type"       -> pure CatType
    "scope"      -> pure CatScope
    "behavior"   -> pure CatBehavior
    "naming"     -> pure CatNaming
    "relation"   -> pure CatRelation
    "constraint" -> pure CatConstraint
    "other"      -> pure CatOther
    _            -> fail $ "Unknown AmbiguityCategory: " <> T.unpack t

instance ToJSON AmbiguityCategory where
  toJSON CatType       = String "type"
  toJSON CatScope      = String "scope"
  toJSON CatBehavior   = String "behavior"
  toJSON CatNaming     = String "naming"
  toJSON CatRelation   = String "relation"
  toJSON CatConstraint = String "constraint"
  toJSON CatOther      = String "other"

instance FromJSON AmbiguityOption where
  parseJSON = withObject "AmbiguityOption" $ \v -> do
    aoLabel       <- v .: "label"
    aoDescription <- v .: "description"
    aoConfidence  <- v .: "confidence"
    pure AmbiguityOption{..}

instance ToJSON AmbiguityOption where
  toJSON AmbiguityOption{..} = object
    [ "label"       .= aoLabel
    , "description" .= aoDescription
    , "confidence"  .= aoConfidence
    ]

instance FromJSON AmbiguityResolution where
  parseJSON = withObject "AmbiguityResolution" $ \v -> do
    arChosen    <- v .: "chosen"
    arRationale <- v .: "rationale"
    pure AmbiguityResolution{..}

instance ToJSON AmbiguityResolution where
  toJSON AmbiguityResolution{..} = object
    [ "chosen"    .= arChosen
    , "rationale" .= arRationale
    ]

instance FromJSON Ambiguity where
  parseJSON = withObject "Ambiguity" $ \v -> do
    ambId          <- v .: "id"
    ambSeverity    <- v .: "severity"
    ambCategory    <- v .: "category"
    ambDescription <- v .: "description"
    ambSourceSpan  <- case parseMaybe (.: "sourceSpan") v of
      Just s  -> Just <$> parseSpan s
      Nothing -> pure Nothing
    ambOptions     <- v .:? "options"    .!= []
    ambResolution  <- v .:? "resolution"
    pure Ambiguity{..}

instance ToJSON Ambiguity where
  toJSON Ambiguity{..} = object
    [ "id"          .= ambId
    , "severity"    .= ambSeverity
    , "category"    .= ambCategory
    , "description" .= ambDescription
    , "sourceSpan"  .= fmap (\(a,b) -> [a,b]) ambSourceSpan
    , "options"     .= ambOptions
    , "resolution"  .= ambResolution
    ]

-- ─── Validation functions ──────────────────────────────────────────

-- | Validate a JSON Value as NarrativeIR, returning a structured error on failure.
-- Applies LLM JSON sanitization (null stripping) before parsing.
validateNarrativeIR :: Value -> Either SoelError NarrativeIR
validateNarrativeIR val = case fromJSON (sanitizeLLMJson val) of
  Success nir -> Right nir
  Error msg   -> Left $ IRValidationError
    ("Invalid Narrative IR: " <> T.pack msg)
    [T.pack msg]

-- | Validate a JSON Value as CodeIR, returning a structured error on failure.
-- Applies LLM JSON sanitization (null stripping) before parsing.
validateCodeIR :: Value -> Either SoelError CodeIR
validateCodeIR val = case fromJSON (sanitizeLLMJson val) of
  Success cir -> Right cir
  Error msg   -> Left $ IRValidationError
    ("Invalid Code IR: " <> T.pack msg)
    [T.pack msg]
