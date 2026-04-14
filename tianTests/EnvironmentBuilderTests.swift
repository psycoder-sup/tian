import Testing
import Foundation
@testable import tian

struct EnvironmentBuilderTests {
    private let socketPath = "/var/folders/xx/T/tian-501.sock"
    private let paneID = UUID()
    private let tabID = UUID()
    private let spaceID = UUID()
    private let workspaceID = UUID()
    private let cliPath = "/Applications/tian.app/Contents/MacOS/tian-cli"

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

    @Test func returnsAllKeys() {
        let env = EnvironmentBuilder.buildPaneEnvironment(
            socketPath: socketPath,
            paneID: paneID,
            tabID: tabID,
            spaceID: spaceID,
            workspaceID: workspaceID,
            cliPath: cliPath
        )
        #expect(env.count == 11)
        #expect(env.keys.contains("TIAN_SOCKET"))
        #expect(env.keys.contains("TIAN_PANE_ID"))
        #expect(env.keys.contains("TIAN_TAB_ID"))
        #expect(env.keys.contains("TIAN_SPACE_ID"))
        #expect(env.keys.contains("TIAN_WORKSPACE_ID"))
        #expect(env.keys.contains("TIAN_CLI_PATH"))
        #expect(env.keys.contains("TIAN_RESOURCES_DIR"))
        #expect(env.keys.contains("TIAN_SHELL_INTEGRATION_DIR"))
        #expect(env.keys.contains("ZDOTDIR"))
        #expect(env.keys.contains("TIAN_ORIGINAL_ZDOTDIR"))
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
        #expect(env["TIAN_SOCKET"] == socketPath)
        #expect(env["TIAN_PANE_ID"] == paneID.uuidString)
        #expect(env["TIAN_TAB_ID"] == tabID.uuidString)
        #expect(env["TIAN_SPACE_ID"] == spaceID.uuidString)
        #expect(env["TIAN_WORKSPACE_ID"] == workspaceID.uuidString)
        #expect(env["TIAN_CLI_PATH"] == cliPath)
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
        #expect(path.hasPrefix(Bundle.main.resourceURL!.path))
    }
}
