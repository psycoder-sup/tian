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

    /// Called when the space's last tab is closed. The owning SpaceCollection should remove this space.
    var onEmpty: (() -> Void)?

    init(name: String, initialTab: TabModel) {
        self.id = UUID()
        self.name = name
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
        self.createdAt = Date()

        wireTabClose(initialTab)
    }

    // MARK: - Computed

    var activeTab: TabModel? {
        tabs.first(where: { $0.id == activeTabID })
    }

    // MARK: - Tab Operations

    func createTab(workingDirectory: String = "~") {
        let tabIndex = tabs.count + 1
        let tab = TabModel(name: "Tab \(tabIndex)", workingDirectory: workingDirectory)
        wireTabClose(tab)
        tabs.append(tab)
        activeTabID = tab.id
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
}
