# Worktree Branch Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an inline combobox under the branch-name textfield that lists existing local/remote branches, making it easy to pick one when creating a worktree-backed Space. Also fix the silent-failure bug when a remote-only branch is selected.

**Architecture:** Two new layers — `BranchListService` (pure git/filesystem) and `BranchListViewModel` (`@Observable` presentation state) — integrated into the existing `BranchNameInputView`. `WorktreeService.createWorktree` gains an optional `remoteRef` parameter that, when set, uses `git worktree add --track -b <branch> <path> <remoteRef>`. `WorktreeOrchestrator` gains a `lastError` property, and `WorkspaceWindowContent` replaces its silent `try?` with an alert-bound error handler.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`). Test runner: always use the `test-runner-slim` agent. Build: `scripts/build.sh` (runs `xcodegen generate` + `xcodebuild`).

**Spec:** `docs/feature/worktree-branch-picker/worktree-branch-picker-spec.md`

---

## Task 1: Add `BranchEntry` model + `BranchListService.listBranches`

**Files:**
- Create: `tian/Worktree/BranchListService.swift`
- Create: `tianTests/BranchListServiceTests.swift`

- [ ] **Step 1.1: Write `BranchListService.swift` with model stub**

```swift
// tian/Worktree/BranchListService.swift
import Foundation
import os

struct BranchEntry: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let kind: Kind
    let committerDate: Date
    let isInUse: Bool
    let isCurrent: Bool

    enum Kind: Hashable, Sendable {
        case local(upstream: String?)
        case remote(remoteName: String)
    }
}

enum BranchListService {
    static func listBranches(repoRoot: String) async throws -> [BranchEntry] {
        fatalError("not implemented")
    }
}
```

- [ ] **Step 1.2: Run `xcodegen generate` to register the new file**

Run: `xcodegen generate`
Expected: regenerates `tian.xcodeproj` without errors.

- [ ] **Step 1.3: Write the failing tests**

```swift
// tianTests/BranchListServiceTests.swift
import Testing
import Foundation
@testable import tian

struct BranchListServiceTests {

    // MARK: - Helpers

    private struct TestError: Error { let msg: String }

    private func runGitSync(_ args: [String], in dir: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(filePath: dir)
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TestError(msg: "git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-branch-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init", "--initial-branch=main"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        let readme = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readme, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - Tests

    @Test
    func listBranches_returnsLocalBranches() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        try runGitSync(["branch", "feat/auth"], in: repo)
        try runGitSync(["branch", "feat/onboarding"], in: repo)

        let entries = try await BranchListService.listBranches(repoRoot: repo)

        let names = entries.map(\.displayName).sorted()
        #expect(names == ["feat/auth", "feat/onboarding", "main"])
        #expect(entries.allSatisfy { if case .local = $0.kind { return true } else { return false } })
    }

    @Test
    func listBranches_marksCurrentHead() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let entries = try await BranchListService.listBranches(repoRoot: repo)
        let main = try #require(entries.first { $0.displayName == "main" })
        #expect(main.isCurrent == true)
        #expect(main.isInUse == true)
    }

    @Test
    func listBranches_handlesEmptyRepoWithoutCommits() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-branch-empty-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }
        try runGitSync(["init", "--initial-branch=main"], in: dir)

        let entries = try await BranchListService.listBranches(repoRoot: dir)
        #expect(entries.isEmpty)
    }

    @Test
    func listBranches_marksInUseBranchesFromOtherWorktrees() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        try runGitSync(["branch", "feat/auth"], in: repo)
        let wtPath = (repo as NSString).appendingPathComponent("../wt-\(UUID().uuidString)")
        try runGitSync(["worktree", "add", wtPath, "feat/auth"], in: repo)
        defer { try? FileManager.default.removeItem(atPath: wtPath) }

        let entries = try await BranchListService.listBranches(repoRoot: repo)
        let auth = try #require(entries.first { $0.displayName == "feat/auth" })
        #expect(auth.isInUse == true)
    }

    @Test
    func listBranches_includesRemoteBranches() async throws {
        let remote = try makeTempGitRepo()
        defer { cleanup(remote) }
        try runGitSync(["branch", "feat/remote-only"], in: remote)

        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-clone-\(UUID().uuidString)").path
        defer { cleanup(clone) }
        try runGitSync(["clone", remote, clone], in: FileManager.default.temporaryDirectory.path)

        let entries = try await BranchListService.listBranches(repoRoot: clone)
        let remoteEntry = try #require(entries.first {
            $0.displayName == "feat/remote-only"
            && { if case .remote = $0.kind { return true } else { return false } }()
        })
        if case .remote(let name) = remoteEntry.kind {
            #expect(name == "origin")
        } else {
            Issue.record("expected remote kind")
        }
    }
}
```

- [ ] **Step 1.4: Run the tests and confirm they fail**

Dispatch the `test-runner-slim` agent:
> Run `BranchListServiceTests` via `xcodebuild test -scheme tian -derivedDataPath .build -only-testing:tianTests/BranchListServiceTests`. Report pass/fail counts and which tests failed with which error. They should fail with a `fatalError("not implemented")` trap.

Expected: all five tests fail (the service body is `fatalError`).

- [ ] **Step 1.5: Implement `listBranches`**

Replace the stub in `tian/Worktree/BranchListService.swift` with:

```swift
enum BranchListService {

    // MARK: - Public API

