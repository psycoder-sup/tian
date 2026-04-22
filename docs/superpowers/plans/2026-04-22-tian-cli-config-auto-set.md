# `tian-cli config --auto-set` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `tian config auto-set` subcommand that shells out to `claude -p` with read-only tools and writes a validated `.tian/config.toml` populated with `[[setup]]` and `[[copy]]` sections reflecting the current repo.

**Architecture:** One new subcommand group (`ConfigGroup`) in `tian-cli/` wired into `main.swift`. Orchestration lives in a pure-Swift `ConfigAutoSetRunner` that is unit-tested with a stubbed `ClaudeInvoker`. The real `ProcessClaudeInvoker` spawns `claude -p` and captures stdout. Output is validated with a small TOMLKit-based `ConfigValidator` (we do not share `WorktreeConfigParser` across targets for v1).

**Tech Stack:** Swift 6.0, `swift-argument-parser` (tian-cli target), `TOMLKit` (transitive via `tian` target), Swift Testing, XcodeGen, xcodebuild. macOS 26 only.

**Spec reference:** `docs/superpowers/specs/2026-04-22-tian-cli-config-auto-set-design.md`

---

## File Structure

### New files

| Path | Responsibility | Test target? |
|---|---|---|
| `tian-cli/AutoSetPrompt.swift` | Pure string constant — prompt template with schema + guidelines + few-shot examples. | Yes (shared) |
| `tian-cli/ConfigValidator.swift` | Validates a TOML string parses and has well-formed `[[setup]]` / `[[copy]]` entries. Returns counts. | Yes (shared) |
| `tian-cli/ClaudeInvoker.swift` | Protocol `ClaudeInvoker` + real `ProcessClaudeInvoker` that spawns `claude -p`. | Yes (shared) |
| `tian-cli/ConfigAutoSetRunner.swift` | Pure-Swift orchestrator: resolve repo root, check existing, invoke, validate, atomic write. Injects `ClaudeInvoker`. | Yes (shared) |
| `tian-cli/ConfigGroup.swift` | `ArgumentParser` command types (`ConfigGroup`, `ConfigAutoSet`) that glue CLI flags into `ConfigAutoSetRunner`. | **No** — ArgumentParser is not available to the test target. |
| `tianTests/AutoSetPromptTests.swift` | Regression tests for prompt anchors. | — |
| `tianTests/ConfigValidatorTests.swift` | TOML validator unit tests. | — |
| `tianTests/ConfigAutoSetRunnerTests.swift` | Runner unit tests with `StubClaudeInvoker`. | — |

### Modified files

| Path | Change |
|---|---|
| `tian-cli/main.swift:10-19` | Add `ConfigGroup.self` to `TianCLI.configuration.subcommands`. |
| `project.yml:170-172` | Under `tianTests.sources`, add four `tian-cli/…` shared source entries. |

### Rationale for the split

- `ConfigGroup.swift` is the **only** file that imports `ArgumentParser`. This lets every other tian-cli source file be shared with `tianTests` via `project.yml` without pulling ArgumentParser into the test bundle.
- `ConfigAutoSetRunner` is testable because its single dependency on the outside world — spawning `claude` — is behind the `ClaudeInvoker` protocol.
- `ConfigValidator` is a separate tiny enum (not merged into the runner) so its unit tests can exercise malformed TOML directly without going through the runner.

### Deviations from the spec

1. **Exit codes.** The spec listed distinct exit codes per failure (1/2/3/4/127). To avoid extending `CLIError` with new cases whose semantics overlap existing ones, **all tian-cli-side failures use `CLIError.general` → exit 1**. User-facing error *messages* are preserved exactly. This is a UX-invariant simplification.
2. **TOML validation.** The spec said "validate with the existing `WorktreeConfigParser`". That parser lives in the `tian` app target and has transitive dependencies on `Log`, `WorktreeError`, and `SplitDirection` — sharing it with `tian-cli` is more churn than re-implementing the tiny subset of validation we actually need. tian-cli gets its own `ConfigValidator` using `TOMLKit` (already a transitive dep of `tian`, which `tianTests` links against).

---

## Task 1: Project scaffolding

**Files:**
- Create empty: `tian-cli/AutoSetPrompt.swift`, `tian-cli/ConfigValidator.swift`, `tian-cli/ClaudeInvoker.swift`, `tian-cli/ConfigAutoSetRunner.swift`, `tian-cli/ConfigGroup.swift`
- Modify: `project.yml:167-174` (tianTests sources)

**Purpose:** Get the file structure and Xcode project in place so subsequent TDD tasks can build.

- [ ] **Step 1: Create the five empty Swift files.**

Each file should contain a single line so the compiler treats it as a valid empty Swift file:

```bash
for f in AutoSetPrompt ConfigValidator ClaudeInvoker ConfigAutoSetRunner ConfigGroup; do
  printf 'import Foundation\n' > "tian-cli/$f.swift"
done
```

- [ ] **Step 2: Update `project.yml` tianTests sources.**

Find lines 170-172:

```yaml
    sources:
      - path: tianTests
      - path: tian-cli/CommandLogger.swift
```

Replace with:

```yaml
    sources:
      - path: tianTests
      - path: tian-cli/CommandLogger.swift
      - path: tian-cli/AutoSetPrompt.swift
      - path: tian-cli/ConfigValidator.swift
      - path: tian-cli/ClaudeInvoker.swift
      - path: tian-cli/ConfigAutoSetRunner.swift
      - path: tian-cli/CLIError.swift
```

