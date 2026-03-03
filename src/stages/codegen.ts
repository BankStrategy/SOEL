import type { CodeIR } from '../ir/types.js';
import type { Ambiguity } from '../ir/types.js';
import type { SoelConfig } from '../config.js';
import { llmRequest, extractJSON } from '../llm/openrouter.js';
import { loadPromptWithVars } from '../llm/prompts.js';
import { CodegenError } from '../utils/errors.js';
import { log, spinner } from '../utils/logger.js';

export interface CodegenResult {
  haskellSource: string;
  moduleName: string;
}

export async function generateHaskell(
  codeIR: CodeIR,
  resolvedAmbiguities: Ambiguity[],
  sourceText: string,
  config: SoelConfig
): Promise<CodegenResult> {
  log.stage('Generating Haskell code');

  const resolutions = resolvedAmbiguities
    .filter((a) => a.resolution)
    .map((a) => `- ${a.description}: ${a.resolution!.chosen} (${a.resolution!.rationale})`)
    .join('\n');

  const prompt = loadPromptWithVars('codegen-haskell', {
    CODE_IR: JSON.stringify(codeIR, null, 2),
    RESOLUTIONS: resolutions || 'No ambiguities to resolve.',
    SOURCE_TEXT: sourceText,
    EXTENSIONS: config.haskell.extensions.join(', '),
  });

  const spin = spinner('Generating Haskell source...').start();

  try {
    const raw = await llmRequest({
      apiKey: config.openrouter.apiKey!,
      model: config.openrouter.model,
      messages: [{ role: 'system', content: prompt }],
      temperature: 0.2,
      maxTokens: 16384,
    });

    spin.succeed('Haskell code generated');

    // Extract Haskell code from response and ensure module Main
    const haskellSource = ensureModuleMain(extractHaskell(raw));

    if (!haskellSource.includes('module ') && !haskellSource.includes('main ')) {
      throw new CodegenError('Generated code does not contain a valid Haskell module');
    }

    return {
      haskellSource,
      moduleName: codeIR.module.name,
    };
  } catch (e) {
    spin.fail('Code generation failed');
    if (e instanceof CodegenError) throw e;
    throw new CodegenError(e instanceof Error ? e.message : String(e));
  }
}

function extractHaskell(text: string): string {
  // Try to find Haskell in code fences
  const fenceMatch = text.match(/```(?:haskell)?\s*\n([\s\S]*?)\n```/);
  if (fenceMatch) {
    return fenceMatch[1].trim();
  }

  // If no fences, look for module declaration and take everything from there
  const moduleMatch = text.match(/((?:\{-#[\s\S]*?#-\}\s*)*module\s[\s\S]*)/);
  if (moduleMatch) {
    return moduleMatch[1].trim();
  }

  // Last resort: return everything, trimmed
  return text.trim();
}

/**
 * GHC requires `module Main where` for executables.
 * Replace whatever module name the LLM chose.
 */
function ensureModuleMain(source: string): string {
  return source.replace(/^(module\s+)\S+(\s+where)/m, '$1Main$2');
}
