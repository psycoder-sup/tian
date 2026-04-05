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

    @Test @MainActor func pingReturnsPong() {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "ping", params: [:], env: dummyEnv)
        let response = handler.handle(request)
        #expect(response.ok == true)
        #expect(response.result?["message"]?.stringValue == "pong")
    }

    // MARK: - Version mismatch

    @Test @MainActor func versionMismatchReturnsError() {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 999, command: "ping", params: [:], env: dummyEnv)
        let response = handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Protocol version mismatch") == true)
    }

    // MARK: - Unknown command

    @Test @MainActor func unknownCommandReturnsError() {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "foo.bar", params: [:], env: dummyEnv)
        let response = handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Unknown command") == true)
    }
}