(We also include `CLIError.swift` because the runner throws `CLIError.general` and tests need to match against it.)

- [ ] **Step 3: Regenerate Xcode project.**

Run: `xcodegen generate`
Expected: `Generated project successfully.` (or equivalent); no errors. `tian.xcodeproj` is updated.

- [ ] **Step 4: Baseline build to confirm scaffolding is green.**

Run: `scripts/build.sh Debug`
Expected: Build succeeds. `tian-cli/*.swift` are empty (just `import Foundation`) so no symbols are added yet.

- [ ] **Step 5: Commit.**

```bash
git add tian-cli/AutoSetPrompt.swift tian-cli/ConfigValidator.swift \
        tian-cli/ClaudeInvoker.swift tian-cli/ConfigAutoSetRunner.swift \
        tian-cli/ConfigGroup.swift project.yml
git commit -m "🔧 chore(cli): scaffold config auto-set source files"
```

---

## Task 2: `AutoSetPrompt.template` constant

**Files:**
- Modify: `tian-cli/AutoSetPrompt.swift`
- Create: `tianTests/AutoSetPromptTests.swift`

**Purpose:** Hold the `claude -p` prompt as a stable, diffable, unit-testable Swift string constant.

- [ ] **Step 1: Write the failing test.**

Create `tianTests/AutoSetPromptTests.swift`:

```swift
import Testing
import Foundation

struct AutoSetPromptTests {

    @Test func templateContainsTaskStatement() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("Output ONLY valid TOML"))
        #expect(prompt.contains("no markdown fences"))
    }

    @Test func templateContainsSchemaAnchors() {
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("[[setup]]"))
        #expect(prompt.contains("[[copy]]"))
        #expect(prompt.contains("command = "))
        #expect(prompt.contains("source = "))
        #expect(prompt.contains("dest = "))
    }

    @Test func templateListsOutOfScopeFields() {
        // Guidelines should tell Claude to omit these.
        let prompt = AutoSetPrompt.template
        #expect(prompt.contains("worktree_dir"))
        #expect(prompt.contains("layout"))
        #expect(prompt.contains("intentionally out of scope"))
    }

    @Test func templateIncludesFewShotExamples() {
        let prompt = AutoSetPrompt.template
        // Node example
        #expect(prompt.contains("bun install"))
        // Swift/XcodeGen example (this repo)
        #expect(prompt.contains("xcodegen generate"))
    }
}
```

- [ ] **Step 2: Run the test to confirm it fails.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/AutoSetPromptTests 2>&1 | tail -40
```
Expected: Build error — `AutoSetPrompt` is undefined (file only has `import Foundation`).

- [ ] **Step 3: Implement `AutoSetPrompt.template`.**

Replace the contents of `tian-cli/AutoSetPrompt.swift` with:

```swift
import Foundation

/// Prompt template for `tian config auto-set`.
///
/// Held as a single static constant so it is diffable, reviewable, and
/// unit-testable without invoking `claude -p`.
enum AutoSetPrompt {
    static let template: String = """
    Analyze this repository and generate a `.tian/config.toml` file.

    Output ONLY valid TOML — no markdown fences, no explanation, no prose.
    Do not wrap the output in triple backticks.

    # Schema

    Only these two sections are in scope. Omit everything else.

    ```
    # [[setup]] — one-shot shell commands run once when a worktree is
    # created for this repo. Each [[setup]] is an independent entry with
    # a required `command` field. Commands run sequentially with the
    # worktree root as cwd.
    [[setup]]
    command = "<shell command>"

    # [[copy]] — files copied from the main worktree into each new worktree.
    # `source` is a glob relative to repo root; `dest` is a path relative
    # to repo root. A trailing `/` on dest means "place files inside this
    # directory".
    [[copy]]
    source = "<glob>"
    dest = "<path>"
    ```

    # Guidelines

    - Include `[[setup]]` for: dependency install (`bun install`,
      `npm ci`, `cargo fetch`, `uv sync`, `bundle install`), copying
      example env files (`cp .env.example .env`), and project-specific
      bootstrap scripts found in `scripts/`, `Makefile`, or
      `package.json`'s `scripts.setup`.
    - Include `[[copy]]` for: `.env*` files (but NOT `.env.example`,
      which git already tracks), `*.local.*` files, and local-only
      secrets the `.gitignore` lists that would break dev if missing.
    - If nothing obvious is detected, emit a short header comment
      saying so and leave both arrays empty.
    - Omit `worktree_dir`, `setup_timeout`, `shell_ready_delay`, and
      `[layout]` — they are intentionally out of scope for this command.

    # Examples

    ## Example 1: Node/Bun repo

    Given a repo with `package.json` containing `"packageManager": "bun@1"`,
    a `.env.example` tracked in git, and a `.env.local` in `.gitignore`,
    output:

    # tian worktree config — auto-generated by `tian config auto-set`
    [[setup]]
    command = "bun install"

    [[setup]]
    command = "cp .env.example .env"

    [[copy]]
    source = ".env.local"
    dest = "."

    ## Example 2: Swift / XcodeGen repo

    Given a repo with `project.yml`, `scripts/build-ghostty.sh`, and a
    `.ghostty-src` symlink in `.gitignore`, output:

    # tian worktree config — auto-generated by `tian config auto-set`
    [[setup]]
    command = "xcodegen generate"

    [[setup]]
    command = "MAIN=$(dirname \\"$(git rev-parse --path-format=absolute --git-common-dir)\\") && ln -sfn \\"$MAIN/.ghostty-src\\" .ghostty-src"

    Now analyze the current repository (your `cwd` is the repo root) and
    produce the TOML.
    """
}
```

- [ ] **Step 4: Run the test to confirm it passes.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/AutoSetPromptTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` and all four `@Test` cases pass.

