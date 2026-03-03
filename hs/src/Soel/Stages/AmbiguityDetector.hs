{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Soel.Stages.AmbiguityDetector
  ( detectAmbiguities
  , emitDiagnostics
  , mapIssueCategory
  ) where

import Control.Monad (unless)
import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.IO (stderr)

import Soel.Types (App, SoelError(..), SoelConfig(..))
import Soel.Config (CompilerConfig(..))
import Soel.IR.Types
import Soel.Utils.Logger (logInfo, formatDiagnostic, DiagnosticOpts(..))

-- | Detect ambiguities from the Narrative IR and Code IR.
-- Classifies each as error (blocks compilation) or warning (informational).
detectAmbiguities :: NarrativeIR -> CodeIR -> App AmbiguityResult
detectAmbiguities nir cir = do
  cfg <- ask
  let threshold = ccAmbiguityThreshold (cfgCompiler cfg)

      (a1, idx1) = detectLowConfidenceEntities threshold (nirEntities nir) 1
      (a2, idx2) = detectConflictingRelations (nirRelationships nir) idx1
      (a3, idx3) = detectNarrativeAmbiguities threshold (nirAmbiguities nir) idx2
      (a4, idx4) = detectMissingEntryPoint (cirEntryPoint cir) idx3
      (a5, _)    = detectLowConfidenceEvents threshold (nirEvents nir) idx4

      allAmbs  = a1 ++ a2 ++ a3 ++ a4 ++ a5
      errors   = filter (\a -> ambSeverity a == SevError) allAmbs
      warnings = filter (\a -> ambSeverity a == SevWarning) allAmbs

  unless (null errors) $
    liftIO $ logInfo $ T.pack (show (length errors)) <> " semantic error(s), "
                    <> T.pack (show (length warnings)) <> " warning(s)"

  unless (not (null errors) || null warnings) $
    liftIO $ logInfo $ T.pack (show (length warnings)) <> " semantic warning(s)"

  pure AmbiguityResult
    { arErrors   = errors
    , arWarnings = warnings
    , arAll      = allAmbs
    }

-- ─── Pure detection functions ─────────────────────────────────────

mkId :: Int -> Text
mkId i = "S" <> T.justifyRight 3 '0' (T.pack (show i))

-- | Detect low-confidence entity mentions.
detectLowConfidenceEntities :: Double -> [NarrativeEntity] -> Int -> ([Ambiguity], Int)
detectLowConfidenceEntities threshold entities startIdx =
  foldr go ([], startIdx) entities
  where
    go entity (acc, idx) =
      let lowConf = filter (\m -> menConfidence m < threshold) (neMentions entity)
      in if null lowConf
         then (acc, idx)
         else
           let maxConf   = maximum (map menConfidence lowConf)
               sev       = if maxConf < threshold * 0.5 then SevError else SevWarning
               firstSpan = menSpan (head lowConf)
               amb = Ambiguity
                 { ambId          = mkId idx
                 , ambSeverity    = sev
                 , ambCategory    = CatNaming
                 , ambDescription = "Ambiguous entity \"" <> neCanonicalName entity
                                 <> "\" -- semantic encoder cannot confidently resolve this concept"
                 , ambSourceSpan  = Just firstSpan
                 , ambOptions     =
                     [ AmbiguityOption
                         { aoLabel       = "Keep as \"" <> neCanonicalName entity <> "\""
                         , aoDescription = "Use the name as-is for the Haskell type"
                         , aoConfidence  = 0.6
                         }
                     , AmbiguityOption
                         { aoLabel       = "Rename / clarify"
                         , aoDescription = "Provide a clearer name for this concept"
                         , aoConfidence  = 0.4
                         }
                     ]
                 , ambResolution  = Nothing
                 }
           in (amb : acc, idx + 1)

-- | Detect conflicting relationships (multiple rels between same entity pair).
detectConflictingRelations :: [NarrativeRelationship] -> Int -> ([Ambiguity], Int)
detectConflictingRelations rels startIdx =
  let relMap :: Map (Text, Text) [NarrativeRelationship]
      relMap = Map.fromListWith (++)
        [ ((nrSourceEntityId r, nrTargetEntityId r), [r]) | r <- rels ]
      conflicts = filter (\(_, rs) -> length rs > 1) (Map.toList relMap)
  in foldr go ([], startIdx) conflicts
  where
    go (key, rs) (acc, idx) =
      let names  = map (\r -> "\"" <> nrRelation r <> "\"") rs
          keyStr = fst key <> "-" <> snd key
          amb = Ambiguity
            { ambId          = mkId idx
            , ambSeverity    = SevError
            , ambCategory    = CatRelation
            , ambDescription = "Conflicting relations between " <> keyStr <> ": "
                            <> T.intercalate " vs " names
            , ambSourceSpan  = Just (nrEvidenceSpan (head rs))
            , ambOptions     = map (\r -> AmbiguityOption
                { aoLabel       = nrRelation r
                , aoDescription = "Use \"" <> nrRelation r <> "\" relationship"
                , aoConfidence  = nrConfidence r
                }) rs
            , ambResolution  = Nothing
            }
      in (amb : acc, idx + 1)

-- | Detect narrative-level ambiguities from the encoder.
detectNarrativeAmbiguities :: Double -> [NarrativeAmbiguity] -> Int -> ([Ambiguity], Int)
detectNarrativeAmbiguities threshold narAmbs startIdx =
  foldr go ([], startIdx) narAmbs
  where
    go na (acc, idx) =
      let interps = naInterpretations na
          maxConf = if null interps then 0.0
                    else maximum (map intConfidence interps)
          spread  = if length interps > 1
                    then abs (intConfidence (head interps) - intConfidence (interps !! 1))
                    else 1.0
          sev = if spread < 0.2 || maxConf < threshold then SevError else SevWarning
          amb = Ambiguity
            { ambId          = mkId idx
            , ambSeverity    = sev
            , ambCategory    = mapIssueCategory (naIssue na)
            , ambDescription = naIssue na
            , ambSourceSpan  = Just (naSpan na)
            , ambOptions     = map (\interp -> AmbiguityOption
                { aoLabel       = T.take 80 (intReading interp)
                , aoDescription = intReading interp
                , aoConfidence  = intConfidence interp
                }) interps
            , ambResolution  = Nothing
            }
      in (amb : acc, idx + 1)

-- | Detect missing entry point.
detectMissingEntryPoint :: Maybe EntryPointDecl -> Int -> ([Ambiguity], Int)
detectMissingEntryPoint (Just _) idx = ([], idx)
detectMissingEntryPoint Nothing  idx =
  ( [ Ambiguity
      { ambId          = mkId idx
      , ambSeverity    = SevError
      , ambCategory    = CatBehavior
      , ambDescription = "No entry point: program has no discernible main behavior"
      , ambSourceSpan  = Nothing
      , ambOptions     =
          [ AmbiguityOption
              { aoLabel       = "Interactive CLI"
              , aoDescription = "Run as an interactive command-line program"
              , aoConfidence  = 0.3
              }
          , AmbiguityOption
              { aoLabel       = "Print demo"
              , aoDescription = "Print a demonstration of the defined types and functions"
              , aoConfidence  = 0.5
              }
          , AmbiguityOption
              { aoLabel       = "Custom"
              , aoDescription = "Let me describe the entry point"
              , aoConfidence  = 0.2
              }
          ]
      , ambResolution  = Nothing
      }
    ]
  , idx + 1
  )

-- | Detect low-confidence events.
detectLowConfidenceEvents :: Double -> [NarrativeEvent] -> Int -> ([Ambiguity], Int)
detectLowConfidenceEvents threshold events startIdx =
  foldr go ([], startIdx) events
  where
    go event (acc, idx) =
      let cert = modCertainty (nevModality event)
      in if cert >= threshold
         then (acc, idx)
         else
           let sev = if cert < threshold * 0.5 then SevError else SevWarning
               amb = Ambiguity
                 { ambId          = mkId idx
                 , ambSeverity    = sev
                 , ambCategory    = CatBehavior
                 , ambDescription = "Uncertain semantics for \"" <> nevPredicate event
                                 <> "\" -- cannot determine intended behavior"
                 , ambSourceSpan  = Just (etSpan (nevTrigger event))
                 , ambOptions     =
                     [ AmbiguityOption
                         { aoLabel       = "Keep as described"
                         , aoDescription = "Implement \"" <> nevPredicate event
                                        <> "\" as the encoder understood it"
                         , aoConfidence  = cert
                         }
                     , AmbiguityOption
                         { aoLabel       = "Clarify behavior"
                         , aoDescription = "Provide more details about what this should do"
                         , aoConfidence  = 1 - cert
                         }
                     ]
                 , ambResolution  = Nothing
                 }
           in (amb : acc, idx + 1)

-- | Emit diagnostics to stderr and throw if there are unresolved errors.
emitDiagnostics :: AmbiguityResult -> FilePath -> Text -> App ()
emitDiagnostics result filePath sourceText = do
  liftIO $ mapM_ (\amb -> TIO.hPutStr stderr $ formatDiagnostic $ ambiguityDiag filePath sourceText amb)
    (arAll result)

  unless (null (arErrors result)) $
    throwError $ SemanticAmbiguityError $
      "Compilation failed: " <> T.pack (show (length (arErrors result)))
      <> " semantic error(s), " <> T.pack (show (length (arWarnings result)))
      <> " warning(s)"

-- | Build diagnostic options from an ambiguity.
ambiguityDiag :: FilePath -> Text -> Ambiguity -> DiagnosticOpts
ambiguityDiag fp sourceText amb = DiagnosticOpts
  { diagFile       = fp
  , diagSeverity   = severityText (ambSeverity amb)
  , diagId         = ambId amb
  , diagCategory   = categoryText (ambCategory amb)
  , diagMessage    = ambDescription amb
  , diagSpan       = ambSourceSpan amb
  , diagSourceText = Just sourceText
  , diagOptions    = map (\o -> (aoLabel o, aoConfidence o)) (ambOptions amb)
  }

-- | Map issue text to an ambiguity category.
mapIssueCategory :: Text -> AmbiguityCategory
mapIssueCategory issue
  | T.isInfixOf "type" issue || T.isInfixOf "kind" issue = CatType
  | T.isInfixOf "scope" issue                             = CatScope
  | T.isInfixOf "name" issue || T.isInfixOf "coref" issue = CatNaming
  | T.isInfixOf "relation" issue || T.isInfixOf "causal" issue = CatRelation
  | T.isInfixOf "constrain" issue || T.isInfixOf "rule" issue  = CatConstraint
  | otherwise                                              = CatOther
