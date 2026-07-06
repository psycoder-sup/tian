import Foundation

/// Dispatches IPC requests to the appropriate model layer operations.
@MainActor
final class IPCCommandHandler {
    private let windowCoordinator: WindowCoordinator
    private let statusManager: PaneStatusManager
    private let notificationManager: NotificationManager
    private let worktreeOrchestrator: WorktreeOrchestrator

    init(
        windowCoordinator: WindowCoordinator,
        statusManager: PaneStatusManager = .shared,
        notificationManager: NotificationManager = NotificationManager()
    ) {
        self.windowCoordinator = windowCoordinator
        self.statusManager = statusManager
        self.notificationManager = notificationManager
        self.worktreeOrchestrator = WorktreeOrchestrator(workspaceProvider: windowCoordinator)
    }

    func handle(_ request: IPCRequest) async -> IPCResponse {
        // Version check
        guard request.version == ipcProtocolVersion else {
            return .failure(
                code: 1,
                message: "Protocol version mismatch: client sent v\(request.version), server supports v\(ipcProtocolVersion). Update your CLI."
            )
        }

        switch request.command {
        case "ping":
            return .success(["message": .string("pong")])

        // Workspace
        case "workspace.create": return handleWorkspaceCreate(request)
        case "workspace.list":   return handleWorkspaceList(request)
        case "workspace.close":  return handleWorkspaceClose(request)
        case "workspace.focus":  return handleWorkspaceFocus(request)

        // Session
        case "session.create": return handleSessionCreate(request)
        case "session.list":   return handleSessionList(request)
        case "session.close":  return handleSessionClose(request)
        case "session.focus":  return handleSessionFocus(request)

        // Pane
        case "pane.split": return handlePaneSplit(request)
        case "pane.list":  return handlePaneList(request)
        case "pane.close": return handlePaneClose(request)
        case "pane.focus": return handlePaneFocus(request)
        case "pane.send":  return handlePaneSend(request)
        case "pane.capture": return handlePaneCapture(request)
        case "pane.set-directory": return handlePaneSetDirectory(request)
        case "pane.set-restore-command": return handleSetRestoreCommand(request)

        // Status (Phase 4)
        case "status.set":   return handleStatusSet(request)
        case "status.clear": return handleStatusClear(request)

        // Prompt
        case "prompt.set": return handlePromptSet(request)

        // Background Activity
        case "activity.sync":   return handleActivitySync(request)

        // Notify (Phase 5)
        case "notify": return await handleNotify(request)

        // Worktree
        case "worktree.create": return await handleWorktreeCreate(request)
        case "worktree.remove": return await handleWorktreeRemove(request)

        // Git
        case "git.refresh": return handleGitRefresh(request)

        default:
            return .failure(code: 1, message: "Unknown command: \(request.command)")
        }
    }

    // MARK: - Workspace Commands

    private func handleWorkspaceCreate(_ request: IPCRequest) -> IPCResponse {
        guard let name = stringParam("name", from: request.params) else {
            return missingParameter("name")
        }

        guard let collection = resolveCollection() else {
            return .failure(code: 1, message: "No window available.")
        }

        let directory = stringParam("directory", from: request.params)
        guard let workspace = collection.createWorkspace(name: name, workingDirectory: directory) else {
            return .failure(code: 1, message: "Invalid workspace name (empty after trimming).")
        }

        return .success(["id": .string(workspace.id.uuidString)])
    }

    private func handleWorkspaceList(_ request: IPCRequest) -> IPCResponse {
        guard let collection = resolveCollection() else {
            return .success(["workspaces": .array([])])
        }

        let items: [IPCValue] = collection.workspaces.map { workspace in
            .object([
                "id": .string(workspace.id.uuidString),
                "name": .string(workspace.name),
                "sessionCount": .int(workspace.sessionCollection.sessions.count),
                "active": .bool(workspace.id == collection.activeWorkspaceID),
            ])
        }

        return .success(["workspaces": .array(items)])
    }

    private func handleWorkspaceClose(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return missingParameter("id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return invalidUUID(idStr)
        }

        guard let (collection, workspace) = resolveWorkspace(id: id) else {
            return .failure(code: 1, message: "Workspace not found: \(idStr)")
        }

        let force = optionalBool("force", from: request.params)
        let panes = workspace.sessionCollection.sessions.flatMap(\.allPanes)
        if let error = checkProcessSafety(force: force, panes: panes) { return error }

        collection.removeWorkspace(id: id)
        return .success()
    }