- [ ] **Step 5: Commit.**

```bash
git add tian-cli/AutoSetPrompt.swift tianTests/AutoSetPromptTests.swift
git commit -m "✨ feat(cli): add auto-set prompt template"
```

---

## Task 3: `ConfigValidator` — TOML structure validation

**Files:**
- Modify: `tian-cli/ConfigValidator.swift`
- Create: `tianTests/ConfigValidatorTests.swift`

**Purpose:** Validate Claude's TOML output has well-formed `[[setup]]` and `[[copy]]` entries, and return counts for the success message.

- [ ] **Step 1: Write failing tests.**

Create `tianTests/ConfigValidatorTests.swift`:

```swift
import Testing
import Foundation

struct ConfigValidatorTests {

    @Test func emptyTOMLIsValidWithZeroCounts() throws {
        let result = try ConfigValidator.validate(tomlString: "")
        #expect(result.setupCount == 0)
        #expect(result.copyCount == 0)
    }

    @Test func commentsOnlyIsValid() throws {
        let toml = "# nothing to configure\n"
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 0)
        #expect(result.copyCount == 0)
    }

    @Test func countsSetupEntries() throws {
        let toml = """
        [[setup]]
        command = "bun install"

        [[setup]]
        command = "cp .env.example .env"
        """
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 2)
        #expect(result.copyCount == 0)
    }

    @Test func countsCopyEntries() throws {
        let toml = """
        [[copy]]
        source = ".env*"
        dest = "."

        [[copy]]
        source = "config/local.yml"
        dest = "config/"
        """
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 0)
        #expect(result.copyCount == 2)
    }

    @Test func rejectsMalformedTOML() {
        let toml = "this is = = not valid toml"
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml)
        }
    }

    @Test func rejectsSetupMissingCommand() {
        let toml = """
        [[setup]]
        # missing `command`
        """
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml)
        }
    }

    @Test func rejectsCopyMissingSourceOrDest() {
        let toml1 = """
        [[copy]]
        dest = "."
        """
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml1)
        }

        let toml2 = """
        [[copy]]
        source = ".env*"
        """
        #expect(throws: CLIError.self) {
            try ConfigValidator.validate(tomlString: toml2)
        }
    }

    @Test func ignoresUnknownTopLevelFields() throws {
        // We don't generate `worktree_dir`/`[layout]` but if Claude
        // produces them anyway, validation still passes (they're just
        // ignored — WorktreeConfigParser will handle them at app read time).
        let toml = """
        worktree_dir = "~/.worktrees"

        [[setup]]
        command = "bun install"
        """
        let result = try ConfigValidator.validate(tomlString: toml)
        #expect(result.setupCount == 1)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigValidatorTests 2>&1 | tail -30
```
Expected: Build error — `ConfigValidator` and `ConfigValidationResult` are undefined.

- [ ] **Step 3: Implement `ConfigValidator`.**

Replace contents of `tian-cli/ConfigValidator.swift`:

```swift
import Foundation
import TOMLKit

/// Counts of well-formed entries in a validated config.
struct ConfigValidationResult: Equatable {
    let setupCount: Int
    let copyCount: Int
}

/// Validates the TOML produced by `claude -p` has well-formed
/// `[[setup]]` and `[[copy]]` entries.
///
/// Does **not** validate the full `WorktreeConfig` schema — that is the
/// app's job when it reads the file at worktree-creation time. We only
/// check the two sections this CLI is meant to generate.
enum ConfigValidator {
    static func validate(tomlString: String) throws -> ConfigValidationResult {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: tomlString)
        } catch let error as TOMLParseError {
            throw CLIError.general(
                "Claude returned invalid TOML: line \(error.source.begin.line): \(error.description)"
            )
        } catch {
            throw CLIError.general(
                "Claude returned invalid TOML: \(error.localizedDescription)"
            )
        }

        var setupCount = 0
        if let setupArray = table["setup"]?.array {
            for (i, item) in setupArray.enumerated() {
                guard let setupTable = item.table else {
                    throw CLIError.general(
                        "Invalid [[setup]] entry #\(i + 1): not a table."
                    )
                }
                guard setupTable["command"]?.string != nil else {
                    throw CLIError.general(
                        "Invalid [[setup]] entry #\(i + 1): missing required 'command' field."
                    )
                }
                setupCount += 1
            }
        }

        var copyCount = 0
        if let copyArray = table["copy"]?.array {
            for (i, item) in copyArray.enumerated() {
                guard let copyTable = item.table else {
                    throw CLIError.general(
                        "Invalid [[copy]] entry #\(i + 1): not a table."
                    )
                }
                guard copyTable["source"]?.string != nil else {
                    throw CLIError.general(
                        "Invalid [[copy]] entry #\(i + 1): missing required 'source' field."
                    )
                }
                guard copyTable["dest"]?.string != nil else {
                    throw CLIError.general(
                        "Invalid [[copy]] entry #\(i + 1): missing required 'dest' field."
                    )
                }
                copyCount += 1
            }
        }

        return ConfigValidationResult(setupCount: setupCount, copyCount: copyCount)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigValidatorTests 2>&1 | tail -15
```
Expected: All eight `@Test` cases pass.

