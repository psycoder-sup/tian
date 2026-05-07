import Foundation
import Observation
import SwiftUI

/// Test seam: anything that can produce a path list given a working tree or
/// filesystem root. The default `LiveInspectFileScanner` forwards to
/// `InspectFileScanner`. Tests inject blocking / fixed-result implementations.
protocol InspectFileScanning: Sendable {
    func scanGitTracked(workingTree: String) async throws -> [String]
    func scanGitIgnored(workingTree: String) async throws -> Set<String>
    func scanFileSystem(root: URL) async throws -> [String]
}

extension InspectFileScanning {
    /// Default: no ignored entries. Tests that don't care about ignored
    /// state inherit this and don't need to override.
    func scanGitIgnored(workingTree: String) async throws -> Set<String> { [] }
}

struct LiveInspectFileScanner: InspectFileScanning {
    func scanGitTracked(workingTree: String) async throws -> [String] {
        try await InspectFileScanner.scanGitTracked(workingTree: workingTree)
    }
    func scanGitIgnored(workingTree: String) async throws -> Set<String> {
        try await InspectFileScanner.scanGitIgnored(workingTree: workingTree)
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
    /// Relative paths git considers ignored. May contain rolled-up directory
    /// entries — use `isIgnored(_:)` to look up a node correctly.
    private var ignoredEntries: Set<String> = []
    private(set) var isInitialScanInFlight: Bool = false
    private(set) var isInitialScanSlow: Bool = false

    /// Returns `true` if `relativePath` is gitignored, either directly or
    /// because one of its parent directories is.
    func isIgnored(_ relativePath: String) -> Bool {
        if ignoredEntries.isEmpty { return false }
        if ignoredEntries.contains(relativePath) { return true }
        var current = relativePath
        while let lastSlash = current.lastIndex(of: "/") {
            current = String(current[..<lastSlash])
            if ignoredEntries.contains(current) { return true }
        }
        return false
    }

    var expandedPaths: Set<String> = []   // by canonical absolute path
    var selectedPath: String?

    // MARK: - Public API

    /// Switches the tree to a new root. Any in-flight scan for the previous
    /// root is cancelled (FR-28a). Pass `nil` to enter the empty state.
    func setRoot(_ url: URL?) {
        // Cancel previous scan + slow-flag timer (FR-28a).
        scanTask?.cancel()
        scanTask = nil
        slowFlagTask?.cancel()
        slowFlagTask = nil
        isInitialScanSlow = false

        // Tear down old watcher.
        watcher?.stop()
        watcher = nil

        rootDirectory = url

        guard let url else {
            // Empty state.
            allNodes = []
            childrenByParent = [:]
            visibleRows = []
            worktreeKind = .noWorkingDirectory
            isInitialScanInFlight = false
            return
        }

        isInitialScanInFlight = true

        // Slow-flag timer: flips after `slowFlagDelay` if we're still in flight.
        let slowDelay = slowFlagDelay
        slowFlagTask = Task { [weak self] in
            try? await Task.sleep(for: slowDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.isInitialScanInFlight {
                    self.isInitialScanSlow = true
                }
            }
        }

        // Scan task. Keep the URL captured so `runScan` knows what root we
        // expected — protects against races where `setRoot` is called again
        // before our task completes.
        let target = url
        let scanner = self.scanner
        let classify = self.classify
        scanTask = Task { [weak self] in
            await self?.runScan(url: target, scanner: scanner, classify: classify)
        }
    }

    /// Toggles directory expansion (FR-13).
    func toggle(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
        recomputeVisibleRows()
    }

    /// Updates the row selection (FR-23).
    func select(_ path: String?) {
        selectedPath = path
    }

    /// Pushes a fresh `git status` result into the tree so badges re-render.
    /// File paths receive their explicit status; ancestor directories inherit
    /// the highest-severity status among their descendants
    /// (`GitFileStatus.severity`). FR-19b: rename's `path` is the new path;
    /// we set R there. (Old-path "D if still present" requires upstream parser
    /// changes; with today's `GitChangedFile` shape we only see the new path.)
    func updateStatus(_ files: [GitChangedFile]) {
        var map: [String: GitFileStatus] = [:]
        for file in files {
            map[file.path] = file.status

            // Propagate to every ancestor directory of this file.
            var components = file.path.split(separator: "/").map(String.init)
            _ = components.popLast()
            var prefix = ""
            for c in components {
                prefix = prefix.isEmpty ? c : prefix + "/" + c
                if let existing = map[prefix] {
                    if file.status.severity > existing.severity {
                        map[prefix] = file.status
                    }
                } else {
                    map[prefix] = file.status
                }
            }
        }
        statusByRelativePath = map
    }

    /// Re-runs the scan for the current root WITHOUT flipping
    /// `isInitialScanInFlight` or restarting the watcher. The existing tree
    /// stays visible while the rescan runs, so FS-event refreshes don't blink
    /// the panel back to the Loading… state.
    func refresh() {
        guard let url = rootDirectory else { return }
        scanTask?.cancel()
        let scanner = self.scanner
        let classify = self.classify
        scanTask = Task { [weak self] in
            await self?.runScan(url: url, scanner: scanner, classify: classify, isRefresh: true)
        }
    }

    /// Tears down the watcher and cancels the scan (called on workspace close).
    func teardown() {
        scanTask?.cancel()
        scanTask = nil
        slowFlagTask?.cancel()
        slowFlagTask = nil
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Test seams (Debug only)

    #if DEBUG
    /// Test affordance: awaits completion of the most recently kicked-off scan.
    /// Returns immediately if no scan is currently in flight.
    func waitForFirstScan() async {
        await scanTask?.value
    }

    /// Test affordance: replaces the scanner. Called between scans when a
    /// test wants subsequent `setRoot`s to use different scanner behavior.
    func replaceScanner(_ scanner: InspectFileScanning) {
        self.scanner = scanner
    }

    /// Test affordance: exposes the unfiltered tree for assertions.
    var allNodesForTest: [FileTreeNode] { allNodes }
    #endif

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

    // MARK: - Scan flow

    private func runScan(
        url: URL,
        scanner: InspectFileScanning,
        classify: @Sendable (String?) async -> WorktreeKind,
        isRefresh: Bool = false
    ) async {
        // Resolve worktree kind first so the panel can render its label even
        // if the scan is slow.
        let kind = await classify(url.path)

        // Bail if cancelled while classifying.
        if Task.isCancelled { return }

        // Set worktreeKind immediately so the panel header can render the
        // worktree label even during slow scans (before the file list arrives).
        self.worktreeKind = kind

        // Pick the right scanner method based on kind.
        let paths: [String]
        var ignored: Set<String> = []
        do {
            switch kind {
            case .linkedWorktree, .mainCheckout:
                async let pathsFetch = scanner.scanGitTracked(workingTree: url.path)
                async let ignoredFetch = scanner.scanGitIgnored(workingTree: url.path)
                paths = try await pathsFetch
                ignored = (try? await ignoredFetch) ?? []
            case .notARepo:
                paths = try await scanner.scanFileSystem(root: url)
            case .noWorkingDirectory:
                paths = []
            }
        } catch is CancellationError {
            return
        } catch {
            // Treat scan failures as empty results — view will show the empty
            // state. The error is already logged by the scanner.
            paths = []
        }

        // After awaiting the scan, re-check cancellation. A second `setRoot`
        // landing during the scan must not let us write stale results.
        if Task.isCancelled { return }

        // Merge rolled-up ignored directory entries (e.g. `node_modules/`)
        // so the file tree shows them as single dimmed nodes without listing
        // their 50k+ descendants. De-duplicate against tracked paths.
        let mergedPaths: [String]
        if ignored.isEmpty {
            mergedPaths = paths
        } else {
            let trackedSet = Set(paths)
            var combined = paths
            for entry in ignored where !trackedSet.contains(entry) {
                combined.append(entry)
            }
            mergedPaths = combined
        }

        // Build the tree off the MainActor — at 10k+ entries this loop is
        // non-trivial and would visibly stall the UI if run inline.
        let urlPath = url.path
        let result = await Task.detached(priority: .userInitiated) {
            InspectFileTreeViewModel.buildNodes(rootPath: urlPath, paths: mergedPaths)
        }.value
        if Task.isCancelled { return }

        allNodes = result.nodes
        childrenByParent = result.childrenByParent
        if ignoredEntries != ignored {
            ignoredEntries = ignored
        }

        // FR-26: clear selection if it points at a path that no longer exists.
        if let selected = selectedPath, !result.nodes.contains(where: { $0.id == selected }) {
            selectedPath = nil
        }

        // FR-28: prune expanded paths that no longer correspond to a directory
        // in the tree. (Keeps the set bounded, and matches the spec's "when
        // those still exist" semantics.)
        let nodeIDs = Set(result.nodes.map(\.id))
        expandedPaths = expandedPaths.intersection(nodeIDs)

        recomputeVisibleRows()

        // Initial scans manage the loading flag + watcher; refresh scans leave
        // both untouched (the tree stays visible during the rescan and the
        // watcher is already running).
        if !isRefresh {
            isInitialScanInFlight = false
            slowFlagTask?.cancel()
            slowFlagTask = nil
            isInitialScanSlow = false
            startWatcher(for: url)
        }
    }

    private func startWatcher(for url: URL) {
        // Each FS-event burst triggers an in-place `refresh()` — the tree
        // stays visible while the rescan runs (no Loading… flicker).
        watcher = WorkingTreeWatcher(root: url.path) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.rootDirectory == url else { return }
                self.refresh()
            }
        }
    }

