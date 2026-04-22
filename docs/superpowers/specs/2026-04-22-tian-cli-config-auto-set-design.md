# `tian-cli config --auto-set` — Design

**Date:** 2026-04-22
**Status:** Approved for implementation planning

## Summary

Add a new `tian-cli` subcommand, `tian config auto-set`, that generates a
`.tian/config.toml` for the current repository by invoking `claude -p` in
headless mode with read-only tools. The generated config populates only the
`[[setup]]` and `[[copy]]` sections of the existing `WorktreeConfig` schema.

The goal is to remove the friction of hand-writing a `.tian/config.toml` for
every project the user opens in tian: instead of reading the schema and
figuring out which commands to run, the user types one command and gets a
sensible starting config.

## Goals

- One command (`tian config auto-set`) produces a valid `.tian/config.toml`
  that `WorktreeConfigParser` accepts.
- The generated config reflects the current repo: dependency installs, env
  file copies, and project-specific bootstrap scripts.
- Safe by default: refuses to overwrite an existing config unless `--force`
  is passed.
- Reuses existing plumbing (`WorktreeConfigParser`, `CLIError`,
  `CommandLogger`) — no new parser or serializer.

## Non-goals (v1)

- Layout tree generation (`[layout]` section).
- Editing or merging an existing config (only full overwrite via `--force`).
- Streaming Claude's tool-use events as a live log.
- Model selection UI beyond a `--model` string flag.
- Running the subcommand outside a tian terminal session
  (`TIAN_SOCKET` is still required for UX consistency with other subcommands).
- A `config refresh` command for re-running after repo structure changes.
- `[[setup]]` ordering optimization, timeouts, or failure recovery.

## User-visible surface

```
tian config auto-set [--force] [--model <name>] [--claude-path <path>]
```

Flags:

- `--force` — overwrite an existing `.tian/config.toml`. Without it, the
  command exits 1 with an error.
- `--model <name>` — model passed through to `claude -p --model`. Defaults
  to `sonnet`.
- `--claude-path <path>` — override the `claude` executable path. Defaults
  to resolution via `PATH`.

Environment / preconditions:

- `TIAN_SOCKET` must be set (enforced via
  `TianEnvironment.fromEnvironment()`). The subcommand does **not** send an
  IPC request — the check exists purely for UX consistency with the other
  subcommands.
- `cwd` must be inside a git repository. The repo root is resolved via
  `git rev-parse --show-toplevel`.

## Architecture

### New file: `tian-cli/ConfigGroup.swift`

Contains three pieces:

1. **`ConfigGroup` / `ConfigAutoSet`** — `ParsableCommand` types wired into
   `TianCLI.configuration.subcommands` (via a one-line addition to
   `main.swift`).
2. **`ClaudeInvoker` protocol + `ProcessClaudeInvoker`** — wraps the
   subprocess call so tests can inject a stub.
3. **`AutoSetPrompt`** — an enum with a `static let template: String`
   constant holding the prompt.

No changes to `WorktreeConfig`, `WorktreeConfigParser`, or any app-side
code.

### Data flow

```
tian config auto-set [--force]
        │
        ▼
resolveRepoRoot()         `git rev-parse --show-toplevel` from cwd
        │  repoRoot: URL
        ▼
checkExisting()           if .tian/config.toml exists && !force → CLIError
        │
        ▼
buildPrompt()             AutoSetPrompt.template
        │  prompt: String
        ▼
print status             "Analyzing repository with claude -p (this usually
        │                 takes 20–60s)…" → user's stderr
        ▼
ClaudeInvoker.run()       spawns: claude -p
        │                   --allowedTools "Read,Glob,Grep"
        │                   --permission-mode acceptEdits
        │                   --model <model>
        │                   <prompt>
        │                 cwd = repoRoot; env inherited
        │                 stderr → user terminal (pass-through, mostly silent)
        │                 stdout → captured buffer
        │  tomlString: String
        ▼
validateTOML()            WorktreeConfigParser.parse(tomlString:)
        │                 on failure: write .tian/config.toml.rejected,
        │                 surface parser error, exit 3
        ▼
writeFile()               mkdir -p .tian/;
        │                 write to .tian/config.toml.tmp → rename (atomic)
        ▼
print summary             "Wrote .tian/config.toml
                          (N setup commands, M copy rules)"
```

Key decisions baked into the flow:

- Claude's subprocess `cwd` is the repo root, so `Read`/`Glob`/`Grep`
  resolve paths the way the few-shot examples assume.
- Tool allowlist is `Read,Glob,Grep` only — no `Bash`, no `Write`. tian-cli
  is the only component that touches the filesystem.
- `--permission-mode acceptEdits` prevents Claude from blocking on
  interactive permission prompts (read-only tools don't edit anything, but
  the flag defends against future schema changes in the Claude CLI).
- stdout is captured in full and parsed once at the end. stderr is passed
  through but `claude -p` in text mode is mostly silent during tool use;
  to avoid a blank-terminal UX, tian-cli prints a single status line to
  stderr before spawning (`Analyzing repository with claude -p…`).
- Atomic write (temp + rename) avoids a corrupted file if the process is
  killed mid-write.
- On parse failure, Claude's raw output is preserved at
  `.tian/config.toml.rejected` so the user can inspect/edit rather than
  lose the work.

## Prompt design

Held in `AutoSetPrompt.template` so it is stable, diffable, and
unit-testable without hitting the network.