- [ ] **Step 5: Commit.**

```bash
git add tian-cli/ConfigValidator.swift tianTests/ConfigValidatorTests.swift
git commit -m "✨ feat(cli): add TOML validator for auto-set output"
```

---

## Task 4: `ClaudeInvoker` protocol + real `ProcessClaudeInvoker`

**Files:**
- Modify: `tian-cli/ClaudeInvoker.swift`

**Purpose:** Abstract the `claude -p` subprocess behind a protocol so tests inject a stub. Provide the real `Process`-based implementation.

*No unit tests for `ProcessClaudeInvoker` — it's a thin subprocess wrapper, covered by the manual smoke test in Task 8.*

- [ ] **Step 1: Implement the protocol and real invoker.**

Replace contents of `tian-cli/ClaudeInvoker.swift`:

```swift
import Foundation

/// Invokes `claude -p` with a given prompt and returns stdout.
///
/// Extracted behind a protocol so `ConfigAutoSetRunner` tests can inject
/// a stub without spawning a real subprocess.
protocol ClaudeInvoker {
    /// - Parameters:
    ///   - prompt: The prompt to send to `claude -p`.
    ///   - cwd: Working directory for the subprocess (the repo root).
    ///   - model: Model name passed via `--model`.
    /// - Returns: Full captured stdout, UTF-8 decoded.
    /// - Throws: `CLIError.general` on spawn failure, non-zero exit, or
    ///   output decoding failure.
    func run(prompt: String, cwd: URL, model: String) throws -> String
}

/// Spawns `claude -p` with read-only tools and captures stdout.
struct ProcessClaudeInvoker: ClaudeInvoker {
    /// Path to the `claude` executable. `nil` means resolve via `PATH`.
    let claudePath: String?

    init(claudePath: String? = nil) {
        self.claudePath = claudePath
    }

    func run(prompt: String, cwd: URL, model: String) throws -> String {
        let process = Process()

        // Resolve the claude executable.
        if let override = claudePath {
            process.executableURL = URL(fileURLWithPath: override)
        } else {
            // Use /usr/bin/env so PATH resolution matches the user's shell.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        }

        var arguments: [String] = []
        if claudePath == nil { arguments.append("claude") }
        arguments.append(contentsOf: [
            "-p",
            "--allowedTools", "Read,Glob,Grep",
            "--permission-mode", "acceptEdits",
            "--model", model,
            prompt,
        ])
        process.arguments = arguments

        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // Let stderr pass through to the user's terminal so any claude
        // diagnostics are visible. (claude -p is mostly silent in text
        // mode, so this is rarely chatty.)
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw CLIError.general(
                "Could not launch claude. Install the Claude CLI (https://claude.com/claude-code) or pass --claude-path. Underlying error: \(error.localizedDescription)"
            )
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CLIError.general(
                "claude -p failed (exit \(process.terminationStatus)). See stderr above for details."
            )
        }

        guard let output = String(data: stdoutData, encoding: .utf8) else {
            throw CLIError.general("claude -p output was not valid UTF-8.")
        }

        return output
    }
}
```

- [ ] **Step 2: Build to confirm it compiles.**

Run: `scripts/build.sh Debug`
Expected: Build succeeds; no test regressions (nothing calls the new types yet).

- [ ] **Step 3: Commit.**

```bash
git add tian-cli/ClaudeInvoker.swift
git commit -m "✨ feat(cli): add ClaudeInvoker protocol and Process implementation"
```

---

## Task 5: `ConfigAutoSetRunner` — resolve repo root

**Files:**
- Modify: `tian-cli/ConfigAutoSetRunner.swift`
- Create (new tests file): `tianTests/ConfigAutoSetRunnerTests.swift`

**Purpose:** Start the runner with its simplest helper: find the repo root from a cwd. Subsequent tasks layer the rest of the orchestration onto this skeleton.

- [ ] **Step 1: Write failing tests.**

Create `tianTests/ConfigAutoSetRunnerTests.swift`:

```swift
import Testing
import Foundation

struct ConfigAutoSetRunnerTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-auto-set-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Initializes a bare git repo at the given directory.
    private func gitInit(at dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "init", "-q"]
        p.currentDirectoryURL = dir
        try p.run()
        p.waitUntilExit()
        precondition(p.terminationStatus == 0, "git init failed")
    }

    // MARK: - resolveRepoRoot

    @Test func resolveRepoRoot_returnsRepoRoot_whenCwdIsInsideRepo() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let sub = tmp.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let runner = ConfigAutoSetRunner(invoker: StubClaudeInvoker(output: ""))
        let resolved = try runner.resolveRepoRoot(from: sub)

        // resolvingSymlinksInPath() normalizes /var/ vs /private/var/ on macOS.
        #expect(resolved.resolvingSymlinksInPath() == tmp.resolvingSymlinksInPath())
    }

    @Test func resolveRepoRoot_throws_whenCwdIsNotInsideRepo() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        // No `git init` — tmp is not a repo.

        let runner = ConfigAutoSetRunner(invoker: StubClaudeInvoker(output: ""))
        #expect(throws: CLIError.self) {
            try runner.resolveRepoRoot(from: tmp)
        }
    }
}

// MARK: - StubClaudeInvoker

/// Test double that returns pre-configured output and records calls.
final class StubClaudeInvoker: ClaudeInvoker {
    var output: String
    var error: Error?
    private(set) var calls: [(prompt: String, cwd: URL, model: String)] = []

    init(output: String = "", error: Error? = nil) {
        self.output = output
        self.error = error
    }

    func run(prompt: String, cwd: URL, model: String) throws -> String {
        calls.append((prompt: prompt, cwd: cwd, model: model))
        if let error { throw error }
        return output
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigAutoSetRunnerTests 2>&1 | tail -30
```
Expected: Build error — `ConfigAutoSetRunner` is undefined.

