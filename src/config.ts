import { z } from 'zod';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { homedir } from 'node:os';
import { ConfigError } from './utils/errors.js';

const SoelConfigSchema = z.object({
  openrouter: z.object({
    apiKey: z.string().optional(),
    model: z.string().default('anthropic/claude-opus-4.6'),
  }).default({}),
  haskell: z.object({
    ghcPath: z.string().default('ghc'),
    ghcFlags: z.array(z.string()).default(['-O2', '-Wall']),
    extensions: z.array(z.string()).default(['OverloadedStrings', 'DeriveGeneric']),
  }).default({}),
  compiler: z.object({
    encoderMode: z.enum(['full', 'fast']).default('full'),
    ambiguityThreshold: z.number().min(0).max(1).default(0.7),
    maxDialogRounds: z.number().int().positive().default(5),
  }).default({}),
});

export type SoelConfig = z.infer<typeof SoelConfigSchema>;

const CONFIG_FILES = ['.soelrc', '.soelrc.json'];

export function loadConfig(overrides: Partial<{
  fast: boolean;
  noDialog: boolean;
}>  = {}): SoelConfig {
  let rawConfig: Record<string, unknown> = {};

  // Search for config file upward from cwd
  let dir = process.cwd();
  while (true) {
    for (const name of CONFIG_FILES) {
      const p = resolve(dir, name);
      if (existsSync(p)) {
        try {
          rawConfig = JSON.parse(readFileSync(p, 'utf-8'));
        } catch (e) {
          throw new ConfigError(`Invalid JSON in ${p}: ${e}`);
        }
        break;
      }
    }
    if (Object.keys(rawConfig).length > 0) break;
    const parent = resolve(dir, '..');
    if (parent === dir) break;
    dir = parent;
  }

  const config = SoelConfigSchema.parse(rawConfig);

  // Env var override for API key
  const envKey = process.env['OPENROUTER_API_KEY'];
  if (envKey) {
    config.openrouter.apiKey = envKey;
  }

  // CLI overrides
  if (overrides.fast) {
    config.compiler.encoderMode = 'fast';
  }

  // Auto-detect GHC via ghcup if the default 'ghc' isn't on PATH
  if (config.haskell.ghcPath === 'ghc') {
    const ghcupGhc = join(homedir(), '.ghcup', 'bin', 'ghc');
    if (existsSync(ghcupGhc)) {
      config.haskell.ghcPath = ghcupGhc;
    }
  }

  return config;
}

export function requireApiKey(config: SoelConfig): string {
  if (!config.openrouter.apiKey) {
    throw new ConfigError(
      'OpenRouter API key required. Set OPENROUTER_API_KEY env var or add to .soelrc'
    );
  }
  return config.openrouter.apiKey;
}
