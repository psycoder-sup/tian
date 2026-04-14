import Testing
import Foundation
@testable import tian

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

    @Test @MainActor func statusSetMissingBothLabelAndStateReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(version: 1, command: "status.set", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("at least one of") == true)
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

    // MARK: - Status Set with State

    @Test @MainActor func statusSetInvalidStateReturnsErrorWithValidValues() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(
            version: 1,
            command: "status.set",
            params: ["state": .string("invalid_state")],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid state") == true)
        #expect(response.error?.message.contains("active") == true)
        #expect(response.error?.message.contains("busy") == true)
        #expect(response.error?.message.contains("needs_attention") == true)
    }

    @Test @MainActor func statusSetWithStateOnlyNonexistentPaneReturnsError() async {
        let statusManager = PaneStatusManager()
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: statusManager)
        let request = IPCRequest(
            version: 1,
            command: "status.set",
            params: ["state": .string("busy")],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    @Test @MainActor func statusSetWithLabelOnlyStillWorks() async {
        let statusManager = PaneStatusManager()
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: statusManager)
        let request = IPCRequest(
            version: 1,
            command: "status.set",
            params: ["label": .string("Thinking...")],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        // Passes param validation, fails at pane lookup (dummyEnv uses zero UUID)
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    // MARK: - Status Set with State Only (CLI Extension)

    @Test @MainActor func statusSetWithStateOnlyValidatesStateParam() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(
            version: 1,
            command: "status.set",
            params: ["state": .string("busy")],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        // Passes param validation (state is valid), fails at pane lookup (dummyEnv uses zero UUID)
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    @Test @MainActor func statusSetWithStateAndLabelValidationWorks() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(
            version: 1,
            command: "status.set",
            params: ["state": .string("active"), "label": .string("Testing coexistence")],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        // Passes param validation (both state and label are provided), fails at pane lookup
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    @Test @MainActor func statusSetWithEmptyParamsStillValidatesError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let request = IPCRequest(version: 1, command: "status.set", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("at least one of") == true)
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

    // MARK: - Worktree Commands

    @Test @MainActor func worktreeCreateMissingBranchNameReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "worktree.create", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: branchName") == true)
    }

    @Test @MainActor func worktreeRemoveMissingSpaceIdReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "worktree.remove", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: spaceId") == true)
    }

    @Test @MainActor func worktreeRemoveInvalidUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "worktree.remove", params: ["spaceId": .string("not-a-uuid")], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func worktreeCreateWithNoWindowReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(
            version: 1,
            command: "worktree.create",
            params: ["branchName": .string("feature/test")],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        // No windows open, so orchestrator can't resolve a workspace or repo
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
    }

    @Test @MainActor func worktreeRemoveNonexistentSpaceSucceeds() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let nonexistentId = UUID().uuidString
        let request = IPCRequest(
            version: 1,
            command: "worktree.remove",
            params: ["spaceId": .string(nonexistentId)],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        // removeWorktreeSpace returns early (no-op) when space not found
        #expect(response.ok == true)
    }

    // MARK: - Pane Restore Command

    @Test @MainActor func setRestoreCommandMissingCommandReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "pane.set-restore-command", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: command") == true)
    }

    @Test @MainActor func setRestoreCommandInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(
            paneId: "not-a-uuid",
            tabId: "00000000-0000-0000-0000-000000000000",
            spaceId: "00000000-0000-0000-0000-000000000000",
            workspaceId: "00000000-0000-0000-0000-000000000000"
        )
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(
            version: 1,
            command: "pane.set-restore-command",
            params: ["command": .string("claude --resume abc")],
            env: invalidEnv
        )
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func setRestoreCommandNonexistentPaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(
            version: 1,
            command: "pane.set-restore-command",
            params: ["command": .string("claude --resume abc")],
            env: dummyEnv
        )
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
    }
}
