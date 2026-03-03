# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

SOEL (Semantic Open-Ended Language) is a programming language where you write natural language prose and the compiler — powered by an LLM via OpenRouter — generates executable Haskell. There are two implementations: TypeScript (original) and Haskell (native port). Both share the same LLM prompt templates in `prompts/` and produce identical pipeline behavior.

## Build & Run

### TypeScript

```bash
npm install
npm run build          # TypeScript → dist/
npm run dev            # watch mode
soel compile prog.soel --lenient   # after npm link
```

### Haskell

```bash
cd hs
# GHC and cabal must be on PATH — typically via ghcup
env PATH="$HOME/.ghcup/bin:$PATH" cabal build
env PATH="$HOME/.ghcup/bin:$PATH" cabal run soel -- compile ../examples/hello-world.soel --lenient
```

Prompt templates are embedded at compile time via `file-embed` in `hs/src/Soel/LLM/Prompts.hs`. After editing any file in `prompts/`, the Haskell binary must be rebuilt (`cabal build`) to pick up changes.

### API Key

```bash
export OPENROUTER_API_KEY="sk-or-v1-..."
```

Or use a `.soelrc` file (searches upward from cwd). Env var takes precedence.

## Architecture

Seven-stage pipeline — three stages call the LLM, one is interactive, three are local:

```
.soel source
  → Reader (hash for cache)
  → SemanticEncoder (LLM → NarrativeIR)
  → Transform (LLM → CodeIR)
  → AmbiguityDetector (pure analysis)
  → Dialog (interactive or auto-resolve)
  → Codegen (LLM → Haskell source)
  → Writer + GHC (write .hs, optionally compile + run)
```

### Two-layer IR

**NarrativeIR** — rich narrative semantics: entities with typed attributes and mentions, events with thematic roles and participants, relationships, themes, and flagged ambiguities. Output of the semantic encoder.

**CodeIR** — Haskell-oriented: module declaration, imports, type definitions (record/sum/newtype/alias), pure functions, IO actions, constraints, and an entry point. Output of the transform stage.

Both IRs are JSON. The TypeScript version validates with Zod schemas (`src/ir/validate.ts`). The Haskell version uses Aeson `FromJSON` instances (`src/Soel/IR/Validate.hs`) with a `sanitizeLLMJson` pre-pass that strips null values from LLM output before parsing.

### App Monad (Haskell)

```haskell
type App a = ReaderT SoelConfig (ExceptT SoelError IO) a
```

Config via `ask`/`asks`, errors via `throwError`. Seven error constructors in `SoelError` (see `Utils/Errors.hs`). API key extraction is centralized in `requireApiKeyM`.

### Ambiguity Modes

- **Strict** (default) — errors halt compilation, warnings auto-resolve
- **Dialog** (`--dialog`) — interactive resolution via haskeline
- **Lenient** (`--lenient`) — everything auto-resolves with highest confidence

### LLM Integration

All LLM calls go through OpenRouter (`llmRequest` in both implementations). The `extractJSON` function handles fenced code blocks and raw JSON extraction from LLM responses. Prompts explicitly forbid null values — the sanitization layer (`sanitizeLLMJson`) is defense-in-depth for when the LLM ignores this.

### Caching

File-based in `.soel-cache/`. Keyed by SHA-256 hash of source content. Caches NarrativeIR and CodeIR separately — cache hits skip the corresponding LLM call.

## Key Conventions

- Haskell modules mirror TypeScript 1:1 — `src/stages/codegen.ts` ↔ `hs/src/Soel/Stages/Codegen.hs`
- Orphan instances for IR JSON serialization live in `Validate.hs` (imported via `import Soel.IR.Validate ()`)
- `severityText` and `categoryText` are canonical display functions in `IR/Types.hs` — do not redefine locally
- The Haskell Codegen stage forces `module Main where` on generated code (GHC requirement for executables)
- AmbiguityDetector is pure — no IORef, threads an index counter through detection functions
