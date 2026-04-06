import Testing
import Foundation
@testable import aterm

struct IPCCommandHandlerTests {
    private let dummyEnv = IPCEnv(
        paneId: "00000000-0000-0000-0000-000000000000",
        tabId: "00000000-0000-0000-0000-000000000000",
        spaceId: "00000000-0000-0000-0000-000000000000",
        workspaceId: "00000000-0000-0000-0000-000000000000"
    )

    // MARK: - Ping

    @Test @MainActor func pingReturnsPong() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "ping", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == true)
        #expect(response.result?["message"]?.stringValue == "pong")
    }

    // MARK: - Version mismatch

    @Test @MainActor func versionMismatchReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 999, command: "ping", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Protocol version mismatch") == true)
    }

    // MARK: - Unknown command

    @Test @MainActor func unknownCommandReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "foo.bar", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Unknown command") == true)
    }

    // MARK: - Status Commands

    @Test @MainActor func statusSetMissingLabelReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(version: 1, command: "status.set", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: label") == true)
    }

    @Test @MainActor func statusSetInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(
            paneId: "not-a-uuid",
            tabId: "00000000-0000-0000-0000-000000000000",
            spaceId: "00000000-0000-0000-0000-000000000000",
            workspaceId: "00000000-0000-0000-0000-000000000000"
        )
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(version: 1, command: "status.set", params: ["label": .string("test")], env: invalidEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func statusSetNonexistentPaneReturnsError() async {
        let statusManager = PaneStatusManager()
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: statusManager)
        let request = IPCRequest(version: 1, command: "status.set", params: ["label": .string("test")], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
        #expect(statusManager.statuses.isEmpty)
    }

    @Test @MainActor func statusClearSuccess() async {
        let paneID = UUID()
        let statusManager = PaneStatusManager()
        statusManager.setStatus(paneID: paneID, label: "Running")

        let env = IPCEnv(
            paneId: paneID.uuidString,
            tabId: "00000000-0000-0000-0000-000000000000",
            spaceId: "00000000-0000-0000-0000-000000000000",
            workspaceId: "00000000-0000-0000-0000-000000000000"
        )
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: statusManager)
        let request = IPCRequest(version: 1, command: "status.clear", params: [:], env: env)
        let response = await handler.handle(request)
        #expect(response.ok == true)
        #expect(statusManager.statuses[paneID] == nil)
    }

    @Test @MainActor func statusClearInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(
            paneId: "invalid",
            tabId: "00000000-0000-0000-0000-000000000000",
            spaceId: "00000000-0000-0000-0000-000000000000",
            workspaceId: "00000000-0000-0000-0000-000000000000"
        )
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(version: 1, command: "status.clear", params: [:], env: invalidEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func statusClearWithNoExistingStatusSucceeds() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(version: 1, command: "status.clear", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == true)
    }

    // MARK: - Notify Commands

    @Test @MainActor func notifyMissingMessageReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "notify", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: message") == true)
    }

    @Test @MainActor func notifyInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(
            paneId: "not-valid",
            tabId: "00000000-0000-0000-0000-000000000000",
            spaceId: "00000000-0000-0000-0000-000000000000",
            workspaceId: "00000000-0000-0000-0000-000000000000"
        )
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "notify", params: ["message": .string("hello")], env: invalidEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }
}
