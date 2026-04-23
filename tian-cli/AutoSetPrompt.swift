import Foundation

/// Prompt template for `tian-cli config auto-set`.
///
/// Held as a single static constant so it is diffable, reviewable, and
/// unit-testable without invoking `claude -p`. Output shape is enforced
/// server-side via `--json-schema` (see `AutoSetPayload.jsonSchema`), so
/// this prompt focuses on WHAT to populate — not HOW to format.
enum AutoSetPrompt {
    static let template: String = """
    Analyze this repository and decide how a fresh `git worktree` copy of \
    it should be bootstrapped. Your response is validated against a JSON \
    Schema: return `setup` (array of commands) and `copy` (array of files \
    to hydrate from the main worktree), plus optional `notes`.

    # Fields

    - `setup[].command` — a shell command run once when a worktree is \
      created, with the worktree root as cwd. Use for: dependency \
      install (`bun install`, `npm ci`, `cargo fetch`, `uv sync`, \
      `bundle install`), bootstrap scripts found in `scripts/`, \
      `Makefile`, or `package.json`'s `scripts.setup`, and project \
      generators (e.g. `xcodegen generate`). Copying example env files \
      (`cp .env.example .env`) belongs here, NOT in `copy`.
    - `copy[].source` — glob relative to repo root. Use for files the \
      `.gitignore` lists that would break dev if missing: `.env*` files \
      (but NOT `.env.example`, which git already tracks), `*.local.*` \
      files, and local-only secrets.
    - `copy[].dest` — path relative to repo root. A trailing `/` means \
      "place files inside this directory".
    - `notes` — optional, short. One or two sentences the user will see \
      as a `# comment` block above the generated TOML. Leave blank if \
      nothing noteworthy.

    # Out of scope

    Do NOT include `worktree_dir`, `setup_timeout`, \
    `shell_ready_delay`, or `layout`. They are intentionally excluded \
    from this command.

    # What to detect

    Look at: `package.json`, `Cargo.toml`, `pyproject.toml`, \
    `Gemfile`, `go.mod`, `project.yml` + XcodeGen, `Makefile`, the \
    `scripts/` directory, and `.gitignore`. If the repo has no \
    recognizable build system, return empty `setup` and `copy` arrays \
    — that is a valid response.

    # Examples

    A Node/Bun repo with `package.json` containing `"packageManager": \
    "bun@1"`, a tracked `.env.example`, and a `.gitignore` that lists \
    `.env.local`, should produce:

        setup: [{"command": "bun install"}, {"command": "cp .env.example .env"}]
        copy:  [{"source": ".env.local", "dest": "."}]

    A Swift / XcodeGen repo with `project.yml` and a `.ghostty-src` \
    symlink in `.gitignore` should produce:

        setup: [
          {"command": "xcodegen generate"},
          {"command": "MAIN=$(dirname \\"$(git rev-parse --path-format=absolute --git-common-dir)\\") && ln -sfn \\"$MAIN/.ghostty-src\\" .ghostty-src"}
        ]
        copy:  []

    Now analyze the current repository (your `cwd` is the repo root) \
    and return the `setup`, `copy`, and optional `notes` fields.
    """
}