    // MARK: - Tree construction

    /// Builds the unfiltered node list from a flat list of POSIX-relative
    /// paths. Directories are derived from path prefixes.
    ///
    /// Returns:
    ///   - nodes: every directory + file under root, depth-first ordered with
    ///            directories-first, alphabetical within each level.
    ///   - childrenByParent: parent-id → ordered children, used by the
    ///                       expansion walker in `recomputeVisibleRows()`.
    private nonisolated static func buildNodes(
        rootPath: String,
        paths: [String]
    ) -> (nodes: [FileTreeNode], childrenByParent: [String: [FileTreeNode]]) {
        // Collect directory relative paths (every prefix of every file path).
        var dirRelative = Set<String>()
        var fileRelative = Set<String>()
        for raw in paths {
            // Defensive: some scanners might emit "" for an empty root —
            // skip them.
            guard !raw.isEmpty else { continue }
            fileRelative.insert(raw)
            // Each path component except the last contributes a directory.
            var components = raw.split(separator: "/").map(String.init)
            _ = components.popLast()
            var prefix = ""
            for c in components {
                prefix = prefix.isEmpty ? c : prefix + "/" + c
                dirRelative.insert(prefix)
            }
        }

        // Build nodes (directories + files), keyed by relativePath.
        var nodesByRelative: [String: FileTreeNode] = [:]
        for rel in dirRelative {
            // depth = number of "/" separators in the relative path
            let depth = rel.filter { $0 == "/" }.count
            let node = FileTreeNode(
                id: absoluteJoin(rootPath, rel),
                name: lastComponent(rel),
                kind: .directory(canRead: true),
                relativePath: rel,
                depth: depth
            )
            nodesByRelative[rel] = node
        }
        for rel in fileRelative {
            let depth = rel.filter { $0 == "/" }.count
            let node = FileTreeNode(
                id: absoluteJoin(rootPath, rel),
                name: lastComponent(rel),
                kind: .file(ext: fileExtension(rel)),
                relativePath: rel,
                depth: depth
            )
            nodesByRelative[rel] = node
        }

        // Index by parent relative path.
        var childrenIndex: [String: [FileTreeNode]] = [:]
        for (rel, node) in nodesByRelative {
            let parentRel = parentRelative(rel)
            childrenIndex[parentRel, default: []].append(node)
        }
        // Sort each child list: directories first (alphabetical), files
        // alphabetical.
        for (k, v) in childrenIndex {
            childrenIndex[k] = v.sorted(by: nodeOrder)
        }

        // Depth-first ordered list, starting from root's children.
        var ordered: [FileTreeNode] = []
        var stack: [FileTreeNode] = (childrenIndex[""] ?? []).reversed()
        while let next = stack.popLast() {
            ordered.append(next)
            if next.isDirectory, let children = childrenIndex[next.relativePath] {
                // Push reversed so the stack pops them in order.
                for child in children.reversed() {
                    stack.append(child)
                }
            }
        }

        // Re-key childrenIndex by absolute id for consumers (recompute uses
        // the relative-path index internally so we keep relative keys).
        // We only return relative-keyed for the recompute step.
        return (ordered, childrenIndex)
    }

