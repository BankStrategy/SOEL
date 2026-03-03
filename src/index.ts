#!/usr/bin/env node

import { Command } from 'commander';
import { loadConfig, requireApiKey } from './config.js';
import { log, setLogLevel } from './utils/logger.js';
import { runCompile, runCheck, runRepair, runRun } from './pipeline.js';
import type { AmbiguityMode } from './pipeline.js';
import { SoelError } from './utils/errors.js';
import { SemanticAmbiguityError } from './utils/errors.js';

function resolveAmbiguityMode(opts: { dialog?: boolean; lenient?: boolean }): AmbiguityMode {
  if (opts.dialog) return 'dialog';
  if (opts.lenient) return 'lenient';
  return 'strict';
}

const program = new Command();

program
  .name('soel')
  .description('SOEL — Semantic Open-Ended Language compiler')
  .version('0.1.0');

program
  .command('compile')
  .description('Compile a .soel file to Haskell')
  .argument('<file>', 'Path to .soel source file')
  .option('-o, --output <path>', 'Output .hs file path')
  .option('--ir-only', 'Output semantic IR JSON instead of Haskell')
  .option('--fast', 'Use fast encoder (less detail)')
  .option('--dialog', 'Interactively resolve semantic ambiguities')
  .option('--lenient', 'Auto-resolve ambiguities instead of failing')
  .option('--verbose', 'Verbose output')
  .action(async (file: string, opts) => {
    if (opts.verbose) setLogLevel('debug');
    const config = loadConfig({ fast: opts.fast });
    requireApiKey(config);
    await runCompile(file, {
      output: opts.output,
      irOnly: opts.irOnly,
      ambiguityMode: resolveAmbiguityMode(opts),
      config,
    });
  });

program
  .command('run')
  .description('Compile .soel → Haskell, then GHC compile + execute')
  .argument('<file>', 'Path to .soel source file')
  .option('--fast', 'Use fast encoder')
  .option('--dialog', 'Interactively resolve semantic ambiguities')
  .option('--lenient', 'Auto-resolve ambiguities instead of failing')
  .option('--verbose', 'Verbose output')
  .action(async (file: string, opts) => {
    if (opts.verbose) setLogLevel('debug');
    const config = loadConfig({ fast: opts.fast });
    requireApiKey(config);
    await runRun(file, {
      ambiguityMode: resolveAmbiguityMode(opts),
      config,
    });
  });

program
  .command('check')
  .description('Analyze .soel file and report semantic errors/warnings')
  .argument('<file>', 'Path to .soel source file')
  .option('--fast', 'Use fast encoder')
  .option('--verbose', 'Verbose output')
  .action(async (file: string, opts) => {
    if (opts.verbose) setLogLevel('debug');
    const config = loadConfig({ fast: opts.fast });
    requireApiKey(config);
    await runCheck(file, { config });
  });

program
  .command('repair')
  .description('Conversational debugging loop for a .soel program')
  .argument('<file>', 'Path to .soel source file')
  .option('--verbose', 'Verbose output')
  .action(async (file: string, opts) => {
    if (opts.verbose) setLogLevel('debug');
    const config = loadConfig();
    requireApiKey(config);
    await runRepair(file, { config });
  });

program.parseAsync(process.argv).catch((err) => {
  if (err instanceof SemanticAmbiguityError) {
    // Diagnostics already printed; just emit the summary
    log.error(err.message);
  } else if (err instanceof SoelError) {
    log.error(`[${err.code}] ${err.message}`);
  } else {
    log.error(err instanceof Error ? err.message : String(err));
  }
  process.exit(1);
});
