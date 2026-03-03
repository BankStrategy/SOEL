# SOEL

**Semantic Open-Ended Language** — a programming language where you write natural language narratives and the compiler generates executable Haskell.

SOEL is grounded in the neuroscientific observation that the human brain processes natural language and computer code through entirely separate neural networks. Traditional programming engages the Multiple Demand network (spatial reasoning, rule execution). Natural language engages the perisylvian language network (meaning, inference, social intent). SOEL is an attempt to build a programming language that lives in the second one.

You write prose. The compiler semantically encodes it, detects ambiguities (and treats them as compiler errors), then generates GHC-compilable Haskell.

## How it works

```
.soel source
  → semantic encoding (LLM)
  → narrative IR
  → code IR transformation (LLM)
  → ambiguity detection
  → dialogical resolution (human + LLM)
  → Haskell code generation (LLM)
  → GHC compilation + execution
```

The compiler has a 7-stage pipeline. Three of those stages call an LLM via OpenRouter. One is interactive. The rest are local.

## Example

A SOEL program (`hello-world.soel`):

```
This is a simple greeting program.

There is a Greeter who has a name and a greeting message.

When the program starts, it creates a greeter named "SOEL" with the
message "Hello, World!".

It then displays the greeting by printing the greeter's message to
the screen.

Finally, it asks the user for their name and greets them personally,
saying "Nice to meet you, [name]!".
```

### Successful compilation (`--lenient`)

```
$ soel run examples/hello-world.soel --lenient

▸ Reading source

▸ Semantic encoding (full mode)
⠋ Encoding narrative semantics...
✔ Semantic encoding complete

▸ Transforming narrative IR → code IR
⠋ Generating code-oriented IR...
✔ Code IR generated
ℹ 2 semantic warning(s)
examples/hello-world.soel:5:67: warning [S001]: coreference
  ├─ category: naming
  │
       4 │
  ▸    5 │ When the program starts, it creates a greeter named "SOEL" with the message "Hello, World!".
         │                                                                   ~~~~
       6 │
  │
  ├─ possible interpretations:
  │   • SOEL is the name attribute of the Greeter object, not a separate person entity (70%)
  │   • SOEL is a named entity representing the greeter's identity (30%)
  │
examples/hello-world.soel:9:69: warning [S002]: role_assignment
  ├─ category: other
  │
       8 │
  ▸    9 │ Finally, it asks the user for their name and greets them personally, saying "Nice to meet you, [name]!".
         │                                                                     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      10 │
  │
  ├─ possible interpretations:
  │   • The program itself outputs the personal greeting (80%)
  │   • The Greeter object is the one performing the personal greeting (20%)
  │
⚠ Auto-resolving 0 error(s) and 2 warning(s) in lenient mode

▸ Generating Haskell code
⠋ Generating Haskell source...
✔ Haskell code generated
✓ Wrote examples/hello-world.hs
✓ Compilation complete: examples/hello-world.hs

▸ Compiling with GHC
⠋ Compiling hello-world.hs...
✔ Compiled → examples/hello-world

▸ Running program

Hello, World!
What is your name?
Nice to meet you, World!

✓ Program finished
```

### Strict mode (default) — semantic errors halt compilation

```
$ soel compile examples/ecommerce.soel

▸ Reading source

▸ Semantic encoding (full mode)
⠋ Encoding narrative semantics...
✔ Semantic encoding complete

▸ Transforming narrative IR → code IR
⠋ Generating code-oriented IR...
✔ Code IR generated
ℹ 1 semantic error(s), 1 warning(s)
examples/ecommerce.soel:14:149: error [S001]: scope
  ├─ category: scope
  │
      13 │
  ▸   14 │ The main program creates two customers (one regular, one VIP), several products (a laptop
           at $999.99, headphones at $49.99, and a book at $15.00), adds items to both customers'
           carts, and prints receipts for each.
         │                                                     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      15 │
  │
  ├─ possible interpretations:
  │   • Items from all three products are added to both customers' carts. (50%)
  │   • Different subsets of products are added to each customer's cart. (50%)
  │
examples/ecommerce.soel:14:188: warning [S002]: role_assignment
  ├─ category: other
  │
      13 │
  ▸   14 │ ...adds items to both customers' carts, and prints receipts for each.
         │                                                      ~~~~~~~~~~~~~~~~
      15 │
  │
  ├─ possible interpretations:
  │   • 'for each' refers to each customer (both regular and VIP get a receipt). (90%)
  │   • 'for each' could refer to each cart or each order. (10%)
  │
✗ Compilation failed: 1 semantic error(s), 1 warning(s)
```

