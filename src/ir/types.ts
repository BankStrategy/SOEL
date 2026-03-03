/**
 * SOEL Semantic IR — the structured representation bridging
 * natural language narratives and Haskell code generation.
 *
 * Two-layer design:
 *  1. NarrativeIR — output of the semantic encoder (rich narrative semantics)
 *  2. CodeIR — output of the transform pass (code-generation-oriented)
 */

// ─── Narrative IR (from semantic encoder) ───────────────────────────

export interface NarrativeIR {
  meta: NarrativeMeta;
  entities: NarrativeEntity[];
  events: NarrativeEvent[];
  relationships: NarrativeRelationship[];
  themes: NarrativeTheme[];
  ambiguities: NarrativeAmbiguity[];
  segments: NarrativeSegment[];
}

export interface NarrativeMeta {
  language: string;
  genre_guess: string;
  narrative_pov: string;
  timeframe: string;
  global_confidence: number;
}

export interface NarrativeEntity {
  id: string;
  type: string;
  canonical_name: string;
  aliases: string[];
  mentions: Array<{
    span: [number, number];
    surface: string;
    confidence: number;
  }>;
  attributes: {
    stable: Array<{
      key: string;
      value: string;
      evidence_span: [number, number];
      confidence: number;
    }>;
    temporary: Array<{
      key: string;
      value: string;
      evidence_span: [number, number];
      confidence: number;
    }>;
  };
}

export interface NarrativeEvent {
  id: string;
  event_type: string;
  predicate: string;
  tense_aspect: string;
  polarity: string;
  trigger: { span: [number, number]; text: string };
  participants: Array<{
    role: string;
    entity_id: string;
    span: [number, number];
    confidence: number;
  }>;
  relations: Array<{
    type: string;
    target_event_id: string;
    evidence_span: [number, number];
    confidence: number;
  }>;
  modality: {
    certainty: number;
    source: string;
    evidence_span: [number, number];
  };
}

export interface NarrativeRelationship {
  id: string;
  source_entity_id: string;
  target_entity_id: string;
  relation: string;
  directional: boolean;
  status: string;
  evidence_span: [number, number];
  confidence: number;
}

export interface NarrativeTheme {
  theme: string;
  support: Array<{
    evidence_span: [number, number];
    note: string;
    confidence: number;
  }>;
  confidence: number;
}

export interface NarrativeAmbiguity {
  id: string;
  issue: string;
  span: [number, number];
  interpretations: Array<{
    reading: string;
    confidence: number;
  }>;
}

export interface NarrativeSegment {
  id: string;
  span: [number, number];
  summary: string;
  key_events: string[];
  notes: string[];
}

// ─── Code IR (for Haskell generation) ───────────────────────────────

export interface CodeIR {
  module: ModuleDecl;
  imports: ImportDecl[];
  types: TypeDecl[];
  functions: FunctionDecl[];
  actions: ActionDecl[];
  constraints: ConstraintDecl[];
  entryPoint?: EntryPointDecl;
}

export interface ModuleDecl {
  name: string;
  description: string;
  extensions: string[];
}

export interface ImportDecl {
  module: string;
  qualified?: boolean;
  alias?: string;
  items?: string[];
}

export interface TypeDecl {
  name: string;
  kind: 'record' | 'sum' | 'newtype' | 'alias';
  description: string;
  deriving: string[];
  fields?: FieldDecl[];
  constructors?: ConstructorDecl[];
  wrappedType?: string;
  aliasTarget?: string;
}

export interface FieldDecl {
  name: string;
  type: string;
  description: string;
  optional: boolean;
}

export interface ConstructorDecl {
  name: string;
  fields?: FieldDecl[];
}

export interface FunctionDecl {
  name: string;
  signature: string;
  description: string;
  pure: boolean;
  body?: string;
}

export interface ActionDecl {
  name: string;
  signature: string;
  description: string;
  ioType: 'IO' | 'pure';
  body?: string;
}

export interface ConstraintDecl {
  name: string;
  targetType: string;
  description: string;
  predicateSignature: string;
}

export interface EntryPointDecl {
  description: string;
  steps: string[];
}

// ─── Ambiguity tracking (shared) ────────────────────────────────────

export type AmbiguitySeverity = 'error' | 'warning';

export interface Ambiguity {
  id: string;
  severity: AmbiguitySeverity;
  category: 'type' | 'scope' | 'behavior' | 'naming' | 'relation' | 'constraint' | 'other';
  description: string;
  sourceSpan?: [number, number];
  options: Array<{
    label: string;
    description: string;
    confidence: number;
  }>;
  resolution?: {
    chosen: string;
    rationale: string;
  };
}