    static func listBranches(repoRoot: String) async throws -> [BranchEntry] {
        let inUse = try await loadInUseBranchSet(repoRoot: repoRoot)
        let currentPerWorktree = try await loadCurrentHeads(repoRoot: repoRoot)

        // format: <refname>%00<upstream>%00<committerdate:iso-strict>
        let format = "%(refname)%00%(upstream)%00%(committerdate:iso-strict)"
        let result = try await runGit(
            [
                "for-each-ref",
                "--sort=-committerdate",
                "--format=\(format)",
                "refs/heads",
                "refs/remotes",
            ],
            workingDirectory: repoRoot
        )
        guard result.exitCode == 0 else {
            throw WorktreeError.gitError(
                command: "git for-each-ref", stderr: result.stderr
            )
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        var entries: [BranchEntry] = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { continue }
            let refname = parts[0]
            let upstream = parts[1].isEmpty ? nil : parts[1]
            let dateStr = parts[2]
            let committerDate = iso.date(from: dateStr) ?? isoNoFrac.date(from: dateStr) ?? .distantPast

            if refname.hasPrefix("refs/heads/") {
                let name = String(refname.dropFirst("refs/heads/".count))
                let upstreamDisplay = upstream.map {
                    $0.hasPrefix("refs/remotes/") ? String($0.dropFirst("refs/remotes/".count)) : $0
                }
                entries.append(
                    BranchEntry(
                        id: "local:\(name)",
                        displayName: name,
                        kind: .local(upstream: upstreamDisplay),
                        committerDate: committerDate,
                        isInUse: inUse.contains(name),
                        isCurrent: currentPerWorktree.contains(name)
                    )
                )
            } else if refname.hasPrefix("refs/remotes/") {
                let trimmed = String(refname.dropFirst("refs/remotes/".count))
                if trimmed.hasSuffix("/HEAD") { continue }
                guard let slash = trimmed.firstIndex(of: "/") else { continue }
                let remoteName = String(trimmed[..<slash])
                let branchName = String(trimmed[trimmed.index(after: slash)...])
                entries.append(
                    BranchEntry(
                        id: "\(remoteName):\(branchName)",
                        displayName: branchName,
                        kind: .remote(remoteName: remoteName),
                        committerDate: committerDate,
                        isInUse: false,
                        isCurrent: false
                    )
                )
            }
        }
        return entries
    }

    // MARK: - Internals