The compiler detected that "adds items to both customers' carts" is genuinely ambiguous — it's unclear whether all products go to all carts or different products go to different carts. This is a semantic error: the compiler cannot proceed without human clarification, just as a traditional compiler cannot proceed past a syntax error.

### Another example — calculator

```
$ soel run examples/calculator.soel --lenient

▸ Reading source

▸ Semantic encoding (full mode)
✔ Semantic encoding complete

▸ Transforming narrative IR → code IR
✔ Code IR generated
ℹ 1 semantic warning(s)
examples/calculator.soel:7:140: warning [S001]: other
  ├─ possible interpretations:
  │   • 'Nothing' is a Maybe/Option type constructor indicating absence of a valid result (80%)
  │   • 'Nothing' is a general English word meaning no value is returned. (20%)
⚠ Auto-resolving 0 error(s) and 1 warning(s) in lenient mode

▸ Generating Haskell code
✔ Haskell code generated
✓ Wrote examples/calculator.hs

▸ Compiling with GHC
✔ Compiled → examples/calculator

▸ Running program

10 + 5 = 15.0
20 - 8 = 12.0
6 * 7 = 42.0
15 / 3 = 5.0
15 / 0 = Error: Division by zero (Nothing)

✓ Program finished
```

The compiler inferred `Maybe Double` as the return type for division, correctly mapping the English word "Nothing" to Haskell's `Nothing` constructor.

## Setup

```bash
npm install
npm run build
```

Set your OpenRouter API key:

```bash
export OPENROUTER_API_KEY="sk-or-v1-..."
```

Or create a `.soelrc` file (see `.soelrc.example`):

```json
{
  "openrouter": {
    "apiKey": "sk-or-v1-...",
    "model": "anthropic/claude-opus-4.6"
  }
}
```

Optionally link the CLI globally:

```bash
npm link
```

## Commands

### `soel compile <file>`

Compile a `.soel` file to Haskell.

```bash
soel compile program.soel              # strict mode (default)
soel compile program.soel --dialog     # interactively resolve ambiguities
soel compile program.soel --lenient    # auto-resolve ambiguities
soel compile program.soel -o out.hs    # custom output path
soel compile program.soel --ir-only    # output semantic IR JSON only
soel compile program.soel --fast       # use fast encoder (less detail)
```

### `soel run <file>`

Compile, then GHC compile and execute.

```bash
soel run program.soel --lenient
```

### `soel check <file>`

Semantic analysis only — reports errors and warnings without generating code.

```bash
soel check program.soel
```

### `soel repair <file>`

Conversational debugging. Compiles the program, attempts GHC compilation, and if it fails, enters an LLM-powered fix loop (up to 5 rounds).

```bash
soel repair program.soel
```

## Ambiguity modes

SOEL has no formal syntax. The source text is natural language. This means the compiler can encounter genuine semantic ambiguity — concepts that could be interpreted multiple ways, conflicting relationships between entities, or behavior the encoder isn't confident about.

These are treated as compiler diagnostics, analogous to how a traditional compiler reports syntax errors.

**Strict** (default) — Semantic ambiguities classified as errors halt compilation. Warnings are auto-resolved. Diagnostics are printed with source locations, context, and candidate interpretations. Use `--dialog` or rewrite your prose to fix them.

