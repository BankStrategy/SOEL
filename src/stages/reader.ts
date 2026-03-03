import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, basename, extname } from 'node:path';
import { SoelError } from '../utils/errors.js';
import { log } from '../utils/logger.js';

export interface SourceFile {
  path: string;
  name: string;
  content: string;
  hash: string;
}

export function readSource(filePath: string): SourceFile {
  const absPath = resolve(filePath);

  if (extname(absPath) !== '.soel') {
    throw new SoelError(`Expected .soel file, got: ${extname(absPath)}`, 'INVALID_FILE');
  }

  let content: string;
  try {
    content = readFileSync(absPath, 'utf-8');
  } catch (e) {
    throw new SoelError(`Cannot read file: ${absPath}`, 'FILE_NOT_FOUND');
  }

  if (content.trim().length === 0) {
    throw new SoelError('Source file is empty', 'EMPTY_FILE');
  }

  const hash = createHash('sha256').update(content).digest('hex');
  const name = basename(absPath, '.soel');

  log.debug(`Read ${absPath} (${content.length} chars, hash: ${hash.slice(0, 12)}...)`);

  return { path: absPath, name, content, hash };
}
