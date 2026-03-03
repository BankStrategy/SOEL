import { readFileSync, writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { resolve, basename } from 'node:path';
import chalk from 'chalk';
import type { SoelConfig } from '../config.js';
import { llmRequest, extractJSON } from '../llm/openrouter.js';
import { loadPrompt } from '../llm/prompts.js';
import { readSource } from './reader.js';
import { semanticEncode } from './semantic-encoder.js';
import { transformToCodeIR } from '../ir/transform.js';
import { detectAmbiguities } from './ambiguity-detector.js';
import { autoResolveAll } from './dialog.js';
import { generateHaskell } from './codegen.js';
import { writeHaskell } from './writer.js';
import { ghcCompile, ghcRun } from './ghc.js';
import { GHCError } from '../utils/errors.js';
import { log, spinner } from '../utils/logger.js';

interface RepairResult {
  diagnosis: string;
  root_cause: string;
  fix_type: string;
  fixed_code: string;
  explanation: string;
  soel_suggestion?: string;
}

export async function repairLoop(
  filePath: string,
  config: SoelConfig
): Promise<void> {
  log.stage('Pragmatic repair mode');

  const source = readSource(filePath);
  const hsPath = source.path.replace(/\.soel$/, '.hs');

  // First, do a full compile
  console.error(chalk.dim('\n  Performing initial compilation...\n'));

  const narrativeIR = await semanticEncode(source.content, config);
  const codeIR = await transformToCodeIR(narrativeIR, source.content, config);
  const ambResult = detectAmbiguities(narrativeIR, codeIR, config);
  const resolved = autoResolveAll(ambResult.all);
  let { haskellSource } = await generateHaskell(codeIR, resolved, source.content, config);

  writeHaskell(haskellSource, { sourcePath: source.path, outputPath: hsPath });

  const rl = createInterface({
    input: process.stdin,
    output: process.stderr,
  });
  const ask = (prompt: string): Promise<string> =>
    new Promise((resolve) => rl.question(prompt, resolve));

  const maxRounds = 5;
  let round = 0;

  while (round < maxRounds) {
    round++;
    console.error(chalk.cyan(`\n─── Repair round ${round}/${maxRounds} ───\n`));

    try {
      const result = await ghcCompile(hsPath, config);
      await ghcRun(result.executablePath);

      log.success('Program compiled and ran successfully!');
      rl.close();
      return;
    } catch (e) {
      if (!(e instanceof GHCError)) throw e;

      console.error(chalk.red('\n  GHC Error:'));
      console.error(chalk.dim(e.stderr.split('\n').map((l) => `    ${l}`).join('\n')));

      // Ask LLM to repair
      const spin = spinner('Analyzing error and generating fix...').start();

      try {
        const systemPrompt = loadPrompt('pragmatic-repair');
        const raw = await llmRequest({
          apiKey: config.openrouter.apiKey!,
          model: config.openrouter.model,
          messages: [
            { role: 'system', content: systemPrompt },
            {
              role: 'user',
              content: JSON.stringify({
                soel_source: source.content,
                haskell_code: haskellSource,
                ghc_error: e.stderr,
                code_ir: codeIR,
              }),
            },
          ],
          temperature: 0.2,
          maxTokens: 16384,
        });

        const json = extractJSON(raw);
        const repair = JSON.parse(json) as RepairResult;

        spin.succeed('Fix generated');

        console.error(chalk.yellow(`\n  Diagnosis: ${repair.diagnosis}`));
        console.error(chalk.white(`  Fix: ${repair.explanation}`));

        if (repair.soel_suggestion) {
          console.error(chalk.dim(`\n  SOEL suggestion: ${repair.soel_suggestion}`));
        }

        const answer = await ask(chalk.green('\n  Apply fix? [Y/n] '));

        if (answer.trim().toLowerCase() !== 'n') {
          haskellSource = repair.fixed_code;
          writeHaskell(haskellSource, { sourcePath: source.path, outputPath: hsPath });
          log.info('Fix applied, retrying...');
        } else {
          log.info('Fix skipped');
          const custom = await ask(chalk.green('  Describe the issue or press Enter to retry: '));
          if (custom.trim()) {
            // Send custom feedback to LLM in next round
            console.error(chalk.dim(`  Will incorporate: "${custom}"`));
          }
        }
      } catch (repairErr) {
        spin.fail('Repair analysis failed');
        console.error(chalk.red(`  ${repairErr}`));
      }
    }
  }

  log.warn(`Max repair rounds (${maxRounds}) reached`);
  rl.close();
}
