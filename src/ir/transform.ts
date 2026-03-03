import type { NarrativeIR, CodeIR } from './types.js';
import type { SoelConfig } from '../config.js';
import { llmRequest, extractJSON } from '../llm/openrouter.js';
import { loadPromptWithVars } from '../llm/prompts.js';
import { validateCodeIR } from './validate.js';
import { SemanticEncodingError } from '../utils/errors.js';
import { log, spinner } from '../utils/logger.js';

export async function transformToCodeIR(
  narrativeIR: NarrativeIR,
  sourceText: string,
  config: SoelConfig
): Promise<CodeIR> {
  log.stage('Transforming narrative IR → code IR');

  const prompt = loadPromptWithVars('ir-transform', {
    SOURCE_TEXT: sourceText,
    NARRATIVE_IR: JSON.stringify(narrativeIR, null, 2),
  });

  const spin = spinner('Generating code-oriented IR...').start();

  try {
    const raw = await llmRequest({
      apiKey: config.openrouter.apiKey!,
      model: config.openrouter.model,
      messages: [
        { role: 'system', content: prompt },
      ],
      jsonMode: true,
      temperature: 0.2,
    });

    spin.succeed('Code IR generated');

    const json = extractJSON(raw);
    let parsed: unknown;
    try {
      parsed = JSON.parse(json);
    } catch {
      throw new SemanticEncodingError('Failed to parse transform response as JSON', raw);
    }

    return validateCodeIR(parsed);
  } catch (e) {
    spin.fail('Code IR transformation failed');
    throw e;
  }
}