- [ ] **Step 3: Implement the runner skeleton with `resolveRepoRoot`.**

Replace contents of `tian-cli/ConfigAutoSetRunner.swift`:

```swift
import Foundation

/// Result of a successful `config auto-set` run.
struct ConfigAutoSetResult: Equatable {
    let setupCount: Int
    let copyCount: Int
}

/// Orchestrates `tian config auto-set`: resolves the repo, invokes
/// `claude -p`, validates the output, and writes `.tian/config.toml`.
///
/// Pure Swift — no dependency on `ArgumentParser`. All outside-world
/// behavior (spawning `claude`, etc.) is behind the `ClaudeInvoker`
/// protocol for testability.
struct ConfigAutoSetRunner {
    let invoker: ClaudeInvoker

    /// Runs `git rev-parse --show-toplevel` from the given cwd and
    /// returns the repo root URL.
    func resolveRepoRoot(from cwd: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "--show-toplevel"]
        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe() // swallow git's error output

        do {
            try process.run()
        } catch {
            throw CLIError.general(
                "Could not launch git: \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CLIError.general(
                "Not a git repository. Run this command from inside the repo you want to configure."
            )
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else {
            throw CLIError.general("git output was not valid UTF-8.")
        }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw CLIError.general("git rev-parse returned empty output.")
        }
        return URL(fileURLWithPath: path)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigAutoSetRunnerTests 2>&1 | tail -15
```
Expected: Both test cases pass.

- [ ] **Step 5: Commit.**

```bash
git add tian-cli/ConfigAutoSetRunner.swift tianTests/ConfigAutoSetRunnerTests.swift
git commit -m "✨ feat(cli): add ConfigAutoSetRunner.resolveRepoRoot"
```

---

## Task 6: Runner `run()` — happy path

**Files:**
- Modify: `tian-cli/ConfigAutoSetRunner.swift`
- Modify: `tianTests/ConfigAutoSetRunnerTests.swift`

**Purpose:** Full happy-path orchestration: resolve repo → invoke → validate → atomic write → return counts.

- [ ] **Step 1: Add failing tests.**

Append these test cases inside `struct ConfigAutoSetRunnerTests`:

```swift
    // MARK: - run() happy path

    @Test func run_writesConfigFile_fromValidTOML() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let toml = """
        # tian worktree config — auto-generated by `tian config auto-set`
        [[setup]]
        command = "bun install"

        [[copy]]
        source = ".env.local"
        dest = "."
        """
        let stub = StubClaudeInvoker(output: toml)
        let runner = ConfigAutoSetRunner(invoker: stub)

        let result = try runner.run(cwd: tmp, force: false, model: "sonnet")

        #expect(result.setupCount == 1)
        #expect(result.copyCount == 1)

        // File written at <repo>/.tian/config.toml.
        let configURL = tmp.appendingPathComponent(".tian/config.toml")
        #expect(FileManager.default.fileExists(atPath: configURL.path))
        let written = try String(contentsOf: configURL, encoding: .utf8)
        #expect(written == toml)

        // Invoker received the cwd and model.
        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].cwd.resolvingSymlinksInPath() == tmp.resolvingSymlinksInPath())
        #expect(stub.calls[0].model == "sonnet")
    }

    @Test func run_createsDotTianDirectory_ifMissing() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)
        // No .tian/ dir yet.

        let stub = StubClaudeInvoker(output: "")
        let runner = ConfigAutoSetRunner(invoker: stub)

        _ = try runner.run(cwd: tmp, force: false, model: "sonnet")

        var isDir: ObjCBool = false
        let dotTian = tmp.appendingPathComponent(".tian").path
        #expect(FileManager.default.fileExists(atPath: dotTian, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }
```

