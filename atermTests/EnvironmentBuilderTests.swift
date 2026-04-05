import Testing
import Foundation
@testable import aterm

struct EnvironmentBuilderTests {
    private let socketPath = "/var/folders/xx/T/aterm-501.sock"
    private let paneID = UUID()
    private let tabID = UUID()
    private let spaceID = UUID()
    private let workspaceID = UUID()
    private let cliPath = "/Applications/aterm.app/Contents/MacOS/aterm-cli"

    // MARK: - PaneHierarchyContext

    @Test func contextHoldsAllFields() {
        let ctx = PaneHierarchyContext(
            socketPath: socketPath,
            workspaceID: workspaceID,
            spaceID: spaceID,
            tabID: tabID,
            cliPath: cliPath
        )
        #expect(ctx.socketPath == socketPath)
        #expect(ctx.workspaceID == workspaceID)
        #expect(ctx.spaceID == spaceID)
        #expect(ctx.tabID == tabID)
        #expect(ctx.cliPath == cliPath)
    }

    // MARK: - EnvironmentBuilder

    @Test func returnsAllSevenKeys() {
        let env = EnvironmentBuilder.buildPaneEnvironment(
            socketPath: socketPath,
            paneID: paneID,
            tabID: tabID,
            spaceID: spaceID,
            workspaceID: workspaceID,
            cliPath: cliPath
        )
        #expect(env.count == 7)
        #expect(env.keys.contains("ATERM_SOCKET"))
        #expect(env.keys.contains("ATERM_PANE_ID"))
        #expect(env.keys.contains("ATERM_TAB_ID"))
        #expect(env.keys.contains("ATERM_SPACE_ID"))
        #expect(env.keys.contains("ATERM_WORKSPACE_ID"))
        #expect(env.keys.contains("ATERM_CLI_PATH"))
        #expect(env.keys.contains("PATH"))
    }

    @Test func valuesMatchInput() {
        let env = EnvironmentBuilder.buildPaneEnvironment(
            socketPath: socketPath,
            paneID: paneID,
            tabID: tabID,
            spaceID: spaceID,
            workspaceID: workspaceID,
            cliPath: cliPath
        )
        #expect(env["ATERM_SOCKET"] == socketPath)
        #expect(env["ATERM_PANE_ID"] == paneID.uuidString)
        #expect(env["ATERM_TAB_ID"] == tabID.uuidString)
        #expect(env["ATERM_SPACE_ID"] == spaceID.uuidString)
        #expect(env["ATERM_WORKSPACE_ID"] == workspaceID.uuidString)
        #expect(env["ATERM_CLI_PATH"] == cliPath)
    }

    @Test func pathIsPrependedNotReplaced() throws {
        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let env = EnvironmentBuilder.buildPaneEnvironment(
            socketPath: socketPath,
            paneID: paneID,
            tabID: tabID,
            spaceID: spaceID,
            workspaceID: workspaceID,
            cliPath: cliPath
        )
        let path = try #require(env["PATH"])
        #expect(path.contains(originalPath))
        #expect(path.hasPrefix(Bundle.main.executableURL!.deletingLastPathComponent().path))
    }
}
