import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROMPTS_DIR = resolve(__dirname, '../../prompts');

const cache = new Map<string, string>();

export function loadPrompt(name: string): string {
  if (cache.has(name)) {
    return cache.get(name)!;
  }
  const path = resolve(PROMPTS_DIR, `${name}.md`);
  const content = readFileSync(path, 'utf-8');
  cache.set(name, content);
  return content;
}

export function loadPromptWithVars(
  name: string,
  vars: Record<string, string>
): string {
  let content = loadPrompt(name);
  for (const [key, value] of Object.entries(vars)) {
    content = content.replaceAll(`{{${key}}}`, value);
  }
  return content;
}