    private func recomputeVisibleRows() {
        // Walk the relative-path index from the root's children, prune at
        // directories not present in `expandedPaths`. The set holds absolute
        // paths (= node.id), so compare by id.
        var ordered: [FileTreeNode] = []
        let rootChildren = childrenByParent[""] ?? []
        var stack: [FileTreeNode] = rootChildren.reversed()
        while let next = stack.popLast() {
            ordered.append(next)
            if next.isDirectory, expandedPaths.contains(next.id),
               let children = childrenByParent[next.relativePath] {
                for child in children.reversed() {
                    stack.append(child)
                }
            }
        }
        visibleRows = ordered
    }

    // MARK: - Helpers

    private nonisolated static func absoluteJoin(_ root: String, _ relative: String) -> String {
        if root.hasSuffix("/") { return root + relative }
        return root + "/" + relative
    }

    private nonisolated static func lastComponent(_ relative: String) -> String {
        if let slash = relative.lastIndex(of: "/") {
            return String(relative[relative.index(after: slash)...])
        }
        return relative
    }

    private nonisolated static func parentRelative(_ relative: String) -> String {
        if let slash = relative.lastIndex(of: "/") {
            return String(relative[..<slash])
        }
        return ""
    }

    private nonisolated static func fileExtension(_ relative: String) -> String? {
        let name = lastComponent(relative)
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            return String(name[name.index(after: dot)...])
        }
        return nil
    }

    private nonisolated static func nodeOrder(_ a: FileTreeNode, _ b: FileTreeNode) -> Bool {
        switch (a.isDirectory, b.isDirectory) {
        case (true, false): return true
        case (false, true): return false
        default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