    private func handleWorkspaceFocus(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return missingParameter("id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return invalidUUID(idStr)
        }

        guard let (collection, _) = resolveWorkspace(id: id) else {
            return .failure(code: 1, message: "Workspace not found: \(idStr)")
        }

        collection.activateWorkspace(id: id)
        return .success()
    }

    // MARK: - Session Commands

    private func handleSessionCreate(_ request: IPCRequest) -> IPCResponse {
        let workspaceIdStr = stringParam("workspaceId", from: request.params)

        guard let (_, workspace) = resolveWorkspaceFromParamOrEnv(workspaceIdStr, env: request.env) else {
            return .failure(code: 1, message: "Workspace not found: \(workspaceIdStr ?? request.env.workspaceId)")
        }

        let background = optionalBool("background", from: request.params)
        let name = stringParam("name", from: request.params)
        let session = workspace.sessionCollection.createSession(name: name, focusOnCreate: !background)

        return .success(["id": .string(session.id.uuidString)])
    }

    private func handleSessionList(_ request: IPCRequest) -> IPCResponse {
        let workspaceIdStr = stringParam("workspaceId", from: request.params)

        guard let (_, workspace) = resolveWorkspaceFromParamOrEnv(workspaceIdStr, env: request.env) else {
            return .failure(code: 1, message: "Workspace not found: \(workspaceIdStr ?? request.env.workspaceId)")
        }

        let items: [IPCValue] = workspace.sessionCollection.sessions.map { session in
            // Use the same floored value the GUI dot reads (`aggregateClaudeState`
            // lifts a clean turn-end to `.busy` while non-stale background work is
            // outstanding), so `tian session list` and the sidebar agree. The
            // unfloored `statusManager.aggregateSessionState(in:)` would report
            // `idle` mid-background-work, defeating orchestrator polling.
            let claudeState = session.aggregateClaudeState
            return .object([
                "id": .string(session.id.uuidString),
                "name": .string(session.displayName),
                "claudeState": claudeState.map { .string($0.rawValue) } ?? .null,
                "paneCount": .int(session.allPanes.reduce(0) { $0 + $1.splitTree.leafCount }),
                "active": .bool(session.id == workspace.sessionCollection.activeSessionID),
            ])
        }

        return .success(["sessions": .array(items)])
    }

    private func handleSessionClose(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return missingParameter("id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return invalidUUID(idStr)
        }

        let workspaceIdStr = stringParam("workspaceId", from: request.params)
        guard let (workspace, session) = resolveSession(id: id, workspaceId: workspaceIdStr.flatMap(UUID.init)) else {
            return .failure(code: 1, message: "Session not found: \(idStr)")
        }

        let force = optionalBool("force", from: request.params)
        if let error = checkProcessSafety(force: force, panes: session.allPanes) { return error }

        workspace.sessionCollection.removeSession(id: id)
        return .success()
    }

    private func handleSessionFocus(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return missingParameter("id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return invalidUUID(idStr)
        }

        let workspaceIdStr = stringParam("workspaceId", from: request.params)
        guard let (workspace, _) = resolveSession(id: id, workspaceId: workspaceIdStr.flatMap(UUID.init)) else {
            return .failure(code: 1, message: "Session not found: \(idStr)")
        }

        // Activate the session and its parent workspace
        workspace.sessionCollection.activateSession(id: id)
        if let collection = resolveCollection() {
            collection.activateWorkspace(id: workspace.id)
        }

        return .success()
    }

    // MARK: - Pane Commands

    private func handlePaneSplit(_ request: IPCRequest) -> IPCResponse {
        let paneIdStr = stringParam("paneId", from: request.params) ?? request.env.paneId
        guard let paneId = UUID(uuidString: paneIdStr) else {
            return invalidUUID(paneIdStr)
        }

        guard let (_, paneViewModel, _) = resolvePane(id: paneId) else {
            return .failure(code: 1, message: "Pane not found: \(paneIdStr)")
        }

        guard paneViewModel.allowsSplits else {
            return .failure(code: 1, message: "Claude pane cannot be split.")
        }

        let directionStr = stringParam("direction", from: request.params) ?? "vertical"
        let direction: SplitDirection
        switch directionStr {
        case "horizontal": direction = .horizontal
        case "vertical":   direction = .vertical
        default:
            return .failure(code: 1, message: "Invalid direction: \(directionStr). Use 'horizontal' or 'vertical'.")
        }

        let background = optionalBool("background", from: request.params)
        guard let newPaneID = paneViewModel.splitPane(direction: direction, targetPaneID: paneId, focusOnCreate: !background) else {
            return .failure(code: 1, message: "Failed to split pane.")
        }

        return .success(["id": .string(newPaneID.uuidString)])
    }

