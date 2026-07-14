import Foundation
import Testing
@testable import tian

struct ScanRootGuardTests {

    // MARK: - Refused roots

    @Test func refusesHomeDirectoryFromFileManager() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(ScanRootGuard.isTooBroad(home))
    }

    @Test func refusesHomeDirectoryFromNSHomeDirectory() {
        let home = URL(filePath: NSHomeDirectory())
        #expect(ScanRootGuard.isTooBroad(home))
    }

    @Test func refusesHomeDirectoryWithTrailingSlash() {
        var path = NSHomeDirectory()
        if !path.hasSuffix("/") { path += "/" }
        let home = URL(filePath: path)
        #expect(ScanRootGuard.isTooBroad(home))
    }

    @Test func refusesHomeDirectoryResolvedForm() {
        // Resolve symlinks ourselves (e.g. a `/private/...` form on some
        // systems) and confirm the guard still recognizes it as home.
        let resolved = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
        #expect(ScanRootGuard.isTooBroad(resolved))
    }

    @Test func refusesRoot() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/")))
    }

    @Test func refusesUsersDirectory() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/Users")))
    }

    @Test func refusesUsersDirectoryWithTrailingSlash() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/Users/")))
    }

    @Test func refusesVolumeRoot() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/Volumes/SomeVolume")))
    }

    @Test func refusesVolumeRootWithTrailingSlash() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/Volumes/SomeVolume/")))
    }

    @Test func refusesVolumesDirectory() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/Volumes")))
    }

    @Test func refusesVolumesDirectoryWithTrailingSlash() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/Volumes/")))
    }

    @Test func refusesSystemVolumesData() {
        #expect(ScanRootGuard.isTooBroad(URL(filePath: "/System/Volumes/Data")))
    }

    // MARK: - Allowed roots

    @Test func allowsSubdirectoryOfHome() {
        let project = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Code/myproject")
        #expect(!ScanRootGuard.isTooBroad(project))
    }

    @Test func allowsTmpSubdirectory() {
        #expect(!ScanRootGuard.isTooBroad(URL(filePath: "/tmp/whatever")))
    }

    @Test func allowsVolumeSubdirectory() {
        #expect(!ScanRootGuard.isTooBroad(URL(filePath: "/Volumes/SomeVolume/project")))
    }

    @Test func allowsVolumesSiblingLookingPath() {
        // Sanity check the volume-root heuristic isn't overly broad: a path
        // that merely starts with "Volumes" two levels deep should not match.
        #expect(!ScanRootGuard.isTooBroad(URL(filePath: "/some/Volumes/thing")))
    }
}
