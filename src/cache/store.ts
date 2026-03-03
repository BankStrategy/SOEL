import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { log } from '../utils/logger.js';

const CACHE_DIR = '.soel-cache';

interface CacheEntry {
  hash: string;
  timestamp: number;
  data: unknown;
}

function cacheDir(): string {
  const dir = resolve(process.cwd(), CACHE_DIR);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  return dir;
}

function cacheFile(key: string): string {
  // Sanitize key for filesystem
  const safe = key.replace(/[^a-zA-Z0-9_-]/g, '_');
  return resolve(cacheDir(), `${safe}.json`);
}

export function getCached<T>(key: string, hash: string): T | null {
  const path = cacheFile(key);
  if (!existsSync(path)) return null;

  try {
    const entry = JSON.parse(readFileSync(path, 'utf-8')) as CacheEntry;
    if (entry.hash === hash) {
      log.debug(`Cache hit: ${key}`);
      return entry.data as T;
    }
    log.debug(`Cache miss (hash mismatch): ${key}`);
    return null;
  } catch {
    return null;
  }
}

export function setCache(key: string, hash: string, data: unknown): void {
  const path = cacheFile(key);
  const entry: CacheEntry = {
    hash,
    timestamp: Date.now(),
    data,
  };
  writeFileSync(path, JSON.stringify(entry, null, 2), 'utf-8');
  log.debug(`Cached: ${key}`);
}
