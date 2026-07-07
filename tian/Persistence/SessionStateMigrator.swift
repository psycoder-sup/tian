import Foundation

/// Handles schema version detection and migration of persisted session state.
///
/// Migration functions operate on raw JSON dictionaries so they can handle
/// any structural change without requiring the old schema's typed models.
enum SessionStateMigrator {
    /// A migration transforms a JSON dictionary from one version to the next.
    typealias Migration = @Sendable ([String: Any]) throws -> [String: Any]

    /// The current schema version that the app expects.
    static let currentVersion = SessionSerializer.currentVersion

    /// Ordered registry of migrations. Key is the source version.
    /// For example, `migrations[1]` migrates v1 → v2.
    static let migrations: [Int: Migration] = [
        // v1 → v2: Added optional worktreePath to SpaceState.
        // The field is optional so existing v1 data decodes correctly without transformation.
        1: { json in json },
        // v2 → v3: Added optional claudeSessionState to PaneLeafState.
        // The field is optional so existing v2 data decodes correctly without transformation.
        2: { json in json },
        // v4 → v5: Added optional `inspectPanelVisible` and `inspectPanelWidth`
        // to `WorkspaceState`. Both fields are optional so v4 decodes as nil and
        // the runtime applies defaults (true / 320) on first load.
        4: { json in json },
        // v5 → v6: Added optional `activeTab: String?` to `WorkspaceState`. The
        // field is optional so v5 decodes as nil; the runtime applies the
        // default (.files) on load.
        5: { json in json },
        // v3 → v4: Split flat SpaceState.tabs into (claudeSection, terminalSection).
        // Legacy tabs (all shell, per v3 semantics) move into terminalSection
        // preserving order + PaneLeafState.claudeSessionState. A fresh Claude
        // section with one pane is synthesised at the Space's default
        // working directory.
        3: { json in
            var dict = json
            guard var workspaces = dict["workspaces"] as? [[String: Any]] else {
                return dict
            }
            for wi in workspaces.indices {
                guard var spaces = workspaces[wi]["spaces"] as? [[String: Any]] else { continue }
                for si in spaces.indices {
                    var newSpace = spaces[si]

                    // 1. Legacy tabs → Terminal section.
                    let legacyTabs = (newSpace["tabs"] as? [[String: Any]]) ?? []
                    let taggedTabs: [[String: Any]] = legacyTabs.map { tab in
                        var t = tab
                        t["sectionKind"] = "terminal"
                        return t
                    }
                    let legacyActive = newSpace["activeTabId"] as? String
                    let terminalActiveTabId: Any
                    if taggedTabs.isEmpty {
                        terminalActiveTabId = NSNull()
                    } else {
                        terminalActiveTabId = legacyActive ?? (taggedTabs[0]["id"] as? String ?? "")
                    }
                    newSpace["terminalSection"] = [
                        "id": UUID().uuidString,
                        "kind": "terminal",
                        "activeTabId": terminalActiveTabId,
                        "tabs": taggedTabs,
                    ] as [String: Any]

                    // 2. Synthesise a fresh Claude section with one tab + one pane.
                    let paneID = UUID().uuidString
                    let tabID = UUID().uuidString
                    let wd = (newSpace["defaultWorkingDirectory"] as? String)
                        ?? ProcessInfo.processInfo.environment["HOME"] ?? "/"
                    let leaf: [String: Any] = [
                        "type": "pane",
                        "paneID": paneID,
                        "workingDirectory": wd,
                    ]
                    let freshTab: [String: Any] = [
                        "id": tabID,
                        "activePaneId": paneID,
                        "root": leaf,
                        "sectionKind": "claude",
                    ]
                    newSpace["claudeSection"] = [
                        "id": UUID().uuidString,
                        "kind": "claude",
                        "activeTabId": tabID,
                        "tabs": [freshTab],
                    ] as [String: Any]

                    // 3. Layout defaults.
                    newSpace["terminalVisible"] = false
                    newSpace["dockPosition"] = "right"
                    newSpace["splitRatio"] = 0.7
                    newSpace["focusedSectionKind"] = "claude"

                    // 4. Remove legacy keys.
                    newSpace.removeValue(forKey: "tabs")
                    newSpace.removeValue(forKey: "activeTabId")

                    spaces[si] = newSpace
                }
                workspaces[wi]["spaces"] = spaces
            }
            dict["workspaces"] = workspaces
            return dict
        },
        // v6 → v7: Flatten Workspace → Space → Section → Tab into a flat list
        // of Sessions. Each surviving Claude tab becomes a Session; the active
        // Claude tab's Session inherits the space's active Terminal tab as its
        // attached terminal panel. Reader tabs and non-active Terminal tabs are
        // dropped. See `migrateV6ToV7` for the per-space rules.
        6: { json in try SessionStateMigrator.migrateV6ToV7(json) },
        // v7 → v8: Added optional `remote: RemoteConnectionState?` to
        // `WorkspaceState`. The field is optional so v7 decodes as nil (a local
        // workspace) with no transformation.
        7: { json in json },
    ]

    // MARK: - v6 → v7 Migration