- [ ] **Step 2: Run tests to confirm they fail.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigAutoSetRunnerTests 2>&1 | tail -30
```
Expected: Build error — `ConfigAutoSetRunner.run(cwd:force:model:)` is undefined.

- [ ] **Step 3: Add `run()` to the runner.**

In `tian-cli/ConfigAutoSetRunner.swift`, add this method inside `struct ConfigAutoSetRunner`:

```swift
    /// Top-level orchestration for `tian config auto-set`.
    ///
    /// - Parameters:
    ///   - cwd: User's current working directory.
    ///   - force: Overwrite an existing `.tian/config.toml` if true.
    ///   - model: Claude model name passed through to `claude -p --model`.
    /// - Returns: Counts of setup/copy entries written.
    /// - Throws: `CLIError` on any failure.
    @discardableResult
    func run(cwd: URL, force: Bool, model: String) throws -> ConfigAutoSetResult {
        let repoRoot = try resolveRepoRoot(from: cwd)
        let configURL = repoRoot
            .appendingPathComponent(".tian")
            .appendingPathComponent("config.toml")

        if FileManager.default.fileExists(atPath: configURL.path) && !force {
            throw CLIError.general(
                ".tian/config.toml already exists. Re-run with --force to overwrite."
            )
        }

        FileHandle.standardError.write(Data(
            "Analyzing repository with claude -p (this usually takes 20–60s)…\n".utf8
        ))

        let tomlString = try invoker.run(
            prompt: AutoSetPrompt.template,
            cwd: repoRoot,
            model: model
        )

        let validation: ConfigValidationResult
        do {
            validation = try ConfigValidator.validate(tomlString: tomlString)
        } catch {
            try? writeRejectedOutput(tomlString, repoRoot: repoRoot)
            throw CLIError.general(
                "\(error.localizedDescription) Raw output saved to .tian/config.toml.rejected."
            )
        }

        try writeConfig(tomlString, to: configURL)

        return ConfigAutoSetResult(
            setupCount: validation.setupCount,
            copyCount: validation.copyCount
        )
    }

    // MARK: - File writes

    /// Atomically writes the validated TOML to `.tian/config.toml`.
    private func writeConfig(_ tomlString: String, to configURL: URL) throws {
        let dir = configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        } catch {
            throw CLIError.general(
                "Failed to create \(dir.path): \(error.localizedDescription)"
            )
        }

        let tmpURL = configURL.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tmpURL) // clear stale tmp
        do {
            try tomlString.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            throw CLIError.general(
                "Failed to write \(tmpURL.path): \(error.localizedDescription)"
            )
        }

        // Atomic replace. If the destination doesn't exist,
        // replaceItemAt throws, so fall back to a plain move.
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                _ = try FileManager.default.replaceItemAt(configURL, withItemAt: tmpURL)
            } catch {
                throw CLIError.general(
                    "Failed to replace \(configURL.path): \(error.localizedDescription)"
                )
            }
        } else {
            do {
                try FileManager.default.moveItem(at: tmpURL, to: configURL)
            } catch {
                throw CLIError.general(
                    "Failed to move \(tmpURL.path) → \(configURL.path): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Writes Claude's raw output to `.tian/config.toml.rejected` for
    /// user inspection when validation fails.
    private func writeRejectedOutput(_ tomlString: String, repoRoot: URL) throws {
        let dir = repoRoot.appendingPathComponent(".tian")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rejected = dir.appendingPathComponent("config.toml.rejected")
        try tomlString.write(to: rejected, atomically: true, encoding: .utf8)
    }
```

- [ ] **Step 4: Run tests to confirm they pass.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigAutoSetRunnerTests 2>&1 | tail -15
```
Expected: The two new test cases pass (plus the two from Task 5 still pass → 4 total).

- [ ] **Step 5: Commit.**

```bash
git add tian-cli/ConfigAutoSetRunner.swift tianTests/ConfigAutoSetRunnerTests.swift
git commit -m "✨ feat(cli): implement auto-set happy-path orchestration"
```

---

## Task 7: Runner `run()` — overwrite guard

**Files:**
- Modify: `tianTests/ConfigAutoSetRunnerTests.swift`

**Purpose:** Verify that an existing `.tian/config.toml` is preserved unless `--force` is passed.

*No production code changes — Task 6 already implemented the guard. We add tests to lock in the behavior.*

- [ ] **Step 1: Add failing tests.**

Append inside `struct ConfigAutoSetRunnerTests`:

```swift
    // MARK: - Overwrite guard

    @Test func run_refuses_whenConfigExists_andForceIsFalse() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        // Pre-create the file with known content.
        let dotTian = tmp.appendingPathComponent(".tian")
        try FileManager.default.createDirectory(at: dotTian, withIntermediateDirectories: true)
        let configURL = dotTian.appendingPathComponent("config.toml")
        let original = "# existing content\n"
        try original.write(to: configURL, atomically: true, encoding: .utf8)

        let stub = StubClaudeInvoker(output: "[[setup]]\ncommand = \"echo hi\"\n")
        let runner = ConfigAutoSetRunner(invoker: stub)

        #expect(throws: CLIError.self) {
            try runner.run(cwd: tmp, force: false, model: "sonnet")
        }

        // File unchanged.
        let after = try String(contentsOf: configURL, encoding: .utf8)
        #expect(after == original)

        // Invoker NOT called — we bailed before calling claude.
        #expect(stub.calls.isEmpty)
    }

    @Test func run_overwrites_whenConfigExists_andForceIsTrue() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let dotTian = tmp.appendingPathComponent(".tian")
        try FileManager.default.createDirectory(at: dotTian, withIntermediateDirectories: true)
        let configURL = dotTian.appendingPathComponent("config.toml")
        try "# existing content\n".write(to: configURL, atomically: true, encoding: .utf8)

        let newToml = "[[setup]]\ncommand = \"echo hi\"\n"
        let stub = StubClaudeInvoker(output: newToml)
        let runner = ConfigAutoSetRunner(invoker: stub)

        _ = try runner.run(cwd: tmp, force: true, model: "sonnet")

        let after = try String(contentsOf: configURL, encoding: .utf8)
        #expect(after == newToml)
        #expect(stub.calls.count == 1)
    }
```

- [ ] **Step 2: Run tests to confirm they pass.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigAutoSetRunnerTests 2>&1 | tail -15
```
Expected: All six test cases pass.

- [ ] **Step 3: Commit.**

```bash
git add tianTests/ConfigAutoSetRunnerTests.swift
git commit -m "🧪 test(cli): cover auto-set overwrite guard"
```

---

## Task 8: Runner `run()` — rejected file on validation failure

**Files:**
- Modify: `tianTests/ConfigAutoSetRunnerTests.swift`

**Purpose:** When Claude returns invalid TOML, tian-cli should not write `config.toml` but should save the raw output to `config.toml.rejected` for user inspection.

*No production code changes — Task 6 implemented this. Adding tests.*

- [ ] **Step 1: Add failing tests.**

Append inside `struct ConfigAutoSetRunnerTests`:

```swift
    // MARK: - Invalid TOML handling

    @Test func run_writesRejectedFile_onMalformedTOML() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let bad = "this is = = not valid toml\n"
        let stub = StubClaudeInvoker(output: bad)
        let runner = ConfigAutoSetRunner(invoker: stub)

        #expect(throws: CLIError.self) {
            try runner.run(cwd: tmp, force: false, model: "sonnet")
        }

        // config.toml was NOT written.
        let configURL = tmp.appendingPathComponent(".tian/config.toml")
        #expect(!FileManager.default.fileExists(atPath: configURL.path))

        // config.toml.rejected WAS written with the raw output.
        let rejectedURL = tmp.appendingPathComponent(".tian/config.toml.rejected")
        #expect(FileManager.default.fileExists(atPath: rejectedURL.path))
        let rejected = try String(contentsOf: rejectedURL, encoding: .utf8)
        #expect(rejected == bad)
    }

    @Test func run_writesRejectedFile_onMissingCommandField() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        // Valid TOML syntax, but missing required 'command' in [[setup]].
        let bad = "[[setup]]\n"
        let stub = StubClaudeInvoker(output: bad)
        let runner = ConfigAutoSetRunner(invoker: stub)

        #expect(throws: CLIError.self) {
            try runner.run(cwd: tmp, force: false, model: "sonnet")
        }

        let rejectedURL = tmp.appendingPathComponent(".tian/config.toml.rejected")
        #expect(FileManager.default.fileExists(atPath: rejectedURL.path))
    }
