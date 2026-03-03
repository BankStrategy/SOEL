import chalk from 'chalk';
import ora, { type Ora } from 'ora';

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

let currentLevel: LogLevel = 'info';

export function setLogLevel(level: LogLevel): void {
  currentLevel = level;
}

function shouldLog(level: LogLevel): boolean {
  return LEVEL_ORDER[level] >= LEVEL_ORDER[currentLevel];
}

export const log = {
  debug(msg: string): void {
    if (shouldLog('debug')) {
      console.error(chalk.gray(`[debug] ${msg}`));
    }
  },
  info(msg: string): void {
    if (shouldLog('info')) {
      console.error(chalk.blue('ℹ') + ` ${msg}`);
    }
  },
  success(msg: string): void {
    if (shouldLog('info')) {
      console.error(chalk.green('✓') + ` ${msg}`);
    }
  },
  warn(msg: string): void {
    if (shouldLog('warn')) {
      console.error(chalk.yellow('⚠') + ` ${msg}`);
    }
  },
  error(msg: string): void {
    if (shouldLog('error')) {
      console.error(chalk.red('✗') + ` ${msg}`);
    }
  },
  stage(name: string): void {
    if (shouldLog('info')) {
      console.error(chalk.cyan(`\n▸ ${name}`));
    }
  },
};

export function spinner(text: string): Ora {
  return ora({ text, stream: process.stderr });
}

/**
 * Format an ambiguity as a compiler diagnostic, like GCC/GHC errors.
 */
export function formatDiagnostic(opts: {
  file: string;
  severity: 'error' | 'warning';
  id: string;
  category: string;
  message: string;
  span?: [number, number];
  sourceText?: string;
  options?: Array<{ label: string; confidence: number }>;
}): string {
  const { file, severity, id, category, message, span, sourceText, options } = opts;

  const sevColor = severity === 'error' ? chalk.red : chalk.yellow;
  const sevLabel = sevColor.bold(severity);

  // Location string
  let loc = file;
  let lineNum: number | undefined;
  let colNum: number | undefined;
  if (span && span[0] >= 0 && sourceText) {
    const before = sourceText.slice(0, span[0]);
    lineNum = (before.match(/\n/g) ?? []).length + 1;
    colNum = span[0] - before.lastIndexOf('\n');
    loc = `${file}:${lineNum}:${colNum}`;
  }

  const lines: string[] = [];
  lines.push(`${chalk.bold(loc)}: ${sevLabel} ${chalk.bold(`[${id}]`)}: ${message}`);
  lines.push(chalk.dim(`  ├─ category: ${category}`));

  // Source context
  if (span && span[0] >= 0 && sourceText && lineNum !== undefined) {
    const sourceLines = sourceText.split('\n');
    const contextStart = Math.max(0, lineNum - 2);
    const contextEnd = Math.min(sourceLines.length, lineNum + 1);
    lines.push(chalk.dim('  │'));
    for (let i = contextStart; i < contextEnd; i++) {
      const ln = String(i + 1).padStart(4);
      const marker = i === lineNum - 1 ? sevColor('▸') : ' ';
      lines.push(`  ${marker} ${chalk.dim(ln + ' │')} ${sourceLines[i]}`);
      // Underline the span on the matching line
      if (i === lineNum - 1 && colNum !== undefined && span[1] > span[0]) {
        const underLen = Math.min(span[1] - span[0], sourceLines[i].length - colNum + 1);
        const pad = ' '.repeat(colNum - 1);
        lines.push(`  ${' '} ${chalk.dim('     │')} ${pad}${sevColor('~'.repeat(Math.max(1, underLen)))}`);
      }
    }
  }

  // Options
  if (options && options.length > 0) {
    lines.push(chalk.dim('  │'));
    lines.push(chalk.dim('  ├─ possible interpretations:'));
    for (const opt of options) {
      const conf = `${(opt.confidence * 100).toFixed(0)}%`;
      lines.push(chalk.dim(`  │   • ${opt.label} (${conf})`));
    }
  }

  lines.push(chalk.dim('  │'));
  return lines.join('\n');
}