    /// Rewrites every workspace, replacing its `spaces` list with a flat
    /// `sessions` list and renaming `activeSpaceId` → `activeSessionId`.
    private static func migrateV6ToV7(_ json: [String: Any]) throws -> [String: Any] {
        var dict = json
        guard var workspaces = dict["workspaces"] as? [[String: Any]] else {
            return dict
        }
        for wi in workspaces.indices {
            var workspace = workspaces[wi]

            let spaces = (workspace["spaces"] as? [[String: Any]]) ?? []
            var sessions: [[String: Any]] = []
            for space in spaces {
                sessions.append(contentsOf: sessionsFromSpace(space))
            }
            workspace["sessions"] = sessions

            // Key renames on the workspace itself.
            if let activeSpaceId = workspace["activeSpaceId"] {
                workspace["activeSessionId"] = activeSpaceId
            }
            workspace.removeValue(forKey: "activeSpaceId")
            workspace.removeValue(forKey: "spaces")

            workspaces[wi] = workspace
        }
        dict["workspaces"] = workspaces
        return dict
    }

    /// Expands one v6 space into its flat list of v7 sessions.
    private static func sessionsFromSpace(_ space: [String: Any]) -> [[String: Any]] {
        let spaceId = space["id"] as? String ?? UUID().uuidString
        // v7 sessions carry an optional `customName` (nil = auto-derived name).
        // The primary session inherits the space's name, except the pre-flatten
        // "default" placeholder, which maps to nil so it auto-names instead.
        let primaryCustomName: Any = {
            if let name = space["name"] as? String, name != "default" { return name }
            return NSNull()
        }()
        let defaultWorkingDirectory = space["defaultWorkingDirectory"] ?? NSNull()
        let worktreePath = space["worktreePath"] ?? NSNull()
        let parentSessionID = space["parentSpaceID"] ?? NSNull()
        let dockPosition = space["dockPosition"] as? String ?? "right"
        let splitRatio = space["splitRatio"] as? Double ?? 0.7
        let spaceTerminalVisible = space["terminalVisible"] as? Bool ?? false
        let focusedSectionKind = space["focusedSectionKind"] as? String ?? "claude"

        // Terminal tree = the terminal section's active tab (fallback: first).
        var terminalRoot: Any = NSNull()
        var terminalFocusedPaneId: Any = NSNull()
        if let terminalSection = space["terminalSection"] as? [String: Any],
           let terminalTabs = terminalSection["tabs"] as? [[String: Any]],
           !terminalTabs.isEmpty {
            let activeTerminalTabId = terminalSection["activeTabId"] as? String
            let selected = terminalTabs.first { ($0["id"] as? String) == activeTerminalTabId }
                ?? terminalTabs[0]
            if let root = selected["root"] as? [String: Any] {
                terminalRoot = root
                terminalFocusedPaneId = selected["activePaneId"] ?? NSNull()
            }
        }
        let hasTerminal = !(terminalRoot is NSNull)
        let terminalVisible = spaceTerminalVisible && hasTerminal
        // Focus can't rest on an absent terminal.
        let focusedArea = hasTerminal ? focusedSectionKind : "claude"

        // Builds a session dict, copying the space-level fields shared by all
        // sessions carved out of this space.
        func makeSession(
            id: String,
            customName: Any,
            claudePane: Any,
            terminalRoot: Any,
            terminalFocusedPaneId: Any,
            terminalVisible: Bool,
            focusedArea: String
        ) -> [String: Any] {
            [
                "id": id,
                "customName": customName,
                "defaultWorkingDirectory": defaultWorkingDirectory,
                "worktreePath": worktreePath,
                "claudePane": claudePane,
                "terminalRoot": terminalRoot,
                "terminalFocusedPaneId": terminalFocusedPaneId,
                "terminalVisible": terminalVisible,
                "dockPosition": dockPosition,
                "splitRatio": splitRatio,
                "focusedArea": focusedArea,
                "parentSessionID": parentSessionID,
            ]
        }

        // Claude tabs, minus reader tabs (markdown/image readers aren't persisted in v7).
        let claudeSection = space["claudeSection"] as? [String: Any]
        let claudeTabs = ((claudeSection?["tabs"] as? [[String: Any]]) ?? [])
            .filter { !isReaderTab($0) }

        // Rule 5: a space with no surviving Claude tab becomes one session with
        // an empty (null) Claude pane, keeping the space's terminal tree.
        guard !claudeTabs.isEmpty else {
            return [makeSession(
                id: spaceId,
                customName: primaryCustomName,
                claudePane: NSNull(),
                terminalRoot: terminalRoot,
                terminalFocusedPaneId: terminalFocusedPaneId,
                terminalVisible: terminalVisible,
                focusedArea: focusedArea
            )]
        }

        // The primary session comes from the ACTIVE claude tab (fallback: first).
        let activeClaudeTabId = claudeSection?["activeTabId"] as? String
        let primaryTabId: String
        if let active = claudeTabs.first(where: { ($0["id"] as? String) == activeClaudeTabId }),
           let id = active["id"] as? String {
            primaryTabId = id
        } else {
            primaryTabId = claudeTabs[0]["id"] as? String ?? ""
        }

        var sessions: [[String: Any]] = []
        for tab in claudeTabs {
            let tabId = tab["id"] as? String ?? UUID().uuidString
            let claudePane: Any = (tab["root"] as? [String: Any])
                .flatMap { claudeLeaf(fromRoot: $0) } ?? NSNull()

            if tabId == primaryTabId {
                // Primary: id = space.id (preserves activeSpaceId + parentSpaceID
                // referential integrity), gets the terminal tree.
                sessions.append(makeSession(
                    id: spaceId,
                    customName: primaryCustomName,
                    claudePane: claudePane,
                    terminalRoot: terminalRoot,
                    terminalFocusedPaneId: terminalFocusedPaneId,
                    terminalVisible: terminalVisible,
                    focusedArea: focusedArea
                ))
            } else {
                // Sibling: flat peer (never nested under the primary), no terminal.
                // Carry the tab's own custom name as-is; a nil name auto-derives.
                let siblingCustomName: Any = tab["name"] as? String ?? NSNull()
                sessions.append(makeSession(
                    id: tabId,
                    customName: siblingCustomName,
                    claudePane: claudePane,
                    terminalRoot: NSNull(),
                    terminalFocusedPaneId: NSNull(),
                    terminalVisible: false,
                    focusedArea: "claude"
                ))
            }
        }
        return sessions
    }