```

- [ ] **Step 2: Run tests to confirm they pass.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests/ConfigAutoSetRunnerTests 2>&1 | tail -15
```
Expected: All eight test cases pass.

- [ ] **Step 3: Commit.**

```bash
git add tianTests/ConfigAutoSetRunnerTests.swift
git commit -m "🧪 test(cli): cover auto-set rejected-output behavior"
```

---

## Task 9: `ConfigGroup` ArgumentParser wiring

**Files:**
- Modify: `tian-cli/ConfigGroup.swift`
- Modify: `tian-cli/main.swift:10-19`

**Purpose:** Expose the runner as a real CLI subcommand: `tian config auto-set [--force] [--model <name>] [--claude-path <path>]`.

*Not unit-tested — `ArgumentParser` is not in the test target and this file is pure wiring. Covered by the manual smoke test in Task 10.*

- [ ] **Step 1: Implement `ConfigGroup` and `ConfigAutoSet`.**

Replace contents of `tian-cli/ConfigGroup.swift`:

```swift
import ArgumentParser
import Foundation

struct ConfigGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage .tian/config.toml.",
        subcommands: [
            ConfigAutoSet.self,
        ]
    )
}

struct ConfigAutoSet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auto-set",
        abstract: "Generate .tian/config.toml using claude -p.",
        discussion: """
            Analyzes the current repository with `claude -p` (read-only \
            tools) and writes a .tian/config.toml populated with \
            [[setup]] and [[copy]] sections. Must be run from inside a \
            git repository; refuses to overwrite an existing file unless \
            --force is passed.
            """
    )

    @Flag(name: .long, help: "Overwrite an existing .tian/config.toml.")
    var force: Bool = false

    @Option(name: .long, help: "Claude model passed to `claude -p --model`.")
    var model: String = "sonnet"

    @Option(name: .long, help: "Override path to the claude executable.")
    var claudePath: String?

    func run() throws {
        // Enforce TIAN_SOCKET for UX consistency with other subcommands
        // (we do not send an IPC request — the check only validates we're
        // running inside a tian session).
        _ = try TianEnvironment.fromEnvironment()

        let invoker = ProcessClaudeInvoker(claudePath: claudePath)
        let runner = ConfigAutoSetRunner(invoker: invoker)

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let result = try runner.run(cwd: cwd, force: force, model: model)

        let setupWord = result.setupCount == 1 ? "setup command" : "setup commands"
        let copyWord = result.copyCount == 1 ? "copy rule" : "copy rules"
        FileHandle.standardError.write(Data(
            "Wrote .tian/config.toml (\(result.setupCount) \(setupWord), \(result.copyCount) \(copyWord))\n".utf8
        ))
    }
}
```

- [ ] **Step 2: Add `ConfigGroup.self` to the subcommands list.**

In `tian-cli/main.swift`, find lines 10-19:

