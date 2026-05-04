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
        case emptyTabs(spaceName: String, kind: SectionKind)

        var description: String {
            switch self {
            case .emptyWorkspaces:
                "Session state contains no workspaces"
            case .emptySpaces(let name):
                "Workspace '\(name)' contains no spaces"
            case .emptyTabs(let name, let kind):
                "Space '\(name)' has no tabs in \(kind) section"
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
                // FR-25 — Claude section must have ≥1 tab; Terminal may be empty.
                guard !space.claudeSection.tabs.isEmpty else {
                    throw RestoreError.emptyTabs(spaceName: space.name, kind: .claude)
                }

                let validatedClaudeSection = validateSection(
                    space.claudeSection,
                    kind: .claude,
                    spaceName: space.name,
                    workspaceDefaultDirectory: workspace.defaultWorkingDirectory,
                    metrics: &metrics,
                    allowEmpty: false
                )
                let validatedTerminalSection = validateSection(
                    space.terminalSection,
                    kind: .terminal,
                    spaceName: space.name,
                    workspaceDefaultDirectory: workspace.defaultWorkingDirectory,
                    metrics: &metrics,
                    allowEmpty: true
                )

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
                    defaultWorkingDirectory: resolveDirectory(space.defaultWorkingDirectory),
                    worktreePath: validatedWorktreePath,
                    claudeSection: validatedClaudeSection,
                    terminalSection: validatedTerminalSection,
                    terminalVisible: space.terminalVisible,
                    dockPosition: space.dockPosition,
                    splitRatio: space.splitRatio,
                    focusedSectionKind: space.focusedSectionKind
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
                isFullscreen: workspace.isFullscreen,
                inspectPanelVisible: workspace.inspectPanelVisible,
                inspectPanelWidth: workspace.inspectPanelWidth
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
                let claudeSection = buildSection(from: sp.claudeSection)
                let terminalSection = buildSection(from: sp.terminalSection)
                return SpaceModel(
                    id: sp.id,
                    name: sp.name,
                    claudeSection: claudeSection,
                    terminalSection: terminalSection,
                    terminalVisible: sp.terminalVisible,
                    dockPosition: sp.dockPosition,
                    splitRatio: sp.splitRatio,
                    focusedSectionKind: sp.focusedSectionKind,
                    defaultWorkingDirectory: sp.defaultWorkingDirectory.map { URL(fileURLWithPath: $0) },
                    worktreePath: sp.worktreePath
                )
            }

            let wdURL = ws.defaultWorkingDirectory.map { URL(fileURLWithPath: $0) }
            let spaceCollection = SpaceCollection(
                spaces: spaces,
                activeSpaceID: ws.activeSpaceId,
                workspaceDefaultDirectory: wdURL
            )

            let inspectPanelState = InspectPanelState(
                isVisible: ws.inspectPanelVisible ?? true,
                width: ws.inspectPanelWidth.map { CGFloat($0) } ?? InspectPanelState.defaultWidth
            )
            return Workspace(
                id: ws.id,
                name: ws.name,
                defaultWorkingDirectory: wdURL,
                spaceCollection: spaceCollection,
                inspectPanelState: inspectPanelState
            )
        }

        return WorkspaceCollection(
            workspaces: workspaces,
            activeWorkspaceID: state.activeWorkspaceId
        )
    }

    // MARK: - Section Helpers

    private static func validateSection(
        _ section: SectionState,
        kind: SectionKind,
        spaceName: String,
        workspaceDefaultDirectory: String?,
        metrics: inout RestoreMetrics,
        allowEmpty: Bool
    ) -> SectionState {
        let validatedTabs = section.tabs.map { tab -> TabState in
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
                root: resolveWorkingDirectories(in: tab.root, fallback: workspaceDefaultDirectory, metrics: &metrics),
                sectionKind: kind
            )
        }
        metrics.tabCount += validatedTabs.count

        let fixedActiveTabId: UUID?
        if validatedTabs.isEmpty {
            if !allowEmpty {
                Log.persistence.warning("Section \(kind) for Space '\(spaceName)' unexpectedly empty")
            }
            fixedActiveTabId = nil
        } else {
            if let candidate = section.activeTabId,
               validatedTabs.contains(where: { $0.id == candidate }) {
                fixedActiveTabId = candidate
            } else {
                if section.activeTabId != nil {
                    metrics.staleTabIdFixes += 1
                }
                fixedActiveTabId = validatedTabs[0].id
            }
        }

        return SectionState(
            id: section.id,
            kind: kind,
            activeTabId: fixedActiveTabId,
            tabs: validatedTabs
        )
    }

    @MainActor
    private static func buildSection(from state: SectionState) -> SectionModel {
        let tabs = state.tabs.map { tab -> TabModel in
            let pvm = PaneViewModel.fromState(tab.root, focusedPaneID: tab.activePaneId, sectionKind: state.kind)
            return TabModel(id: tab.id, customName: tab.name, paneViewModel: pvm, sectionKind: state.kind)
        }
        let fallbackActiveTabID = tabs.first?.id ?? UUID()
        return SectionModel(
            id: state.id,
            kind: state.kind,
            tabs: tabs,
            activeTabID: state.activeTabId ?? fallbackActiveTabID
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
