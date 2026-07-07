import AppKit
import Foundation

/// Reads persisted session state from disk and reconstructs the live model hierarchy.
///
/// Fallback chain: state.json → state.prev.json → nil (caller creates default state).
enum SessionRestorer {

    // MARK: - Errors

    enum RestoreError: Error, CustomStringConvertible {
        case emptyWorkspaces
        case emptySessions(workspaceName: String)

        var description: String {
            switch self {
            case .emptyWorkspaces:
                "Session state contains no workspaces"
            case .emptySessions(let name):
                "Workspace '\(name)' contains no sessions"
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
            guard !workspace.sessions.isEmpty else {
                throw RestoreError.emptySessions(workspaceName: workspace.name)
            }

            // A remote workspace's paths live on another host, so they can't be
            // validated (or nulled) against the local disk — pass them through.
            let isRemote = workspace.remote != nil
            func validateDir(_ path: String?) -> String? {
                isRemote ? path : resolveDirectory(path)
            }

            // IDs of every Session in this workspace, for validating parent
            // links. Validation never drops individual Sessions (empty
            // workspaces throw), so the original ID set matches the restored one.
            let workspaceSessionIDs = Set(workspace.sessions.map { $0.id })

            let validatedSessions = workspace.sessions.map { session -> SessionRecord in
                // A nil Claude pane is legal — it persists the empty-claude
                // placeholder state, so there is no "claude must exist" invariant.
                let validatedClaude: PaneLeafState? = session.claudePane.map { claude in
                    guard !isRemote else { return claude }
                    let resolved = resolveWorkingDirectories(
                        in: .pane(claude),
                        fallback: workspace.defaultWorkingDirectory,
                        metrics: &metrics
                    )
                    if case .pane(let leaf) = resolved { return leaf }
                    return claude
                }

                // Resolve the terminal tree's directories and fix its focused
                // pane id (must reference a leaf that exists in the tree).
                let validatedTerminalRoot: PaneNodeState?
                let validatedTerminalFocusedPaneId: UUID?
                if let root = session.terminalRoot {
                    let resolvedRoot = isRemote ? root : resolveWorkingDirectories(
                        in: root,
                        fallback: workspace.defaultWorkingDirectory,
                        metrics: &metrics
                    )
                    validatedTerminalRoot = resolvedRoot
                    if let focus = session.terminalFocusedPaneId,
                       paneExists(focus, in: resolvedRoot) {
                        validatedTerminalFocusedPaneId = focus
                    } else {
                        if session.terminalFocusedPaneId != nil {
                            metrics.stalePaneIdFixes += 1
                        }
                        validatedTerminalFocusedPaneId = resolvedRoot.firstLeaf.paneID
                    }
                } else {
                    validatedTerminalRoot = nil
                    validatedTerminalFocusedPaneId = nil
                }

                // Terminal can't be visible or focused when it doesn't exist.
                let hasTerminal = validatedTerminalRoot != nil
                let terminalVisible = session.terminalVisible && hasTerminal
                let focusedArea: PaneKind = hasTerminal ? session.focusedArea : .claude

                let validatedWorktreePath: String?
                if !isRemote, let wt = session.worktreePath, resolveDirectory(wt) == nil {
                    Log.worktree.warning("Worktree path \(wt) no longer exists on disk for Session '\(session.customName ?? "(auto)")'. Removing association.")
                    validatedWorktreePath = nil
                } else {
                    validatedWorktreePath = session.worktreePath
                }

                // Drop a dangling parent link (orchestrator closed, or a stray
                // self/cross-workspace reference) so the sidebar never renders a
                // phantom child. Mirrors how a stale worktreePath is nulled above.
                let validatedParentSessionID: UUID?
                if let parent = session.parentSessionID,
                   parent == session.id || !workspaceSessionIDs.contains(parent) {
                    Log.persistence.warning("Parent Session \(parent) not present in workspace for Session '\(session.customName ?? "(auto)")'. Dropping nesting.")
                    validatedParentSessionID = nil
                } else {
                    validatedParentSessionID = session.parentSessionID
                }

                return SessionRecord(
                    id: session.id,
                    customName: session.customName,
                    defaultWorkingDirectory: validateDir(session.defaultWorkingDirectory),
                    worktreePath: validatedWorktreePath,
                    claudePane: validatedClaude,
                    terminalRoot: validatedTerminalRoot,
                    terminalFocusedPaneId: validatedTerminalFocusedPaneId,
                    terminalVisible: terminalVisible,
                    dockPosition: session.dockPosition,
                    splitRatio: session.splitRatio,
                    focusedArea: focusedArea,
                    parentSessionID: validatedParentSessionID
                )
            }
            metrics.sessionCount += validatedSessions.count

            let sessionIdValid = validatedSessions.contains(where: { $0.id == workspace.activeSessionId })
            if !sessionIdValid {
                metrics.staleSessionIdFixes += 1
            }
            let fixedActiveSessionId = sessionIdValid
                ? workspace.activeSessionId
                : validatedSessions[0].id

            return WorkspaceState(
                id: workspace.id,
                name: workspace.name,
                activeSessionId: fixedActiveSessionId,
                defaultWorkingDirectory: validateDir(workspace.defaultWorkingDirectory),
                sessions: validatedSessions,
                windowFrame: workspace.windowFrame,
                isFullscreen: workspace.isFullscreen,
                inspectPanelVisible: workspace.inspectPanelVisible,
                inspectPanelWidth: workspace.inspectPanelWidth,
                activeTab: workspace.activeTab,
                remote: workspace.remote
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
            // Build the SSH connection first (this registers its channel), then
            // derive the spawn spec the restored panes bake in — so a restored
            // remote pane spawns over SSH exactly like a fresh one.
            let remoteConnection = ws.remote?.remoteConnection
            let transport = remoteConnection.map {
                SSHConnection(host: $0.host, remoteDirectory: $0.remoteDirectory)
            }
            let remoteSpawn = transport.map {
                RemoteSpawnSpec(channel: $0.channel, remoteDirectory: $0.channel.root)
            }

            let sessions = ws.sessions.map { rec -> Session in
                // Every restored session gets a live Claude pane. A nil persisted
                // claudePane (e.g. an old placeholder record, or a v6→v7 terminal-
                // only space) seeds a *fresh* Claude leaf — no `--resume`, so it
                // launches plain `claude` — rather than restoring the removed
                // empty-claude placeholder state.
                let claudeLeaf = rec.claudePane ?? PaneLeafState(
                    paneID: UUID(),
                    workingDirectory: rec.defaultWorkingDirectory
                        ?? ws.defaultWorkingDirectory
                        ?? "~",
                    restoreCommand: nil,
                    claudeSessionState: nil
                )
                let claudePVM = PaneViewModel.fromState(
                    .pane(claudeLeaf), focusedPaneID: claudeLeaf.paneID, kind: .claude,
                    remoteSpawn: remoteSpawn
                )
                let terminalPVM = rec.terminalRoot.map { root in
                    PaneViewModel.fromState(
                        root,
                        focusedPaneID: rec.terminalFocusedPaneId ?? root.firstLeaf.paneID,
                        kind: .terminal,
                        remoteSpawn: remoteSpawn
                    )
                }
                let session = Session(
                    id: rec.id,
                    customName: rec.customName,
                    claudePane: claudePVM,
                    terminalPanel: terminalPVM,
                    terminalVisible: rec.terminalVisible,
                    dockPosition: rec.dockPosition,
                    splitRatio: rec.splitRatio,
                    focusedArea: rec.focusedArea,
                    defaultWorkingDirectory: rec.defaultWorkingDirectory.map { URL(fileURLWithPath: $0) },
                    worktreePath: rec.worktreePath,
                    remoteChannel: transport?.channel
                )
                session.parentSessionID = rec.parentSessionID
                return session
            }

            let wdURL = ws.defaultWorkingDirectory.map { URL(fileURLWithPath: $0) }
            let sessionCollection = SessionCollection(
                sessions: sessions,
                activeSessionID: ws.activeSessionId,
                workspaceDefaultDirectory: wdURL
            )

            let inspectPanelState = InspectPanelState.restore(
                visible: ws.inspectPanelVisible,
                width: ws.inspectPanelWidth
            )
            let initialTab: InspectTab = ws.activeTab
                .flatMap { InspectTab(rawValue: $0) } ?? .files
            let inspectTabState = InspectTabState(activeTab: initialTab)
            return Workspace(
                id: ws.id,
                name: ws.name,
                defaultWorkingDirectory: wdURL,
                sessionCollection: sessionCollection,
                remote: remoteConnection,
                transport: transport,
                inspectPanelState: inspectPanelState,
                inspectTabState: inspectTabState
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
