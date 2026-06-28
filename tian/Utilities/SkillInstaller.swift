import Foundation

enum SkillInstaller {
    private static let versionKey = "tian.skillSync.lastVersion"

    /// Called once at launch. Copies bundled skills into ~/.claude/skills only
    /// when the app version changed (fresh install or Sparkle update).
    static func syncIfNeeded(
        bundledSkillsURL: URL? = Bundle.main.resourceURL?
            .appendingPathComponent("skills", isDirectory: true),
        destinationRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true),
        currentVersion: String? = Bundle.main
            .infoDictionary?["CFBundleShortVersionString"] as? String,
        defaults: UserDefaults = .standard
    ) {
        guard let bundledSkillsURL,
              FileManager.default.fileExists(atPath: bundledSkillsURL.path) else { return }
        let version = currentVersion ?? "unknown"
        guard defaults.string(forKey: versionKey) != version else { return }
        do {
            try installSkills(from: bundledSkillsURL, to: destinationRoot)
            defaults.set(version, forKey: versionKey)
            Log.lifecycle.info("Synced bundled skills to \(destinationRoot.path) for v\(version)")
        } catch {
            Log.lifecycle.error("Skill sync failed: \(error.localizedDescription)")
        }
    }

    /// Pure file-copy: overwrite each skill subdirectory of `source` into `destination`.
    static func installSkills(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in try fm.contentsOfDirectory(at: source,
                includingPropertiesForKeys: [.isDirectoryKey]) {
            guard (try entry.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            else { continue }
            let dest = destination.appendingPathComponent(entry.lastPathComponent, isDirectory: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: entry, to: dest)
        }
    }
}