Four sections:

### A. Task statement

"Analyze this repository and generate a `.tian/config.toml` file. Output
ONLY valid TOML — no markdown fences, no explanation, no prose."

### B. Inlined schema

Only the two in-scope sections:

```toml
# [[setup]] — one-shot shell commands run once when a worktree is created
# for this repo. Each [[setup]] is an independent entry with a required
# `command` field. Commands run sequentially with the worktree root as cwd.
[[setup]]
command = "<shell command>"

# [[copy]] — files copied from the main worktree into each new worktree.
# `source` is a glob relative to repo root; `dest` is a path relative to
# repo root. A trailing `/` on dest means "place files inside this
# directory".
[[copy]]
source = "<glob>"
dest = "<path>"
```

### C. Guidelines

- Include `[[setup]]` for: dependency install (`bun install`, `npm ci`,
  `cargo fetch`, `uv sync`, `bundle install`), copying example env files
  (`cp .env.example .env`), and project-specific bootstrap scripts found
  in `scripts/`, `Makefile`, or `package.json`'s `scripts.setup`.
- Include `[[copy]]` for: `.env*` files (but NOT `.env.example`, which git
  already tracks), `*.local.*` files, and any local-only secrets the
  `.gitignore` lists that would break dev if missing.
- If nothing obvious is detected, emit a short header comment saying so
  and leave both arrays empty.
- Omit `worktree_dir`, `setup_timeout`, `shell_ready_delay`, and
  `[layout]` — they are intentionally out of scope.

### D. Two few-shot examples

1. A Node/Bun repo → shows `bun install` + `.env.local` copy.
2. A Swift/XcodeGen repo (like tian itself) → shows `xcodegen generate`
   and the Ghostty symlink setup.

Both examples end with the literal TOML output the model should produce,
so it learns the exact formatting (including comment headers).

## Error handling

| Failure | Message | Exit code |
|---|---|---|
| Not inside a git repo | `Not a git repository. Run this command from inside the repo you want to configure.` | 2 |
| `claude` CLI not on PATH | `Could not find 'claude' on PATH. Install the Claude CLI from https://claude.com/claude-code and retry.` | 127 |
| `.tian/config.toml` exists, no `--force` | `.tian/config.toml already exists. Re-run with --force to overwrite.` | 1 |
| `claude -p` exits non-zero | `claude -p failed (exit N). stderr:\n<last 20 lines>` | forwarded (N) |
| Claude output fails TOML parsing | `Claude returned invalid TOML: <parser error>. Raw output saved to .tian/config.toml.rejected.` | 3 |
| Cannot write `.tian/config.toml` | `Failed to write .tian/config.toml: <system error>` | 4 |

All errors are raised as `CLIError`; `CommandLogger.log(...)` already
records exit codes, so no logging changes are needed.

Explicitly **not** handled: network / model errors inside `claude -p`
surface as its own non-zero exit — we do not reimplement its diagnostics.

## Testing

Unit tests go in `tianTests/` (the existing test bundle). If the CLI
source files are not already members of the test target, add them in
`project.yml` and regenerate with `xcodegen generate` (per `CLAUDE.md`).

### `ConfigAutoSetTests`

- `test_refusesWhenFileExistsWithoutForce` — precreate the file, run,
  assert `CLIError` + file unchanged.
- `test_overwritesWithForce` — precreate, run with `--force`, assert new
  content.
- `test_rejectsNonGitDirectory` — run in a tmp dir without `.git`, assert
  `CLIError` with "Not a git repository".
- `test_invalidTOMLFromClaudeWritesRejectedFile` — stub `ClaudeInvoker`
  to return malformed TOML, assert `.tian/config.toml.rejected` exists,
  `.tian/config.toml` does not, and exit code is 3.
- `test_writesValidConfig` — stub `ClaudeInvoker` to return known-good
  TOML, assert file contents match and `WorktreeConfigParser` accepts it.

### `AutoSetPromptTests`

- `test_templateContainsSchemaAnchors` — asserts the template contains
  `[[setup]]`, `[[copy]]`, and the literal "output ONLY valid TOML"
  directive. Guards against accidental prompt regressions.

### Not unit-tested

`ProcessClaudeInvoker` is a thin subprocess wrapper. Manual smoke testing
is the acceptance gate.

### Manual smoke tests

1. Scratch Node repo — assert generated config passes
   `WorktreeConfigParser.parse` and contains `bun install` or `npm ci`.
2. This tian repo — assert it detects `scripts/build-ghostty.sh` and/or
   `xcodegen generate`.
3. Run with `--force` over the existing file; compare diff.

## Rejected alternatives

**Streaming with `--output-format stream-json`.** Would render a live
"Claude is reading package.json…" log, but requires a stream-JSON parser
and Claude-CLI-version coupling. Deferred until the spinner-only UX proves
insufficient.

**Swift pre-gathering + JSON output.** Walk the repo in Swift, stuff file
contents into the prompt, use `--output-format json`, convert JSON→TOML in
Swift. Deterministic but reinvents what Claude already does well, and adds
a JSON→TOML serializer to maintain. Rejected.

**Runnable outside a tian session.** More flexible, but inconsistent with
every other `tian-cli` subcommand. Can be lifted later if users ask for
it.

**Auto-generating `[layout]`.** Useful but open-ended — "what pane
commands does this project want?" doesn't have a good answer without more
context than the filesystem can provide. Deferred to a later iteration.
