import type { NarrativeIR, CodeIR } from '../ir/types.js';
import type { Ambiguity, AmbiguitySeverity } from '../ir/types.js';
import type { SoelConfig } from '../config.js';
import { SemanticAmbiguityError } from '../utils/errors.js';
import { log, formatDiagnostic } from '../utils/logger.js';

export interface AmbiguityResult {
  errors: Ambiguity[];
  warnings: Ambiguity[];
  all: Ambiguity[];
}

/**
 * Detect ambiguities from the Narrative IR and Code IR.
 * Classifies each as error (blocks compilation) or warning (informational).
 */
export function detectAmbiguities(
  narrativeIR: NarrativeIR,
  codeIR: CodeIR,
  config: SoelConfig
): AmbiguityResult {
  const threshold = config.compiler.ambiguityThreshold;
  const ambiguities: Ambiguity[] = [];
  let idx = 1;

  // 1. Low-confidence entities → naming/type ambiguity
  for (const entity of narrativeIR.entities) {
    const lowConf = entity.mentions.filter((m) => m.confidence < threshold);
    if (lowConf.length > 0) {
      const maxConf = Math.max(...lowConf.map((m) => m.confidence));
      ambiguities.push({
        id: `S${String(idx++).padStart(3, '0')}`,
        severity: maxConf < threshold * 0.5 ? 'error' : 'warning',
        category: 'naming',
        description: `Ambiguous entity "${entity.canonical_name}" — semantic encoder cannot confidently resolve this concept`,
        sourceSpan: lowConf[0].span,
        options: [
          {
            label: `Keep as "${entity.canonical_name}"`,
            description: 'Use the name as-is for the Haskell type',
            confidence: 0.6,
          },
          {
            label: 'Rename / clarify',
            description: 'Provide a clearer name for this concept',
            confidence: 0.4,
          },
        ],
      });
    }
  }

  // 2. Conflicting relationships → always error
  const relMap = new Map<string, typeof narrativeIR.relationships>();
  for (const rel of narrativeIR.relationships) {
    const key = `${rel.source_entity_id}-${rel.target_entity_id}`;
    const existing = relMap.get(key) ?? [];
    existing.push(rel);
    relMap.set(key, existing);
  }
  for (const [key, rels] of relMap) {
    if (rels.length > 1) {
      const names = rels.map((r) => `"${r.relation}"`);
      ambiguities.push({
        id: `S${String(idx++).padStart(3, '0')}`,
        severity: 'error',
        category: 'relation',
        description: `Conflicting relations between ${key}: ${names.join(' vs ')}`,
        sourceSpan: rels[0].evidence_span,
        options: rels.map((r) => ({
          label: r.relation,
          description: `Use "${r.relation}" relationship`,
          confidence: r.confidence,
        })),
      });
    }
  }

  // 3. Narrative-level ambiguities from the encoder
  for (const amb of narrativeIR.ambiguities) {
    const maxConf = Math.max(...amb.interpretations.map((i) => i.confidence), 0);
    const spread = amb.interpretations.length > 1
      ? Math.abs(amb.interpretations[0].confidence - amb.interpretations[1].confidence)
      : 1;
    // Error if top interpretations are too close in confidence (genuine ambiguity)
    // or if even the best reading is low confidence
    const sev: AmbiguitySeverity = (spread < 0.2 || maxConf < threshold) ? 'error' : 'warning';

    ambiguities.push({
      id: `S${String(idx++).padStart(3, '0')}`,
      severity: sev,
      category: mapIssueCategory(amb.issue),
      description: amb.issue,
      sourceSpan: amb.span,
      options: amb.interpretations.map((interp) => ({
        label: interp.reading.slice(0, 80),
        description: interp.reading,
        confidence: interp.confidence,
      })),
    });
  }

  // 4. Missing entry point → error
  if (!codeIR.entryPoint) {
    ambiguities.push({
      id: `S${String(idx++).padStart(3, '0')}`,
      severity: 'error',
      category: 'behavior',
      description: 'No entry point: program has no discernible main behavior',
      options: [
        {
          label: 'Interactive CLI',
          description: 'Run as an interactive command-line program',
          confidence: 0.3,
        },
        {
          label: 'Print demo',
          description: 'Print a demonstration of the defined types and functions',
          confidence: 0.5,
        },
        {
          label: 'Custom',
          description: 'Let me describe the entry point',
          confidence: 0.2,
        },
      ],
    });
  }

  // 5. Low-confidence events → severity depends on how uncertain
  for (const event of narrativeIR.events) {
    if (event.modality.certainty < threshold) {
      ambiguities.push({
        id: `S${String(idx++).padStart(3, '0')}`,
        severity: event.modality.certainty < threshold * 0.5 ? 'error' : 'warning',
        category: 'behavior',
        description: `Uncertain semantics for "${event.predicate}" — cannot determine intended behavior`,
        sourceSpan: event.trigger.span,
        options: [
          {
            label: 'Keep as described',
            description: `Implement "${event.predicate}" as the encoder understood it`,
            confidence: event.modality.certainty,
          },
          {
            label: 'Clarify behavior',
            description: 'Provide more details about what this should do',
            confidence: 1 - event.modality.certainty,
          },
        ],
      });
    }
  }

  const errors = ambiguities.filter((a) => a.severity === 'error');
  const warnings = ambiguities.filter((a) => a.severity === 'warning');

  if (errors.length > 0) {
    log.info(`${errors.length} semantic error(s), ${warnings.length} warning(s)`);
  } else if (warnings.length > 0) {
    log.info(`${warnings.length} semantic warning(s)`);
  }

  return { errors, warnings, all: ambiguities };
}

/**
 * Emit diagnostics to stderr and throw if there are unresolved errors.
 * This is the "strict" path — ambiguities are compiler errors.
 */
export function emitDiagnostics(
  result: AmbiguityResult,
  filePath: string,
  sourceText: string
): void {
  for (const amb of result.all) {
    console.error(formatDiagnostic({
      file: filePath,
      severity: amb.severity,
      id: amb.id,
      category: amb.category,
      message: amb.description,
      span: amb.sourceSpan,
      sourceText,
      options: amb.options,
    }));
  }

  if (result.errors.length > 0) {
    const summary = `Compilation failed: ${result.errors.length} semantic error(s), ${result.warnings.length} warning(s)`;
    throw new SemanticAmbiguityError(summary, '');
  }
}

function mapIssueCategory(issue: string): Ambiguity['category'] {
  if (issue.includes('type') || issue.includes('kind')) return 'type';
  if (issue.includes('scope')) return 'scope';
  if (issue.includes('name') || issue.includes('coref')) return 'naming';
  if (issue.includes('relation') || issue.includes('causal')) return 'relation';
  if (issue.includes('constrain') || issue.includes('rule')) return 'constraint';
  return 'other';
}
