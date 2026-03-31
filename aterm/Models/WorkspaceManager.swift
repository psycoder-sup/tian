import Foundation
import Observation

/// Central coordinator for workspace lifecycle. Manages the ordered
/// collection of workspaces, analogous to SpaceCollection for spaces.
@MainActor @Observable
final class WorkspaceManager {
    // MARK: - State

    private(set) var workspaces: [Workspace]
    var activeWorkspaceID: UUID?

    /// Set to `true` when the last workspace is deleted; the app should quit.
    var shouldQuit: Bool = false

    // MARK: - Init

    init() {
        self.workspaces = []
        self.activeWorkspaceID = nil
    }

    // MARK: - Computed

    var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceID else { return nil }
        return workspaces.first(where: { $0.id == id })
    }

    // MARK: - Workspace Operations

    /// Creates a new workspace with a single default space, tab, and pane.
    /// Returns nil if the name is empty after trimming whitespace.
    @discardableResult
    func createWorkspace(
        name: String,
        workingDirectory: URL? = nil
    ) -> Workspace? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let workspace = Workspace(
            name: trimmed,
            defaultWorkingDirectory: workingDirectory
        )
        wireWorkspaceClose(workspace)
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        return workspace
    }

    /// Renames a workspace. Returns false if the name is invalid or workspace not found.
    @discardableResult
    func renameWorkspace(id: UUID, newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return false }
        workspace.name = trimmed
        return true
    }

    /// Deletes a workspace and cleans up all its PTY resources.
    func deleteWorkspace(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = workspaces[index]

        workspace.cleanup()

        workspaces.remove(at: index)

        if workspaces.isEmpty {
            shouldQuit = true
            return
        }

        if activeWorkspaceID == id {
            let newIndex = index > 0 ? index - 1 : 0
            activeWorkspaceID = workspaces[newIndex].id
        }
    }

    /// Switches focus to the given workspace.
    func switchToWorkspace(id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        activeWorkspaceID = id
    }

    /// Reorders a workspace from one position to another.
    func reorderWorkspace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < workspaces.count,
              destinationIndex >= 0, destinationIndex < workspaces.count else { return }
        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: destinationIndex)
    }

    /// Sets or clears the default working directory for a workspace.
    func setDefaultWorkingDirectory(workspaceID: UUID, directory: URL?) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        workspace.defaultWorkingDirectory = directory
    }

    /// Sets or clears the default working directory for a space within any workspace.
    func setDefaultWorkingDirectory(spaceID: UUID, directory: URL?) {
        for workspace in workspaces {
            if let space = workspace.spaceCollection.spaces.first(where: { $0.id == spaceID }) {
                space.defaultWorkingDirectory = directory
                return
            }
        }
    }

    // MARK: - Private

    private func wireWorkspaceClose(_ workspace: Workspace) {
        workspace.onEmpty = { [weak self, workspaceID = workspace.id] in
            self?.deleteWorkspace(id: workspaceID)
        }
    }
}
