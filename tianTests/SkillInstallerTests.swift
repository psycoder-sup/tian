import Testing
import Foundation
@testable import tian

struct SkillInstallerTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Creates a skill subdirectory `name` under `root` containing a SKILL.md
    /// file with the given contents, returning the SKILL.md URL.
    @discardableResult
    private func makeSkill(_ name: String, in root: URL, contents: String) throws -> URL {
        let skillDir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let file = skillDir.appendingPathComponent("SKILL.md")
        try Data(contents.utf8).write(to: file)
        return file
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - installSkills

    @Test func installSkillsCopiesAllSkillSubdirs() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        defer { cleanup(source); cleanup(dest) }

        try makeSkill("tian-cli", in: source, contents: "cli")
        try makeSkill("other", in: source, contents: "other")

        try SkillInstaller.installSkills(from: source, to: dest)

        #expect(try read(dest.appendingPathComponent("tian-cli/SKILL.md")) == "cli")
        #expect(try read(dest.appendingPathComponent("other/SKILL.md")) == "other")
    }

    @Test func installSkillsOverwritesExistingDestSkill() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        defer { cleanup(source); cleanup(dest) }

        // Pre-existing dest skill with stale content (and a stray extra file).
        try makeSkill("tian-cli", in: dest, contents: "old")
        try Data("stray".utf8).write(
            to: dest.appendingPathComponent("tian-cli/stray.txt"))

        try makeSkill("tian-cli", in: source, contents: "new")

        try SkillInstaller.installSkills(from: source, to: dest)

        #expect(try read(dest.appendingPathComponent("tian-cli/SKILL.md")) == "new")
        // The stale extra file is gone because the dir was replaced wholesale.
        #expect(!FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("tian-cli/stray.txt").path))
    }

    @Test func installSkillsLeavesSymlinkedDestSkillUntouched() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        let linkTarget = try makeTempDir()
        defer { cleanup(source); cleanup(dest); cleanup(linkTarget) }

        // Dev-machine setup: ~/.claude/skills/tian-cli is a symlink to a repo checkout.
        try makeSkill("tian-cli", in: linkTarget, contents: "repo")
        let link = dest.appendingPathComponent("tian-cli", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: linkTarget.appendingPathComponent("tian-cli", isDirectory: true))

        try makeSkill("tian-cli", in: source, contents: "bundled")

        try SkillInstaller.installSkills(from: source, to: dest)

        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try read(link.appendingPathComponent("SKILL.md")) == "repo")
    }

    @Test func installSkillsIgnoresNonDirectoryEntries() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        defer { cleanup(source); cleanup(dest) }

        try makeSkill("tian-cli", in: source, contents: "cli")
        // A loose file at the top level of source should be skipped.
        try Data("loose".utf8).write(to: source.appendingPathComponent("README.md"))

        try SkillInstaller.installSkills(from: source, to: dest)

        #expect(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("tian-cli/SKILL.md").path))
        #expect(!FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("README.md").path))
    }

    // MARK: - syncIfNeeded

    @Test func syncIfNeededCopiesAndRecordsVersionWhenMarkerDiffers() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        defer { cleanup(source); cleanup(dest) }

        try makeSkill("tian-cli", in: source, contents: "cli")

        let suite = "tian-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        SkillInstaller.syncIfNeeded(
            bundledSkillsURL: source,
            destinationRoot: dest,
            currentVersion: "1.2.3",
            defaults: defaults
        )

        #expect(try read(dest.appendingPathComponent("tian-cli/SKILL.md")) == "cli")
        #expect(defaults.string(forKey: "tian.skillSync.lastVersion") == "1.2.3")
    }

    @Test func syncIfNeededDoesNothingWhenMarkerMatches() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        defer { cleanup(source); cleanup(dest) }

        try makeSkill("tian-cli", in: source, contents: "cli")

        let suite = "tian-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Marker already equals the current version → no copy should happen.
        defaults.set("1.2.3", forKey: "tian.skillSync.lastVersion")

        SkillInstaller.syncIfNeeded(
            bundledSkillsURL: source,
            destinationRoot: dest,
            currentVersion: "1.2.3",
            defaults: defaults
        )

        #expect(!FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("tian-cli").path))
    }
}
