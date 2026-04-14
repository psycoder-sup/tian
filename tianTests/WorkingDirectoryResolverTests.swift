import Testing
import Foundation
@testable import tian

struct WorkingDirectoryResolverTests {
    @Test func sourcePaneDirectoryTakesPrecedence() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: "/Users/me/project",
            spaceDefault: URL(filePath: "/Users/me/space"),
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/project")
    }

    @Test func spaceDefaultUsedWhenNoSourcePane() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            spaceDefault: URL(filePath: "/Users/me/space"),
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/space")
    }

    @Test func workspaceDefaultUsedWhenNoSpaceDefault() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            spaceDefault: nil,
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/workspace")
    }

    @Test func homeFallbackWhenNothingSet() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            spaceDefault: nil,
            workspaceDefault: nil,
            home: "/Users/me"
        )
        #expect(result == "/Users/me")
    }

    @Test func emptySourcePaneDirectoryFallsThrough() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: "",
            spaceDefault: URL(filePath: "/Users/me/space"),
            workspaceDefault: nil,
            home: "/Users/me"
        )
        #expect(result == "/Users/me/space")
    }

    @Test func tildeSourcePaneDirectoryFallsThrough() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: "~",
            spaceDefault: nil,
            workspaceDefault: URL(filePath: "/Users/me/workspace"),
            home: "/Users/me"
        )
        #expect(result == "/Users/me/workspace")
    }

    @Test func spaceDefaultOverridesWorkspaceDefault() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            spaceDefault: URL(filePath: "/space-level"),
            workspaceDefault: URL(filePath: "/workspace-level"),
            home: "/Users/me"
        )
        #expect(result == "/space-level")
    }

    @Test func allNilExceptHomeFallsToHome() {
        let result = WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            spaceDefault: nil,
            workspaceDefault: nil,
            home: "/home/testuser"
        )
        #expect(result == "/home/testuser")
    }
}
