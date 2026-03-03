import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { log } from '../utils/logger.js';

export interface WriteOptions {
  sourcePath: string;
  outputPath?: string;
}

/**
 * Write Haskell source to a .hs file.
 */
export function writeHaskell(
  haskellSource: string,
  opts: WriteOptions
): string {
  const outPath = opts.outputPath
    ?? resolve(dirname(opts.sourcePath), basename(opts.sourcePath, '.soel') + '.hs');

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, haskellSource + '\n', 'utf-8');

  log.success(`Wrote ${outPath}`);
  return outPath;
}

/**
 * Write IR JSON to a file.
 */
export function writeIR(ir: unknown, sourcePath: string): string {
  const outPath = resolve(
    dirname(sourcePath),
    basename(sourcePath, '.soel') + '.ir.json'
  );

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(ir, null, 2) + '\n', 'utf-8');

  log.success(`Wrote ${outPath}`);
  return outPath;
}
