import Foundation
import Observation

/// A named group of tabs within a Space, specialised by `SectionKind`.
///
/// Holds the tab-bar-owning role previously played by `SpaceModel`.
/// Claude panes and Terminal panes live in separate Sections so FR-04
/// (section isolation) falls out of the type system.
@MainActor @Observable
final class SectionModel: Identifiable {
    let id: UUID
    let kind: SectionKind
    private(set) var tabs: [TabModel]
    var activeTabID: UUID

    /// Most-recently-focused pane inside this section. Used by
    /// `SpaceModel.cycleFocusedSection()` (FR-20).
    var lastFocusedPaneID: UUID?

    /// Called when the last tab is removed. Owning `SpaceModel` decides
    /// whether to auto-hide (Terminal) or enter empty state (Claude).
    var onEmpty: (() -> Void)?

    // MARK: - Init

    /// Preconditions: `initialTab.sectionKind == kind` (debug-asserted).
    init(kind: SectionKind, initialTab: TabModel) {
        assert(initialTab.sectionKind == kind, "initialTab.sectionKind must match section kind")
        self.id = UUID()
        self.kind = kind
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
    }

    /// Restore a Section with a specific ID and a pre-built tab list.
    /// Preconditions: every tab's `sectionKind` equals `kind` (debug-asserted).
    init(id: UUID, kind: SectionKind, tabs: [TabModel], activeTabID: UUID) {
        for tab in tabs {
            assert(tab.sectionKind == kind, "tab.sectionKind must match section kind")
        }
        self.id = id
        self.kind = kind
        self.tabs = tabs
        if tabs.contains(where: { $0.id == activeTabID }) {
            self.activeTabID = activeTabID
        } else if let first = tabs.first {
            self.activeTabID = first.id
        } else {
            // Empty-section restore (Terminal-only). Use a sentinel UUID;
            // consumers must consult `tabs.isEmpty` before dereferencing.
            self.activeTabID = UUID()
        }
    }

    // MARK: - Computed

    var activeTab: TabModel? {
        tabs.first(where: { $0.id == activeTabID })
    }

    // MARK: - Tab Operations

    @discardableResult
    func createTab(workingDirectory: String) -> TabModel {
        let tab = TabModel(workingDirectory: workingDirectory, sectionKind: kind)
        wireTabClose(tab)
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

    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
    }

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

        if !tabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = ofID
        }
    }

    // MARK: - Internal

    /// Appends a pre-built tab (used by SpaceModel for section seeding).
    func appendTab(_ tab: TabModel) {
        assert(tab.sectionKind == kind, "tab.sectionKind must match section kind")
        wireTabClose(tab)
        tabs.append(tab)
        if tabs.count == 1 {
            activeTabID = tab.id
        }
    }

    /// Wires every existing tab's `onEmpty` closure to `removeTab`. Used
    /// by SpaceModel restore paths where tabs are handed in pre-built.
    func rewireTabCloseHandlers() {
        for tab in tabs {
            wireTabClose(tab)
        }
    }

    /// Internal teardown — kills every tab's panes, clears the list, and
    /// fires `onEmpty` only if the section had tabs before the call.
    func clearAllTabs() {
        let hadTabs = !tabs.isEmpty
        for tab in tabs {
            tab.cleanup()
        }
        tabs.removeAll()
        activeTabID = UUID()
        if hadTabs {
            onEmpty?()
        }
    }

    // MARK: - Private

    private func wireTabClose(_ tab: TabModel) {
        tab.onEmpty = { [weak self, tabID = tab.id] in
            self?.removeTab(id: tabID)
        }
    }
}