    private func handlePaneList(_ request: IPCRequest) -> IPCResponse {
        let sessionIdStr = stringParam("sessionId", from: request.params)
        guard let (_, session) = resolveSessionFromParamOrEnv(sessionIdStr, env: request.env) else {
            return .failure(code: 1, message: "Session not found: \(sessionIdStr ?? request.env.sessionId)")
        }

        // Optional kind filter; default lists both the Claude pane and the Terminal panel.
        let kindFilter: PaneKind?
        switch stringParam("kind", from: request.params) {
        case nil: kindFilter = nil
        case "claude": kindFilter = .claude
        case "terminal": kindFilter = .terminal
        case let other?:
            return .failure(code: 1, message: "Invalid kind: \(other) (expected claude or terminal)")
        }

        let panes = session.allPanes.filter { kindFilter == nil || $0.kind == kindFilter }
        var items: [IPCValue] = []
        for pvm in panes {
            let focusedID = pvm.splitTree.focusedPaneID
            for (paneID, wd) in pvm.splitTree.allLeafInfo() {
                let stateStr: String
                switch pvm.paneState(for: paneID) {
                case .running: stateStr = "running"
                case .exited: stateStr = "exited"
                case .spawnFailed: stateStr = "spawn-failed"
                }

                let sessionState = statusManager.sessionState(for: paneID)
                let label = statusManager.statuses[paneID]?.label
                let focused = paneID == focusedID && session.effectiveFocusedArea == pvm.kind

                items.append(.object([
                    "id": .string(paneID.uuidString),
                    "kind": .string(pvm.kind.rawValue),
                    "workingDirectory": .string(wd),
                    "state": .string(stateStr),
                    "sessionState": sessionState.map { .string($0.rawValue) } ?? .null,
                    "label": label.map { .string($0) } ?? .null,
                    "focused": .bool(focused),
                ]))
            }
        }

        return .success(["panes": .array(items)])
    }

    private func handlePaneClose(_ request: IPCRequest) -> IPCResponse {
        let paneIdStr = stringParam("paneId", from: request.params) ?? request.env.paneId
        guard let paneId = UUID(uuidString: paneIdStr) else {
            return invalidUUID(paneIdStr)
        }

        guard let (_, paneViewModel, _) = resolvePane(id: paneId) else {
            return .failure(code: 1, message: "Pane not found: \(paneIdStr)")
        }

        paneViewModel.closePane(paneID: paneId)
        return .success()
    }

    private func handlePaneFocus(_ request: IPCRequest) -> IPCResponse {
        guard let target = stringParam("target", from: request.params) else {
            return missingParameter("target")
        }

        let sourcePaneIdStr = stringParam("paneId", from: request.params) ?? request.env.paneId
        guard let sourcePaneId = UUID(uuidString: sourcePaneIdStr) else {
            return invalidUUID(sourcePaneIdStr)
        }

        guard let (_, paneViewModel, _) = resolvePane(id: sourcePaneId) else {
            return .failure(code: 1, message: "Pane not found: \(sourcePaneIdStr)")
        }

        // Check if target is a direction
        switch target {
        case "up":    paneViewModel.focusDirection(.up); return .success()
        case "down":  paneViewModel.focusDirection(.down); return .success()
        case "left":  paneViewModel.focusDirection(.left); return .success()
        case "right": paneViewModel.focusDirection(.right); return .success()
        default: break
        }

        // Otherwise treat as UUID
        guard let targetId = UUID(uuidString: target) else {
            return .failure(code: 1, message: "Invalid target: \(target). Use a UUID or direction (up/down/left/right).")
        }

        guard paneViewModel.splitTree.root.containsLeaf(paneID: targetId) else {
            return .failure(code: 1, message: "Pane not found: \(target)")
        }

        paneViewModel.focusPane(paneID: targetId)
        return .success()
    }

