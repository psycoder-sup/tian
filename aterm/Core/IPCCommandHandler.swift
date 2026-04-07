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
        self.worktreeOrchestrator = WorktreeOrchestrator(windowCoordinator: windowCoordinator)
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

        // Space
        case "space.create": return handleSpaceCreate(request)
        case "space.list":   return handleSpaceList(request)
        case "space.close":  return handleSpaceClose(request)
        case "space.focus":  return handleSpaceFocus(request)

        // Tab
        case "tab.create": return handleTabCreate(request)
        case "tab.list":   return handleTabList(request)
        case "tab.close":  return handleTabClose(request)
        case "tab.focus":  return handleTabFocus(request)

        // Pane
        case "pane.split": return handlePaneSplit(request)
        case "pane.list":  return handlePaneList(request)
        case "pane.close": return handlePaneClose(request)
        case "pane.focus": return handlePaneFocus(request)

        // Status (Phase 4)
        case "status.set":   return handleStatusSet(request)
        case "status.clear": return handleStatusClear(request)

        // Notify (Phase 5)
        case "notify": return await handleNotify(request)

        // Worktree
        case "worktree.create": return await handleWorktreeCreate(request)
        case "worktree.remove": return await handleWorktreeRemove(request)

        default:
            return .failure(code: 1, message: "Unknown command: \(request.command)")
        }
    }

    // MARK: - Workspace Commands

    private func handleWorkspaceCreate(_ request: IPCRequest) -> IPCResponse {
        guard let name = stringParam("name", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: name")
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
                "spaceCount": .int(workspace.spaceCollection.spaces.count),
                "active": .bool(workspace.id == collection.activeWorkspaceID),
            ])
        }

        return .success(["workspaces": .array(items)])
    }

    private func handleWorkspaceClose(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(idStr)")
        }

        guard let (collection, workspace) = resolveWorkspace(id: id) else {
            return .failure(code: 1, message: "Workspace not found: \(idStr)")
        }

        let force = optionalBool("force", from: request.params)
        let tabs = workspace.spaceCollection.spaces.flatMap(\.tabs)
        if let error = checkProcessSafety(force: force, tabs: tabs) { return error }

        collection.removeWorkspace(id: id)
        return .success()
    }

    private func handleWorkspaceFocus(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(idStr)")
        }

        guard let (collection, _) = resolveWorkspace(id: id) else {
            return .failure(code: 1, message: "Workspace not found: \(idStr)")
        }

        collection.activateWorkspace(id: id)
        return .success()
    }

    // MARK: - Space Commands

    private func handleSpaceCreate(_ request: IPCRequest) -> IPCResponse {
        let workspaceIdStr = stringParam("workspaceId", from: request.params)

        guard let (_, workspace) = resolveWorkspaceFromParamOrEnv(workspaceIdStr, env: request.env) else {
            return .failure(code: 1, message: "Workspace not found: \(workspaceIdStr ?? request.env.workspaceId)")
        }

        let space = workspace.spaceCollection.createSpace()
        if let name = stringParam("name", from: request.params) {
            space.name = name
        }

        return .success(["id": .string(space.id.uuidString)])
    }

    private func handleSpaceList(_ request: IPCRequest) -> IPCResponse {
        let workspaceIdStr = stringParam("workspaceId", from: request.params)

        guard let (_, workspace) = resolveWorkspaceFromParamOrEnv(workspaceIdStr, env: request.env) else {
            return .failure(code: 1, message: "Workspace not found: \(workspaceIdStr ?? request.env.workspaceId)")
        }

        let items: [IPCValue] = workspace.spaceCollection.spaces.map { space in
            .object([
                "id": .string(space.id.uuidString),
                "name": .string(space.name),
                "tabCount": .int(space.tabs.count),
                "active": .bool(space.id == workspace.spaceCollection.activeSpaceID),
            ])
        }

        return .success(["spaces": .array(items)])
    }

    private func handleSpaceClose(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(idStr)")
        }

        let workspaceIdStr = stringParam("workspaceId", from: request.params)
        guard let (workspace, space) = resolveSpace(id: id, workspaceId: workspaceIdStr.flatMap(UUID.init)) else {
            return .failure(code: 1, message: "Space not found: \(idStr)")
        }

        let force = optionalBool("force", from: request.params)
        if let error = checkProcessSafety(force: force, tabs: space.tabs) { return error }

        workspace.spaceCollection.removeSpace(id: id)
        return .success()
    }

    private func handleSpaceFocus(_ request: IPCRequest) -> IPCResponse {
        guard let idStr = stringParam("id", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: id")
        }
        guard let id = UUID(uuidString: idStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(idStr)")
        }

        let workspaceIdStr = stringParam("workspaceId", from: request.params)
        guard let (workspace, _) = resolveSpace(id: id, workspaceId: workspaceIdStr.flatMap(UUID.init)) else {
            return .failure(code: 1, message: "Space not found: \(idStr)")
        }

        // Activate the space and its parent workspace
        workspace.spaceCollection.activateSpace(id: id)
        if let collection = resolveCollection() {
            collection.activateWorkspace(id: workspace.id)
        }

        return .success()
    }

    // MARK: - Tab Commands

    private func handleTabCreate(_ request: IPCRequest) -> IPCResponse {
        let spaceIdStr = stringParam("spaceId", from: request.params)

        guard let (_, space) = resolveSpaceFromParamOrEnv(spaceIdStr, env: request.env) else {
            return .failure(code: 1, message: "Space not found: \(spaceIdStr ?? request.env.spaceId)")
        }

        let directory = stringParam("directory", from: request.params) ?? "~"
        let tab = space.createTab(workingDirectory: directory)
        return .success(["id": .string(tab.id.uuidString)])
    }

    private func handleTabList(_ request: IPCRequest) -> IPCResponse {
        let spaceIdStr = stringParam("spaceId", from: request.params)

        guard let (_, space) = resolveSpaceFromParamOrEnv(spaceIdStr, env: request.env) else {
            return .failure(code: 1, message: "Space not found: \(spaceIdStr ?? request.env.spaceId)")
        }

        let items: [IPCValue] = space.tabs.map { tab in
            .object([
                "id": .string(tab.id.uuidString),
                "name": tab.customName.map { .string($0) } ?? .null,
                "title": .string(tab.title),
                "paneCount": .int(tab.paneViewModel.splitTree.leafCount),
                "active": .bool(tab.id == space.activeTabID),
            ])
        }

        return .success(["tabs": .array(items)])
    }

    private func handleTabClose(_ request: IPCRequest) -> IPCResponse {
        let idStr = stringParam("id", from: request.params) ?? request.env.tabId
        guard let id = UUID(uuidString: idStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(idStr)")
        }

        guard let (space, tab) = resolveTab(id: id, spaceId: nil) else {
            return .failure(code: 1, message: "Tab not found: \(idStr)")
        }

        let force = optionalBool("force", from: request.params)
        if let error = checkProcessSafety(force: force, tabs: [tab]) { return error }

        space.removeTab(id: id)
        return .success()
    }

    private func handleTabFocus(_ request: IPCRequest) -> IPCResponse {
        guard let target = stringParam("target", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: target")
        }

        // Try as UUID first
        if let uuid = UUID(uuidString: target) {
            guard let (space, _) = resolveTab(id: uuid, spaceId: nil) else {
                return .failure(code: 1, message: "Tab not found: \(target)")
            }
            space.activateTab(id: uuid)
            return .success()
        }

        // Try as 1-based index
        if let index = Int(target) {
            // Resolve the space from env
            guard let spaceId = UUID(uuidString: request.env.spaceId) else {
                return .failure(code: 1, message: "Invalid space ID in environment.")
            }
            guard let (_, space) = resolveSpace(id: spaceId, workspaceId: nil) else {
                return .failure(code: 1, message: "Space not found from environment.")
            }
            space.goToTab(index: index)
            return .success()
        }

        return .failure(code: 1, message: "Invalid target: \(target). Provide a UUID or 1-based index.")
    }

    // MARK: - Pane Commands

    private func handlePaneSplit(_ request: IPCRequest) -> IPCResponse {
        let paneIdStr = stringParam("paneId", from: request.params) ?? request.env.paneId
        guard let paneId = UUID(uuidString: paneIdStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(paneIdStr)")
        }

        guard let (_, paneViewModel, _) = resolvePane(id: paneId, tabId: nil) else {
            return .failure(code: 1, message: "Pane not found: \(paneIdStr)")
        }

        let directionStr = stringParam("direction", from: request.params) ?? "vertical"
        let direction: SplitDirection
        switch directionStr {
        case "horizontal": direction = .horizontal
        case "vertical":   direction = .vertical
        default:
            return .failure(code: 1, message: "Invalid direction: \(directionStr). Use 'horizontal' or 'vertical'.")
        }

        guard let newPaneID = paneViewModel.splitPane(direction: direction, targetPaneID: paneId) else {
            return .failure(code: 1, message: "Failed to split pane.")
        }

        return .success(["id": .string(newPaneID.uuidString)])
    }

    private func handlePaneList(_ request: IPCRequest) -> IPCResponse {
        let tabIdStr = stringParam("tabId", from: request.params) ?? request.env.tabId
        guard let tabId = UUID(uuidString: tabIdStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(tabIdStr)")
        }

        guard let (_, tab) = resolveTab(id: tabId, spaceId: nil) else {
            return .failure(code: 1, message: "Tab not found: \(tabIdStr)")
        }

        let pvm = tab.paneViewModel
        let leaves = pvm.splitTree.allLeafInfo()
        let focusedID = pvm.splitTree.focusedPaneID

        let items: [IPCValue] = leaves.map { (paneID, wd) in
            let stateStr: String
            switch pvm.paneState(for: paneID) {
            case .running: stateStr = "running"
            case .exited: stateStr = "exited"
            case .spawnFailed: stateStr = "spawn-failed"
            }

            return .object([
                "id": .string(paneID.uuidString),
                "workingDirectory": .string(wd),
                "state": .string(stateStr),
                "focused": .bool(paneID == focusedID),
            ])
        }

        return .success(["panes": .array(items)])
    }

    private func handlePaneClose(_ request: IPCRequest) -> IPCResponse {
        let paneIdStr = stringParam("paneId", from: request.params) ?? request.env.paneId
        guard let paneId = UUID(uuidString: paneIdStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(paneIdStr)")
        }

        guard let (_, paneViewModel, _) = resolvePane(id: paneId, tabId: nil) else {
            return .failure(code: 1, message: "Pane not found: \(paneIdStr)")
        }

        paneViewModel.closePane(paneID: paneId)
        return .success()
    }

    private func handlePaneFocus(_ request: IPCRequest) -> IPCResponse {
        guard let target = stringParam("target", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: target")
        }

        let sourcePaneIdStr = stringParam("paneId", from: request.params) ?? request.env.paneId
        guard let sourcePaneId = UUID(uuidString: sourcePaneIdStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(sourcePaneIdStr)")
        }

        guard let (_, paneViewModel, _) = resolvePane(id: sourcePaneId, tabId: nil) else {
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

    // MARK: - Status Commands

    private func handleStatusSet(_ request: IPCRequest) -> IPCResponse {
        guard let label = stringParam("label", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: label")
        }

        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return .failure(code: 1, message: "Invalid pane UUID: \(request.env.paneId)")
        }

        // Validate the pane still exists in the hierarchy
        guard resolvePane(id: paneId, tabId: nil) != nil else {
            return .failure(code: 1, message: "Pane not found: \(request.env.paneId)")
        }

        statusManager.setStatus(paneID: paneId, label: label)
        return .success()
    }

    private func handleStatusClear(_ request: IPCRequest) -> IPCResponse {
        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return .failure(code: 1, message: "Invalid pane UUID: \(request.env.paneId)")
        }

        statusManager.clearStatus(paneID: paneId)
        return .success()
    }

    // MARK: - Notify Command

    private func handleNotify(_ request: IPCRequest) async -> IPCResponse {
        guard let message = stringParam("message", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: message")
        }

        guard let paneId = UUID(uuidString: request.env.paneId) else {
            return .failure(code: 1, message: "Invalid pane UUID: \(request.env.paneId)")
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
                message: "Notification permission denied. Enable notifications for aterm in System Settings > Notifications."
            )
        } catch {
            return .failure(code: 1, message: "Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Worktree Commands

    private func handleWorktreeCreate(_ request: IPCRequest) async -> IPCResponse {
        guard let branchName = stringParam("branchName", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: branchName")
        }

        let existing = optionalBool("existing", from: request.params)
        let path = stringParam("path", from: request.params)
        let workspaceID = stringParam("workspaceId", from: request.params).flatMap(UUID.init)

        do {
            let result = try await worktreeOrchestrator.createWorktreeSpace(
                branchName: branchName,
                existingBranch: existing,
                repoPath: path,
                workspaceID: workspaceID
            )
            return .success([
                "space_id": .string(result.spaceID.uuidString),
                "existed": .bool(result.existed),
            ])
        } catch let error as WorktreeError {
            return .failure(code: 1, message: error.description)
        } catch {
            return .failure(code: 1, message: error.localizedDescription)
        }
    }

    private func handleWorktreeRemove(_ request: IPCRequest) async -> IPCResponse {
        guard let spaceIdStr = stringParam("spaceId", from: request.params) else {
            return .failure(code: 1, message: "Missing required parameter: spaceId")
        }
        guard let spaceID = UUID(uuidString: spaceIdStr) else {
            return .failure(code: 1, message: "Invalid UUID: \(spaceIdStr)")
        }

        let force = optionalBool("force", from: request.params)

        do {
            try await worktreeOrchestrator.removeWorktreeSpace(
                spaceID: spaceID,
                force: force
            )
            return .success()
        } catch WorktreeError.uncommittedChanges(let path) {
            return .failure(code: 3, message: "Worktree at '\(path)' has uncommitted changes. Use --force to remove anyway.")
        } catch let error as WorktreeError {
            return .failure(code: 1, message: error.description)
        } catch {
            return .failure(code: 1, message: error.localizedDescription)
        }
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

    private func resolveSpace(id: UUID, workspaceId: UUID?) -> (Workspace, SpaceModel)? {
        for collection in windowCoordinator.allWorkspaceCollections {
            let workspaces = if let workspaceId {
                collection.workspaces.filter { $0.id == workspaceId }
            } else {
                collection.workspaces
            }
            for workspace in workspaces {
                if let space = workspace.spaceCollection.spaces.first(where: { $0.id == id }) {
                    return (workspace, space)
                }
            }
        }
        return nil
    }

    private func resolveTab(id: UUID, spaceId: UUID?) -> (SpaceModel, TabModel)? {
        for collection in windowCoordinator.allWorkspaceCollections {
            for workspace in collection.workspaces {
                let spaces = if let spaceId {
                    workspace.spaceCollection.spaces.filter { $0.id == spaceId }
                } else {
                    workspace.spaceCollection.spaces
                }
                for space in spaces {
                    if let tab = space.tabs.first(where: { $0.id == id }) {
                        return (space, tab)
                    }
                }
            }
        }
        return nil
    }

    private func resolvePane(id: UUID, tabId: UUID?) -> (TabModel, PaneViewModel, UUID)? {
        for collection in windowCoordinator.allWorkspaceCollections {
            for workspace in collection.workspaces {
                for space in workspace.spaceCollection.spaces {
                    let tabs = if let tabId {
                        space.tabs.filter { $0.id == tabId }
                    } else {
                        space.tabs
                    }
                    for tab in tabs {
                        if tab.paneViewModel.splitTree.root.containsLeaf(paneID: id) {
                            return (tab, tab.paneViewModel, id)
                        }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Env-based Resolution Helpers

    /// Resolves workspace from an explicit param UUID string, or falls back to env.
    private func resolveWorkspaceFromParamOrEnv(
        _ paramIdStr: String?,
        env: IPCEnv
    ) -> (WorkspaceCollection, Workspace)? {
        let idStr = paramIdStr ?? env.workspaceId
        guard let id = UUID(uuidString: idStr) else { return nil }
        return resolveWorkspace(id: id)
    }

    /// Resolves space from an explicit param UUID string, or falls back to env.
    private func resolveSpaceFromParamOrEnv(
        _ paramIdStr: String?,
        env: IPCEnv
    ) -> (Workspace, SpaceModel)? {
        let idStr = paramIdStr ?? env.spaceId
        guard let id = UUID(uuidString: idStr) else { return nil }
        return resolveSpace(id: id, workspaceId: nil)
    }

    // MARK: - Helpers

    private func stringParam(_ key: String, from params: [String: IPCValue]) -> String? {
        params[key]?.stringValue
    }

    private func optionalBool(_ key: String, from params: [String: IPCValue]) -> Bool {
        params[key]?.boolValue ?? false
    }

    private func checkProcessSafety(force: Bool, tabs: [TabModel]) -> IPCResponse? {
        guard !force else { return nil }
        let count = ProcessDetector.runningProcessCount(in: tabs)
        guard count > 0 else { return nil }
        return .failure(code: 3, message: "\(count) running process\(count == 1 ? "" : "es") detected. Use --force to close anyway.")
    }
}
