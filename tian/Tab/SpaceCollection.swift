import Foundation
import Observation

/// Owns the ordered list of spaces. Singleton in M3; per-workspace in M4.
@MainActor @Observable
final class SpaceCollection {
    private(set) var spaces: [SpaceModel]
    var activeSpaceID: UUID

    /// Set to `true` when the last space is closed; the app should quit.
    var shouldQuit: Bool = false

    /// Called when the last space is closed. When set, `shouldQuit` is not set;
    /// the callback owner is responsible for propagating the quit signal.
    var onEmpty: (() -> Void)?

    /// The owning workspace's default directory. Propagated to new spaces.
    var workspaceDefaultDirectory: URL?

    /// The owning workspace's ID. Propagated to all spaces.
    var workspaceID: UUID?

    private var spaceCounter: Int = 1

    init(workingDirectory: String = "~") {
        let initialTab = TabModel(workingDirectory: workingDirectory)
        let initialSpace = SpaceModel(name: "default", initialTab: initialTab)
        self.spaces = [initialSpace]
        self.activeSpaceID = initialSpace.id

        wireSpaceClose(initialSpace)
    }

    /// Restore a space collection with pre-built spaces.
    init(spaces: [SpaceModel], activeSpaceID: UUID, workspaceDefaultDirectory: URL?) {
        self.spaces = spaces
        self.activeSpaceID = spaces.contains(where: { $0.id == activeSpaceID })
            ? activeSpaceID
            : spaces[0].id
        self.workspaceDefaultDirectory = workspaceDefaultDirectory

        for space in spaces {
            space.workspaceDefaultDirectory = workspaceDefaultDirectory
            wireSpaceClose(space)
        }
    }

    // MARK: - Computed

    var activeSpace: SpaceModel? {
        spaces.first(where: { $0.id == activeSpaceID })
    }

    // MARK: - Space Operations

    @discardableResult
    func createSpace(workingDirectory: String = "~") -> SpaceModel {
        spaceCounter += 1
        let tab = TabModel(workingDirectory: workingDirectory)
        let space = SpaceModel(name: "Space \(spaceCounter)", initialTab: tab)
        space.workspaceDefaultDirectory = workspaceDefaultDirectory
        if let workspaceID {
            space.propagateWorkspaceID(workspaceID)
        }
        wireSpaceClose(space)
        spaces.append(space)
        activeSpaceID = space.id
        return space
    }

    func removeSpace(id: UUID) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let space = spaces[index]
        // Cleanup all tabs in the space
        for tab in space.tabs {
            tab.cleanup()
        }
        space.gitContext.teardown()
        spaces.remove(at: index)

        if spaces.isEmpty {
            if let onEmpty {
                onEmpty()
            } else {
                shouldQuit = true
            }
            return
        }

        // If we removed the active space, activate nearest (prefer left, else right)
        if activeSpaceID == id {
            let newIndex = index > 0 ? index - 1 : 0
            activeSpaceID = spaces[newIndex].id
        }
    }

    func activateSpace(id: UUID) {
        guard spaces.contains(where: { $0.id == id }) else { return }
        activeSpaceID = id
    }

    // MARK: - Navigation

    func nextSpace() {
        guard let currentIndex = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let nextIndex = (currentIndex + 1) % spaces.count
        activeSpaceID = spaces[nextIndex].id
    }

    func previousSpace() {
        guard let currentIndex = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let prevIndex = (currentIndex - 1 + spaces.count) % spaces.count
        activeSpaceID = spaces[prevIndex].id
    }

    // MARK: - Reorder

    func reorderSpace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < spaces.count,
              destinationIndex >= 0, destinationIndex < spaces.count else { return }
        let space = spaces.remove(at: sourceIndex)
        spaces.insert(space, at: destinationIndex)
    }

    // MARK: - Working Directory

    /// Resolves the working directory from the active pane, falling back through
    /// the space → workspace → $HOME hierarchy via `WorkingDirectoryResolver`.
    func resolveWorkingDirectory() -> String {
        let sourcePaneDir = sourcePaneDirectory()
        let spaceDefault = activeSpace?.defaultWorkingDirectory
        return WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: sourcePaneDir,
            spaceDefault: spaceDefault,
            workspaceDefault: workspaceDefaultDirectory
        )
    }

    /// Extracts the working directory from the active pane (OSC 7 or tree node).
    private func sourcePaneDirectory() -> String? {
        guard let space = activeSpace,
              let tab = space.activeTab else { return nil }
        let pvm = tab.paneViewModel
        let focusedID = pvm.splitTree.focusedPaneID
        if let surface = pvm.surface(for: focusedID)?.surface {
            let inherited = ghostty_surface_inherited_config(surface, GHOSTTY_SURFACE_CONTEXT_WINDOW)
            if let wdPtr = inherited.working_directory {
                return String(cString: wdPtr)
            }
        }
        if case .leaf(_, let wd) = pvm.splitTree.findLeaf(paneID: focusedID),
           !wd.isEmpty, wd != "~" {
            return wd
        }
        return nil
    }

    /// Updates the workspace ID on this collection and all owned spaces.
    func propagateWorkspaceID(_ id: UUID) {
        workspaceID = id
        for space in spaces {
            space.propagateWorkspaceID(id)
        }
    }

    /// Updates the workspace default directory on this collection and all owned spaces.
    func propagateWorkspaceDefault(_ url: URL?) {
        workspaceDefaultDirectory = url
        for space in spaces {
            space.workspaceDefaultDirectory = url
        }
    }

    // MARK: - Private

    private func wireSpaceClose(_ space: SpaceModel) {
        space.onEmpty = { [weak self, spaceID = space.id] in
            self?.removeSpace(id: spaceID)
        }
    }
}