**Dialog** (`--dialog`) — All ambiguities (errors and warnings) are presented in an interactive terminal loop. You pick an interpretation or type a custom response, which the LLM interprets. This is the "fix it live" mode.

**Lenient** (`--lenient`) — All diagnostics are printed but everything is auto-resolved using the highest-confidence interpretation. Compilation continues regardless. Useful for prototyping.

## Semantic IR

The compiler produces a two-layer intermediate representation:

**Narrative IR** — the output of the semantic encoder. Rich narrative semantics: entities with attributes, events with thematic roles, relationships, themes, and flagged ambiguities.

**Code IR** — the output of the transform pass. Haskell-oriented: module declarations, type definitions (record, sum, newtype, alias), pure functions, IO actions, constraints, imports, and an entry point.

Inspect the IR with `--ir-only`:

```bash
soel compile program.soel --ir-only > program.ir.json
```

## Haskell mapping

| SOEL concept | Haskell output |
|---|---|
| Entity with attributes | `data Entity = Entity { field :: Type }` |
| Entity with variants | `data Entity = A \| B \| C` |
| Simple wrapper entity | `newtype Wrapper = Wrapper Type` |
| Pure computation | `functionName :: A -> B` |
| Side effect | `actionName :: A -> IO B` |
| "owns" / "has" relation | Record field |
| "contains" relation | `[Item]` list field |
| Optional attribute | `Maybe a` |
| Currency | `newtype Currency = Currency Integer` |
| Temporal attribute | `UTCTime` |
| Constraint / validation | `predicate :: Type -> Bool` |

## Configuration

Full `.soelrc` options:

```json
{
  "openrouter": {
    "apiKey": "sk-or-v1-...",
    "model": "anthropic/claude-opus-4.6"
  },
  "haskell": {
    "ghcPath": "ghc",
    "ghcFlags": ["-O2", "-Wall"],
    "extensions": ["OverloadedStrings", "DeriveGeneric"]
  },
  "compiler": {
    "encoderMode": "full",
    "ambiguityThreshold": 0.7,
    "maxDialogRounds": 5
  }
}
```

`OPENROUTER_API_KEY` env var takes precedence over the config file. GHC is auto-detected via ghcup if not on PATH.

## Requirements

- Node.js >= 20
- GHC (for `soel run` and `soel repair` — auto-detected via ghcup)
- OpenRouter API key

## Project structure

```
src/
  index.ts                CLI entry point
  config.ts               Config loading (.soelrc + env)
  pipeline.ts             7-stage orchestration
  stages/
    reader.ts             Read + hash .soel files
    semantic-encoder.ts   LLM semantic encoding
    ambiguity-detector.ts Semantic error/warning detection
    dialog.ts             Interactive ambiguity resolution
    codegen.ts            LLM Haskell generation
    writer.ts             Write .hs files
    ghc.ts                GHC compilation + execution
    repair.ts             Conversational debugging loop
  ir/
    types.ts              NarrativeIR + CodeIR type definitions
    validate.ts           Zod runtime validation
    transform.ts          Narrative IR → Code IR (LLM)
  llm/
    openrouter.ts         OpenRouter API client
    prompts.ts            Prompt template loader
  cache/
    store.ts              File-based .soel-cache/
  utils/
    logger.ts             Diagnostics, colored output, spinners
    errors.ts             Typed error hierarchy
prompts/
  semantic-encoder-full.md
  semantic-encoder-fast.md
  ir-transform.md
  codegen-haskell.md
  ambiguity-resolver.md
  pragmatic-repair.md
examples/
  hello-world.soel
  calculator.soel
  todo-list.soel
  ecommerce.soel
```

## Background

See [SPEC.md](SPEC.md) for the full theoretical foundation — the neurobiology of code vs. language processing, why English-like syntax (Inform 7) doesn't work, and the formal specification of semantically open-ended programming.
