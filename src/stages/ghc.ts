import { execFile, spawn } from 'node:child_process';
import { resolve, dirname, basename } from 'node:path';
import { unlinkSync, existsSync } from 'node:fs';
import type { SoelConfig } from '../config.js';
import { GHCError } from '../utils/errors.js';
import { log, spinner } from '../utils/logger.js';

export interface GHCResult {
  executablePath: string;
  stdout: string;
  stderr: string;
}

function exec(
  cmd: string,
  args: string[],
  cwd: string
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  return new Promise((resolve) => {
    execFile(cmd, args, { cwd, timeout: 120_000, env: { ...process.env } }, (error, stdout, stderr) => {
      if (error) {
        const exitCode = 'status' in error && typeof error.status === 'number'
          ? error.status
          : 1;
        const errMsg = error.code === 'ENOENT'
          ? `Command not found: ${cmd}`
          : (stderr ?? error.message);
        resolve({
          stdout: stdout ?? '',
          stderr: errMsg,
          exitCode,
        });
      } else {
        resolve({
          stdout: stdout ?? '',
          stderr: stderr ?? '',
          exitCode: 0,
        });
      }
    });
  });
}

/**
 * Compile a .hs file with GHC.
 */
export async function ghcCompile(
  hsPath: string,
  config: SoelConfig
): Promise<GHCResult> {
  log.stage('Compiling with GHC');

  const absPath = resolve(hsPath);
  const dir = dirname(absPath);
  const name = basename(absPath, '.hs');
  const executablePath = resolve(dir, name);

  const ghc = config.haskell.ghcPath;
  const flags = [...config.haskell.ghcFlags];

  // Add language extensions as flags
  for (const ext of config.haskell.extensions) {
    flags.push(`-X${ext}`);
  }

  const args = [...flags, absPath, '-o', executablePath];

  const spin = spinner(`Compiling ${basename(absPath)}...`).start();

  const result = await exec(ghc, args, dir);

  if (result.exitCode !== 0) {
    spin.fail('GHC compilation failed');
    throw new GHCError(
      `GHC compilation failed for ${absPath}`,
      result.stderr,
      result.exitCode
    );
  }

  spin.succeed(`Compiled → ${executablePath}`);

  // Clean up .o and .hi files
  for (const ext of ['.o', '.hi']) {
    const artifact = resolve(dir, name + ext);
    if (existsSync(artifact)) {
      try { unlinkSync(artifact); } catch { /* ignore */ }
    }
  }

  return {
    executablePath,
    stdout: result.stdout,
    stderr: result.stderr,
  };
}

/**
 * Run a compiled Haskell executable with inherited stdio
 * so the program can interact with the user's terminal.
 */
export async function ghcRun(executablePath: string): Promise<string> {
  log.stage('Running program');

  console.error('');

  return new Promise((res, reject) => {
    const child = spawn(executablePath, [], {
      cwd: dirname(executablePath),
      stdio: 'inherit',
    });

    child.on('error', (err) => {
      reject(new GHCError(`Failed to run program: ${err.message}`, err.message, 1));
    });

    child.on('close', (code) => {
      console.error('');
      if (code !== 0) {
        reject(new GHCError(`Program exited with code ${code}`, '', code));
      } else {
        log.success('Program finished');
        res('');
      }
    });
  });
}