```swift
        subcommands: [
            Ping.self,
            WorkspaceGroup.self,
            SpaceGroup.self,
            TabGroup.self,
            PaneGroup.self,
            StatusGroup.self,
            NotifyCommand.self,
            WorktreeGroup.self,
        ]
```

Replace with:

```swift
        subcommands: [
            Ping.self,
            WorkspaceGroup.self,
            SpaceGroup.self,
            TabGroup.self,
            PaneGroup.self,
            StatusGroup.self,
            NotifyCommand.self,
            WorktreeGroup.self,
            ConfigGroup.self,
        ]
```

- [ ] **Step 3: Build to confirm it compiles.**

Run: `scripts/build.sh Debug`
Expected: Build succeeds.

- [ ] **Step 4: Run the full test suite to confirm no regressions.**

Run:
```bash
xcodebuild test -project tian.xcodeproj -scheme tian \
  -derivedDataPath .build \
  -only-testing:tianTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`. All previously-passing tests still pass; no new failures.

- [ ] **Step 5: Commit.**

```bash
git add tian-cli/ConfigGroup.swift tian-cli/main.swift
git commit -m "✨ feat(cli): wire \`tian config auto-set\` subcommand"
```

---

## Task 10: Manual smoke test

**Files:** none

**Purpose:** Acceptance gate for the real `ProcessClaudeInvoker` and the full end-to-end UX (which the unit suite cannot cover).

Run from a Ghostty-backed tian session so `TIAN_SOCKET` is set. The `claude` CLI must be installed and authenticated.

- [ ] **Step 1: Scratch Node repo smoke test.**

```bash
cd /tmp
rm -rf smoke-node && mkdir smoke-node && cd smoke-node
git init -q
cat > package.json <<'JSON'
{ "name": "smoke-node", "packageManager": "bun@1.1.0",
  "scripts": { "dev": "bun run index.ts" } }
JSON
cat > .env.example <<'ENV'
API_KEY=replace-me
ENV
cat > .gitignore <<'GI'
.env.local
node_modules/
GI

tian config auto-set
```

Expected (approximately):
- stderr: `Analyzing repository with claude -p (this usually takes 20–60s)…`
- After 20–60s: `Wrote .tian/config.toml (N setup commands, M copy rules)` where `N ≥ 1` and the file contains at least `bun install`.
- `.tian/config.toml` is valid TOML (verify with `cat .tian/config.toml`).

- [ ] **Step 2: Overwrite guard smoke test.**

```bash
# From the same /tmp/smoke-node directory
tian config auto-set
```

Expected: stderr `Error: .tian/config.toml already exists. Re-run with --force to overwrite.` Exit code is non-zero (`echo $?` prints 1).

- [ ] **Step 3: `--force` smoke test.**

```bash
tian config auto-set --force
```

Expected: Overwrites the file. `git diff .tian/config.toml` may be empty (same output) or show minor whitespace differences from a new Claude run.

- [ ] **Step 4: Swift/XcodeGen repo smoke test.**

```bash
cd /Users/psycoder/.worktrees/git-pr-error/feat/config-setting
tian config auto-set --force
```

Expected: Output contains at least one of `xcodegen generate` or `scripts/build-ghostty.sh`. Verify the generated file parses by triggering a worktree creation (optional — or just inspect manually).

- [ ] **Step 5: Non-git-repo error smoke test.**

```bash
cd /tmp
mkdir smoke-nongit && cd smoke-nongit
tian config auto-set
```

Expected: stderr `Error: Not a git repository. Run this command from inside the repo you want to configure.` Exit code 1.

- [ ] **Step 6: Manual verification complete — document results inline in the PR description.**

No commit. Proceed to opening a PR once all smoke checks pass.

---

## Self-Review (for the author)

### Spec coverage
- ✅ §User-visible surface → Task 9 (flags, defaults, TIAN_SOCKET check).
- ✅ §Architecture/New file → Tasks 2, 3, 4, 5–6, 9 cover all five new files.
- ✅ §Data flow → Task 6 implements: resolve → check-existing → status line → invoke → validate → atomic write.
- ✅ §Prompt design → Task 2 ships the full template; Task 2 tests cover the schema/guidelines/examples anchors.
- ✅ §Error handling → Task 5 (not-git-repo), Task 4 (claude-not-on-PATH), Task 7 (already-exists), Task 4 (non-zero exit), Task 8 (invalid TOML), Task 6 (write failure). See "Deviations" for exit-code simplification.
- ✅ §Testing → Tasks 2, 3, 5, 6, 7, 8 cover every unit-test case listed in the spec. Task 10 covers manual smoke.
- ✅ §Non-goals → Plan does not touch `[layout]`, merge semantics, streaming, or TIAN_SOCKET-optional mode.

### Placeholder scan
None. All steps contain complete code/commands and expected outputs.

### Type consistency
- `ConfigValidationResult { setupCount, copyCount }` used consistently in Tasks 3, 6, 9.
- `ConfigAutoSetResult { setupCount, copyCount }` (separate type, same fields) used in Tasks 6, 9.
- `ClaudeInvoker.run(prompt:cwd:model:)` signature matches between Task 4 (protocol + real), Task 5 (stub), Task 6 (call site), Task 9 (wiring).
- `ConfigAutoSetRunner.run(cwd:force:model:)` matches between Task 6 (defn), Tasks 6–8 (tests), Task 9 (call site).
