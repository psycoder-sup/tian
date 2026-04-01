import Foundation
import Observation

/// Per-window workspace ownership. Each window owns one WorkspaceCollection
/// containing multiple workspaces. Follows the SpaceCollection pattern.
@MainActor @Observable
final class WorkspaceCollection {
    private(set) var workspaces: [Workspace]
    var activeWorkspaceID: UUID

    /// Set when the last workspace is removed and `onEmpty` is nil.
    var shouldQuit: Bool = false

    /// Called when the last workspace is removed. When set, `shouldQuit` is not used.
    var onEmpty: (() -> Void)?

    private var workspaceCounter: Int = 1

    init(workingDirectory: String? = nil) {
        let wd = workingDirectory
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "~"
        let workspace = Workspace(
            name: "default",
            defaultWorkingDirectory: URL(fileURLWithPath: wd)
        )
        self.workspaces = [workspace]
        self.activeWorkspaceID = workspace.id
        wireWorkspaceClose(workspace)
    }

    // MARK: - Computed

    var activeWorkspace: Workspace? {
        workspaces.first(where: { $0.id == activeWorkspaceID })
    }

    var activeSpaceCollection: SpaceCollection? {
        activeWorkspace?.spaceCollection
    }

    // MARK: - Workspace Operations

    /// Creates a workspace with an auto-generated name ("Workspace 2", "Workspace 3", ...).
    @discardableResult
    func createWorkspace(workingDirectory: String? = nil) -> Workspace? {
        createWorkspace(name: "Workspace \(workspaceCounter + 1)", workingDirectory: workingDirectory)
    }

    @discardableResult
    func createWorkspace(name: String, workingDirectory: String? = nil) -> Workspace? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        workspaceCounter += 1

        let wdURL: URL? = if let wd = workingDirectory {
            URL(fileURLWithPath: wd)
        } else {
            nil
        }

        let workspace = Workspace(
            name: trimmed,
            defaultWorkingDirectory: wdURL
        )
        wireWorkspaceClose(workspace)
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        return workspace
    }

    func removeWorkspace(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = workspaces[index]

        workspace.cleanup()
        workspaces.remove(at: index)

        if workspaces.isEmpty {
            if let onEmpty {
                onEmpty()
            } else {
                shouldQuit = true
            }
            return
        }

        if activeWorkspaceID == id {
            let newIndex = index > 0 ? index - 1 : 0
            activeWorkspaceID = workspaces[newIndex].id
        }
    }

    func activateWorkspace(id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        activeWorkspaceID = id
    }

    @discardableResult
    func renameWorkspace(id: UUID, newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return false }
        workspace.name = trimmed
        return true
    }

    // MARK: - Navigation

    func nextWorkspace() {
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        let nextIndex = (currentIndex + 1) % workspaces.count
        activeWorkspaceID = workspaces[nextIndex].id
    }

    func previousWorkspace() {
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) else { return }
        let prevIndex = (currentIndex - 1 + workspaces.count) % workspaces.count
        activeWorkspaceID = workspaces[prevIndex].id
    }

    // MARK: - Reorder

    func reorderWorkspace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < workspaces.count,
              destinationIndex >= 0, destinationIndex < workspaces.count else { return }
        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: destinationIndex)
    }

    // MARK: - Private

    private func wireWorkspaceClose(_ workspace: Workspace) {
        workspace.onEmpty = { [weak self, workspaceID = workspace.id] in
            self?.removeWorkspace(id: workspaceID)
        }
    }
}