    private static func loadInUseBranchSet(repoRoot: String) async throws -> Set<String> {
        let result = try await runGit(
            ["worktree", "list", "--porcelain"], workingDirectory: repoRoot
        )
        guard result.exitCode == 0 else {
            throw WorktreeError.gitError(
                command: "git worktree list --porcelain", stderr: result.stderr
            )
        }
        var set: Set<String> = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("branch ") {
                let full = String(line.dropFirst("branch ".count))
                if full.hasPrefix("refs/heads/") {
                    set.insert(String(full.dropFirst("refs/heads/".count)))
                }
            }
        }
        return set
    }

    private static func loadCurrentHeads(repoRoot: String) async throws -> Set<String> {
        // Same source as loadInUseBranchSet — every non-bare worktree's HEAD is its "current" branch.
        return try await loadInUseBranchSet(repoRoot: repoRoot)
    }

    private static func runGit(
        _ arguments: [String],
        workingDirectory: String
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = URL(filePath: workingDirectory)
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: (
                        process.terminationStatus,
                        String(data: outData, encoding: .utf8) ?? "",
                        String(data: errData, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 1.6: Run the tests and confirm they pass**

Dispatch `test-runner-slim`:
> Run `BranchListServiceTests` via `xcodebuild test -scheme tian -derivedDataPath .build -only-testing:tianTests/BranchListServiceTests`. All five tests should pass.

- [ ] **Step 1.7: Commit**

```bash
git add tian/Worktree/BranchListService.swift tianTests/BranchListServiceTests.swift tian.xcodeproj
git commit -m "$(cat <<'EOF'
✨ feat(worktree): add BranchListService.listBranches

Reads local and remote branches via git for-each-ref and flags
in-use/current branches via git worktree list. Foundation for the
branch picker UI.
EOF
)"
```

---

## Task 2: Add `BranchListService.fetchRemotes`

**Files:**
- Modify: `tian/Worktree/BranchListService.swift`
- Modify: `tianTests/BranchListServiceTests.swift`

- [ ] **Step 2.1: Write the failing tests**

Add to `BranchListServiceTests.swift`:

```swift
    @Test
    func fetchRemotes_refreshesRemoteRefs() async throws {
        let remote = try makeTempGitRepo()
        defer { cleanup(remote) }

        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-fetch-\(UUID().uuidString)").path
        defer { cleanup(clone) }
        try runGitSync(["clone", remote, clone], in: FileManager.default.temporaryDirectory.path)

        // Add a new branch in the remote AFTER cloning
        try runGitSync(["branch", "feat/new-after-clone"], in: remote)

        // Before fetch — the clone should not see the new branch
        let before = try await BranchListService.listBranches(repoRoot: clone)
        #expect(before.first { $0.displayName == "feat/new-after-clone" } == nil)

        // Fetch, then re-list
        try await BranchListService.fetchRemotes(repoRoot: clone)
        let after = try await BranchListService.listBranches(repoRoot: clone)
        #expect(after.first { $0.displayName == "feat/new-after-clone" } != nil)
    }

    @Test
    func fetchRemotes_throwsGitErrorOnFailure() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-bad-fetch-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }
        try runGitSync(["init"], in: dir)
        try runGitSync(["remote", "add", "origin", "/nonexistent/repo.git"], in: dir)

        await #expect(throws: WorktreeError.self) {
            try await BranchListService.fetchRemotes(repoRoot: dir)
        }
    }
```

- [ ] **Step 2.2: Run tests and confirm they fail**

Dispatch `test-runner-slim`:
> Run `BranchListServiceTests` — the two new tests should fail (method doesn't exist).

- [ ] **Step 2.3: Implement `fetchRemotes`**

Add to `BranchListService.swift` (inside the `enum BranchListService`, after `listBranches`):

```swift
    static func fetchRemotes(repoRoot: String) async throws {
        let result = try await runGit(
            ["fetch", "--all", "--prune"], workingDirectory: repoRoot
        )
        guard result.exitCode == 0 else {
            throw WorktreeError.gitError(
                command: "git fetch --all --prune", stderr: result.stderr
            )
        }
    }
```

- [ ] **Step 2.4: Run tests and confirm they pass**

Dispatch `test-runner-slim`:
> Run `BranchListServiceTests`. All tests should pass.

- [ ] **Step 2.5: Commit**

```bash
git add tian/Worktree/BranchListService.swift tianTests/BranchListServiceTests.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): add BranchListService.fetchRemotes

Wraps `git fetch --all --prune`. Used by the branch picker to refresh
remote refs in the background when the popover opens.
EOF
)"
```

---

## Task 3: Add `BranchListProviding` protocol + service wrapper

This indirection lets `BranchListViewModel` tests inject a fake without invoking git.

**Files:**
- Modify: `tian/Worktree/BranchListService.swift`

- [ ] **Step 3.1: Add the protocol and a wrapper**

Append to `tian/Worktree/BranchListService.swift` (top level):

```swift
// MARK: - Protocol for injection

protocol BranchListProviding: Sendable {
    func listBranches(repoRoot: String) async throws -> [BranchEntry]
    func fetchRemotes(repoRoot: String) async throws
}

struct BranchListServiceAdapter: BranchListProviding {
    func listBranches(repoRoot: String) async throws -> [BranchEntry] {
        try await BranchListService.listBranches(repoRoot: repoRoot)
    }
    func fetchRemotes(repoRoot: String) async throws {
        try await BranchListService.fetchRemotes(repoRoot: repoRoot)
    }
}
```

- [ ] **Step 3.2: Build to verify it compiles**

Run: `scripts/build.sh Debug`
Expected: build succeeds.

- [ ] **Step 3.3: Commit**

```bash
git add tian/Worktree/BranchListService.swift
git commit -m "$(cat <<'EOF'
♻️ refactor(worktree): extract BranchListProviding protocol

Enables dependency injection so BranchListViewModel tests can run
without invoking real git.
EOF
)"
```

---

## Task 4: `BranchListViewModel` — model + dedup logic

**Files:**
- Create: `tian/View/Worktree/BranchListViewModel.swift`
- Create: `tianTests/BranchListViewModelTests.swift`

- [ ] **Step 4.1: Create the view model stub**

```swift
// tian/View/Worktree/BranchListViewModel.swift
import Foundation
import Observation

struct BranchRow: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let badge: Badge
    let committerDate: Date
    let relativeDate: String
    let isInUse: Bool
    let isCurrent: Bool
    let remoteRef: String?    // non-nil only for remote-only rows

    enum Badge: Hashable, Sendable {
        case local
        case origin(String)           // e.g. "origin"
        case localAndOrigin(String)   // branch exists locally AND at remote
    }
}

@MainActor
@Observable
final class BranchListViewModel {
    enum Mode { case newBranch, existingBranch }
    enum Direction { case up, down }

    var query: String = "" {
        didSet { recomputeRows() }
    }
    var mode: Mode = .newBranch

    private(set) var rows: [BranchRow] = []
    private(set) var highlightedID: String?
    private(set) var isFetching: Bool = false
    private(set) var loadError: String?
    private(set) var usedCachedRemotes: Bool = false

    private var rawEntries: [BranchEntry] = []
    private let service: any BranchListProviding

    init(service: any BranchListProviding = BranchListServiceAdapter()) {
        self.service = service
    }

    // MARK: - Placeholders (filled in later tasks)

    func load(repoRoot: String) async { fatalError("not implemented") }
    func moveHighlight(_ direction: Direction) { fatalError("not implemented") }
    func selectedRow() -> BranchRow? { fatalError("not implemented") }
    func collision(for query: String) -> BranchRow? { fatalError("not implemented") }

    private func recomputeRows() { /* filled in later task */ }

    // MARK: - Dedup (implemented below)

    static func dedup(_ entries: [BranchEntry]) -> [BranchRow] {
        fatalError("not implemented")
    }

    static func formatRelative(_ date: Date, now: Date = Date()) -> String {
        fatalError("not implemented")
    }
}
```

- [ ] **Step 4.2: Run `xcodegen generate`**

Run: `xcodegen generate`

- [ ] **Step 4.3: Write the failing dedup tests**

```swift
// tianTests/BranchListViewModelTests.swift
import Testing
import Foundation
@testable import tian

@MainActor
struct BranchListViewModelTests {

    // MARK: - Fixtures

    private func entry(
        local: String? = nil,
        remote: (String, String)? = nil,      // (remoteName, branchName)
        date: Date = Date(),
        upstream: String? = nil,
        inUse: Bool = false,
        current: Bool = false
    ) -> BranchEntry {
        if let name = local {
            return BranchEntry(
                id: "local:\(name)",
                displayName: name,
                kind: .local(upstream: upstream),
                committerDate: date,
                isInUse: inUse,
                isCurrent: current
            )
        } else if let (remoteName, branchName) = remote {
            return BranchEntry(
                id: "\(remoteName):\(branchName)",
                displayName: branchName,
                kind: .remote(remoteName: remoteName),
                committerDate: date,
                isInUse: inUse,
                isCurrent: current
            )
        } else {
            fatalError("need local or remote")
        }
    }

    // MARK: - Dedup

    @Test
    func dedup_collapsesLocalAndRemoteWithSameName() {
        let now = Date()
        let raw = [
            entry(local: "feat/auth", date: now),
            entry(remote: ("origin", "feat/auth"), date: now.addingTimeInterval(-60)),
        ]
        let rows = BranchListViewModel.dedup(raw)
        #expect(rows.count == 1)
        #expect(rows[0].displayName == "feat/auth")
        #expect(rows[0].badge == .localAndOrigin("origin"))
        #expect(rows[0].remoteRef == nil)   // picking local
    }

    @Test
    func dedup_keepsRemoteOnlyAsOrigin() {
        let rows = BranchListViewModel.dedup([
            entry(remote: ("origin", "feat/x"))
        ])
        #expect(rows.count == 1)
        #expect(rows[0].badge == .origin("origin"))
        #expect(rows[0].remoteRef == "origin/feat/x")
    }

    @Test
    func dedup_keepsLocalOnlyAsLocal() {
        let rows = BranchListViewModel.dedup([
            entry(local: "feat/y")
        ])
        #expect(rows.count == 1)
        #expect(rows[0].badge == .local)
        #expect(rows[0].remoteRef == nil)
    }

    @Test
    func dedup_sortsByMostRecentCommitterDate() {
        let now = Date()
        let raw = [
            entry(local: "oldest", date: now.addingTimeInterval(-10_000)),
            entry(local: "newest", date: now),
            entry(local: "middle", date: now.addingTimeInterval(-5_000)),
        ]
        let rows = BranchListViewModel.dedup(raw)
        #expect(rows.map(\.displayName) == ["newest", "middle", "oldest"])
    }

    @Test
    func dedup_preservesInUseFlagFromLocal() {
        let now = Date()
        let raw = [
            entry(local: "main", date: now, inUse: true, current: true),
            entry(remote: ("origin", "main"), date: now),
        ]
        let rows = BranchListViewModel.dedup(raw)
        #expect(rows[0].isInUse == true)
        #expect(rows[0].isCurrent == true)
    }
}
```

- [ ] **Step 4.4: Run tests and confirm they fail**

Dispatch `test-runner-slim`:
> Run `BranchListViewModelTests` via `xcodebuild test -scheme tian -derivedDataPath .build -only-testing:tianTests/BranchListViewModelTests`. All dedup tests should fail with `fatalError("not implemented")`.

- [ ] **Step 4.5: Implement dedup + relative-date helper**

Replace the `dedup` and `formatRelative` stubs in `BranchListViewModel.swift`:

```swift
    static func dedup(_ entries: [BranchEntry]) -> [BranchRow] {
        // Sort input by committerDate desc first so local wins when picking a representative.
        let sorted = entries.sorted { $0.committerDate > $1.committerDate }

        var localsByName: [String: BranchEntry] = [:]
        var remotesByName: [String: [BranchEntry]] = [:]   // name -> [remote entries]

        for e in sorted {
            switch e.kind {
            case .local:
                localsByName[e.displayName] = e
            case .remote(let remoteName):
                remotesByName[e.displayName, default: []].append(e)
                _ = remoteName
            }
        }

        // Build rows. Walk sorted entries so date order is preserved; skip duplicates.
        var seen: Set<String> = []
        var out: [BranchRow] = []
        for e in sorted {
            if seen.contains(e.displayName) { continue }
            seen.insert(e.displayName)

            if let local = localsByName[e.displayName] {
                let remotes = remotesByName[e.displayName] ?? []
                let badge: BranchRow.Badge =
                    remotes.isEmpty ? .local : .localAndOrigin(remotes.first!.kind.remoteNameOrEmpty)
                out.append(
                    BranchRow(
                        id: local.id,
                        displayName: local.displayName,
                        badge: badge,
                        committerDate: local.committerDate,
                        relativeDate: formatRelative(local.committerDate),
                        isInUse: local.isInUse,
                        isCurrent: local.isCurrent,
                        remoteRef: nil
                    )
                )
            } else if let remote = remotesByName[e.displayName]?.first {
                let remoteName = remote.kind.remoteNameOrEmpty
                out.append(
                    BranchRow(
                        id: remote.id,
                        displayName: remote.displayName,
                        badge: .origin(remoteName),
                        committerDate: remote.committerDate,
                        relativeDate: formatRelative(remote.committerDate),
                        isInUse: false,
                        isCurrent: false,
                        remoteRef: "\(remoteName)/\(remote.displayName)"
                    )
                )
            }
        }
        return out
    }

    static func formatRelative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 86_400 * 2 { return "yesterday" }
        if seconds < 86_400 * 7 { return "\(Int(seconds / 86_400))d ago" }
        if seconds < 86_400 * 30 { return "\(Int(seconds / 86_400 / 7))w ago" }
        return "\(Int(seconds / 86_400 / 30))mo ago"
    }
```

Also add a small extension at the bottom of the file:

```swift
private extension BranchEntry.Kind {
    var remoteNameOrEmpty: String {
        if case .remote(let name) = self { return name }
        return ""
    }
}
```

- [ ] **Step 4.6: Run tests and confirm they pass**

Dispatch `test-runner-slim`:
> Run `BranchListViewModelTests`. All dedup tests should pass.

- [ ] **Step 4.7: Commit**

```bash
git add tian/View/Worktree/BranchListViewModel.swift tianTests/BranchListViewModelTests.swift tian.xcodeproj
git commit -m "$(cat <<'EOF'
✨ feat(worktree): add BranchListViewModel dedup + BranchRow

Collapses local+remote duplicates into a single row (local preferred),
sorts by committer date desc, and formats relative dates. Pure
presentation logic; no git I/O.
EOF
)"
```

---

## Task 5: `BranchListViewModel` — filter + highlight + collision

**Files:**
- Modify: `tian/View/Worktree/BranchListViewModel.swift`
- Modify: `tianTests/BranchListViewModelTests.swift`

- [ ] **Step 5.1: Write the failing tests**

Append to `BranchListViewModelTests.swift`:

```swift
    // MARK: - Fake service

    private actor FakeService: BranchListProviding {
        var entries: [BranchEntry]
        var fetchCalls = 0
        var fetchShouldThrow = false

        init(_ entries: [BranchEntry]) {
            self.entries = entries
        }

        func setEntries(_ new: [BranchEntry]) { self.entries = new }
        func setFetchShouldThrow(_ v: Bool) { fetchShouldThrow = v }

        func listBranches(repoRoot: String) async throws -> [BranchEntry] {
            entries
        }

        func fetchRemotes(repoRoot: String) async throws {
            fetchCalls += 1
            if fetchShouldThrow {
                throw WorktreeError.gitError(command: "git fetch", stderr: "no network")
            }
        }
    }

    private func makeModel(
        entries: [BranchEntry]
    ) -> (BranchListViewModel, FakeService) {
        let service = FakeService(entries)
        let model = BranchListViewModel(service: service)
        return (model, service)
    }

    // MARK: - Filter

    @Test
    func filter_isCaseInsensitiveSubstring() async {
        let (model, _) = makeModel(entries: [
            entry(local: "feat/auth"),
            entry(local: "feat/onboarding"),
            entry(local: "main"),
        ])
        await model.load(repoRoot: "/unused")
        model.query = "AUT"
        #expect(model.rows.map(\.displayName) == ["feat/auth"])
    }

    @Test
    func filter_autoHighlightsFirstMatch() async {
        let (model, _) = makeModel(entries: [
            entry(local: "feat/auth", date: Date()),
            entry(local: "feat/account", date: Date().addingTimeInterval(-60)),
        ])
        await model.load(repoRoot: "/unused")
        model.query = "feat"
        #expect(model.highlightedID == "local:feat/auth")
    }

    // MARK: - Highlight

    @Test
    func moveHighlight_skipsInUseRows() async {
        let now = Date()
        let (model, _) = makeModel(entries: [
            entry(local: "a", date: now),
            entry(local: "b", date: now.addingTimeInterval(-10), inUse: true),
            entry(local: "c", date: now.addingTimeInterval(-20)),
        ])
        await model.load(repoRoot: "/unused")
        // highlight starts on "a"
        #expect(model.highlightedID == "local:a")
        model.moveHighlight(.down)
        #expect(model.highlightedID == "local:c")  // skipped "b"
        model.moveHighlight(.up)
        #expect(model.highlightedID == "local:a")
    }

    @Test
    func selectedRow_returnsNilForInUse() async {
        let (model, _) = makeModel(entries: [
            entry(local: "main", inUse: true, current: true),
        ])
        await model.load(repoRoot: "/unused")
        // Only row is in-use — highlight should be nil.
        #expect(model.highlightedID == nil)
        #expect(model.selectedRow() == nil)
    }

    // MARK: - Collision

    @Test
    func collision_returnsMatchingRowInNewBranchMode() async {
        let (model, _) = makeModel(entries: [
            entry(local: "main"),
        ])
        await model.load(repoRoot: "/unused")
        model.mode = .newBranch
        #expect(model.collision(for: "main")?.displayName == "main")
        #expect(model.collision(for: "feat/new") == nil)
    }
```

- [ ] **Step 5.2: Run tests and confirm they fail**

Dispatch `test-runner-slim`:
> Run `BranchListViewModelTests`. The new tests should fail (load/moveHighlight/etc are still `fatalError`).

- [ ] **Step 5.3: Implement filter, highlight, selectedRow, collision**

Replace the four stubs and `recomputeRows` in `BranchListViewModel.swift`:

```swift
    func load(repoRoot: String) async {
        // Placeholder until Task 6. For now just populate from the service once.
        do {
            rawEntries = try await service.listBranches(repoRoot: repoRoot)
            loadError = nil
        } catch {
            rawEntries = []
            loadError = error.localizedDescription
        }
        recomputeRows()
    }

    func moveHighlight(_ direction: Direction) {
        let selectable = rows.filter { !$0.isInUse }
        guard !selectable.isEmpty else { highlightedID = nil; return }

        if let current = highlightedID,
           let idx = selectable.firstIndex(where: { $0.id == current }) {
            let nextIdx: Int
            switch direction {
            case .down: nextIdx = (idx + 1) % selectable.count
            case .up:   nextIdx = (idx - 1 + selectable.count) % selectable.count
            }
            highlightedID = selectable[nextIdx].id
        } else {
            highlightedID = selectable.first?.id
        }
    }

    func selectedRow() -> BranchRow? {
        guard let id = highlightedID else { return nil }
        return rows.first { $0.id == id && !$0.isInUse }
    }

    func collision(for query: String) -> BranchRow? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return rows.first { $0.displayName == q }
    }

    private func recomputeRows() {
        let deduped = Self.dedup(rawEntries)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [BranchRow]
        if q.isEmpty {
            filtered = deduped
        } else {
            filtered = deduped.filter { $0.displayName.lowercased().contains(q) }
        }
        rows = filtered
        // Re-anchor highlight on the first selectable row in the new filtered list.
        if let first = filtered.first(where: { !$0.isInUse }) {
            highlightedID = first.id
        } else {
            highlightedID = nil
        }
    }
```

- [ ] **Step 5.4: Run tests and confirm they pass**

Dispatch `test-runner-slim`:
> Run `BranchListViewModelTests`. All tests should pass.

- [ ] **Step 5.5: Commit**

```bash
git add tian/View/Worktree/BranchListViewModel.swift tianTests/BranchListViewModelTests.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): add filter/highlight/collision to BranchListViewModel

Case-insensitive substring filter, arrow-key highlight that skips
in-use rows, and collision() for new-branch-mode warnings.
EOF
)"
```

---

## Task 6: `BranchListViewModel.load` — cache-then-fetch flow

**Files:**
- Modify: `tian/View/Worktree/BranchListViewModel.swift`
- Modify: `tianTests/BranchListViewModelTests.swift`

- [ ] **Step 6.1: Write the failing tests**

Append to `BranchListViewModelTests.swift`:

```swift
    // MARK: - Load flow

    @Test
    func load_invokesFetchAfterInitialList() async {
        let (model, service) = makeModel(entries: [entry(local: "a")])
        await model.load(repoRoot: "/unused")
        #expect(await service.fetchCalls == 1)
        #expect(model.isFetching == false)
        #expect(model.usedCachedRemotes == false)
    }

    @Test
    func load_marksUsedCachedRemotesOnFetchFailure() async {
        let (model, service) = makeModel(entries: [entry(local: "a")])
        await service.setFetchShouldThrow(true)
        await model.load(repoRoot: "/unused")
        #expect(model.usedCachedRemotes == true)
        #expect(model.rows.map(\.displayName) == ["a"])  // cached list still shown
    }
```

- [ ] **Step 6.2: Run tests and confirm they fail**

Dispatch `test-runner-slim`:
> Run the two new tests in `BranchListViewModelTests`. They should fail — fetchCalls stays at 0 and usedCachedRemotes stays false.

- [ ] **Step 6.3: Implement the full `load` flow**

Replace the `load` method in `BranchListViewModel.swift`:

```swift
    func load(repoRoot: String) async {
        // Step 1: cache-only read (fast path)
        do {
            rawEntries = try await service.listBranches(repoRoot: repoRoot)
            loadError = nil
        } catch {
            rawEntries = []
            loadError = error.localizedDescription
        }
        recomputeRows()

        // Step 2: background fetch, refresh list when it finishes
        isFetching = true
        defer { isFetching = false }
        do {
            try await service.fetchRemotes(repoRoot: repoRoot)
            usedCachedRemotes = false
            do {
                rawEntries = try await service.listBranches(repoRoot: repoRoot)
                recomputeRows()
            } catch {
                // keep previously-loaded rows; surface the error
                loadError = error.localizedDescription
            }
        } catch {
            usedCachedRemotes = true
            // silent fallback — cached rows already displayed
        }
    }
```

- [ ] **Step 6.4: Run tests and confirm they pass**

Dispatch `test-runner-slim`:
> Run `BranchListViewModelTests`. All tests should pass.

- [ ] **Step 6.5: Commit**

```bash
git add tian/View/Worktree/BranchListViewModel.swift tianTests/BranchListViewModelTests.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): stale-then-fresh load flow in BranchListViewModel

Populates rows from the cache immediately, then fires a background
fetch and reloads when it finishes. Falls back silently to cached
remotes if fetch fails, marking usedCachedRemotes for UI display.
EOF
)"
```

---

## Task 7: `WorktreeService.createWorktree` — add `remoteRef` param

**Files:**
- Modify: `tian/Worktree/WorktreeService.swift:74-106`
- Modify: `tianTests/WorktreeServiceTests.swift`

- [ ] **Step 7.1: Write the failing tests**

Append to `tianTests/WorktreeServiceTests.swift`:

```swift
    // MARK: - Remote-only tracking

    @Test
    func createWorktree_fromRemoteOnlyBranch_createsLocalTrackingBranch() async throws {
        let remote = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(atPath: remote) }
        try runGitSync(["branch", "feat/x"], in: remote)

        let clone = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: clone) }
        try runGitSync(["clone", remote, clone], in: FileManager.default.temporaryDirectory.path)

        // "feat/x" exists only as origin/feat/x from the clone's perspective
        let path = try await WorktreeService.createWorktree(
            repoRoot: clone,
            worktreeDir: ".worktrees",
            branchName: "feat/x",
            existingBranch: false,
            remoteRef: "origin/feat/x"
        )

        // Verify local branch now exists in the clone
        let refResult = try await WorktreeServiceTestsRunner.run(
            ["rev-parse", "--verify", "refs/heads/feat/x"], in: clone
        )
        #expect(refResult.exitCode == 0)

        // Cleanup
        _ = try? await WorktreeServiceTestsRunner.run(
            ["worktree", "remove", "--force", path], in: clone
        )
    }
```

Add a small test-runner utility at the top of the same file (above `struct WorktreeServiceTests`):

```swift
// MARK: - Lightweight git runner for assertions

enum WorktreeServiceTestsRunner {
    static func run(_ args: [String], in dir: String) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(filePath: "/usr/bin/git")
                p.arguments = args
                p.currentDirectoryURL = URL(filePath: dir)
                let o = Pipe(); let e = Pipe()
                p.standardOutput = o; p.standardError = e
                do {
                    try p.run(); p.waitUntilExit()
                    continuation.resume(returning: (
                        p.terminationStatus,
                        String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                        String(data: e.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    ))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
```

- [ ] **Step 7.2: Run tests and confirm they fail**

Dispatch `test-runner-slim`:
> Run `WorktreeServiceTests`. The new test should fail to even compile — `createWorktree` doesn't have a `remoteRef` parameter yet.

- [ ] **Step 7.3: Update `createWorktree` signature and arg construction**

In `tian/Worktree/WorktreeService.swift`, replace the `createWorktree` method (currently around lines 74-106):

```swift
    static func createWorktree(
        repoRoot: String,
        worktreeDir: String,
        branchName: String,
        existingBranch: Bool,
        remoteRef: String? = nil
    ) async throws -> String {
        let base = resolveWorktreeBase(repoRoot: repoRoot, worktreeDir: worktreeDir)
        let worktreePath = (base as NSString).appendingPathComponent(branchName)

        var args: [String]
        if let remoteRef {
            args = ["worktree", "add", "--track", "-b", branchName, worktreePath, remoteRef]
        } else if existingBranch {
            args = ["worktree", "add", worktreePath, branchName]
        } else {
            args = ["worktree", "add", worktreePath, "-b", branchName]
        }

        Log.worktree.info("Creating git worktree: git \(args.joined(separator: " "))")

        let result = try await runGit(args, workingDirectory: repoRoot)
        guard result.exitCode == 0 else {
            Log.worktree.error("Failed to create worktree: \(result.stderr)")
            if result.stderr.contains("already exists") {
                if result.stderr.contains("a branch named") {
                    throw WorktreeError.branchAlreadyExists(branchName: branchName)
                }
                throw WorktreeError.worktreePathExists(path: worktreePath)
            }
            throw WorktreeError.gitError(command: "git worktree add", stderr: result.stderr)
        }

        Log.worktree.info("Created worktree at \(worktreePath) for branch \(branchName)")
        return worktreePath
    }
```

- [ ] **Step 7.4: Run tests and confirm they pass**

Dispatch `test-runner-slim`:
> Run `WorktreeServiceTests`. All existing tests plus the new remote-ref test should pass.

- [ ] **Step 7.5: Commit**

```bash
git add tian/Worktree/WorktreeService.swift tianTests/WorktreeServiceTests.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): createWorktree accepts a remoteRef for tracking

When remoteRef is provided, uses `git worktree add --track -b <branch>
<path> <remoteRef>`. Makes remote-only branch checkout work without
depending on `worktree.guessRemote` git config.
EOF
)"
```

---

## Task 8: `WorktreeOrchestrator` — `remoteRef` param, `lastError`, `presentError`

**Files:**
- Modify: `tian/Worktree/WorktreeOrchestrator.swift:15-50, 86-112`
- Modify: `tianTests/WorktreeOrchestratorTests.swift`

- [ ] **Step 8.1: Write the failing tests**

Append to `tianTests/WorktreeOrchestratorTests.swift` (inside `struct WorktreeOrchestratorTests`):

```swift
    @Test
    func createWorktreeSpace_withRemoteRef_skipsBranchExistsPreflight() async throws {
        // Seed a remote with a branch, clone it — the branch only exists as origin/feat/r in the clone.
        let remote = try makeTempGitRepo()
        defer { cleanup(remote) }
        try runGitSync(["branch", "feat/r"], in: remote)

        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-orch-clone-\(UUID().uuidString)").path
        defer { cleanup(clone) }
        try runGitSync(["clone", remote, clone], in: FileManager.default.temporaryDirectory.path)

        let (provider, _) = makeProvider(repoPath: clone)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "feat/r",
            existingBranch: true,
            remoteRef: "origin/feat/r",
            repoPath: clone
        )
        #expect(result.existed == false)
    }

    @Test
    func presentError_storesLastError() async {
        let (provider, _) = makeProvider(repoPath: "/tmp")
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)
        #expect(orchestrator.lastError == nil)

        orchestrator.presentError(
            WorktreeError.gitError(command: "test", stderr: "boom")
        )
        #expect(orchestrator.lastError != nil)
    }
```

- [ ] **Step 8.2: Run tests and confirm they fail**

Dispatch `test-runner-slim`:
> Run `WorktreeOrchestratorTests`. The two new tests should fail to compile — `remoteRef` and `lastError` don't exist yet.

- [ ] **Step 8.3: Update `WorktreeOrchestrator`**

In `tian/Worktree/WorktreeOrchestrator.swift`:

**Add a stored property** under the existing `isCreating` / `setupCancelled` (around line 17):

```swift
    /// Last error surfaced by the orchestrator, for UI binding.
    var lastError: WorktreeError?
```

**Add a helper** in the MARK: - Cancellation section (or just below it):

```swift
    /// Stores an error for the UI alert binding to consume.
    func presentError(_ error: Error) {
        if let wErr = error as? WorktreeError {
            lastError = wErr
        } else {
            lastError = .gitError(command: "unknown", stderr: String(describing: error))
        }
    }
```

**Update the `createWorktreeSpace` signature** (around line 46):

```swift
    func createWorktreeSpace(
        branchName: String,
        existingBranch: Bool = false,
        remoteRef: String? = nil,
        repoPath: String? = nil,
        workspaceID: UUID? = nil
    ) async throws -> WorktreeCreateResult {
```

**Update the pre-flight branch check** (around line 86):

```swift
        // Step 4: Pre-flight checks
        if !existingBranch && remoteRef == nil {
            let exists = try await WorktreeService.branchExists(
                repoRoot: repoRoot, branchName: branchName
            )
            if exists {
                throw WorktreeError.branchAlreadyExists(branchName: branchName)
            }
        }
```

**Update the `createWorktree` call** (around line 107):

```swift
        // Step 6: Create worktree on disk
        let worktreePath = try await WorktreeService.createWorktree(
            repoRoot: repoRoot,
            worktreeDir: config.worktreeDir,
            branchName: branchName,
            existingBranch: existingBranch,
            remoteRef: remoteRef
        )
```

- [ ] **Step 8.4: Run tests and confirm they pass**

Dispatch `test-runner-slim`:
> Run `WorktreeOrchestratorTests`. All tests including the two new ones should pass.

- [ ] **Step 8.5: Commit**

```bash
git add tian/Worktree/WorktreeOrchestrator.swift tianTests/WorktreeOrchestratorTests.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): orchestrator forwards remoteRef + exposes lastError

Threads remoteRef from the caller down to WorktreeService. Adds
lastError + presentError so the UI can bind an alert when creation
fails instead of relying on try? at the call site.
EOF
)"
```

---

## Task 9: `BranchNameInputView` — integrate combobox

No unit tests (per project policy — UI is manually verified). This task is one atomic edit to the view.

**Files:**
- Modify: `tian/View/Worktree/BranchNameInputView.swift`

- [ ] **Step 9.1: Rewrite the view**

Replace the entire contents of `tian/View/Worktree/BranchNameInputView.swift` with:

```swift
import SwiftUI

/// Overlay for entering a branch name when creating a new worktree Space.
struct BranchNameInputView: View {
    let repoRoot: URL
    let worktreeDir: String
    let onSubmit: (String, Bool, String?) -> Void
    let onCancel: () -> Void

    @State private var isExistingBranch: Bool = false
    @State private var viewModel = BranchListViewModel()
    @FocusState private var isFocused: Bool

    private var resolvedPath: String {
        let base = WorktreeService.resolveWorktreeBase(
            repoRoot: repoRoot.path, worktreeDir: worktreeDir
        )
        let name = viewModel.query.isEmpty ? "<branch>" : viewModel.query
        return (base as NSString).appendingPathComponent(name)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { onCancel() }

            VStack(spacing: 12) {
                Text("New Worktree Space")
                    .font(.system(size: 15, weight: .semibold))

                Picker("", selection: $isExistingBranch) {
                    Text("New branch").tag(false)
                    Text("Existing branch").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: isExistingBranch) { _, new in
                    viewModel.mode = new ? .existingBranch : .newBranch
                }

                TextField("Branch name", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(handleSubmit)
                    .onExitCommand { onCancel() }
                    .onKeyPress(.upArrow) {
                        viewModel.moveHighlight(.up); return .handled
                    }
                    .onKeyPress(.downArrow) {
                        viewModel.moveHighlight(.down); return .handled
                    }

                if isExistingBranch {
                    branchList
                } else if let hit = viewModel.collision(for: viewModel.query) {
                    collisionRow(for: hit)
                }

                footer
            }
            .padding(20)
            .frame(width: 360)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .task {
            viewModel.mode = isExistingBranch ? .existingBranch : .newBranch
            await viewModel.load(repoRoot: repoRoot.path)
        }
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }

    // MARK: - Subviews

    private var branchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if viewModel.rows.isEmpty {
                    Text(viewModel.loadError ?? "No matching branches")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.rows) { row in
                        branchRow(row)
                    }
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func branchRow(_ row: BranchRow) -> some View {
        let highlighted = row.id == viewModel.highlightedID
        HStack(spacing: 8) {
            badge(row.badge)
                .frame(width: 52, alignment: .leading)
            Text(row.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            if row.isCurrent {
                Text("(current)")
                    .font(.system(size: 10).italic())
                    .foregroundStyle(.secondary)
            } else if row.isInUse {
                Text("(in use)")
                    .font(.system(size: 10).italic())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.relativeDate)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(highlighted ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(highlighted ? Color.accentColor : .clear)
                .frame(width: 2)
        }
        .opacity(row.isInUse ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !row.isInUse else { return }
            submit(row: row)
        }
    }

    @ViewBuilder
    private func badge(_ b: BranchRow.Badge) -> some View {
        switch b {
        case .local:
            Text("local")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
        case .origin(let name):
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.orange)
        case .localAndOrigin:
            Text("local")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func collisionRow(for row: BranchRow) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("“\(row.displayName)” already exists")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if viewModel.isFetching {
                ProgressView().controlSize(.mini)
                Text("Syncing remotes…")
            } else if viewModel.usedCachedRemotes {
                Text("Using cached remotes")
            } else {
                Text(resolvedPath)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private func handleSubmit() {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if isExistingBranch {
            guard let row = viewModel.selectedRow() else { return }   // no-op, prevents silent failure
            submit(row: row)
        } else {
            onSubmit(trimmed, false, nil)
        }
    }

    private func submit(row: BranchRow) {
        onSubmit(row.displayName, true, row.remoteRef)
    }
}
```

- [ ] **Step 9.2: Build**

Run: `scripts/build.sh Debug`
Expected: build succeeds.

If build fails with errors about the old 2-arg `onSubmit` shape in `WorkspaceWindowContent.swift`, that's expected — the next task updates the caller. For now, temporarily update the caller at `tian/View/Workspace/WorkspaceWindowContent.swift:34-41` to match the 3-arg signature (just ignore the third arg):

```swift
                    onSubmit: { branch, existing, _ in
                        branchInputContext = nil
                        Task {
                            _ = try? await worktreeOrchestrator.createWorktreeSpace(
                                branchName: branch, existingBranch: existing
                            )
                        }
                    },
```

Then re-run `scripts/build.sh Debug`. This temporary edit is replaced in Task 10.

- [ ] **Step 9.3: Commit**

```bash
git add tian/View/Worktree/BranchNameInputView.swift tian/View/Workspace/WorkspaceWindowContent.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): inline branch combobox in BranchNameInputView

TextField plus a filtering scrollable list of local/remote branches,
sorted by recency, with arrow-key + click selection. In new-branch
mode, shows an inline collision warning when the typed name exists.
EOF
)"
```

---

## Task 10: `WorkspaceWindowContent` — error alert + forward `remoteRef`

**Files:**
- Modify: `tian/View/Workspace/WorkspaceWindowContent.swift`

- [ ] **Step 10.1: Update the onSubmit closure and bind the alert**

Replace lines 29-46 in `tian/View/Workspace/WorkspaceWindowContent.swift` (the `.overlay { … }` block) with:

```swift
        .overlay {
            if let ctx = branchInputContext {
                BranchNameInputView(
                    repoRoot: ctx.repoRoot,
                    worktreeDir: ctx.worktreeDir,
                    onSubmit: { branch, existing, remoteRef in
                        branchInputContext = nil
                        Task {
                            do {
                                _ = try await worktreeOrchestrator.createWorktreeSpace(
                                    branchName: branch,
                                    existingBranch: existing,
                                    remoteRef: remoteRef
                                )
                            } catch {
                                worktreeOrchestrator.presentError(error)
                            }
                        }
                    },
                    onCancel: { branchInputContext = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .alert(
            "Worktree creation failed",
            isPresented: Binding(
                get: { worktreeOrchestrator.lastError != nil },
                set: { if !$0 { worktreeOrchestrator.lastError = nil } }
            ),
            presenting: worktreeOrchestrator.lastError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { err in
            Text(String(describing: err))   // WorktreeError conforms to CustomStringConvertible
        }
```

- [ ] **Step 10.2: Build**

Run: `scripts/build.sh Debug`
Expected: build succeeds.

- [ ] **Step 10.3: Manual verification — happy paths**

Launch tian from the built bundle and confirm each scenario:

1. Open a repo with ≥3 local and ≥3 remote branches (a fresh clone of your own repo works). Press `Cmd+Shift+B` or use the context menu → "New Worktree Space…".
2. In "Existing branch" mode, confirm the list populates from cache almost immediately.
3. Confirm the footer briefly says "Syncing remotes…" with a spinner, then returns to the resolved-path line.
4. Pick a local branch by clicking a row — a worktree Space should be created.
5. Pick a remote-only branch (one that exists only as `origin/<name>`) — a worktree should be created and `git branch` in the new worktree should show the local tracking branch.
6. Type a branch name and use arrow keys to move the highlight; confirm in-use branches are skipped.
7. Confirm the current-worktree branch (usually `main`) shows `(current)` and is not selectable.

- [ ] **Step 10.4: Manual verification — error paths**

1. In "New branch" mode, type the name of an existing branch — confirm the yellow collision warning appears.
2. Press Enter in that state — confirm the alert appears ("already exists") via the `WorktreeError` path.
3. Disable your network, reopen the popover — confirm the footer reads "Using cached remotes" after the fetch timeout.
4. Re-enable network, reopen — confirm the footer goes back to the resolved-path line.

- [ ] **Step 10.5: Commit**

```bash
git add tian/View/Workspace/WorkspaceWindowContent.swift
git commit -m "$(cat <<'EOF'
🐛 fix(worktree): surface orchestrator errors via alert

Replace silent \`try?\` with explicit do/catch that forwards to
presentError, and bind an .alert to lastError. Also forwards the new
remoteRef argument from BranchNameInputView all the way through.

Fixes the silent-failure mode where typing a remote-only branch name
in "Existing branch" mode did nothing.
EOF
)"
```

---

## Task 11: Final sweep — xcodegen + full test run

**Files:** none modified in this task (sanity check only).

- [ ] **Step 11.1: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: no changes (already regenerated in prior tasks) or a clean regeneration.

- [ ] **Step 11.2: Run the full test suite**

Dispatch `test-runner-slim`:
> Run the full tian test suite via `xcodebuild test -scheme tian -derivedDataPath .build`. Skip UI tests. Report total pass/fail counts and any failures.

Expected: all existing tests continue to pass plus the new `BranchListServiceTests`, `BranchListViewModelTests`, and additions in `WorktreeServiceTests` / `WorktreeOrchestratorTests`.

- [ ] **Step 11.3: Final build of the release bundle**

Run: `scripts/build.sh Debug`
Expected: build succeeds.

- [ ] **Step 11.4: Smoke-test the full flow once more**

From a repo with both local and remote branches:
1. Create a worktree Space from a local branch. Confirm working directory is correct and prompt is ready.
2. Create a worktree Space from a remote-only branch. Confirm `git branch --show-current` inside the new worktree prints the expected name (not detached HEAD).
3. Close one of the Spaces to confirm the cleanup path still works unchanged.

- [ ] **Step 11.5: No commit needed** (no code changes in this task).

If the smoke test surfaces any issue, fix it in a new commit before closing the branch.

---

## Summary of files touched

| File | Change |
|---|---|
| `tian/Worktree/BranchListService.swift` | **New** — service + model + protocol |
| `tian/View/Worktree/BranchListViewModel.swift` | **New** — presentation state |
| `tian/View/Worktree/BranchNameInputView.swift` | Rewrite — combobox integrated |
| `tian/View/Workspace/WorkspaceWindowContent.swift` | Edit — forward remoteRef, bind alert |
| `tian/Worktree/WorktreeOrchestrator.swift` | Edit — remoteRef, lastError, presentError |
| `tian/Worktree/WorktreeService.swift` | Edit — remoteRef param in createWorktree |
| `tianTests/BranchListServiceTests.swift` | **New** |
| `tianTests/BranchListViewModelTests.swift` | **New** |
| `tianTests/WorktreeServiceTests.swift` | Edit — 1 test added |
| `tianTests/WorktreeOrchestratorTests.swift` | Edit — 2 tests added |

Tasks 1–8 are unit-tested (TDD, small commits). Tasks 9–10 are UI integration with manual verification. Task 11 is the end-to-end smoke test.
