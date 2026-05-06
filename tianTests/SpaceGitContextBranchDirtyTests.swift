import Foundation
import Testing
@testable import tian

@MainActor
struct SpaceGitContextBranchDirtyTests {

    // MARK: - branchGraphDirty flag

    /// FSEvents batch hitting refs/heads/* marks the repo's branchGraphDirty flag.
    @Test func refHeadsBatchSetsDirty() {
        let context = SpaceGitContext(worktreePath: nil)
        let repoID = GitRepoID(path: "/tmp/testrepo/.git")
        let commonDir = "/tmp/testrepo/.git"
        let paths = [commonDir + "/refs/heads/feature"]

        context.processFSEventBatch(repoID: repoID, paths: paths, canonicalCommonDir: commonDir)

        #expect(context.branchGraphDirty.contains(repoID))
    }

    /// FSEvents batch hitting only working-tree files does NOT set branchGraphDirty.
    @Test func workingTreeBatchDoesNotSetDirty() {
        let context = SpaceGitContext(worktreePath: nil)
        let repoID = GitRepoID(path: "/tmp/testrepo/.git")
        let commonDir = "/tmp/testrepo/.git"
        let paths = ["/tmp/testrepo/src/main.swift", "/tmp/testrepo/README.md"]

        context.processFSEventBatch(repoID: repoID, paths: paths, canonicalCommonDir: commonDir)

        #expect(!context.branchGraphDirty.contains(repoID))
    }

    /// clearBranchGraphDirty removes the specified repoID from the set.
    @Test func clearRemovesEntry() {
        let context = SpaceGitContext(worktreePath: nil)
        let repoID = GitRepoID(path: "/tmp/testrepo/.git")
        let commonDir = "/tmp/testrepo/.git"
        let paths = [commonDir + "/refs/heads/main"]

        // Pre-populate via a branch-graph-affecting batch
        context.processFSEventBatch(repoID: repoID, paths: paths, canonicalCommonDir: commonDir)
        #expect(context.branchGraphDirty.contains(repoID))

        context.clearBranchGraphDirty(repoID: repoID)

        #expect(!context.branchGraphDirty.contains(repoID))
    }
}
