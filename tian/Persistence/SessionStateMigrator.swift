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
