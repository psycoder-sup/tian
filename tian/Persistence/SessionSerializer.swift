import Foundation

/// Captures a snapshot of the live workspace model and writes it to disk as JSON.
enum SessionSerializer {
    static let currentVersion = 4

    static var stateDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/tian", isDirectory: true)
    }

    static var stateFileURL: URL {
        stateDirectory.appendingPathComponent("state.json")
    }

    static var backupFileURL: URL {
        stateDirectory.appendingPathComponent("state.prev.json")
    }

    // MARK: - Snapshot

    /// Captures the current state of the workspace collection as a serializable snapshot.
    @MainActor
    static func snapshot(
        from collection: WorkspaceCollection,
        windowFrame: WindowFrame? = nil,
        isFullscreen: Bool? = nil
    ) -> SessionState {
        let sessionStates = PaneStatusManager.shared.sessionStates
        let workspaces = collection.workspaces.map { workspace in
            WorkspaceState(
                id: workspace.id,
                name: workspace.name,
                activeSpaceId: workspace.spaceCollection.activeSpaceID,
                defaultWorkingDirectory: workspace.defaultWorkingDirectory?.path,
                spaces: workspace.spaceCollection.spaces.map { space in
                    SpaceState(
                        id: space.id,
                        name: space.name,
                        defaultWorkingDirectory: space.defaultWorkingDirectory?.path,
                        worktreePath: space.worktreePath?.path,
                        claudeSection: sectionState(from: space.claudeSection, sessionStates: sessionStates),
                        terminalSection: sectionState(from: space.terminalSection, sessionStates: sessionStates),
                        terminalVisible: space.terminalVisible,
                        dockPosition: space.dockPosition,
                        splitRatio: space.splitRatio,
                        focusedSectionKind: space.focusedSectionKind
                    )
                },
                windowFrame: windowFrame,
                isFullscreen: isFullscreen
            )
        }

        return SessionState(
            version: currentVersion,
            savedAt: Date(),
            // Fallback sentinel when `workspaces` is empty; SessionRestorer.validate
            // rejects empty-workspace states on read, so the value is unobservable.
            activeWorkspaceId: collection.activeWorkspaceID ?? UUID(),
            workspaces: workspaces
        )
    }

    @MainActor
    private static func sectionState(
        from section: SectionModel,
        sessionStates: [UUID: ClaudeSessionState]
    ) -> SectionState {
        let tabs = section.tabs.map { tab in
            TabState(
                id: tab.id,
                name: tab.customName,
                activePaneId: tab.paneViewModel.splitTree.focusedPaneID,
                root: tab.paneViewModel.splitTree.root.toState(
                    restoreCommands: tab.paneViewModel.restoreCommands,
                    sessionStates: sessionStates
                ),
                sectionKind: section.kind
            )
        }
        return SectionState(
            id: section.id,
            kind: section.kind,
            activeTabId: tabs.isEmpty ? nil : section.activeTabID,
            tabs: tabs
        )
    }

    // MARK: - Encode

    /// Encodes a SessionState to JSON data.
    static func encode(_ state: SessionState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }

    // MARK: - Save

    /// Encodes the state and writes it atomically to disk with backup rotation.
    static func save(_ state: SessionState) throws {
        let data = try encode(state)
        let fm = FileManager.default

        // Ensure directory exists
        try fm.createDirectory(at: stateDirectory, withIntermediateDirectories: true)

        // Rotate backup: copy current state.json → state.prev.json
        if fm.fileExists(atPath: stateFileURL.path) {
            do {
                if fm.fileExists(atPath: backupFileURL.path) {
                    try fm.removeItem(at: backupFileURL)
                }
                try fm.copyItem(at: stateFileURL, to: backupFileURL)
            } catch {
                Log.persistence.warning("Failed to rotate backup: \(error.localizedDescription)")
            }
        }

        // Atomic write: write to temp file, then move into place
        let tempURL = stateDirectory.appendingPathComponent("state.\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        _ = try fm.replaceItemAt(stateFileURL, withItemAt: tempURL)

        // Set file permissions to 0600 (owner read/write only)
        try fm.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateFileURL.path
        )
    }
}
