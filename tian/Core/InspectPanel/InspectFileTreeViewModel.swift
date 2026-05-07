import Foundation
import Observation
import SwiftUI

/// Test seam: anything that can produce a path list given a working tree or
/// filesystem root. The default `LiveInspectFileScanner` forwards to
/// `InspectFileScanner`. Tests inject blocking / fixed-result implementations.
protocol InspectFileScanning: Sendable {
    func scanGitTracked(workingTree: String) async throws -> [String]
    func scanGitIgnored(workingTree: String) async throws -> InspectIgnoredEntries
    func scanFileSystem(root: URL) async throws -> [String]
    /// Returns immediate (non-recursive) children of `absolutePath`. Used to
    /// lazy-load descendants of rolled-up ignored directories on expand.
    func scanImmediateChildren(absolutePath: String) async throws -> [InspectChildEntry]
}

extension InspectFileScanning {
    func scanGitIgnored(workingTree: String) async throws -> InspectIgnoredEntries { .empty }
    func scanImmediateChildren(absolutePath: String) async throws -> [InspectChildEntry] { [] }
}

struct LiveInspectFileScanner: InspectFileScanning {
    func scanGitTracked(workingTree: String) async throws -> [String] {
        try await InspectFileScanner.scanGitTracked(workingTree: workingTree)
    }
    func scanGitIgnored(workingTree: String) async throws -> InspectIgnoredEntries {
        try await InspectFileScanner.scanGitIgnored(workingTree: workingTree)
    }
    func scanFileSystem(root: URL) async throws -> [String] {
        try await InspectFileScanner.scanFileSystem(root: root)
    }
    func scanImmediateChildren(absolutePath: String) async throws -> [InspectChildEntry] {
        try await InspectFileScanner.scanImmediateChildren(absolutePath: absolutePath)
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

        cancelPendingIgnoredChildrenLoads()

        // Tear down old watcher.
        watcher?.stop()
        watcher = nil

        rootDirectory = url

        guard let url else {
            // Empty state.
            allNodes = []
            childrenByParent = [:]
            nodeByID = [:]
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

    /// Toggles directory expansion (FR-13). Expanding a rolled-up ignored
    /// directory whose children we haven't enumerated yet kicks off a lazy
    /// FileManager scan; results land asynchronously and update the tree.
    func toggle(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            loadIgnoredChildrenIfNeeded(forID: path)
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
        cancelPendingIgnoredChildrenLoads()
        watcher?.stop()
        watcher = nil
    }

    /// Cancels every in-flight lazy children load. Lazy loads are tied to a
    /// specific tree root, so any teardown or re-root must clear them — they'd
    /// otherwise land into a stale tree.
    private func cancelPendingIgnoredChildrenLoads() {
        for (_, task) in ignoredChildrenLoadTasks { task.cancel() }
        ignoredChildrenLoadTasks.removeAll()
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

    /// Test affordance: awaits all in-flight lazy children loads (toggle on
    /// rolled-up ignored directories). No-ops if no loads are pending.
    func waitForPendingIgnoredChildrenLoads() async {
        let tasks = Array(ignoredChildrenLoadTasks.values)
        for task in tasks { await task.value }
    }
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
    /// Node id (absolute path) → node. Mirrors `allNodes` for O(1) lookup.
    /// `loadIgnoredChildrenIfNeeded` and the post-rebuild reload loop hit this
    /// per click / per expanded path — a linear scan over `allNodes` would be
    /// quadratic on large repos.
    private var nodeByID: [String: FileTreeNode] = [:]

    /// In-flight `scanImmediateChildren` calls, keyed by node id (absolute path).
    /// Prevents firing duplicate FS scans when the user rapidly toggles a row,
    /// and lets `setRoot`/`teardown` cancel any pending lazy loads.
    private var ignoredChildrenLoadTasks: [String: Task<Void, Never>] = [:]

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
        var ignored: InspectIgnoredEntries = .empty
        do {
            switch kind {
            case .linkedWorktree, .mainCheckout:
                async let pathsFetch = scanner.scanGitTracked(workingTree: url.path)
                async let ignoredFetch = scanner.scanGitIgnored(workingTree: url.path)
                paths = try await pathsFetch
                ignored = (try? await ignoredFetch) ?? .empty
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

        // Merge rolled-up ignored *file* entries (e.g. matches of `*.log`)
        // into the file path list, de-duplicated against tracked paths.
        // Ignored *directories* are passed separately so `buildNodes` creates
        // them as `.directory` nodes (foldable, lazy-loaded on expand) rather
        // than mistakenly flattening them into files.
        let trackedSet = Set(paths)
        let mergedPaths: [String]
        if ignored.files.isEmpty {
            mergedPaths = paths
        } else {
            var combined = paths
            for file in ignored.files where !trackedSet.contains(file) {
                combined.append(file)
            }
            mergedPaths = combined
        }
        let ignoredDirs = ignored.directories.subtracting(trackedSet)
        let allIgnored = ignored.all

        // Build the tree off the MainActor — at 10k+ entries this loop is
        // non-trivial and would visibly stall the UI if run inline.
        let urlPath = url.path
        let result = await Task.detached(priority: .userInitiated) {
            InspectFileTreeViewModel.buildNodes(
                rootPath: urlPath,
                paths: mergedPaths,
                ignoredDirectories: ignoredDirs
            )
        }.value
        if Task.isCancelled { return }

        allNodes = result.nodes
        childrenByParent = result.childrenByParent
        nodeByID = Dictionary(uniqueKeysWithValues: result.nodes.map { ($0.id, $0) })
        if ignoredEntries != allIgnored {
            ignoredEntries = allIgnored
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

        // After a rebuild, any rolled-up ignored directories that are still
        // expanded need their children re-fetched — `buildNodes` rolled them
        // up so `childrenByParent` no longer carries them. Without this, an
        // expanded `node_modules` would render as an empty disclosure.
        for expanded in expandedPaths {
            loadIgnoredChildrenIfNeeded(forID: expanded)
        }

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

    /// Lazy-loads immediate children of a rolled-up ignored directory the
    /// first time it's expanded (or after a rebuild that wiped them). No-ops
    /// for tracked directories — those come pre-populated via path prefixes
    /// in `buildNodes` — and for ignored directories that are already loaded.
    private func loadIgnoredChildrenIfNeeded(forID id: String) {
        guard let node = nodeByID[id], node.isDirectory else { return }
        // A non-nil entry — even an empty array — marks "already loaded".
        if childrenByParent[node.relativePath] != nil { return }
        guard isIgnored(node.relativePath) else { return }
        if ignoredChildrenLoadTasks[id] != nil { return }

        let absolute = node.id
        let parentRelative = node.relativePath
        let parentDepth = node.depth
        let scanner = self.scanner
        let expectedRoot = self.rootDirectory

        let task = Task { [weak self] in
            let entries: [InspectChildEntry]
            do {
                entries = try await scanner.scanImmediateChildren(absolutePath: absolute)
            } catch is CancellationError {
                return
            } catch {
                entries = []
            }
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                self.ignoredChildrenLoadTasks[absolute] = nil
                // A re-root or a rebuild that no longer recognizes this dir
                // (e.g. user un-gitignored it) means our results are stale.
                guard self.rootDirectory == expectedRoot,
                      let rootPath = self.rootDirectory?.path,
                      self.nodeByID[absolute] != nil
                else { return }

                let childNodes = entries.map { entry -> FileTreeNode in
                    let rel = parentRelative.isEmpty
                        ? entry.name
                        : parentRelative + "/" + entry.name
                    let kind: FileTreeNode.Kind = entry.isDirectory
                        ? .directory(canRead: true)
                        : .file(ext: Self.fileExtension(rel))
                    return FileTreeNode(
                        id: Self.absoluteJoin(rootPath, rel),
                        name: entry.name,
                        kind: kind,
                        relativePath: rel,
                        depth: parentDepth + 1
                    )
                }.sorted(by: Self.nodeOrder)
                // Empty array still gets stored — it marks "loaded, no kids".
                self.childrenByParent[parentRelative] = childNodes
                self.allNodes.append(contentsOf: childNodes)
                for child in childNodes {
                    self.nodeByID[child.id] = child
                }
                self.recomputeVisibleRows()
            }
        }
        ignoredChildrenLoadTasks[id] = task
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
    /// paths. Directories are derived from path prefixes plus any explicit
    /// rolled-up ignored directories the caller supplies.
    ///
    /// Returns:
    ///   - nodes: every directory + file under root, depth-first ordered with
    ///            directories-first, alphabetical within each level.
    ///   - childrenByParent: parent-id → ordered children, used by the
    ///                       expansion walker in `recomputeVisibleRows()`.
    nonisolated static func buildNodes(
        rootPath: String,
        paths: [String],
        ignoredDirectories: Set<String> = []
    ) -> (nodes: [FileTreeNode], childrenByParent: [String: [FileTreeNode]]) {
        // Collect directory relative paths (every prefix of every file path)
        // plus any rolled-up ignored directories the caller supplied.
        var dirRelative = ignoredDirectories
        var fileRelative = Set<String>()
        for raw in paths {
            // Defensive: some scanners might emit "" for an empty root —
            // skip them.
            guard !raw.isEmpty else { continue }
            // A path that's also explicitly an ignored directory belongs in
            // dirRelative only — never duplicated as a file (would clash on
            // the nodesByRelative key and produce a phantom file row).
            if !ignoredDirectories.contains(raw) {
                fileRelative.insert(raw)
            }
            for prefix in parentPrefixes(of: raw) { dirRelative.insert(prefix) }
        }
        for dir in ignoredDirectories {
            for prefix in parentPrefixes(of: dir) { dirRelative.insert(prefix) }
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

    /// Every ancestor directory of `relative`, root-first. `"a/b/c.txt"` →
    /// `["a", "a/b"]`. Used to derive directory nodes from flat path lists.
    private nonisolated static func parentPrefixes(of relative: String) -> [String] {
        var components = relative.split(separator: "/").map(String.init)
        _ = components.popLast()
        var prefixes: [String] = []
        var prefix = ""
        for c in components {
            prefix = prefix.isEmpty ? c : prefix + "/" + c
            prefixes.append(prefix)
        }
        return prefixes
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
