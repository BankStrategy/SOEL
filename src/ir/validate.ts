import { z } from 'zod';
import { IRValidationError } from '../utils/errors.js';
import type { NarrativeIR, CodeIR } from './types.js';

// ─── Narrative IR Zod Schema ────────────────────────────────────────

const SpanSchema = z.tuple([z.number(), z.number()]);

const NarrativeMetaSchema = z.object({
  language: z.string().default('en'),
  genre_guess: z.string().default('unknown'),
  narrative_pov: z.string().default('unknown'),
  timeframe: z.string().default('unknown'),
  global_confidence: z.number().min(0).max(1).default(0.5),
});

const NarrativeEntitySchema = z.object({
  id: z.string(),
  type: z.string(),
  canonical_name: z.string(),
  aliases: z.array(z.string()).default([]),
  mentions: z.array(z.object({
    span: SpanSchema,
    surface: z.string(),
    confidence: z.number(),
  })).default([]),
  attributes: z.object({
    stable: z.array(z.object({
      key: z.string(),
      value: z.string(),
      evidence_span: SpanSchema,
      confidence: z.number(),
    })).default([]),
    temporary: z.array(z.object({
      key: z.string(),
      value: z.string(),
      evidence_span: SpanSchema,
      confidence: z.number(),
    })).default([]),
  }).default({ stable: [], temporary: [] }),
});

const NarrativeEventSchema = z.object({
  id: z.string(),
  event_type: z.string(),
  predicate: z.string(),
  tense_aspect: z.string().default('unknown'),
  polarity: z.string().default('affirmed'),
  trigger: z.object({
    span: SpanSchema,
    text: z.string(),
  }),
  participants: z.array(z.object({
    role: z.string(),
    entity_id: z.string(),
    span: SpanSchema,
    confidence: z.number(),
  })).default([]),
  relations: z.array(z.object({
    type: z.string(),
    target_event_id: z.string(),
    evidence_span: SpanSchema,
    confidence: z.number(),
  })).default([]),
  modality: z.object({
    certainty: z.number(),
    source: z.string(),
    evidence_span: SpanSchema,
  }).default({ certainty: 0.5, source: 'unknown', evidence_span: [-1, -1] }),
});

const NarrativeRelationshipSchema = z.object({
  id: z.string(),
  source_entity_id: z.string(),
  target_entity_id: z.string(),
  relation: z.string(),
  directional: z.boolean().default(true),
  status: z.string().default('active'),
  evidence_span: SpanSchema,
  confidence: z.number(),
});

const NarrativeThemeSchema = z.object({
  theme: z.string(),
  support: z.array(z.object({
    evidence_span: SpanSchema,
    note: z.string(),
    confidence: z.number(),
  })).default([]),
  confidence: z.number(),
});

const NarrativeAmbiguitySchema = z.object({
  id: z.string(),
  issue: z.string(),
  span: SpanSchema,
  interpretations: z.array(z.object({
    reading: z.string(),
    confidence: z.number(),
  })),
});

const NarrativeSegmentSchema = z.object({
  id: z.string(),
  span: SpanSchema,
  summary: z.string(),
  key_events: z.array(z.string()).default([]),
  notes: z.array(z.string()).default([]),
});

const NarrativeIRSchema = z.object({
  meta: NarrativeMetaSchema,
  entities: z.array(NarrativeEntitySchema).default([]),
  events: z.array(NarrativeEventSchema).default([]),
  relationships: z.array(NarrativeRelationshipSchema).default([]),
  themes: z.array(NarrativeThemeSchema).default([]),
  ambiguities: z.array(NarrativeAmbiguitySchema).default([]),
  segments: z.array(NarrativeSegmentSchema).default([]),
});

// ─── Code IR Zod Schema ────────────────────────────────────────────

const FieldDeclSchema = z.object({
  name: z.string(),
  type: z.string(),
  description: z.string().default(''),
  optional: z.boolean().default(false),
});

const ConstructorDeclSchema = z.object({
  name: z.string(),
  fields: z.array(FieldDeclSchema).optional(),
});

const CodeIRSchema = z.object({
  module: z.object({
    name: z.string(),
    description: z.string().default(''),
    extensions: z.array(z.string()).default([]),
  }),
  imports: z.array(z.object({
    module: z.string(),
    qualified: z.boolean().optional(),
    alias: z.string().optional(),
    items: z.array(z.string()).optional(),
  })).default([]),
  types: z.array(z.object({
    name: z.string(),
    kind: z.enum(['record', 'sum', 'newtype', 'alias']),
    description: z.string().default(''),
    deriving: z.array(z.string()).default([]),
    fields: z.array(FieldDeclSchema).optional(),
    constructors: z.array(ConstructorDeclSchema).optional(),
    wrappedType: z.string().optional(),
    aliasTarget: z.string().optional(),
  })).default([]),
  functions: z.array(z.object({
    name: z.string(),
    signature: z.string(),
    description: z.string().default(''),
    pure: z.boolean().default(true),
    body: z.string().optional(),
  })).default([]),
  actions: z.array(z.object({
    name: z.string(),
    signature: z.string(),
    description: z.string().default(''),
    ioType: z.enum(['IO', 'pure']).default('IO'),
    body: z.string().optional(),
  })).default([]),
  constraints: z.array(z.object({
    name: z.string(),
    targetType: z.string(),
    description: z.string().default(''),
    predicateSignature: z.string(),
  })).default([]),
  entryPoint: z.object({
    description: z.string().default(''),
    steps: z.array(z.string()).default([]),
  }).optional(),
});

// ─── Validation Functions ───────────────────────────────────────────

export function validateNarrativeIR(data: unknown): NarrativeIR {
  const result = NarrativeIRSchema.safeParse(data);
  if (!result.success) {
    const issues = result.error.issues.map(
      (i) => `${i.path.join('.')}: ${i.message}`
    );
    throw new IRValidationError(
      `Invalid Narrative IR: ${issues.length} issues`,
      issues
    );
  }
  return result.data as NarrativeIR;
}

export function validateCodeIR(data: unknown): CodeIR {
  const result = CodeIRSchema.safeParse(data);
  if (!result.success) {
    const issues = result.error.issues.map(
      (i) => `${i.path.join('.')}: ${i.message}`
    );
    throw new IRValidationError(
      `Invalid Code IR: ${issues.length} issues`,
      issues
    );
  }
  return result.data as CodeIR;
}
