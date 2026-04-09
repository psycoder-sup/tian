import Foundation
import Observation

/// A named space containing an ordered list of tabs.
@MainActor @Observable
final class SpaceModel: Identifiable {
    let id: UUID
    var name: String
    private(set) var tabs: [TabModel]
    var activeTabID: UUID
    let createdAt: Date
    var defaultWorkingDirectory: URL?

    /// Filesystem path of the associated git worktree. When non-nil, identifies this Space as worktree-backed.
    var worktreePath: URL? {
        didSet {
            if let worktreePath {
                gitContext.setWorktreePath(worktreePath.path)
            }
        }
    }

    /// Per-Space git repository context. Tracks repos, branch names, and status for sidebar display.
    let gitContext: SpaceGitContext

    /// The owning workspace's default directory, set by SpaceCollection/Workspace.
    var workspaceDefaultDirectory: URL?

    /// The owning workspace's ID, set via `propagateWorkspaceID` from SpaceCollection.
    var workspaceID: UUID?

    /// Called when the space's last tab is closed. The owning SpaceCollection should remove this space.
    var onEmpty: (() -> Void)?

    init(name: String, initialTab: TabModel) {
        self.id = UUID()
        self.name = name
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
        self.createdAt = Date()
        self.gitContext = SpaceGitContext(worktreePath: nil)

        wireTabClose(initialTab)
        wireDirectoryFallback(initialTab)
        wireGitContext(initialTab)
        // Seed git context with initial pane directories
        for (paneID, wd) in initialTab.paneViewModel.splitTree.allLeafInfo() {
            gitContext.paneAdded(paneID: paneID, workingDirectory: wd)
        }
    }

    /// Restore a space with specific ID, pre-built tabs, and active tab selection.
    init(id: UUID, name: String, tabs: [TabModel], activeTabID: UUID, defaultWorkingDirectory: URL?) {
        self.id = id
        self.name = name
        self.tabs = tabs
        self.activeTabID = tabs.contains(where: { $0.id == activeTabID })
            ? activeTabID
            : tabs[0].id
        self.createdAt = Date()
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.gitContext = SpaceGitContext(worktreePath: nil)

        for tab in tabs {
            wireTabClose(tab)
            wireDirectoryFallback(tab)
            wireGitContext(tab)
            // Seed git context with persisted pane directories
            for (paneID, wd) in tab.paneViewModel.splitTree.allLeafInfo() {
                gitContext.paneAdded(paneID: paneID, workingDirectory: wd)
            }
        }
    }

    // MARK: - Computed

    var activeTab: TabModel? {
        tabs.first(where: { $0.id == activeTabID })
    }

    // MARK: - Tab Operations

    @discardableResult
    func createTab(workingDirectory: String = "~") -> TabModel {
        let tab = TabModel(workingDirectory: workingDirectory)
        wireTabClose(tab)
        wireDirectoryFallback(tab)
        wireHierarchyContext(tab)
        wireGitContext(tab)
        let initialPaneID = tab.paneViewModel.splitTree.focusedPaneID
        gitContext.paneAdded(paneID: initialPaneID, workingDirectory: workingDirectory)
        tabs.append(tab)
        activeTabID = tab.id
        return tab
    }

    func removeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        tab.cleanup()
        tabs.remove(at: index)

        if tabs.isEmpty {
            onEmpty?()
            return
        }

        // If we removed the active tab, activate nearest (prefer left, else right)
        if activeTabID == id {
            let newIndex = index > 0 ? index - 1 : 0
            activeTabID = tabs[newIndex].id
        }
    }

    func activateTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    // MARK: - Navigation

    func nextTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        activeTabID = tabs[nextIndex].id
    }

    func previousTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
        activeTabID = tabs[prevIndex].id
    }

    /// Go to the Nth tab (1-indexed). Index 9 always goes to the last tab.
    func goToTab(index: Int) {
        guard !tabs.isEmpty else { return }
        if index == 9 {
            activeTabID = tabs[tabs.count - 1].id
            return
        }
        let arrayIndex = index - 1
        guard arrayIndex >= 0, arrayIndex < tabs.count else { return }
        activeTabID = tabs[arrayIndex].id
    }

    // MARK: - Reorder

    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
    }

    // MARK: - Batch Close

    func closeOtherTabs(keepingID: UUID) {
        let tabsToClose = tabs.filter { $0.id != keepingID }
        for tab in tabsToClose {
            tab.cleanup()
        }
        tabs.removeAll(where: { $0.id != keepingID })
        if let remaining = tabs.first {
            activeTabID = remaining.id
        }
    }

    func closeTabsToRight(ofID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == ofID }) else { return }
        let rightTabs = tabs[(index + 1)...]
        for tab in rightTabs {
            tab.cleanup()
        }
        tabs.removeSubrange((index + 1)...)

        // If active tab was removed, activate the kept tab
        if !tabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = ofID
        }
    }

    // MARK: - Private

    private func wireTabClose(_ tab: TabModel) {
        tab.onEmpty = { [weak self, tabID = tab.id] in
            self?.removeTab(id: tabID)
        }
    }

    private func wireGitContext(_ tab: TabModel) {
        tab.paneViewModel.onPaneDirectoryChanged = { [weak self] paneID, directory in
            self?.gitContext.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: directory)
        }
        tab.paneViewModel.onPaneRemoved = { [weak self] paneID in
            self?.gitContext.paneRemoved(paneID: paneID)
        }
    }

    private func wireDirectoryFallback(_ tab: TabModel) {
        tab.paneViewModel.directoryFallback = { [weak self] in
            guard let self,
                  self.defaultWorkingDirectory != nil || self.workspaceDefaultDirectory != nil
            else { return nil }
            return WorkingDirectoryResolver.resolve(
                sourcePaneDirectory: nil,
                spaceDefault: self.defaultWorkingDirectory,
                workspaceDefault: self.workspaceDefaultDirectory
            )
        }
    }

    private func wireHierarchyContext(_ tab: TabModel) {
        guard let workspaceID else { return }
        let context = PaneHierarchyContext(
            socketPath: IPCServer.socketPath,
            workspaceID: workspaceID,
            spaceID: id,
            tabID: tab.id,
            cliPath: Self.cliPath
        )
        tab.paneViewModel.hierarchyContext = context
        tab.paneViewModel.applyEnvironmentVariables()
    }

    /// Updates the workspace ID and wires hierarchy context for all existing tabs.
    func propagateWorkspaceID(_ id: UUID) {
        self.workspaceID = id
        for tab in tabs {
            wireHierarchyContext(tab)
        }
    }

    private static let cliPath: String = Bundle.main.executableURL!
        .deletingLastPathComponent()
        .appendingPathComponent("aterm-cli")
        .path
}
