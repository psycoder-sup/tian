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
    ]

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
