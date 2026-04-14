import AppKit
import Foundation

/// Reads persisted session state from disk and reconstructs the live model hierarchy.
///
/// Fallback chain: state.json → state.prev.json → nil (caller creates default state).
enum SessionRestorer {

    // MARK: - Errors

    enum RestoreError: Error, CustomStringConvertible {
        case emptyWorkspaces
        case emptySpaces(workspaceName: String)
        case emptyTabs(spaceName: String)

        var description: String {
            switch self {
            case .emptyWorkspaces:
                "Session state contains no workspaces"
            case .emptySpaces(let name):
                "Workspace '\(name)' contains no spaces"
            case .emptyTabs(let name):
                "Space '\(name)' contains no tabs"
            }
        }
    }

    // MARK: - Load

    /// Attempts to load and decode session state from disk.
    /// Tries state.json first, falls back to state.prev.json, returns nil on total failure.
    static func loadState() -> RestoreResult? {
        let clock = ContinuousClock()
        let start = clock.now
        var metrics = RestoreMetrics()

        if let state = loadFrom(url: SessionSerializer.stateFileURL, metrics: &metrics) {
            metrics.source = .primary
            metrics.durationMs = Int((clock.now - start).components.attoseconds / 1_000_000_000_000_000)
            metrics.log()
            return RestoreResult(state: state, metrics: metrics)
        }
        Log.persistence.info("Primary state file failed, trying backup")
        metrics = RestoreMetrics()
        if let state = loadFrom(url: SessionSerializer.backupFileURL, metrics: &metrics) {
            metrics.source = .backup
            metrics.durationMs = Int((clock.now - start).components.attoseconds / 1_000_000_000_000_000)
            metrics.log()
            return RestoreResult(state: state, metrics: metrics)
        }
        Log.persistence.info("No restorable session state found")
        return nil
    }

