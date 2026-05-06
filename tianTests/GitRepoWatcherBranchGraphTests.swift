import Foundation
import Testing
@testable import tian

struct GitRepoWatcherBranchGraphTests {

    // MARK: - pathsAffectBranchGraph

    @Test func matchesLocalRefsHeads() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/refs/heads/feature"]
        #expect(GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func matchesHEAD() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/HEAD"]
        #expect(GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func matchesPackedRefs() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/packed-refs"]
        #expect(GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func matchesMultipleLocalRefsHeads() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [
            commonDir + "/refs/heads/feature",
            commonDir + "/refs/heads/main",
            commonDir + "/refs/heads/develop"
        ]
        #expect(GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func matchesMixedBranchGraphPaths() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [
            commonDir + "/refs/heads/feature",
            commonDir + "/HEAD",
            commonDir + "/packed-refs"
        ]
        #expect(GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func ignoresRemoteRefs() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/refs/remotes/origin/main"]
        #expect(!GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func ignoresWorkingTreeFiles() {
        let commonDir = "/Users/dev/project/.git"
        let paths = ["/Users/dev/project/src/app.swift"]
        #expect(!GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func ignoresUnrelatedPaths() {
        let commonDir = "/Users/dev/project/.git"
        let paths = ["/some/other/path", commonDir + "/objects/abc123"]
        #expect(!GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func ignoresIndexFile() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/index"]
        #expect(!GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func ignoresMixedWithRemotesAndOther() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [
            commonDir + "/refs/remotes/origin/feature",
            "/Users/dev/project/src/main.swift",
            commonDir + "/objects/xyz789"
        ]
        #expect(!GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }

    @Test func trueWhenBatchMixesLocalRefsWithOtherPaths() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [
            commonDir + "/index",
            commonDir + "/refs/heads/feature"
        ]
        #expect(GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: commonDir))
    }
}
