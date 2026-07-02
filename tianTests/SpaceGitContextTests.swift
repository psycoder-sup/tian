import Foundation
import Testing
@testable import tian

@MainActor
struct SpaceGitContextTests {

    // MARK: - Lazy vs Eager Detection

    @Test func lazyDetectionDoesNotDetectOnInitForNonWorktreeSpace() async {
        let context = SpaceGitContext(worktreePath: nil)

        // Give any hypothetical init-time task a chance to run
        try? await Task.sleep(for: .milliseconds(100))

        #expect(context.repoStatuses.isEmpty)
        #expect(context.pinnedRepoOrder.isEmpty)
        #expect(context.paneRepoAssignments.isEmpty)
    }

    @Test func eagerDetectionDetectsOnInitForWorktreeSpace() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: URL(filePath: repo))

        // Wait for the async detection task to complete
        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.repoStatuses.count == 1)
        #expect(context.pinnedRepoOrder.count == 1)
        let status = context.repoStatuses.values.first
        #expect(status?.branchName != nil)
        #expect(status?.branchName?.isEmpty == false)
    }

    // MARK: - Restored Session

    @Test func restoredSessionTriggersDetectionViaPaneAdded() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)

        // Simulate restore: call paneAdded with a persisted working directory
        let paneID = UUID()
        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.paneRepoAssignments[paneID] != nil)
        #expect(context.repoStatuses.count == 1)
        let status = context.repoStatuses.values.first
        #expect(status?.branchName != nil)
    }

    /// Regression: a worktree-backed space, on restore, gets a claude pane
    /// whose persisted working directory is the PARENT repo (not the worktree).
    /// A worktree and its parent share one `GitRepoID` (keyed on
    /// `--git-common-dir`), so the parent-repo pane must NOT clobber the
    /// worktree's authoritative branch/status. Before the fix the parent
    /// detection raced and overwrote the worktree branch; after it, the
    /// worktree branch stays authoritative.
    @Test func worktreeSpacePaneInParentRepoDoesNotClobberBranch() async throws {
        let main = try makeTempGitRepo()
        defer { cleanup(main) }

        // Create a linked worktree on a DISTINCT branch.
        let wtPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-wt-\(UUID().uuidString)")
            .path
        try runGitSync(["worktree", "add", "-b", "feat/worktree-x", wtPath], in: main)
        defer {
            try? runGitSync(["worktree", "remove", "--force", wtPath], in: main)
            cleanup(wtPath)
        }

        // The main repo's default branch must differ from the worktree branch,
        // otherwise the assertion below is meaningless.
        let mainBranch = try currentBranchSync(in: main)
        #expect(mainBranch != "feat/worktree-x")

        let context = SpaceGitContext(worktreePath: URL(filePath: wtPath))

        // Simulate the restore collision: the claude pane persisted in the
        // PARENT repo, added right after the worktree-init detection kicks off.
        context.paneAdded(paneID: UUID(), workingDirectory: main)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }
        // Let the parent-pane task also run so a clobber would have happened.
        try await Task.sleep(for: .milliseconds(300))

        // The worktree and parent share one GitRepoID, so exactly one repo is
        // pinned; its branch must be the worktree's, not the parent's.
        #expect(context.pinnedRepoOrder.count == 1)
        let repoID = try #require(context.pinnedRepoOrder.first)
        let status = try #require(context.repoStatuses[repoID])
        #expect(status.branchName == "feat/worktree-x")
    }

    /// Regression: the Space's own worktree repo is pinned at init with no
    /// `paneRepoAssignments` entry — it's owned by the Space's worktreePath,
    /// not by any pane. A parent-repo pane shares the worktree's `GitRepoID`,
    /// so removing that pane must NOT garbage-collect (unpin) the worktree repo
    /// while the Space is still alive. Before the guard, `paneRemoved` unpinned
    /// the shared repo and the sidebar row vanished; after it, the worktree
    /// repo stays pinned with its own branch.
    @Test func worktreeRepoStaysPinnedAfterCollidingPaneRemoved() async throws {
        let main = try makeTempGitRepo()
        defer { cleanup(main) }

        // Create a linked worktree on a DISTINCT branch.
        let wtPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-wt-\(UUID().uuidString)")
            .path
        try runGitSync(["worktree", "add", "-b", "feat/worktree-x", wtPath], in: main)
        defer {
            try? runGitSync(["worktree", "remove", "--force", wtPath], in: main)
            cleanup(wtPath)
        }

        let context = SpaceGitContext(worktreePath: URL(filePath: wtPath))

        // Add a PARENT-repo pane — it shares the worktree's GitRepoID.
        let paneID = UUID()
        context.paneAdded(paneID: paneID, workingDirectory: main)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }
        // Let the parent-pane task also run.
        try await Task.sleep(for: .milliseconds(300))

        let repoID = try #require(context.pinnedRepoOrder.first)

        // Remove the colliding parent-repo pane.
        context.paneRemoved(paneID: paneID)

        // The worktree repo must stay pinned with its own branch.
        #expect(context.pinnedRepoOrder.contains(repoID))
        #expect(context.repoStatuses[repoID]?.branchName == "feat/worktree-x")
    }

    @Test func paneAddedIgnoresEmptyAndTildeDirectories() async {
        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: nil)
        context.paneAdded(paneID: paneID, workingDirectory: "")
        context.paneAdded(paneID: paneID, workingDirectory: "~")

        try? await Task.sleep(for: .milliseconds(200))

        #expect(context.repoStatuses.isEmpty)
        #expect(context.paneRepoAssignments.isEmpty)
    }

    // MARK: - In-flight Task Cancellation

    @Test func rapidRefreshesCancelPriorTask() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        // Fire multiple rapid directory changes — earlier tasks should be cancelled
        for i in 0..<5 {
            context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: repo)
            // Tiny delay to ensure tasks are actually dispatched
            if i < 4 {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        // Should end up with exactly one repo status (not duplicated)
        #expect(context.repoStatuses.count == 1)
        #expect(context.pinnedRepoOrder.count == 1)
        let status = context.repoStatuses.values.first
        #expect(status?.branchName != nil)
    }

    // MARK: - Pane Removed / Garbage Collection

    @Test func paneRemovedGarbageCollectsOrphanedRepo() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.repoStatuses.count == 1)

        // Remove the only pane referencing this repo
        context.paneRemoved(paneID: paneID)

        #expect(context.repoStatuses.isEmpty)
        #expect(context.pinnedRepoOrder.isEmpty)
    }

    // MARK: - Teardown

    @Test func teardownClearsAllState() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        context.paneAdded(paneID: UUID(), workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        context.teardown()

        #expect(context.repoStatuses.isEmpty)
        #expect(context.pinnedRepoOrder.isEmpty)
        #expect(context.paneRepoAssignments.isEmpty)
    }

    // MARK: - Integration: Full Flow

    @Test func integrationDetectsRepoAndPopulatesBranchName() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create a named branch to verify
        try runGitSync(["checkout", "-b", "feature/test-branch"], in: repo)

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.repoStatuses.count == 1)
        let repoID = try #require(context.pinnedRepoOrder.first)
        let status = try #require(context.repoStatuses[repoID])

        #expect(status.branchName == "feature/test-branch")
        #expect(status.isDetachedHead == false)
        #expect(status.diffSummary.isEmpty)
        #expect(status.changedFiles.isEmpty)
        #expect(status.prStatus == nil)
    }

    // MARK: - Integration: Diff Summary

    @Test func integrationPopulatesDiffSummary() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Modify existing file
        let readmePath = (repo as NSString).appendingPathComponent("README.md")
        try "Modified content".write(toFile: readmePath, atomically: true, encoding: .utf8)

        // Add a new untracked file
        let newFilePath = (repo as NSString).appendingPathComponent("new.txt")
        try "new file".write(toFile: newFilePath, atomically: true, encoding: .utf8)

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            context.repoStatuses.values.first?.diffSummary.isEmpty == false
        }

        let repoID = try #require(context.pinnedRepoOrder.first)
        let status = try #require(context.repoStatuses[repoID])

        #expect(status.diffSummary.modified == 1)
        #expect(status.diffSummary.added == 1)
        #expect(status.diffSummary.totalCount == 2)
        #expect(status.changedFiles.count == 2)
    }

    // MARK: - Watcher Lifecycle

    @Test func watcherStartedOnRepoDetection() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.activeWatcherCount == 1)
    }

    @Test func watcherStoppedOnRepoUnpin() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.activeWatcherCount == 1)

        context.paneRemoved(paneID: paneID)

        #expect(context.activeWatcherCount == 0)
    }

    @Test func teardownStopsAllWatchers() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        context.paneAdded(paneID: UUID(), workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        context.teardown()

        #expect(context.activeWatcherCount == 0)
    }

    // MARK: - Pinning Behavior

    @Test func repoStaysPinnedWhenPaneCdsToNonGitDir() async throws {
        let repo = try makeTempGitRepo()
        let nonGitDir = try makeTempDir()
        defer { cleanup(repo); cleanup(nonGitDir) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        let repoID = context.pinnedRepoOrder.first!

        // cd to non-git directory — repo should stay pinned (FR-020.3)
        context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: nonGitDir)

        // Wait for detection to run
        try await Task.sleep(for: .milliseconds(500))

        #expect(context.pinnedRepoOrder.contains(repoID))
        #expect(context.repoStatuses[repoID] != nil)
    }

    @Test func paneReassignsFromRepoAToRepoB() async throws {
        let repoA = try makeTempGitRepo()
        let repoB = try makeTempGitRepo()
        defer { cleanup(repoA); cleanup(repoB) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        // Start in repo A
        context.paneAdded(paneID: paneID, workingDirectory: repoA)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        let repoAID = context.pinnedRepoOrder.first!
        #expect(context.paneRepoAssignments[paneID] == repoAID)

        // Move to repo B
        context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: repoB)

        try await pollUntil(timeout: 5.0) {
            context.paneRepoAssignments[paneID] != repoAID
        }

        // Pane should now be in repo B; repo A unpinned (no other panes)
        let repoBID = context.paneRepoAssignments[paneID]
        #expect(repoBID != nil)
        #expect(repoBID != repoAID)
        #expect(!context.pinnedRepoOrder.contains(repoAID))
        #expect(context.pinnedRepoOrder.contains(repoBID!))
    }

    @Test func multipleReposDetectedFromMultiplePanes() async throws {
        let repoA = try makeTempGitRepo()
        let repoB = try makeTempGitRepo()
        defer { cleanup(repoA); cleanup(repoB) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneA = UUID()
        let paneB = UUID()

        context.paneAdded(paneID: paneA, workingDirectory: repoA)
        context.paneAdded(paneID: paneB, workingDirectory: repoB)

        try await pollUntil(timeout: 5.0) {
            context.repoStatuses.count == 2
        }

        #expect(context.pinnedRepoOrder.count == 2)
        #expect(context.paneRepoAssignments[paneA] != context.paneRepoAssignments[paneB])
    }

    @Test func pinnedRepoOrderAlphabetical() async throws {
        let repoA = try makeTempGitRepoNamed("aaa-repo")
        let repoB = try makeTempGitRepoNamed("zzz-repo")
        defer { cleanup(repoA); cleanup(repoB) }

        let context = SpaceGitContext(worktreePath: nil)

        // Add zzz first, then aaa
        context.paneAdded(paneID: UUID(), workingDirectory: repoB)
        try await pollUntil(timeout: 5.0) { context.repoStatuses.count == 1 }

        context.paneAdded(paneID: UUID(), workingDirectory: repoA)
        try await pollUntil(timeout: 5.0) { context.repoStatuses.count == 2 }

        // Should be sorted alphabetically
        let order = context.pinnedRepoOrder
        #expect(order[0].path < order[1].path)
    }

    // MARK: - Per-Worktree-Root Branch (per-tab sidebar rows)

    /// Two panes in DIFFERENT worktrees of the same repo share one `GitRepoID`
    /// (keyed on `--git-common-dir`), yet `branch(forPane:)` must resolve each to
    /// its OWN branch. This is what lets the sidebar show a distinct branch per
    /// tab instead of collapsing sibling worktrees onto one row.
    @Test func distinctWorktreesResolveDistinctBranchesPerPane() async throws {
        let main = try makeTempGitRepo()
        defer { cleanup(main) }

        let wtPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-wt-\(UUID().uuidString)")
            .path
        try runGitSync(["worktree", "add", "-b", "feat/branch-x", wtPath], in: main)
        defer {
            try? runGitSync(["worktree", "remove", "--force", wtPath], in: main)
            cleanup(wtPath)
        }

        let mainBranch = try currentBranchSync(in: main)
        #expect(mainBranch != "feat/branch-x")

        // Non-worktree space: both panes drive detection normally.
        let context = SpaceGitContext(worktreePath: nil)
        let paneMain = UUID()
        let paneWt = UUID()
        context.paneAdded(paneID: paneMain, workingDirectory: main)
        context.paneAdded(paneID: paneWt, workingDirectory: wtPath)

        try await pollUntil(timeout: 5.0) {
            context.branch(forPane: paneMain) != nil && context.branch(forPane: paneWt) != nil
        }

        // Same repo (one shared GitRepoID) …
        #expect(context.pinnedRepoOrder.count == 1)
        // … but each pane resolves its own worktree's branch.
        #expect(context.branch(forPane: paneMain) == mainBranch)
        #expect(context.branch(forPane: paneWt) == "feat/branch-x")
    }

    /// Regression (per-worktree diff badge): two panes in different worktrees of
    /// one repo must show their OWN diff, not a single shared one. Before the fix
    /// both rows rendered whichever directory last drove the GitRepoID's status.
    @Test func distinctWorktreesResolveDistinctDiffPerPane() async throws {
        let main = try makeTempGitRepo()
        defer { cleanup(main) }

        let wtPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-wt-\(UUID().uuidString)")
            .path
        try runGitSync(["worktree", "add", "-b", "feat/diff-x", wtPath], in: main)
        defer {
            try? runGitSync(["worktree", "remove", "--force", wtPath], in: main)
            cleanup(wtPath)
        }

        // Dirty ONLY the worktree (modify its copy of the committed README).
        let readme = (wtPath as NSString).appendingPathComponent("README.md")
        try "# Changed only in the worktree".write(toFile: readme, atomically: true, encoding: .utf8)

        let context = SpaceGitContext(worktreePath: nil)
        let paneMain = UUID()
        let paneWt = UUID()
        context.paneAdded(paneID: paneMain, workingDirectory: main)
        context.paneAdded(paneID: paneWt, workingDirectory: wtPath)

        try await pollUntil(timeout: 5.0) {
            context.status(forPane: paneMain) != nil && context.status(forPane: paneWt) != nil
        }

        // Same repo (one GitRepoID), but each pane sees its own worktree's diff.
        #expect(context.status(forPane: paneMain)?.diffSummary.isEmpty == true)
        #expect(context.status(forPane: paneWt)?.diffSummary.isEmpty == false)
    }

    /// Removing a pane drops its worktree-root branch label so a stale branch
    /// never lingers on the sidebar after the tab closes.
    @Test func branchLabelPrunedWhenPaneRemoved() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()
        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) != nil }
        #expect(!context.statusByWorktreeRoot.isEmpty)

        context.paneRemoved(paneID: paneID)

        #expect(context.branch(forPane: paneID) == nil)
        #expect(context.statusByWorktreeRoot.isEmpty)
    }

    /// `teardown()` clears per-worktree branch state along with the rest.
    @Test func teardownClearsBranchState() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()
        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) != nil }

        context.teardown()

        #expect(context.branch(forPane: paneID) == nil)
        #expect(context.statusByWorktreeRoot.isEmpty)
        #expect(context.paneWorktreeRoot.isEmpty)
    }

    /// The Claude→tian bridge: a session enters a worktree nested INSIDE the main
    /// working tree (`.claude/worktrees/<name>`, Claude's default). The OSC 7
    /// same-repo fast path would treat that nested path as "still main" and keep
    /// the branch wrong; `setPaneDirectory` forces a full detect so the pane
    /// resolves the nested worktree's own branch.
    @Test func setPaneDirectoryResolvesBranchForNestedWorktree() async throws {
        let main = try makeTempGitRepo()
        defer { cleanup(main) }

        let nested = (main as NSString).appendingPathComponent(".claude/worktrees/nested")
        try runGitSync(["worktree", "add", "-b", "feat/nested", nested], in: main)
        defer { try? runGitSync(["worktree", "remove", "--force", nested], in: main) }

        let mainBranch = try currentBranchSync(in: main)
        #expect(mainBranch != "feat/nested")

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()
        // Pane starts in main (what the shell reports via OSC 7).
        context.paneAdded(paneID: paneID, workingDirectory: main)
        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) == mainBranch }

        // Bridge reports the worktree the Claude session entered.
        context.setPaneDirectory(paneID: paneID, directory: nested)
        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) == "feat/nested" }

        #expect(context.branch(forPane: paneID) == "feat/nested")
    }

    /// A `setPaneDirectory` repeated for the same dir is a no-op (dedupes a busy
    /// CwdChanged loop). The dedupe keys on the bridge's own history, so the
    /// FIRST report still runs even after `paneAdded`/OSC 7 already saw the dir.
    @Test func setPaneDirectoryIsNoOpWhenUnchanged() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()
        context.paneAdded(paneID: paneID, workingDirectory: repo)
        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) != nil }

        context.setPaneDirectory(paneID: paneID, directory: repo)
        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) != nil }

        let before = context.branch(forPane: paneID)
        // Repeated report for the same dir: deduped, state unchanged.
        context.setPaneDirectory(paneID: paneID, directory: repo)
        #expect(context.branch(forPane: paneID) == before)
    }

    /// Regression (ordering): the OSC 7 same-repo fast path writes
    /// `paneDirectories` for a nested `.claude/worktrees/<name>` path WITHOUT
    /// updating the worktree root (it treats the nested dir as "still main").
    /// A subsequent bridge `setPaneDirectory` for that same path must NOT be
    /// deduped away by the OSC 7 write — it has to force a full detect so the
    /// tab resolves the nested worktree's own branch.
    @Test func setPaneDirectoryNotSuppressedByPriorOSC7Write() async throws {
        let main = try makeTempGitRepo()
        defer { cleanup(main) }

        let nested = (main as NSString).appendingPathComponent(".claude/worktrees/nested")
        try runGitSync(["worktree", "add", "-b", "feat/bridge-nested", nested], in: main)
        defer { try? runGitSync(["worktree", "remove", "--force", nested], in: main) }

        let mainBranch = try currentBranchSync(in: main)
        #expect(mainBranch != "feat/bridge-nested")

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()
        context.paneAdded(paneID: paneID, workingDirectory: main)
        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) == mainBranch }

        // OSC 7 reports the nested worktree dir first — same-repo fast path keeps
        // the pane on main and never updates the worktree root.
        context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: nested)

        // Bridge reports the same dir: must still resolve the nested branch.
        context.setPaneDirectory(paneID: paneID, directory: nested)
        try await pollUntil(timeout: 5.0) { context.branch(forPane: paneID) == "feat/bridge-nested" }
        #expect(context.branch(forPane: paneID) == "feat/bridge-nested")
    }

    // MARK: - Helpers

    private func pollUntil(timeout: Double, condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for condition after \(timeout)s")
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir,
                                                  withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)

        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readmePath, atomically: true, encoding: .utf8)

        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)

        return dir
    }

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
            throw StringError("git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    /// Returns the current branch name for a repo (via `git rev-parse
    /// --abbrev-ref HEAD`). Used to confirm the parent repo's branch differs
    /// from the worktree branch so the collision assertion is meaningful.
    private func currentBranchSync(in dir: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        process.currentDirectoryURL = URL(filePath: dir)
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempGitRepoNamed(_ name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(name + "-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        let readme = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readme, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)
        return dir
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private struct StringError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