    /// A tab that renders a file (markdown or image reader) rather than a
    /// terminal. Reader tabs are dropped by the v7 migration.
    private static func isReaderTab(_ tab: [String: Any]) -> Bool {
        (tab["markdownFilePath"] as? String) != nil || (tab["imageFilePath"] as? String) != nil
    }

    /// The Claude pane leaf for a claude tab's root node. A claude tab's root
    /// should always be a single `.pane`; defensively, a `.split` collapses to
    /// its depth-first first leaf. Strips the node's `"type"` discriminator so
    /// the result is a clean `PaneLeafState` dict.
    private static func claudeLeaf(fromRoot root: [String: Any]) -> [String: Any]? {
        guard let leaf = firstLeafNode(root) else { return nil }
        var stripped = leaf
        stripped.removeValue(forKey: "type")
        return stripped
    }

    /// Depth-first first `"pane"` node within a possibly-split pane node dict.
    private static func firstLeafNode(_ node: [String: Any]) -> [String: Any]? {
        guard let type = node["type"] as? String else { return nil }
        if type == "pane" { return node }
        if type == "split", let first = node["first"] as? [String: Any] {
            return firstLeafNode(first)
        }
        return nil
    }

    // MARK: - Errors

    enum MigrationError: Error, CustomStringConvertible {
        case missingVersion
        case futureVersion(found: Int, current: Int)
        case migrationFailed(fromVersion: Int, underlyingError: Error)

        var description: String {
            switch self {
            case .missingVersion:
                "State file is missing the 'version' field"
            case .futureVersion(let found, let current):
                "State file version \(found) is newer than current version \(current)"
            case .migrationFailed(let fromVersion, let underlyingError):
                "Migration from version \(fromVersion) failed: \(underlyingError)"
            }
        }
    }

    // MARK: - Public API

    /// Checks the version of a JSON dictionary and runs migrations if needed.
    ///
    /// - Returns: The migrated dictionary at the current version.
    /// - Throws: `MigrationError.futureVersion` if the version is from a newer app,
    ///           `MigrationError.missingVersion` if no version field exists.
    static func migrateIfNeeded(json: [String: Any]) throws -> [String: Any] {
        guard let version = json["version"] as? Int else {
            throw MigrationError.missingVersion
        }

        if version == currentVersion {
            return json
        }

        if version > currentVersion {
            throw MigrationError.futureVersion(found: version, current: currentVersion)
        }

        // Run migration chain: v(n) → v(n+1) → ... → v(current)
        var migrated = json
        for v in version..<currentVersion {
            guard let migration = migrations[v] else {
                // No migration registered for this step — assume compatible
                continue
            }
            do {
                migrated = try migration(migrated)
            } catch {
                throw MigrationError.migrationFailed(fromVersion: v, underlyingError: error)
            }
        }

        // Update the version field
        migrated["version"] = currentVersion
        return migrated
    }

    /// Convenience: reads Data, extracts version, migrates if needed, re-serializes to Data.
    ///
    /// - Returns: Migrated JSON data at the current version, or `nil` if the version
    ///   is from the future (downgrade scenario — caller should fall back to default state).
    static func migrateIfNeeded(data: Data) throws -> Data? {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonObject as? [String: Any] else {
            throw MigrationError.missingVersion
        }

        guard let version = json["version"] as? Int else {
            throw MigrationError.missingVersion
        }

        // Current version — return original data without re-serialization
        if version == currentVersion {
            return data
        }

        // Future version — caller should fall back to default state
        if version > currentVersion {
            return nil
        }

        // Older version — run migrations and re-serialize
        let migrated = try migrateIfNeeded(json: json)
        return try JSONSerialization.data(withJSONObject: migrated)
    }
}
