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
        let initialSpace = SpaceModel(name: "default", workingDirectory: workingDirectory)
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

    /// - Parameter focusOnCreate: when `true` (the default) the new space becomes
    ///   the active space. Pass `false` to append it without changing the
    ///   selection (used by worktree creation to honour the user's preference).
    @discardableResult
    func createSpace(name: String? = nil, workingDirectory: String = "~", focusOnCreate: Bool = true) -> SpaceModel {
        spaceCounter += 1
        let resolvedName = name ?? "Space \(spaceCounter)"
        // Seed a Claude section (one Claude tab) and an empty Terminal section.
        let space = SpaceModel(name: resolvedName, workingDirectory: workingDirectory)
        space.workspaceDefaultDirectory = workspaceDefaultDirectory
        if let workspaceID {
            space.propagateWorkspaceID(workspaceID)
        }
        wireSpaceClose(space)
        spaces.append(space)
        if focusOnCreate {
            activeSpaceID = space.id
        }
        return space
    }

    func removeSpace(id: UUID) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let space = spaces[index]
        // Cleanup all tabs in both sections.
        for tab in space.claudeSection.tabs {
            tab.cleanup()
        }
        for tab in space.terminalSection.tabs {
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

    // MARK: - Hierarchy (orchestrator → implementer nesting)

    /// One entry in `hierarchicalOrder()` — a Space plus its render flags.
    struct HierarchicalEntry {
        let space: SpaceModel
        /// `true` when this Space is nested under an orchestrator (indented row).
        let isChild: Bool
        /// `true` when this Space has ≥1 child nested under it (shows the `⌂` marker).
        let isOrchestrator: Bool
    }

    /// Display order for the sidebar: each top-level Space immediately followed
    /// by its children (Spaces whose `parentSpaceID` points at it), regardless of
    /// raw array position. This keeps implementers visually attached to their
    /// orchestrator even after a drag-reorder mutates the raw `spaces` array.
    ///
    /// A Space is top-level when `parentSpaceID` is nil *or* points to a Space not
    /// in this collection (an orphan whose orchestrator was closed) — so a dangling
    /// link degrades to a flat top-level row rather than vanishing. As a final
    /// safety net any Space not reached by the two-level walk (e.g. a deeper
    /// descendant beyond the cap) is appended top-level, so no Space is ever dropped.
    func hierarchicalOrder() -> [HierarchicalEntry] {
        let idSet = Set(spaces.map { $0.id })
        func isTopLevel(_ space: SpaceModel) -> Bool {
            guard let parent = space.parentSpaceID else { return true }
            return !idSet.contains(parent)
        }

        var result: [HierarchicalEntry] = []
        var emitted = Set<UUID>()
        for space in spaces where isTopLevel(space) {
            let children = spaces.filter { $0.parentSpaceID == space.id }
            result.append(HierarchicalEntry(space: space, isChild: false, isOrchestrator: !children.isEmpty))
            emitted.insert(space.id)
            for child in children {
                result.append(HierarchicalEntry(space: child, isChild: true, isOrchestrator: false))
                emitted.insert(child.id)
            }
        }
        // Safety net: never drop a Space (e.g. a grandchild past the two-level cap).
        for space in spaces where !emitted.contains(space.id) {
            result.append(HierarchicalEntry(space: space, isChild: false, isOrchestrator: false))
        }
        return result
    }

    /// Number of Spaces nested directly under `spaceID`.
    func childCount(of spaceID: UUID) -> Int {
        spaces.filter { $0.parentSpaceID == spaceID }.count
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
        // v4 cascade: Space closes only on explicit user gesture
        // (Cmd+W on empty Claude placeholder, sidebar Close, etc.).
        // Section emptiness no longer triggers auto-close.
        space.onSpaceClose = { [weak self, spaceID = space.id] in
            self?.removeSpace(id: spaceID)
        }
    }
}
