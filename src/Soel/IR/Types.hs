{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Soel.IR.Types
  ( -- * Narrative IR
    NarrativeIR(..)
  , NarrativeMeta(..)
  , NarrativeEntity(..)
  , Mention(..)
  , Attribute(..)
  , EntityAttributes(..)
  , NarrativeEvent(..)
  , EventTrigger(..)
  , Participant(..)
  , EventRelation(..)
  , Modality(..)
  , NarrativeRelationship(..)
  , NarrativeTheme(..)
  , ThemeSupport(..)
  , NarrativeAmbiguity(..)
  , Interpretation(..)
  , NarrativeSegment(..)
    -- * Code IR
  , CodeIR(..)
  , ModuleDecl(..)
  , ImportDecl(..)
  , TypeDecl(..)
  , TypeKind(..)
  , FieldDecl(..)
  , ConstructorDecl(..)
  , FunctionDecl(..)
  , ActionDecl(..)
  , IOType(..)
  , ConstraintDecl(..)
  , EntryPointDecl(..)
    -- * Ambiguity tracking
  , Severity(..)
  , AmbiguityCategory(..)
  , AmbiguityOption(..)
  , AmbiguityResolution(..)
  , Ambiguity(..)
  , AmbiguityResult(..)
    -- * Display helpers
  , severityText
  , categoryText
    -- * Source file
  , SourceFile(..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

-- ─── Narrative IR ──────────────────────────────────────────────────

data NarrativeIR = NarrativeIR
  { nirMeta          :: NarrativeMeta
  , nirEntities      :: [NarrativeEntity]
  , nirEvents        :: [NarrativeEvent]
  , nirRelationships :: [NarrativeRelationship]
  , nirThemes        :: [NarrativeTheme]
  , nirAmbiguities   :: [NarrativeAmbiguity]
  , nirSegments      :: [NarrativeSegment]
  } deriving (Show, Eq, Generic)

data NarrativeMeta = NarrativeMeta
  { nmLanguage         :: Text
  , nmGenreGuess       :: Text
  , nmNarrativePov     :: Text
  , nmTimeframe        :: Text
  , nmGlobalConfidence :: Double
  } deriving (Show, Eq, Generic)

data NarrativeEntity = NarrativeEntity
  { neId            :: Text
  , neType          :: Text
  , neCanonicalName :: Text
  , neAliases       :: [Text]
  , neMentions      :: [Mention]
  , neAttributes    :: EntityAttributes
  } deriving (Show, Eq, Generic)

data Mention = Mention
  { menSpan       :: (Int, Int)
  , menSurface    :: Text
  , menConfidence :: Double
  } deriving (Show, Eq, Generic)

data Attribute = Attribute
  { attrKey          :: Text
  , attrValue        :: Text
  , attrEvidenceSpan :: (Int, Int)
  , attrConfidence   :: Double
  } deriving (Show, Eq, Generic)

data EntityAttributes = EntityAttributes
  { eaStable    :: [Attribute]
  , eaTemporary :: [Attribute]
  } deriving (Show, Eq, Generic)

data NarrativeEvent = NarrativeEvent
  { nevId           :: Text
  , nevEventType    :: Text
  , nevPredicate    :: Text
  , nevTenseAspect  :: Text
  , nevPolarity     :: Text
  , nevTrigger      :: EventTrigger
  , nevParticipants :: [Participant]
  , nevRelations    :: [EventRelation]
  , nevModality     :: Modality
  } deriving (Show, Eq, Generic)

data EventTrigger = EventTrigger
  { etSpan :: (Int, Int)
  , etText :: Text
  } deriving (Show, Eq, Generic)

data Participant = Participant
  { partRole       :: Text
  , partEntityId   :: Text
  , partSpan       :: (Int, Int)
  , partConfidence :: Double
  } deriving (Show, Eq, Generic)

data EventRelation = EventRelation
  { erType          :: Text
  , erTargetEventId :: Text
  , erEvidenceSpan  :: (Int, Int)
  , erConfidence    :: Double
  } deriving (Show, Eq, Generic)

data Modality = Modality
  { modCertainty    :: Double
  , modSource       :: Text
  , modEvidenceSpan :: (Int, Int)
  } deriving (Show, Eq, Generic)

data NarrativeRelationship = NarrativeRelationship
  { nrId             :: Text
  , nrSourceEntityId :: Text
  , nrTargetEntityId :: Text
  , nrRelation       :: Text
  , nrDirectional    :: Bool
  , nrStatus         :: Text
  , nrEvidenceSpan   :: (Int, Int)
  , nrConfidence     :: Double
  } deriving (Show, Eq, Generic)

data NarrativeTheme = NarrativeTheme
  { ntTheme      :: Text
  , ntSupport    :: [ThemeSupport]
  , ntConfidence :: Double
  } deriving (Show, Eq, Generic)

data ThemeSupport = ThemeSupport
  { tsEvidenceSpan :: (Int, Int)
  , tsNote         :: Text
  , tsConfidence   :: Double
  } deriving (Show, Eq, Generic)

data NarrativeAmbiguity = NarrativeAmbiguity
  { naId              :: Text
  , naIssue           :: Text
  , naSpan            :: (Int, Int)
  , naInterpretations :: [Interpretation]
  } deriving (Show, Eq, Generic)

data Interpretation = Interpretation
  { intReading    :: Text
  , intConfidence :: Double
  } deriving (Show, Eq, Generic)

data NarrativeSegment = NarrativeSegment
  { nsId        :: Text
  , nsSpan      :: (Int, Int)
  , nsSummary   :: Text
  , nsKeyEvents :: [Text]
  , nsNotes     :: [Text]
  } deriving (Show, Eq, Generic)

-- ─── Code IR ───────────────────────────────────────────────────────

data CodeIR = CodeIR
  { cirModule      :: ModuleDecl
  , cirImports     :: [ImportDecl]
  , cirTypes       :: [TypeDecl]
  , cirFunctions   :: [FunctionDecl]
  , cirActions     :: [ActionDecl]
  , cirConstraints :: [ConstraintDecl]
  , cirEntryPoint  :: Maybe EntryPointDecl
  } deriving (Show, Eq, Generic)

data ModuleDecl = ModuleDecl
  { mdName        :: Text
  , mdDescription :: Text
  , mdExtensions  :: [Text]
  } deriving (Show, Eq, Generic)

data ImportDecl = ImportDecl
  { idModule    :: Text
  , idQualified :: Maybe Bool
  , idAlias     :: Maybe Text
  , idItems     :: Maybe [Text]
  } deriving (Show, Eq, Generic)

data TypeKind
  = KindRecord
  | KindSum
  | KindNewtype
  | KindAlias
  deriving (Show, Eq, Generic)

data TypeDecl = TypeDecl
  { tdName         :: Text
  , tdKind         :: TypeKind
  , tdDescription  :: Text
  , tdDeriving     :: [Text]
  , tdFields       :: Maybe [FieldDecl]
  , tdConstructors :: Maybe [ConstructorDecl]
  , tdWrappedType  :: Maybe Text
  , tdAliasTarget  :: Maybe Text
  } deriving (Show, Eq, Generic)

data FieldDecl = FieldDecl
  { fdName        :: Text
  , fdType        :: Text
  , fdDescription :: Text
  , fdOptional    :: Bool
  } deriving (Show, Eq, Generic)

data ConstructorDecl = ConstructorDecl
  { cdName   :: Text
  , cdFields :: Maybe [FieldDecl]
  } deriving (Show, Eq, Generic)

data FunctionDecl = FunctionDecl
  { fnName        :: Text
  , fnSignature   :: Text
  , fnDescription :: Text
  , fnPure        :: Bool
  , fnBody        :: Maybe Text
  } deriving (Show, Eq, Generic)

data IOType
  = IOTypeIO
  | IOTypePure
  deriving (Show, Eq, Generic)

data ActionDecl = ActionDecl
  { adName        :: Text
  , adSignature   :: Text
  , adDescription :: Text
  , adIoType      :: IOType
  , adBody        :: Maybe Text
  } deriving (Show, Eq, Generic)

data ConstraintDecl = ConstraintDecl
  { conName               :: Text
  , conTargetType         :: Text
  , conDescription        :: Text
  , conPredicateSignature :: Text
  } deriving (Show, Eq, Generic)

data EntryPointDecl = EntryPointDecl
  { epDescription :: Text
  , epSteps       :: [Text]
  } deriving (Show, Eq, Generic)

-- ─── Ambiguity tracking ────────────────────────────────────────────

data Severity
  = SevError
  | SevWarning
  deriving (Show, Eq, Generic)

data AmbiguityCategory
  = CatType
  | CatScope
  | CatBehavior
  | CatNaming
  | CatRelation
  | CatConstraint
  | CatOther
  deriving (Show, Eq, Generic)

data AmbiguityOption = AmbiguityOption
  { aoLabel       :: Text
  , aoDescription :: Text
  , aoConfidence  :: Double
  } deriving (Show, Eq, Generic)

data AmbiguityResolution = AmbiguityResolution
  { arChosen    :: Text
  , arRationale :: Text
  } deriving (Show, Eq, Generic)

data Ambiguity = Ambiguity
  { ambId          :: Text
  , ambSeverity    :: Severity
  , ambCategory    :: AmbiguityCategory
  , ambDescription :: Text
  , ambSourceSpan  :: Maybe (Int, Int)
  , ambOptions     :: [AmbiguityOption]
  , ambResolution  :: Maybe AmbiguityResolution
  } deriving (Show, Eq, Generic)

data AmbiguityResult = AmbiguityResult
  { arErrors   :: [Ambiguity]
  , arWarnings :: [Ambiguity]
  , arAll      :: [Ambiguity]
  } deriving (Show, Eq)

-- ─── Source file ───────────────────────────────────────────────────

data SourceFile = SourceFile
  { sfPath    :: FilePath
  , sfName    :: Text
  , sfContent :: Text
  , sfHash    :: Text
  } deriving (Show, Eq)

-- ─── Display helpers ─────────────────────────────────────────────

severityText :: Severity -> Text
severityText SevError   = "error"
severityText SevWarning = "warning"

categoryText :: AmbiguityCategory -> Text
categoryText CatType       = "type"
categoryText CatScope      = "scope"
categoryText CatBehavior   = "behavior"
categoryText CatNaming     = "naming"
categoryText CatRelation   = "relation"
categoryText CatConstraint = "constraint"
categoryText CatOther      = "other"