    /// Resolves the target pane (param `paneId`, else env), realizes its terminal
    /// surface (creating it off-screen if needed), and runs `body` with the live
    /// surface. Returns the resolution failure response if the pane is
    /// missing/invalid or has no terminal. `body` receives the resolved pane id
    /// string for error messages.
    private func withLiveSurface(
        for request: IPCRequest,
        _ body: (GhosttyTerminalSurface, String) -> IPCResponse
    ) -> IPCResponse {
        let paneIdStr = stringParam("paneId", from: request.params) ?? request.env.paneId
        guard let paneId = UUID(uuidString: paneIdStr) else {
            return invalidUUID(paneIdStr)
        }
        guard let (_, paneViewModel, _) = resolvePane(id: paneId) else {
            return .failure(code: 1, message: "Pane not found: \(paneIdStr)")
        }
        guard let surface = paneViewModel.realizeSurface(for: paneId) else {
            return .failure(code: 1, message: "Pane has no live terminal: \(paneIdStr)")
        }
        return body(surface, paneIdStr)
    }

    private func handlePaneSend(_ request: IPCRequest) -> IPCResponse {
        guard let text = stringParam("text", from: request.params) else {
            return missingParameter("text")
        }
        return withLiveSurface(for: request) { surface, _ in
            surface.injectText(text, submit: request.params["enter"]?.boolValue ?? true)
            return .success()
        }
    }

    private func handlePaneCapture(_ request: IPCRequest) -> IPCResponse {
        withLiveSurface(for: request) { surface, paneIdStr in
            let scrollback = optionalBool("scrollback", from: request.params)
            guard var captured = surface.readContents(fullScrollback: scrollback) else {
                return .failure(code: 1, message: "Failed to read terminal contents for pane: \(paneIdStr)")
            }

            if request.params["strip"]?.boolValue ?? true {
                var stripper = ANSIStripper()
                captured = stripper.strip(captured)
            }

            // Keep the response under the 1 MB IPC read cap (IPCClient.readResponse /
            // IPCServer.readLine abort at 1_048_576 bytes). Keep the tail — most
            // useful for reading recent logs/progress.
            let maxBytes = 900_000
            var truncated = false
            if captured.utf8.count > maxBytes {
                captured = Self.tail(of: captured, maxBytes: maxBytes)
                truncated = true
            }

            return .success([
                "text": .string(captured),
                "truncated": .bool(truncated),
            ])
        }
    }

    /// Returns at most the last `maxBytes` UTF-8 bytes of `string`, trimming any
    /// partial leading multi-byte sequence so the result is valid UTF-8. Slices the
    /// UTF-8 view in place — no intermediate byte-array allocation.
    private static func tail(of string: String, maxBytes: Int) -> String {
        let utf8 = string.utf8
        guard utf8.count > maxBytes else { return string }
        var start = utf8.index(utf8.endIndex, offsetBy: -maxBytes)
        // Advance past any UTF-8 continuation bytes (0x80–0xBF) to a char boundary.
        while start < utf8.endIndex, (utf8[start] & 0xC0) == 0x80 {
            start = utf8.index(after: start)
        }
        return String(decoding: utf8[start...], as: UTF8.self)
    }

    private func handleSetRestoreCommand(_ request: IPCRequest) -> IPCResponse {
        guard let command = stringParam("command", from: request.params) else {
            return missingParameter("command")
        }

        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return invalidUUID(request.env.paneId, label: "pane UUID")
        }

        guard let (_, paneViewModel, _) = resolvePane(id: paneId) else {
            return .failure(code: 1, message: "Pane not found: \(request.env.paneId)")
        }