    private static func loadFrom(url: URL, metrics: inout RestoreMetrics) -> SessionState? {
        do {
            let data = try Data(contentsOf: url)
            metrics.fileBytes = data.count
            guard let migratedData = try SessionStateMigrator.migrateIfNeeded(data: data) else {
                Log.persistence.warning("State file at \(url.lastPathComponent) is from a future version")
                return nil
            }
            metrics.migrated = (data != migratedData)
            let state = try decode(from: migratedData)
            return try validate(state, metrics: &metrics)
        } catch {
            Log.persistence.warning("Failed to load \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Decode

    static func decode(from data: Data) throws -> SessionState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionState.self, from: data)
    }

    // MARK: - Validate

    /// Validates structural integrity and fixes stale references.
    /// Returns a corrected SessionState or throws on unrecoverable issues.
    static func validate(_ state: SessionState) throws -> SessionState {
        var metrics = RestoreMetrics()
        return try validate(state, metrics: &metrics)
    }

    /// Validates structural integrity, fixes stale references, and records corrections in metrics.
    static func validate(_ state: SessionState, metrics: inout RestoreMetrics) throws -> SessionState {
        guard !state.workspaces.isEmpty else {
            throw RestoreError.emptyWorkspaces
        }

        let validatedWorkspaces = try state.workspaces.map { workspace -> WorkspaceState in
            guard !workspace.spaces.isEmpty else {
                throw RestoreError.emptySpaces(workspaceName: workspace.name)
            }

            let validatedSpaces = try workspace.spaces.map { space -> SpaceState in
                guard !space.tabs.isEmpty else {
                    throw RestoreError.emptyTabs(spaceName: space.name)
                }

                let validatedTabs = space.tabs.map { tab -> TabState in
                    let paneIdValid = paneExists(tab.activePaneId, in: tab.root)
                    if !paneIdValid {
                        metrics.stalePaneIdFixes += 1
                    }
                    let fixedActivePaneId = paneIdValid
                        ? tab.activePaneId
                        : firstLeafId(in: tab.root)
                    return TabState(
                        id: tab.id,
                        name: tab.name,
                        activePaneId: fixedActivePaneId,
                        root: resolveWorkingDirectories(in: tab.root, fallback: workspace.defaultWorkingDirectory, metrics: &metrics)
                    )
                }
                metrics.tabCount += validatedTabs.count

                let tabIdValid = validatedTabs.contains(where: { $0.id == space.activeTabId })
                if !tabIdValid {
                    metrics.staleTabIdFixes += 1
                }
                let fixedActiveTabId = tabIdValid
                    ? space.activeTabId
                    : validatedTabs[0].id

                let validatedWorktreePath: String?
                if let wt = space.worktreePath, resolveDirectory(wt) == nil {
                    Log.worktree.warning("Worktree path \(wt) no longer exists on disk for Space '\(space.name)'. Removing association.")
                    validatedWorktreePath = nil
                } else {
                    validatedWorktreePath = space.worktreePath
                }

                return SpaceState(
                    id: space.id,
                    name: space.name,
                    activeTabId: fixedActiveTabId,
                    defaultWorkingDirectory: resolveDirectory(space.defaultWorkingDirectory),
                    worktreePath: validatedWorktreePath,
                    tabs: validatedTabs
                )
            }
            metrics.spaceCount += validatedSpaces.count

            let spaceIdValid = validatedSpaces.contains(where: { $0.id == workspace.activeSpaceId })
            if !spaceIdValid {
                metrics.staleSpaceIdFixes += 1
            }
            let fixedActiveSpaceId = spaceIdValid
                ? workspace.activeSpaceId
                : validatedSpaces[0].id

            return WorkspaceState(
                id: workspace.id,
                name: workspace.name,
                activeSpaceId: fixedActiveSpaceId,
                defaultWorkingDirectory: resolveDirectory(workspace.defaultWorkingDirectory),
                spaces: validatedSpaces,
                windowFrame: workspace.windowFrame,
                isFullscreen: workspace.isFullscreen
            )
        }
        metrics.workspaceCount = validatedWorkspaces.count

        let workspaceIdValid = validatedWorkspaces.contains(where: { $0.id == state.activeWorkspaceId })
        if !workspaceIdValid {
            metrics.staleWorkspaceIdFixes += 1
        }
        let fixedActiveWorkspaceId = workspaceIdValid
            ? state.activeWorkspaceId
            : validatedWorkspaces[0].id

        return SessionState(
            version: state.version,
            savedAt: state.savedAt,
            activeWorkspaceId: fixedActiveWorkspaceId,
            workspaces: validatedWorkspaces
        )
    }

    // MARK: - Build Live Hierarchy

    /// Constructs the live WorkspaceCollection from validated SessionState.
    @MainActor
    static func buildWorkspaceCollection(from state: SessionState) -> WorkspaceCollection {
        let workspaces = state.workspaces.map { ws -> Workspace in
            let spaces = ws.spaces.map { sp -> SpaceModel in
                let tabs = sp.tabs.map { tab -> TabModel in
                    let pvm = PaneViewModel.fromState(tab.root, focusedPaneID: tab.activePaneId)
                    return TabModel(id: tab.id, customName: tab.name, paneViewModel: pvm)
                }
                let space = SpaceModel(
                    id: sp.id,
                    name: sp.name,
                    tabs: tabs,
                    activeTabID: sp.activeTabId,
                    defaultWorkingDirectory: sp.defaultWorkingDirectory.map { URL(fileURLWithPath: $0) }
                )
                space.worktreePath = sp.worktreePath.flatMap { URL(fileURLWithPath: $0) }
                return space
            }

            let wdURL = ws.defaultWorkingDirectory.map { URL(fileURLWithPath: $0) }
            let spaceCollection = SpaceCollection(
                spaces: spaces,
                activeSpaceID: ws.activeSpaceId,
                workspaceDefaultDirectory: wdURL
            )

            return Workspace(
                id: ws.id,
                name: ws.name,
                defaultWorkingDirectory: wdURL,
                spaceCollection: spaceCollection
            )
        }

        return WorkspaceCollection(
            workspaces: workspaces,
            activeWorkspaceID: state.activeWorkspaceId
        )
    }

    // MARK: - Working Directory Helpers

    /// Resolves working directories in a pane tree, replacing missing paths with fallbacks.
    private static func resolveWorkingDirectories(
        in node: PaneNodeState,
        fallback: String?,
        metrics: inout RestoreMetrics
    ) -> PaneNodeState {
        switch node {
        case .pane(let leaf):
            metrics.paneCount += 1
            let original = resolveDirectory(leaf.workingDirectory)
            let resolved = original
                ?? fallback.flatMap { resolveDirectory($0) }
                ?? homeDirectory()
            if original == nil {
                metrics.directoryFallbacks += 1
            }
            return .pane(PaneLeafState(
                paneID: leaf.paneID,
                workingDirectory: resolved,
                restoreCommand: leaf.restoreCommand,
                claudeSessionState: leaf.claudeSessionState
            ))

        case .split(let split):
            return .split(PaneSplitState(
                direction: split.direction,
                ratio: split.ratio,
                first: resolveWorkingDirectories(in: split.first, fallback: fallback, metrics: &metrics),
                second: resolveWorkingDirectories(in: split.second, fallback: fallback, metrics: &metrics)
            ))
        }
    }

    /// Returns the path if the directory exists on disk, nil otherwise.
    private static func resolveDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            ? path
            : nil
    }

    private static func homeDirectory() -> String {
        ProcessInfo.processInfo.environment["HOME"] ?? "~"
    }

    // MARK: - Pane Tree Helpers

    private static func paneExists(_ paneID: UUID, in node: PaneNodeState) -> Bool {
        switch node {
        case .pane(let leaf):
            return leaf.paneID == paneID
        case .split(let split):
            return paneExists(paneID, in: split.first) || paneExists(paneID, in: split.second)
        }
    }

    private static func firstLeafId(in node: PaneNodeState) -> UUID {
        switch node {
        case .pane(let leaf):
            return leaf.paneID
        case .split(let split):
            return firstLeafId(in: split.first)
        }
    }
}

// MARK: - WindowFrame Offscreen Detection

extension WindowFrame {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Returns true if this frame intersects any of the provided screen frames.
    func isOnScreen(screenFrames: [CGRect]) -> Bool {
        let rect = cgRect
        return screenFrames.contains { $0.intersects(rect) }
    }
}
