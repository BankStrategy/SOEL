import { createInterface } from 'node:readline';
import chalk from 'chalk';
import type { Ambiguity } from '../ir/types.js';
import type { SoelConfig } from '../config.js';
import { llmRequest, extractJSON } from '../llm/openrouter.js';
import { loadPrompt } from '../llm/prompts.js';
import { log } from '../utils/logger.js';

/**
 * Interactive dialog loop to resolve ambiguities with the user.
 * Returns resolved ambiguities with user's choices.
 */
export async function resolveAmbiguities(
  ambiguities: Ambiguity[],
  sourceText: string,
  config: SoelConfig
): Promise<Ambiguity[]> {
  if (ambiguities.length === 0) {
    log.info('No ambiguities to resolve');
    return ambiguities;
  }

  log.stage('Dialogical ambiguity resolution');
  console.error(
    chalk.dim(`\n  ${ambiguities.length} ambiguities need resolution. `) +
    chalk.dim(`(max ${config.compiler.maxDialogRounds} rounds)\n`)
  );

  const rl = createInterface({
    input: process.stdin,
    output: process.stderr,
  });

  const ask = (prompt: string): Promise<string> =>
    new Promise((resolve) => rl.question(prompt, resolve));

  const resolved: Ambiguity[] = [];
  let round = 0;

  for (const amb of ambiguities) {
    if (round >= config.compiler.maxDialogRounds) {
      log.warn(`Max dialog rounds (${config.compiler.maxDialogRounds}) reached, auto-resolving remaining`);
      // Auto-resolve remaining with highest confidence option
      resolved.push(autoResolve(amb));
      continue;
    }

    round++;
    console.error(chalk.yellow(`\n─── Ambiguity ${amb.id} [${amb.category}] ───`));
    console.error(chalk.white(`  ${amb.description}\n`));

    // Show options
    for (let i = 0; i < amb.options.length; i++) {
      const opt = amb.options[i];
      const conf = chalk.dim(`(${(opt.confidence * 100).toFixed(0)}%)`);
      console.error(`  ${chalk.cyan(`${i + 1})`)} ${opt.label} ${conf}`);
      if (opt.description !== opt.label) {
        console.error(chalk.dim(`     ${opt.description}`));
      }
    }
    console.error(`  ${chalk.cyan(`${amb.options.length + 1})`)} ${chalk.italic('Custom response...')}`);

    const answer = await ask(chalk.green('\n  Your choice: '));
    const choice = parseInt(answer.trim(), 10);

    if (choice >= 1 && choice <= amb.options.length) {
      const chosen = amb.options[choice - 1];
      resolved.push({
        ...amb,
        resolution: {
          chosen: chosen.label,
          rationale: `User selected: ${chosen.description}`,
        },
      });
      console.error(chalk.green(`  ✓ Resolved: ${chosen.label}`));
    } else if (choice === amb.options.length + 1 || isNaN(choice)) {
      // Custom response — use LLM to interpret
      const customInput = isNaN(choice)
        ? answer.trim()
        : await ask(chalk.green('  Describe your preference: '));

      if (customInput.trim()) {
        const interpretation = await interpretCustomResponse(
          amb,
          customInput,
          sourceText,
          config
        );
        resolved.push({
          ...amb,
          resolution: {
            chosen: interpretation,
            rationale: `User provided custom input: "${customInput}"`,
          },
        });
        console.error(chalk.green(`  ✓ Resolved: ${interpretation}`));
      } else {
        resolved.push(autoResolve(amb));
        console.error(chalk.dim(`  → Auto-resolved with highest confidence option`));
      }
    } else {
      resolved.push(autoResolve(amb));
      console.error(chalk.dim(`  → Auto-resolved with highest confidence option`));
    }
  }

  rl.close();
  log.success(`Resolved ${resolved.filter((a) => a.resolution).length}/${ambiguities.length} ambiguities`);
  return resolved;
}

function autoResolve(amb: Ambiguity): Ambiguity {
  const best = amb.options.reduce((a, b) =>
    a.confidence >= b.confidence ? a : b
  );
  return {
    ...amb,
    resolution: {
      chosen: best.label,
      rationale: `Auto-resolved: highest confidence option (${(best.confidence * 100).toFixed(0)}%)`,
    },
  };
}

async function interpretCustomResponse(
  amb: Ambiguity,
  userInput: string,
  sourceText: string,
  config: SoelConfig
): Promise<string> {
  try {
    const systemPrompt = loadPrompt('ambiguity-resolver');
    const raw = await llmRequest({
      apiKey: config.openrouter.apiKey!,
      model: config.openrouter.model,
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: JSON.stringify({
            ambiguity: amb,
            user_response: userInput,
            source_context: sourceText.slice(0, 2000),
          }),
        },
      ],
      temperature: 0.2,
      maxTokens: 512,
    });

    const json = extractJSON(raw);
    const parsed = JSON.parse(json) as { interpretation: string };
    return parsed.interpretation ?? userInput;
  } catch {
    return userInput;
  }
}

/**
 * Auto-resolve all ambiguities without user interaction.
 */
export function autoResolveAll(ambiguities: Ambiguity[]): Ambiguity[] {
  return ambiguities.map(autoResolve);
}
