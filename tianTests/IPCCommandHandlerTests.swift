import Testing
import Foundation
@testable import tian

struct IPCCommandHandlerTests {
    /// v2 env: `tabId`/`spaceId` are gone; `sessionId` replaces them. A sentinel
    /// (all-zero) session/workspace resolves to nothing, so commands that fall
    /// back to the env hit their "not found" paths.
    private let dummyEnv = IPCEnv(
        paneId: "00000000-0000-0000-0000-000000000000",
        sessionId: "00000000-0000-0000-0000-000000000000",
        workspaceId: "00000000-0000-0000-0000-000000000000"
    )

    private func request(_ command: String, _ params: [String: IPCValue] = [:], env: IPCEnv? = nil) -> IPCRequest {
        IPCRequest(version: ipcProtocolVersion, command: command, params: params, env: env ?? dummyEnv)
    }

    // MARK: - Ping

    @Test @MainActor func pingReturnsPong() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("ping"))
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

    /// Regression guard: the server now speaks v2, so a v1 client is rejected
    /// (clean break — no compat shim).
    @Test @MainActor func version1IsRejected() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let request = IPCRequest(version: 1, command: "ping", params: [:], env: dummyEnv)
        let response = await handler.handle(request)
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Protocol version mismatch") == true)
    }

    // MARK: - Unknown command

    @Test @MainActor func unknownCommandReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("foo.bar"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Unknown command") == true)
    }

    // MARK: - tab.* is gone (clean break → unknown command)

    /// The `tab` command group was deleted in the flatten. Every former verb now
    /// falls through to the unknown-command default — no aliases, no silent
    /// success. This is the contract external tooling must not rely on.
    @Test @MainActor func tabCommandsAreUnknown() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        for verb in ["tab.create", "tab.list", "tab.close", "tab.focus"] {
            let response = await handler.handle(request(verb))
            #expect(response.ok == false)
            #expect(response.error?.code == 1)
            #expect(response.error?.message.contains("Unknown command") == true,
                    "expected \(verb) to be an unknown command")
        }
    }

    // MARK: - Workspace list (sessionCount shape)

    @Test @MainActor func workspaceListWithNoWindowReturnsEmpty() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("workspace.list"))
        #expect(response.ok == true)
        if case .array(let items)? = response.result?["workspaces"] {
            #expect(items.isEmpty)
        } else {
            Issue.record("expected a 'workspaces' array in the result")
        }
    }

    // MARK: - Session Commands (verb wiring / validation)

    @Test @MainActor func sessionCreateWithNoWorkspaceReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.create", ["name": .string("feature")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Workspace not found") == true)
    }

    @Test @MainActor func sessionListWithNoWorkspaceReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.list"))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Workspace not found") == true)
    }

    @Test @MainActor func sessionCloseMissingIdReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.close"))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Missing required parameter: id") == true)
    }

    @Test @MainActor func sessionCloseInvalidUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.close", ["id": .string("not-a-uuid")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func sessionCloseNonexistentReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.close", ["id": .string(UUID().uuidString)]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Session not found") == true)
    }

    @Test @MainActor func sessionFocusMissingIdReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.focus"))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Missing required parameter: id") == true)
    }

    @Test @MainActor func sessionFocusInvalidUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.focus", ["id": .string("nope")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func sessionFocusNonexistentReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("session.focus", ["id": .string(UUID().uuidString)]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Session not found") == true)
    }

    // MARK: - Status Commands

    @Test @MainActor func statusSetMissingBothLabelAndStateReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.set"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("at least one of") == true)
    }

    @Test @MainActor func statusSetInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(paneId: "not-a-uuid", sessionId: "", workspaceId: "")
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.set", ["label": .string("test")], env: invalidEnv))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func statusSetNonexistentPaneReturnsError() async {
        let statusManager = PaneStatusManager()
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: statusManager)
        let response = await handler.handle(request("status.set", ["label": .string("test")]))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
        #expect(statusManager.statuses.isEmpty)
    }

    @Test @MainActor func statusClearSuccess() async {
        let paneID = UUID()
        let statusManager = PaneStatusManager()
        statusManager.setStatus(paneID: paneID, label: "Running")

        let env = IPCEnv(paneId: paneID.uuidString, sessionId: "", workspaceId: "")
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: statusManager)
        let response = await handler.handle(request("status.clear", env: env))
        #expect(response.ok == true)
        #expect(statusManager.statuses[paneID] == nil)
    }

    @Test @MainActor func statusClearInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(paneId: "invalid", sessionId: "", workspaceId: "")
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.clear", env: invalidEnv))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func statusClearWithNoExistingStatusSucceeds() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.clear"))
        #expect(response.ok == true)
    }

    // MARK: - Status Set with State

    @Test @MainActor func statusSetInvalidStateReturnsErrorWithValidValues() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.set", ["state": .string("invalid_state")]))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid state") == true)
        #expect(response.error?.message.contains("active") == true)
        #expect(response.error?.message.contains("busy") == true)
        #expect(response.error?.message.contains("needs_attention") == true)
    }

    @Test @MainActor func statusSetWithStateOnlyNonexistentPaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.set", ["state": .string("busy")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    @Test @MainActor func statusSetWithLabelOnlyStillWorks() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.set", ["label": .string("Thinking...")]))
        // Passes param validation, fails at pane lookup (dummyEnv uses zero UUID)
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    @Test @MainActor func statusSetWithStateOnlyValidatesStateParam() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.set", ["state": .string("busy")]))
        // Passes param validation (state is valid), fails at pane lookup (dummyEnv uses zero UUID)
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    @Test @MainActor func statusSetWithStateAndLabelValidationWorks() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(
            request("status.set", ["state": .string("active"), "label": .string("Testing coexistence")])
        )
        // Passes param validation (both state and label are provided), fails at pane lookup
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    @Test @MainActor func statusSetWithEmptyParamsStillValidatesError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("status.set"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("at least one of") == true)
    }

    // MARK: - Prompt Commands

    @Test @MainActor func promptSetMissingTextReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("prompt.set"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: text") == true)
    }

    @Test @MainActor func promptSetInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(paneId: "not-a-uuid", sessionId: "", workspaceId: "")
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: PaneStatusManager())
        let response = await handler.handle(request("prompt.set", ["text": .string("fix the bug")], env: invalidEnv))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func promptSetNonexistentPaneReturnsError() async {
        let statusManager = PaneStatusManager()
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator(), statusManager: statusManager)
        let response = await handler.handle(request("prompt.set", ["text": .string("fix the bug")]))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
        // Failed pane lookup must not store the prompt.
        #expect(statusManager.lastPrompts.isEmpty)
    }

    // MARK: - Pane split (validation + Claude rejection backstop)

    @Test @MainActor func paneSplitInvalidPaneUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.split", ["paneId": .string("not-a-uuid")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func paneSplitNonexistentPaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.split", ["paneId": .string(UUID().uuidString)]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    // MARK: - Pane list (session scoping)

    @Test @MainActor func paneListWithNoSessionReturnsError() async {
        // Falls back to env.sessionId (sentinel) → no session resolves.
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.list"))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Session not found") == true)
    }

    @Test @MainActor func paneListInvalidSessionParamReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.list", ["sessionId": .string("not-a-uuid")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Session not found") == true)
    }

    // MARK: - Pane focus

    @Test @MainActor func paneFocusMissingTargetReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.focus"))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Missing required parameter: target") == true)
    }

    @Test @MainActor func paneFocusNonexistentSourcePaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.focus", ["target": .string("up")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    // MARK: - Pane close

    @Test @MainActor func paneCloseInvalidUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.close", ["paneId": .string("not-a-uuid")]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func paneCloseNonexistentReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.close", ["paneId": .string(UUID().uuidString)]))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    // MARK: - Pane set-directory

    @Test @MainActor func paneSetDirectoryMissingDirectoryReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.set-directory"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: directory") == true)
    }

    @Test @MainActor func paneSetDirectoryInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(paneId: "not-a-uuid", sessionId: "", workspaceId: "")
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.set-directory", ["directory": .string("/tmp")], env: invalidEnv))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func paneSetDirectoryNonexistentPaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.set-directory", ["directory": .string("/tmp")]))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    // MARK: - Notify Commands

    @Test @MainActor func notifyMissingMessageReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("notify"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: message") == true)
    }

    @Test @MainActor func notifyInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(paneId: "not-valid", sessionId: "", workspaceId: "")
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("notify", ["message": .string("hello")], env: invalidEnv))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    // MARK: - Worktree Commands

    @Test @MainActor func worktreeCreateMissingBranchNameReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("worktree.create"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: branchName") == true)
    }

    @Test @MainActor func worktreeRemoveMissingSessionIdReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("worktree.remove"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: sessionId") == true)
    }

    @Test @MainActor func worktreeRemoveInvalidUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("worktree.remove", ["sessionId": .string("not-a-uuid")]))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func worktreeCreateWithNoWorkspaceContextReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("worktree.create", ["branchName": .string("feature/test")]))
        // dummyEnv's sentinel workspaceId resolves to no workspace and there's no
        // --path, so the handler fails at the no-context guard before the orchestrator.
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("No workspace context") == true)
    }

    @Test @MainActor func worktreeCreateWithExplicitPathBypassesWorkspaceGuard() async throws {
        // An explicit --path is sufficient even with no resolvable workspace: the
        // request must reach the orchestrator (which then fails on the non-git
        // path) rather than short-circuit at the no-workspace guard.
        let tempDir = NSTemporaryDirectory() + "tian-worktree-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(
            request("worktree.create", ["branchName": .string("feature/test"), "path": .string(tempDir)])
        )
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        // Reached the orchestrator (non-git path) instead of failing at the guard.
        #expect(response.error?.message.contains("No workspace context") == false)
    }

    @Test @MainActor func worktreeRemoveNonexistentSessionSucceeds() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("worktree.remove", ["sessionId": .string(UUID().uuidString)]))
        // removeWorktreeSession returns early (no-op) when the session isn't found.
        #expect(response.ok == true)
    }

    // MARK: - Git refresh (resolves from env.sessionId)

    @Test @MainActor func gitRefreshWithUnresolvableSessionReturnsError() async {
        // git.refresh reads env.sessionId (v2). The sentinel session resolves to
        // nothing, so the handler reports the session-from-environment failure.
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("git.refresh"))
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Session not found from environment") == true)
    }

    // MARK: - Pane Restore Command

    @Test @MainActor func setRestoreCommandMissingCommandReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.set-restore-command"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: command") == true)
    }

    @Test @MainActor func setRestoreCommandInvalidPaneUUIDReturnsError() async {
        let invalidEnv = IPCEnv(paneId: "not-a-uuid", sessionId: "", workspaceId: "")
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(
            request("pane.set-restore-command", ["command": .string("claude --resume abc")], env: invalidEnv)
        )
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid pane UUID") == true)
    }

    @Test @MainActor func setRestoreCommandNonexistentPaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(
            request("pane.set-restore-command", ["command": .string("claude --resume abc")])
        )
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    // MARK: - Pane Send

    @Test @MainActor func paneSendMissingTextReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.send"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Missing required parameter: text") == true)
    }

    @Test @MainActor func paneSendInvalidPaneUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(
            request("pane.send", ["text": .string("echo hi"), "paneId": .string("not-a-uuid")])
        )
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func paneSendNonexistentPaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.send", ["text": .string("echo hi")]))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
    }

    // MARK: - Pane Capture

    @Test @MainActor func paneCaptureInvalidPaneUUIDReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.capture", ["paneId": .string("not-a-uuid")]))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Invalid UUID") == true)
    }

    @Test @MainActor func paneCaptureNonexistentPaneReturnsError() async {
        let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
        let response = await handler.handle(request("pane.capture"))
        #expect(response.ok == false)
        #expect(response.error?.code == 1)
        #expect(response.error?.message.contains("Pane not found") == true)
    }
}
