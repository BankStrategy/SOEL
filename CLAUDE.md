# SOEL — Semantic Open-Ended Language

## Overview

SOEL is a programming language where you write natural language narratives and the compiler — powered by an LLM via OpenRouter — semantically encodes them and generates executable Haskell code.

## Tech Stack

- **Language**: TypeScript (Node.js, ESM)
- **LLM**: Claude Sonnet via OpenRouter
- **Target**: GHC-compilable Haskell (`.hs` files)
- **Dependencies**: commander, zod, chalk, ora

## Build & Run

```bash
npm install
npm run build          # compiles TypeScript → dist/
node dist/index.js     # or use `soel` after npm link
```

## CLI Commands

```bash
soel compile program.soel              # → program.hs
soel compile program.soel -o out.hs    # custom output path
soel compile program.soel --ir-only    # output semantic IR JSON only
soel compile program.soel --fast       # fast encoder (less detail)
soel compile program.soel --no-dialog  # skip interactive ambiguity resolution
soel run program.soel                  # compile + GHC compile + execute
soel check program.soel                # show ambiguities only
soel repair program.soel               # conversational debugging loop
```

## Configuration

Set `OPENROUTER_API_KEY` env var, or create a `.soelrc` file (see `.soelrc.example`).

## Architecture

7-stage pipeline:
1. **Read** — parse `.soel` source, hash for caching
2. **Semantic Encode** — LLM converts narrative → Narrative IR (JSON)
3. **Transform** — LLM converts Narrative IR → Code IR (Haskell-oriented)
4. **Detect Ambiguities** — find low-confidence/conflicting areas
5. **Dialogical Feedback** — interactive terminal loop to resolve ambiguities
6. **Generate Haskell** — LLM produces compilable `.hs` from Code IR
7. **Write + GHC** — write file, optionally compile and run with GHC

## Project Structure

- `src/` — TypeScript source
  - `index.ts` — CLI entry point (commander)
  - `config.ts` — `.soelrc` / env var loading (zod)
  - `pipeline.ts` — orchestrates all 7 stages
  - `stages/` — one file per pipeline stage
  - `ir/` — Semantic IR types, validation, transform
  - `llm/` — OpenRouter client, prompt loader
  - `cache/` — file-based `.soel-cache/`
  - `utils/` — logger, error types
- `prompts/` — LLM prompt templates (`.md` files)
- `examples/` — sample `.soel` programs
