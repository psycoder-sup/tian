import Foundation
import Observation
import SwiftUI

/// Test seam: anything that can produce a path list given a working tree or
/// filesystem root. The default `.live` value forwards to `InspectFileScanner`.
/// Tests inject blocking / fixed-result implementations.
protocol InspectFileScanning: Sendable {
    func scanGitTracked(workingTree: String) async throws -> [String]
    func scanFileSystem(root: URL) async throws -> [String]
}

struct LiveInspectFileScanner: InspectFileScanning {
    func scanGitTracked(workingTree: String) async throws -> [String] {
        try await InspectFileScanner.scanGitTracked(workingTree: workingTree)
    }
    func scanFileSystem(root: URL) async throws -> [String] {
        try await InspectFileScanner.scanFileSystem(root: root)
    }
}

@MainActor @Observable
final class InspectFileTreeViewModel {

    // Observable state (drives the view)
    private(set) var rootDirectory: URL?
    private(set) var worktreeKind: WorktreeKind = .noWorkingDirectory
    /// Materialized flat list of visible rows (depth-first, ancestors expanded).
    /// Recomputed on scan completion or expand/collapse.
    private(set) var visibleRows: [FileTreeNode] = []
    private(set) var statusByRelativePath: [String: GitFileStatus] = [:]
    private(set) var isInitialScanInFlight: Bool = false
    private(set) var isInitialScanSlow: Bool = false
    private(set) var hasContent: Bool = false   // true once first scan finished and rows non-empty

    var expandedPaths: Set<String> = []   // by canonical absolute path
    var selectedPath: String?

    // MARK: - Public API

    /// Switches the tree to a new root. Any in-flight scan for the previous
    /// root is cancelled (FR-28a). Pass `nil` to enter the empty state.
    func setRoot(_ url: URL?) {}

    /// Toggles directory expansion (FR-13).
    func toggle(_ path: String) {}

    /// Updates the row selection (FR-23).
    func select(_ path: String?) {}

    /// Pushes a fresh `git status` result into the tree so badges re-render.
    func updateStatus(_ files: [GitChangedFile]) {}

    /// Tears down the watcher and cancels the scan (called on workspace close).
    func teardown() {}

    /// Test affordance: awaits completion of the most recently kicked-off scan.
    /// Returns immediately if no scan is currently in flight.
    func waitForFirstScan() async {}

    /// Test affordance: replaces the scanner. Called between scans when a
    /// test wants subsequent `setRoot`s to use different scanner behavior.
    func replaceScanner(_ scanner: InspectFileScanning) {
        self.scanner = scanner
    }

    /// Test affordance: exposes the unfiltered tree for assertions.
    var allNodesForTest: [FileTreeNode] { allNodes }

    // MARK: - Construction

    init(
        scanner: InspectFileScanning = LiveInspectFileScanner(),
        classify: @escaping @Sendable (String?) async -> WorktreeKind = WorktreeKind.classify(directory:),
        slowFlagDelay: Duration = .seconds(5)
    ) {
        self.scanner = scanner
        self.classify = classify
        self.slowFlagDelay = slowFlagDelay
    }

    // MARK: - Private

    private var scanner: InspectFileScanning
    private let classify: @Sendable (String?) async -> WorktreeKind
    private let slowFlagDelay: Duration

    private var scanTask: Task<Void, Never>?
    private var slowFlagTask: Task<Void, Never>?
    private var watcher: WorkingTreeWatcher?

    /// Full unfiltered tree (set after each scan). View-only state derives from
    /// this + `expandedPaths` to produce `visibleRows`.
    private var allNodes: [FileTreeNode] = []
    private var childrenByParent: [String: [FileTreeNode]] = [:]
}
