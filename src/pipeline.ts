import { resolve } from 'node:path';
import type { SoelConfig } from './config.js';
import type { NarrativeIR, CodeIR, Ambiguity } from './ir/types.js';
import { readSource } from './stages/reader.js';
import { semanticEncode } from './stages/semantic-encoder.js';
import { transformToCodeIR } from './ir/transform.js';
import { detectAmbiguities, emitDiagnostics } from './stages/ambiguity-detector.js';
import { resolveAmbiguities, autoResolveAll } from './stages/dialog.js';
import { generateHaskell } from './stages/codegen.js';
import { writeHaskell, writeIR } from './stages/writer.js';
import { ghcCompile, ghcRun } from './stages/ghc.js';
import { getCached, setCache } from './cache/store.js';
import { repairLoop } from './stages/repair.js';
import { log } from './utils/logger.js';
import { formatDiagnostic } from './utils/logger.js';
import chalk from 'chalk';

export type AmbiguityMode = 'strict' | 'dialog' | 'lenient';

// ─── Compile ────────────────────────────────────────────────────────

export interface CompileOptions {
  output?: string;
  irOnly?: boolean;
  ambiguityMode: AmbiguityMode;
  config: SoelConfig;
}

export async function runCompile(
  filePath: string,
  opts: CompileOptions
): Promise<void> {
  // Stage 1: Read
  log.stage('Reading source');
  const source = readSource(filePath);

  // Check cache for narrative IR
  let narrativeIR = getCached<NarrativeIR>(`narrative-${source.name}`, source.hash);

  if (!narrativeIR) {
    // Stage 2: Semantic Encode
    narrativeIR = await semanticEncode(source.content, opts.config);
    setCache(`narrative-${source.name}`, source.hash, narrativeIR);
  } else {
    log.info('Using cached narrative IR');
  }

  // Stage 2b: Transform to Code IR
  let codeIR = getCached<CodeIR>(`code-${source.name}`, source.hash);

  if (!codeIR) {
    codeIR = await transformToCodeIR(narrativeIR, source.content, opts.config);
    setCache(`code-${source.name}`, source.hash, codeIR);
  } else {
    log.info('Using cached code IR');
  }

  // If --ir-only, output the IR and stop
  if (opts.irOnly) {
    writeIR({ narrative: narrativeIR, code: codeIR }, source.path);
    console.log(JSON.stringify({ narrative: narrativeIR, code: codeIR }, null, 2));
    return;
  }

  // Stage 3: Detect Ambiguities
  const ambResult = detectAmbiguities(narrativeIR, codeIR, opts.config);

  // Stage 4: Resolve Ambiguities — behavior depends on mode
  let resolved: Ambiguity[];

  switch (opts.ambiguityMode) {
    case 'strict':
      // Print diagnostics for all, throw on errors — like a traditional compiler
      emitDiagnostics(ambResult, source.path, source.content);
      // If we get here, there were only warnings — auto-resolve them
      resolved = autoResolveAll(ambResult.warnings);
      break;

    case 'dialog':
      // Print warnings, then enter interactive dialog for everything
      for (const w of ambResult.warnings) {
        console.error(formatDiagnostic({
          file: source.path,
          severity: 'warning',
          id: w.id,
          category: w.category,
          message: w.description,
          span: w.sourceSpan,
          sourceText: source.content,
          options: w.options,
        }));
      }
      resolved = await resolveAmbiguities(ambResult.all, source.content, opts.config);
      break;

    case 'lenient':
      // Print warnings to stderr, auto-resolve everything silently
      if (ambResult.warnings.length > 0 || ambResult.errors.length > 0) {
        for (const amb of ambResult.all) {
          console.error(formatDiagnostic({
            file: source.path,
            severity: amb.severity,
            id: amb.id,
            category: amb.category,
            message: amb.description,
            span: amb.sourceSpan,
            sourceText: source.content,
            options: amb.options,
          }));
        }
        const e = ambResult.errors.length;
        const w = ambResult.warnings.length;
        log.warn(`Auto-resolving ${e} error(s) and ${w} warning(s) in lenient mode`);
      }
      resolved = autoResolveAll(ambResult.all);
      break;
  }

  // Stage 5: Generate Haskell
  const { haskellSource } = await generateHaskell(
    codeIR,
    resolved,
    source.content,
    opts.config
  );

  // Stage 6: Write
  const hsPath = writeHaskell(haskellSource, {
    sourcePath: source.path,
    outputPath: opts.output,
  });

  log.success(`Compilation complete: ${hsPath}`);
}

// ─── Run ────────────────────────────────────────────────────────────

export interface RunOptions {
  ambiguityMode: AmbiguityMode;
  config: SoelConfig;
}

export async function runRun(
  filePath: string,
  opts: RunOptions
): Promise<void> {
  const hsPath = resolve(filePath).replace(/\.soel$/, '.hs');

  await runCompile(filePath, {
    ambiguityMode: opts.ambiguityMode,
    config: opts.config,
    output: hsPath,
  });

  // Stage 7: GHC compile + run
  const { executablePath } = await ghcCompile(hsPath, opts.config);
  await ghcRun(executablePath);
}

// ─── Check ──────────────────────────────────────────────────────────

export interface CheckOptions {
  config: SoelConfig;
}

export async function runCheck(
  filePath: string,
  opts: CheckOptions
): Promise<void> {
  log.stage('Reading source');
  const source = readSource(filePath);

  const narrativeIR = await semanticEncode(source.content, opts.config);
  const codeIR = await transformToCodeIR(narrativeIR, source.content, opts.config);
  const ambResult = detectAmbiguities(narrativeIR, codeIR, opts.config);

  if (ambResult.all.length === 0) {
    log.success('No semantic issues detected');
    return;
  }

  for (const amb of ambResult.all) {
    console.error(formatDiagnostic({
      file: source.path,
      severity: amb.severity,
      id: amb.id,
      category: amb.category,
      message: amb.description,
      span: amb.sourceSpan,
      sourceText: source.content,
      options: amb.options,
    }));
  }

  const e = ambResult.errors.length;
  const w = ambResult.warnings.length;
  console.error(
    chalk.bold(`${e} error(s), ${w} warning(s)`)
  );

  if (e > 0) {
    process.exitCode = 1;
  }
}

// ─── Repair ─────────────────────────────────────────────────────────

export interface RepairOptions {
  config: SoelConfig;
}

export async function runRepair(
  filePath: string,
  opts: RepairOptions
): Promise<void> {
  await repairLoop(filePath, opts.config);
}
