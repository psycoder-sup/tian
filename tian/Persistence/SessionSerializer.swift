import Foundation

/// Captures a snapshot of the live workspace model and writes it to disk as JSON.
enum SessionSerializer {
    static let currentVersion = 7   // bumped from 6 for the flattened Session model

    static var stateDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(stateDirectoryName)", isDirectory: true)
    }

    /// Namespaces the state directory by build variant so tian and tian-debug
    /// don't clobber each other's persisted tab state.
    private static var stateDirectoryName: String {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        return bundleID.hasSuffix(".debug") ? "tian-debug" : "tian"
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
            let sessions = workspace.sessionCollection.sessions.map { session in
                sessionRecord(from: session, sessionStates: sessionStates)
            }
            return WorkspaceState(
                id: workspace.id,
                name: workspace.name,
                // Fallback to the first session's id (then a fresh UUID) when
                // no active session is set; SessionRestorer.validate reshapes a
                // stale value on read, so a sentinel here is harmless.
                activeSessionId: workspace.sessionCollection.activeSessionID
                    ?? sessions.first?.id ?? UUID(),
                defaultWorkingDirectory: workspace.defaultWorkingDirectory?.path,
                sessions: sessions,
                windowFrame: windowFrame,
                isFullscreen: isFullscreen,
                inspectPanelVisible: workspace.inspectPanelState.isVisible,
                inspectPanelWidth: Double(workspace.inspectPanelState.width),
                activeTab: workspace.inspectTabState.activeTab.rawValue
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
    private static func sessionRecord(
        from session: Session,
        sessionStates: [UUID: ClaudeSessionState]
    ) -> SessionRecord {
        // The Claude side is a single leaf. It should always be a `.pane`, but
        // if a stray split slipped in, persist its depth-first first leaf so we
        // never lose the session.
        let claudeLeaf: PaneLeafState? = session.claudePane.map { pvm in
            let root = pvm.splitTree.root.toState(
                restoreCommands: pvm.restoreCommands,
                sessionStates: sessionStates
            )
            return root.firstLeaf
        }
        let terminalRoot: PaneNodeState? = session.terminalPanel.map { pvm in
            pvm.splitTree.root.toState(
                restoreCommands: pvm.restoreCommands,
                sessionStates: sessionStates
            )
        }
        return SessionRecord(
            id: session.id,
            customName: session.customName,
            defaultWorkingDirectory: session.defaultWorkingDirectory?.path,
            worktreePath: session.worktreePath?.path,
            claudePane: claudeLeaf,
            terminalRoot: terminalRoot,
            terminalFocusedPaneId: session.terminalPanel?.splitTree.focusedPaneID,
            terminalVisible: session.terminalVisible,
            dockPosition: session.dockPosition,
            splitRatio: session.splitRatio,
            focusedArea: session.focusedArea,
            parentSessionID: session.parentSessionID
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
