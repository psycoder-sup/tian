import Testing
import Foundation
@testable import tian

struct WorkingDirectoryResolverTests {
    @Test func sourcePaneDirectoryTakesPrecedence() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: "/Users/me/project",
            sessionDefault: URL(filePath: "/Users/me/session"),
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/project")
    }

    @Test func sessionDefaultUsedWhenNoSourcePane() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            sessionDefault: URL(filePath: "/Users/me/session"),
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/session")
    }

    @Test func workspaceDefaultUsedWhenNoSessionDefault() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            sessionDefault: nil,
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/workspace")
    }

    @Test func homeFallbackWhenNothingSet() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            sessionDefault: nil,
            workspaceDefault: nil,
            home: "/Users/me"
        )
        #expect(result == "/Users/me")
    }

    @Test func emptySourcePaneDirectoryFallsThrough() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: "",
            sessionDefault: URL(filePath: "/Users/me/session"),
            workspaceDefault: nil,
            home: "/Users/me"
        )
        #expect(result == "/Users/me/session")
    }

    @Test func tildeSourcePaneDirectoryFallsThrough() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: "~",
            sessionDefault: nil,
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/workspace")
    }

    @Test func sessionDefaultOverridesWorkspaceDefault() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            sessionDefault: URL(filePath: "/session-level"),
            workspaceDefault: URL(filePath: "/workspace-level"),
            home: "/Users/me"
        )
        #expect(result == "/session-level")
    }

    @Test func allNilExceptHomeFallsToHome() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            sessionDefault: nil,
            workspaceDefault: nil,
            home: "/home/testuser"
        )
        #expect(result == "/home/testuser")
    }
}