        paneViewModel.setRestoreCommand(paneID: paneId, command: command)
        return .success()
    }

    /// Associates a pane with a working directory reported out-of-band (a Claude
    /// `CwdChanged` / `EnterWorktree` hook), so the sidebar shows the branch the
    /// session is actually working in even though the shell stays put. Per-pane:
    /// defaults to the caller's `TIAN_PANE_ID`.
    private func handlePaneSetDirectory(_ request: IPCRequest) -> IPCResponse {
        guard let directory = stringParam("directory", from: request.params),
              !directory.isEmpty else {
            return missingParameter("directory")
        }

        let paneIdStr = stringParam("paneId", from: request.params).flatMap { $0.isEmpty ? nil : $0 }
            ?? request.env.paneId
        guard let paneId = UUID(uuidString: paneIdStr) else {
            return invalidUUID(paneIdStr, label: "pane UUID")
        }

        guard let session = resolvePaneSession(id: paneId) else {
            return .failure(code: 1, message: "Pane not found: \(paneIdStr)")
        }

        session.gitContext.setPaneDirectory(paneID: paneId, directory: directory)
        return .success()
    }

    // MARK: - Status Commands

    private func handleStatusSet(_ request: IPCRequest) -> IPCResponse {
        let label = stringParam("label", from: request.params)
        let stateStr = stringParam("state", from: request.params)

        guard label != nil || stateStr != nil else {
            return .failure(
                code: 1,
                message: "Missing required parameter: at least one of 'label' or 'state' must be provided."
            )
        }

        var sessionState: ClaudeSessionState?
        if let stateStr {
            guard let parsed = ClaudeSessionState(rawValue: stateStr) else {
                let validValues = ClaudeSessionState.allCases.map(\.rawValue).joined(separator: ", ")
                return .failure(
                    code: 1,
                    message: "Invalid state: '\(stateStr)'. Valid values: \(validValues)."
                )
            }
            sessionState = parsed
        }

        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return invalidUUID(request.env.paneId, label: "pane UUID")
        }

        guard resolvePane(id: paneId) != nil else {
            return .failure(code: 1, message: "Pane not found: \(request.env.paneId)")
        }

        if let sessionState {
            statusManager.setSessionState(paneID: paneId, state: sessionState)
        }
        if let label {
            statusManager.setStatus(paneID: paneId, label: label)
        }

        return .success()
    }

    private func handleStatusClear(_ request: IPCRequest) -> IPCResponse {
        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return invalidUUID(request.env.paneId, label: "pane UUID")
        }

        statusManager.clearStatus(paneID: paneId)
        return .success()
    }

    // MARK: - Prompt Commands

    /// Records the latest user prompt typed into a pane's Claude session (mirrored
    /// to the owning PaneViewModel by `PaneStatusManager`). Per-pane: targets the
    /// caller's `TIAN_PANE_ID`. Mirrors `handleStatusSet`'s pane-resolution boilerplate.
    private func handlePromptSet(_ request: IPCRequest) -> IPCResponse {
        guard let text = stringParam("text", from: request.params) else {
            return missingParameter("text")
        }

        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return invalidUUID(request.env.paneId, label: "pane UUID")
        }

        guard resolvePane(id: paneId) != nil else {
            return .failure(code: 1, message: "Pane not found: \(request.env.paneId)")
        }

        statusManager.setLastPrompt(paneID: paneId, text: text)
        return .success()
    }

    // MARK: - Background Activity Commands

    /// Replaces the caller pane's whole background-activity set from a Claude
    /// `background_tasks` JSON snapshot, decoded leniently server-side (malformed
    /// input yields an empty set, clearing the pane). Per-pane: targets
    /// `TIAN_PANE_ID`. Mirrors `handleStatusSet`'s pane-resolution boilerplate.
    private func handleActivitySync(_ request: IPCRequest) -> IPCResponse {
        guard let json = stringParam("json", from: request.params) else {
            return missingParameter("json")
        }

        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return invalidUUID(request.env.paneId, label: "pane UUID")
        }

        guard resolvePane(id: paneId) != nil else {
            return .failure(code: 1, message: "Pane not found: \(request.env.paneId)")
        }

        let activities = BackgroundActivity.fromClaudeSnapshot(json: json)
        statusManager.syncActivities(paneID: paneId, activities)
        return .success()
    }

    // MARK: - Notify Command

    private func handleNotify(_ request: IPCRequest) async -> IPCResponse {
        guard let message = stringParam("message", from: request.params) else {
            return missingParameter("message")
        }

        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return invalidUUID(request.env.paneId, label: "pane UUID")
        }

        let title = stringParam("title", from: request.params)
        let subtitle = stringParam("subtitle", from: request.params)

        do {
            try await notificationManager.sendNotification(
                message: message,
                title: title,
                subtitle: subtitle,
                paneID: paneId
            )
            NotificationCenter.default.post(
                name: GhosttyApp.surfaceBellNotification,
                object: nil,
                userInfo: ["paneId": paneId]
            )
            return .success()
        } catch NotificationError.permissionDenied {
            return .failure(
                code: 4,
                message: "Notification permission denied. Enable notifications for tian in System Settings > Notifications."
            )
        } catch {
            return .failure(code: 1, message: "Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Worktree Commands

    private func handleWorktreeCreate(_ request: IPCRequest) async -> IPCResponse {
        guard let branchName = stringParam("branchName", from: request.params) else {
            return missingParameter("branchName")
        }

        let existing = optionalBool("existing", from: request.params)
        let base = stringParam("base", from: request.params)
        let background = optionalBool("background", from: request.params)
        let path = stringParam("path", from: request.params)
        // Place the worktree in the explicitly-named workspace, else the calling
        // pane's env workspace. Require one of those OR an explicit --path: with no
        // workspace context and no repo path, a nil workspaceID would let the
        // orchestrator silently land the worktree in the focused (key) window — the
        // wrong-workspace placement commit 622af51 set out to fix. An explicit
        // --path is sufficient on its own (the user named the repo to use).
        let resolvedWorkspace = resolveWorkspaceFromParamOrEnv(
            stringParam("workspaceId", from: request.params),
            env: request.env
        )?.1
        guard resolvedWorkspace != nil || path != nil else {
            return .failure(
                code: 1,
                message: "No workspace context: run from a tian pane, or pass --workspace <id> or --path <repo>."
            )
        }

        // The calling pane's Session is the creator (orchestrator). Used to nest
        // the new worktree Session under it in the sidebar. Absent/malformed env
        // (e.g. invoked outside a tian pane) leaves it nil → top-level Session.
        let creatorSessionID = UUID(uuidString: request.env.sessionId)

        do {
            let result = try await worktreeOrchestrator.createWorktreeSession(
                branchName: branchName,
                existingBranch: existing,
                base: base,
                repoPath: path,
                workspaceID: resolvedWorkspace?.id,
                background: background,
                creatorSessionID: creatorSessionID
            )
            var out: [String: IPCValue] = [
                "session_id": .string(result.sessionID.uuidString),
                "existed": .bool(result.existed),
            ]
            if let claudePaneID = result.claudePaneID { out["claude_pane_id"] = .string(claudePaneID.uuidString) }
            if let terminalPaneID = result.terminalPaneID { out["terminal_pane_id"] = .string(terminalPaneID.uuidString) }
            return .success(out)
        } catch let error as WorktreeError {
            return .failure(code: 1, message: error.description)
        } catch {
            return .failure(code: 1, message: error.localizedDescription)
        }
    }

    private func handleWorktreeRemove(_ request: IPCRequest) async -> IPCResponse {
        guard let sessionIdStr = stringParam("sessionId", from: request.params) else {
            return missingParameter("sessionId")
        }
        guard let sessionID = UUID(uuidString: sessionIdStr) else {
            return invalidUUID(sessionIdStr)
        }

        let force = optionalBool("force", from: request.params)
        let deleteBranch = optionalBool("deleteBranch", from: request.params)

        do {
            let result = try await worktreeOrchestrator.removeWorktreeSession(
                sessionID: sessionID,
                force: force,
                deleteBranch: deleteBranch
            )
            var out: [String: IPCValue] = [
                "branch_deleted": .bool(result.branchDeleted),
            ]
            if let branch = result.branchName { out["branch"] = .string(branch) }
            if let reason = result.branchKeptReason { out["branch_kept_reason"] = .string(reason) }
            return .success(out)
        } catch WorktreeError.uncommittedChanges(let path) {
            return .failure(code: 3, message: "Worktree at '\(path)' has uncommitted changes. Use --force to remove anyway.")
        } catch WorktreeError.closeInFlight {
            return .failure(code: 5, message: WorktreeError.closeInFlight.description)
        } catch let error as WorktreeError {
            return .failure(code: 1, message: error.description)
        } catch {
            return .failure(code: 1, message: error.localizedDescription)
        }
    }

    // MARK: - Git Commands

    /// Evicts the PR cache for every repo in the calling pane's Session and
    /// refreshes git status. Used by external tooling (e.g. a Claude
    /// PostToolUse hook after `gh pr create`) to update the sidebar badge
    /// without waiting for the 60s PR-cache TTL — `gh pr create` against an
    /// already-pushed branch makes no local file change, so the
    /// FSEvents-based eviction path doesn't fire.
    private func handleGitRefresh(_ request: IPCRequest) -> IPCResponse {
        guard let sessionID = UUID(uuidString: request.env.sessionId),
              let (_, session) = resolveSession(id: sessionID, workspaceId: nil) else {
            return .failure(code: 1, message: "Session not found from environment.")
        }
        session.gitContext.refreshPR()
        return .success()
    }

    // MARK: - Hierarchy Resolution

    private func resolveCollection() -> WorkspaceCollection? {
        windowCoordinator.allWorkspaceCollections.first
    }

    private func resolveWorkspace(id: UUID) -> (WorkspaceCollection, Workspace)? {
        for collection in windowCoordinator.allWorkspaceCollections {
            if let workspace = collection.workspaces.first(where: { $0.id == id }) {
                return (collection, workspace)
            }
        }
        return nil
    }

    private func resolveSession(id: UUID, workspaceId: UUID?) -> (Workspace, Session)? {
        for collection in windowCoordinator.allWorkspaceCollections {
            let workspaces = if let workspaceId {
                collection.workspaces.filter { $0.id == workspaceId }
            } else {
                collection.workspaces
            }
            for workspace in workspaces {
                if let session = workspace.sessionCollection.sessions.first(where: { $0.id == id }) {
                    return (workspace, session)
                }
            }
        }
        return nil
    }

    /// Walks workspaces → sessions → each session's panes, returning the owning
    /// session and pane view model for the leaf `id`.
    private func resolvePane(id: UUID) -> (Session, PaneViewModel, UUID)? {
        for collection in windowCoordinator.allWorkspaceCollections {
            for workspace in collection.workspaces {
                for session in workspace.sessionCollection.sessions {
                    for pvm in session.allPanes {
                        if pvm.splitTree.root.containsLeaf(paneID: id) {
                            return (session, pvm, id)
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Finds the Session that owns a given pane. Used by commands that must reach
    /// the pane's `SessionGitContext` (resolved from the pane, not `env.sessionId`,
    /// so an explicit `--pane` in another session still targets the right context).
    private func resolvePaneSession(id: UUID) -> Session? {
        for collection in windowCoordinator.allWorkspaceCollections {
            for workspace in collection.workspaces {
                for session in workspace.sessionCollection.sessions {
                    if session.allPanes.contains(where: { $0.splitTree.root.containsLeaf(paneID: id) }) {
                        return session
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Env-based Resolution Helpers

    /// Resolves workspace from an explicit param UUID string, or falls back to env.
    /// An empty param string is treated as absent so it can't shadow a valid env id.
    private func resolveWorkspaceFromParamOrEnv(
        _ paramIdStr: String?,
        env: IPCEnv
    ) -> (WorkspaceCollection, Workspace)? {
        let idStr = paramIdStr.flatMap { $0.isEmpty ? nil : $0 } ?? env.workspaceId
        guard let id = UUID(uuidString: idStr) else { return nil }
        return resolveWorkspace(id: id)
    }

    /// Resolves session from an explicit param UUID string, or falls back to env.
    /// An empty param string is treated as absent so it can't shadow a valid env id.
    private func resolveSessionFromParamOrEnv(
        _ paramIdStr: String?,
        env: IPCEnv
    ) -> (Workspace, Session)? {
        let idStr = paramIdStr.flatMap { $0.isEmpty ? nil : $0 } ?? env.sessionId
        guard let id = UUID(uuidString: idStr) else { return nil }
        return resolveSession(id: id, workspaceId: nil)
    }

    // MARK: - Helpers

    private func stringParam(_ key: String, from params: [String: IPCValue]) -> String? {
        params[key]?.stringValue
    }

    /// Standard failure for an absent required parameter.
    private func missingParameter(_ key: String) -> IPCResponse {
        .failure(code: 1, message: "Missing required parameter: \(key)")
    }

    /// Standard failure for an unparseable UUID string. `label` names the value
    /// in the message so each call site keeps its exact wording ("UUID" vs
    /// "pane UUID") — the two forms are asserted separately in the IPC tests.
    private func invalidUUID(_ string: String, label: String = "UUID") -> IPCResponse {
        .failure(code: 1, message: "Invalid \(label): \(string)")
    }

    private func optionalBool(_ key: String, from params: [String: IPCValue]) -> Bool {
        params[key]?.boolValue ?? false
    }

    private func checkProcessSafety(force: Bool, panes: [PaneViewModel]) -> IPCResponse? {
        guard !force else { return nil }
        let count = ProcessDetector.runningProcessCount(in: panes)
        guard count > 0 else { return nil }
        return .failure(code: 3, message: "\(count) running process\(count == 1 ? "" : "es") detected. Use --force to close anyway.")
    }
}
