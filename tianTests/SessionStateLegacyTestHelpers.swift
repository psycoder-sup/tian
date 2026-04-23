import Foundation
@testable import tian

// Legacy v3-shape init overloads used exclusively by the existing
// SessionRestorerTests fixtures. Keeps the >40 constructor sites working
// without rewriting each one — the tests were authored against the v3
// flat `tabs` shape, and Phase 4 introduced v4 `claudeSection` /
// `terminalSection`. These helpers upgrade the legacy arguments into a
// valid v4 SpaceState by:
//   - routing the caller's `tabs` into the Terminal section, and
//   - synthesising a minimal Claude section so validation passes.

extension SpaceState {
    /// v3-shape read-only accessor. Returns Terminal-section tabs. Used by
    /// older SessionRestorerTests fixtures that predate Phase 4.
    var tabs: [TabState] { terminalSection.tabs }

    /// v3-shape read-only accessor. Falls back to the Claude section's
    /// activeTabId when the Terminal section is empty so tests that assert
    /// on this field always see a valid UUID.
    var activeTabId: UUID {
        terminalSection.activeTabId ?? claudeSection.activeTabId ?? UUID()
    }
}

extension TabState {
    /// v3-shape convenience init. Defaults `sectionKind` to `.terminal`
    /// so legacy SessionRestorerTests fixtures keep compiling.
    init(id: UUID, name: String?, activePaneId: UUID, root: PaneNodeState) {
        self.init(
            id: id,
            name: name,
            activePaneId: activePaneId,
            root: root,
            sectionKind: .terminal
        )
    }
}

extension SpaceState {
    /// v3-shape convenience init. Legacy `tabs` are routed into the
    /// Terminal section; a synthesised Claude section with one placeholder
    /// pane satisfies the v4 invariants.
    init(
        id: UUID,
        name: String,
        activeTabId: UUID,
        defaultWorkingDirectory: String?,
        worktreePath: String? = nil,
        tabs: [TabState]
    ) {
        let claudePaneID = UUID()
        let claudeTabID = UUID()
        let wd = defaultWorkingDirectory ?? "/tmp"
        let claudeLeaf = PaneLeafState(paneID: claudePaneID, workingDirectory: wd)
        let claudeTab = TabState(
            id: claudeTabID,
            name: nil,
            activePaneId: claudePaneID,
            root: .pane(claudeLeaf),
            sectionKind: .claude
        )
        let claudeSection = SectionState(
            id: UUID(),
            kind: .claude,
            activeTabId: claudeTabID,
            tabs: [claudeTab]
        )

        // Normalise provided tabs so they all carry `.terminal` — some
        // fixtures construct TabState via the v3-shape init above, which
        // already defaults to `.terminal`; others may pre-tag them.
        let terminalTabs = tabs.map { existing in
            TabState(
                id: existing.id,
                name: existing.name,
                activePaneId: existing.activePaneId,
                root: existing.root,
                sectionKind: .terminal
            )
        }
        let terminalActiveTabId: UUID? = terminalTabs.isEmpty ? nil : activeTabId
        let terminalSection = SectionState(
            id: UUID(),
            kind: .terminal,
            activeTabId: terminalActiveTabId,
            tabs: terminalTabs
        )

        self.init(
            id: id,
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            worktreePath: worktreePath,
            claudeSection: claudeSection,
            terminalSection: terminalSection,
            terminalVisible: false,
            dockPosition: .right,
            splitRatio: 0.7,
            focusedSectionKind: .claude
        )
    }
}
