import type { NarrativeIR } from '../ir/types.js';
import type { SoelConfig } from '../config.js';
import { llmRequest, extractJSON } from '../llm/openrouter.js';
import { loadPrompt } from '../llm/prompts.js';
import { validateNarrativeIR } from '../ir/validate.js';
import { SemanticEncodingError } from '../utils/errors.js';
import { log, spinner } from '../utils/logger.js';

export async function semanticEncode(
  source: string,
  config: SoelConfig
): Promise<NarrativeIR> {
  const mode = config.compiler.encoderMode;
  const promptName = mode === 'fast' ? 'semantic-encoder-fast' : 'semantic-encoder-full';

  log.stage(`Semantic encoding (${mode} mode)`);

  const systemPrompt = loadPrompt(promptName);

  // Replace the placeholder in the prompt template
  const userContent = source;

  const spin = spinner('Encoding narrative semantics...').start();

  try {
    const raw = await llmRequest({
      apiKey: config.openrouter.apiKey!,
      model: config.openrouter.model,
      messages: [
        { role: 'system', content: systemPrompt.replace('<NARRATIVE_SCRIPT>', '') },
        { role: 'user', content: userContent },
      ],
      jsonMode: true,
      temperature: 0.2,
    });

    spin.succeed('Semantic encoding complete');

    const json = extractJSON(raw);
    let parsed: unknown;
    try {
      parsed = JSON.parse(json);
    } catch {
      throw new SemanticEncodingError('Failed to parse encoder response as JSON', raw);
    }

    // The fast encoder has a slightly different shape — normalize it
    if (mode === 'fast') {
      parsed = normalizeFastIR(parsed as Record<string, unknown>);
    }

    return validateNarrativeIR(parsed);
  } catch (e) {
    spin.fail('Semantic encoding failed');
    if (e instanceof SemanticEncodingError) throw e;
    // Include validation details in the error message
    const msg = e instanceof Error ? e.message : String(e);
    const details = (e as any)?.issues ? `\n  ${(e as any).issues.join('\n  ')}` : '';
    throw new SemanticEncodingError(msg + details);
  }
}

/**
 * Normalize the fast encoder's compact format to the full NarrativeIR shape.
 */
function normalizeFastIR(data: Record<string, unknown>): Record<string, unknown> {
  const meta = data.meta as Record<string, unknown> | undefined;
  const normalizedMeta = {
    language: meta?.language ?? 'en',
    genre_guess: 'unknown',
    narrative_pov: meta?.pov ?? 'unknown',
    timeframe: 'unknown',
    global_confidence: (meta?.global_sentiment as Record<string, unknown>)?.confidence ?? 0.5,
  };

  // Normalize entities
  const rawEntities = (data.entities ?? []) as Array<Record<string, unknown>>;
  const entities = rawEntities.map((e) => ({
    id: e.id,
    type: e.type,
    canonical_name: e.name ?? e.canonical_name,
    aliases: e.aliases ?? [],
    mentions: [],
    attributes: { stable: [], temporary: [] },
  }));

  // Normalize events
  const rawEvents = (data.events ?? []) as Array<Record<string, unknown>>;
  const events = rawEvents.map((ev) => ({
    id: ev.id,
    event_type: 'action',
    predicate: ev.pred ?? ev.predicate,
    tense_aspect: ev.time ?? ev.tense_aspect ?? 'unknown',
    polarity: ev.polarity ?? 'affirmed',
    trigger: ev.trigger_span
      ? { span: ev.trigger_span, text: '' }
      : ev.trigger ?? { span: [-1, -1], text: '' },
    participants: ((ev.roles ?? ev.participants ?? []) as Array<Record<string, unknown>>).map((r) => ({
      role: r.role,
      entity_id: r.entity ?? r.entity_id,
      span: r.evidence_span ?? r.span ?? [-1, -1],
      confidence: r.confidence ?? 0.5,
    })),
    relations: ((ev.links ?? ev.relations ?? []) as Array<Record<string, unknown>>).map((l) => ({
      type: l.type,
      target_event_id: l.target ?? l.target_event_id,
      evidence_span: l.evidence_span ?? [-1, -1],
      confidence: l.confidence ?? 0.5,
    })),
    modality: { certainty: 0.5, source: 'unknown', evidence_span: [-1, -1] as [number, number] },
  }));

  // Normalize relationships (from relations.social)
  const rawRelations = data.relations as Record<string, unknown> | undefined;
  const socialRels = (rawRelations?.social ?? []) as Array<Record<string, unknown>>;
  const relationships = socialRels.map((r, i) => ({
    id: `R${i + 1}`,
    source_entity_id: r.a,
    target_entity_id: r.b,
    relation: r.type,
    directional: true,
    status: 'active',
    evidence_span: r.evidence_span ?? [-1, -1],
    confidence: r.confidence ?? 0.5,
  }));

  // Themes
  const rawThemes = (data.themes ?? []) as Array<Record<string, unknown>>;
  const themes = rawThemes.map((t) => ({
    theme: t.label ?? t.theme,
    support: ((t.evidence_spans ?? []) as Array<[number, number]>).map((s) => ({
      evidence_span: s,
      note: '',
      confidence: t.confidence as number ?? 0.5,
    })),
    confidence: t.confidence as number ?? 0.5,
  }));

  // Ambiguities (from high_uncertainty)
  const rawAmb = (data.high_uncertainty ?? data.ambiguities ?? []) as Array<Record<string, unknown>>;
  const ambiguities = rawAmb.map((a, i) => ({
    id: (a.id as string) ?? `A${i + 1}`,
    issue: a.issue ?? 'other',
    span: a.span ?? [-1, -1],
    interpretations: (a.options ?? a.interpretations ?? []) as Array<{
      reading: string;
      confidence: number;
    }>,
  }));

  return {
    meta: normalizedMeta,
    entities,
    events,
    relationships,
    themes,
    ambiguities,
    segments: [],
  };
}
