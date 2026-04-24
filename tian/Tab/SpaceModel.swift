import Foundation
import Observation

/// A named space. Owns two `SectionModel`s (Claude + Terminal) plus layout
/// metadata (visibility, dock position, split ratio, focused section).
@MainActor @Observable
final class SpaceModel: Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var defaultWorkingDirectory: URL?

    // MARK: - Sections (Phase 1)

    let claudeSection: SectionModel
    let terminalSection: SectionModel
    var terminalVisible: Bool
    var dockPosition: DockPosition
    var splitRatio: Double
    var focusedSectionKind: SectionKind

    /// Minimal stub for Phase 1; drag handling lands in Phase 2.
    let sectionDividerDragController: SectionDividerDragController

    // MARK: - Git

    /// Filesystem path of the associated git worktree.
    var worktreePath: URL? {
        didSet {
            if let worktreePath {
                gitContext.setWorktreePath(worktreePath.path)
            }
        }
    }

    let gitContext: SpaceGitContext

    /// The owning workspace's default directory.
    var workspaceDefaultDirectory: URL?

    /// The owning workspace's ID.
    var workspaceID: UUID?

    /// Called when the user explicitly asks to close this Space
    /// (Cmd+W on empty Claude placeholder, sidebar close, etc.).
    /// NEVER fires automatically from section emptiness.
    var onSpaceClose: (() -> Void)?

    // MARK: - Init (primary, Phase 1)

    init(
        id: UUID = UUID(),
        name: String,
        claudeSection: SectionModel,
        terminalSection: SectionModel,
        terminalVisible: Bool = false,
        dockPosition: DockPosition = .right,
        splitRatio: Double = 0.7,
        focusedSectionKind: SectionKind = .claude,
        defaultWorkingDirectory: URL? = nil,
        worktreePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.claudeSection = claudeSection
        self.terminalSection = terminalSection
        self.terminalVisible = terminalVisible
        self.dockPosition = dockPosition
        self.splitRatio = splitRatio.clamped(to: 0.1...0.9)
        self.focusedSectionKind = focusedSectionKind
        self.defaultWorkingDirectory = defaultWorkingDirectory
        let worktreeURL = worktreePath.map { URL(fileURLWithPath: $0) }
        self.worktreePath = worktreeURL
        self.gitContext = SpaceGitContext(worktreePath: worktreeURL)
        self.sectionDividerDragController = SectionDividerDragController()

        // FR-15 — apply any dock toggle that was queued mid-drag once the
        // gesture ends. Weak self to avoid retaining the space via its own
        // controller callback.
        self.sectionDividerDragController.onDragEnd = { [weak self] queued in
            guard let self, let queued else { return }
            self.dockPosition = queued
        }

        wireSectionCloseHandlers()
        for section in [claudeSection, terminalSection] {
            for tab in section.tabs {
                wireDirectoryFallback(tab)
                wireGitContext(tab)
                wireCrossSectionFocus(tab)
                for (paneID, wd) in tab.paneViewModel.splitTree.allLeafInfo() {
                    gitContext.paneAdded(paneID: paneID, workingDirectory: wd)
                }
            }
        }
    }

    /// Convenience — constructs a Space with a fresh Claude section (one
    /// `claude` pane) and an empty Terminal section. Used by
    /// `SpaceCollection.createSpace` in Phase 1.
    convenience init(name: String, workingDirectory: String) {
        let claudeTab = TabModel(workingDirectory: workingDirectory, sectionKind: .claude)
        let claudeSection = SectionModel(kind: .claude, initialTab: claudeTab)
        let terminalSection = SectionModel(
            id: UUID(),
            kind: .terminal,
            tabs: [],
            activeTabID: UUID()
        )
        self.init(
            name: name,
            claudeSection: claudeSection,
            terminalSection: terminalSection
        )
    }

    // MARK: - Legacy compat (will move to focusedSection in later phases)

    /// Phase 1 compat shim: returns Terminal-section tabs only. Kept for
    /// the legacy IPC `tab.create`/`tab.list` and sidebar tab-count call
    /// sites that are intentionally Terminal-scoped. For anything that
    /// needs to see Claude panes too (status tracking, process safety,
    /// pane resolution, focus), use `allTabs`.
    var tabs: [TabModel] { terminalSection.tabs }

    /// Every tab across both sections.
    var allTabs: [TabModel] { claudeSection.tabs + terminalSection.tabs }

    /// Phase 1 compat: legacy active-tab id for the Terminal section.
    var activeTabID: UUID {
        get { terminalSection.activeTabID }
        set { terminalSection.activateTab(id: newValue) }
    }

    var activeTab: TabModel? { terminalSection.activeTab }

    @discardableResult
    func createTab(workingDirectory: String = "~") -> TabModel {
        createTab(in: terminalSection, workingDirectory: workingDirectory)
    }

    /// FR-18 — create a tab in the named section and wire SpaceModel-level
    /// hooks (directory fallback, hierarchy context, git context,
    /// cross-section focus). Called by the key dispatcher for `.newTab` in
    /// the focused pane's section.
    @discardableResult
    func createTab(in section: SectionModel, workingDirectory: String) -> TabModel {
        let tab = section.createTab(workingDirectory: workingDirectory)
        wireTab(tab)
        let initialPaneID = tab.paneViewModel.splitTree.focusedPaneID
        gitContext.paneAdded(paneID: initialPaneID, workingDirectory: workingDirectory)
        return tab
    }

    func removeTab(id: UUID) { terminalSection.removeTab(id: id) }
    func activateTab(id: UUID) { terminalSection.activateTab(id: id) }

    /// Section-aware tab activation. Routes to the section that owns the
    /// tab (Claude or Terminal), updates `focusedSectionKind`, and
    /// unhides the Terminal section when activating a Terminal tab while
    /// it's hidden. Use this whenever a tab is being focused from outside
    /// the section (e.g. IPC, notification click) — the legacy
    /// `activateTab(id:)` shim only handles Terminal tabs.
    func activate(tab: TabModel) {
        let owningSection = (tab.sectionKind == .claude) ? claudeSection : terminalSection
        owningSection.activateTab(id: tab.id)
        focusedSectionKind = tab.sectionKind
        if tab.sectionKind == .terminal && !terminalVisible {
            terminalVisible = true
        }
    }

    func nextTab() { terminalSection.nextTab() }
    func previousTab() { terminalSection.previousTab() }
    func goToTab(index: Int) { terminalSection.goToTab(index: index) }
    func reorderTab(from sourceIndex: Int, to destinationIndex: Int) {
        terminalSection.reorderTab(from: sourceIndex, to: destinationIndex)
    }
    func closeOtherTabs(keepingID: UUID) { terminalSection.closeOtherTabs(keepingID: keepingID) }
    func closeTabsToRight(ofID: UUID) { terminalSection.closeTabsToRight(ofID: ofID) }

    // MARK: - Section accessors (new API)

    var focusedSection: SectionModel {
        switch focusedSectionKind {
        case .claude: return claudeSection
        case .terminal: return terminalSection
        }
    }

    var isEffectivelyEmpty: Bool {
        claudeSection.tabs.isEmpty && terminalSection.tabs.isEmpty
    }

    // MARK: - Terminal visibility

    func showTerminal() {
        let wasEmpty = terminalSection.tabs.isEmpty
        if wasEmpty {
            let wd = resolvedWorkingDirectoryForSpawn()
            createTab(in: terminalSection, workingDirectory: wd)
        }
        terminalVisible = true
        focusedSectionKind = .terminal
        Log.lifecycle.info("Terminal section shown (space=\(self.name), spawnedFreshTab=\(wasEmpty))")
    }

    func hideTerminal() {
        // FR-13 invariant: never mutates tabs/panes/focusedSectionKind.
        terminalVisible = false
        Log.lifecycle.info("Terminal section hidden (space=\(self.name))")
    }

    func toggleTerminal() {
        if terminalVisible {
            hideTerminal()
        } else {
            showTerminal()
        }
    }

    func setDockPosition(_ position: DockPosition) {
        if sectionDividerDragController.isDragging {
            sectionDividerDragController.enqueueDockPosition(position)
        } else {
            dockPosition = position
        }
    }

    func setSplitRatio(_ ratio: Double) {
        splitRatio = ratio.clamped(to: 0.1...0.9)
    }

    /// Explicit user-initiated teardown — kills every Terminal tab/pane
    /// (SIGHUP each shell) and returns the section to zero-tab state.
    func resetTerminalSection() {
        terminalSection.clearAllTabs()
        terminalVisible = false
        focusedSectionKind = .claude
    }

    /// FR-20 — alternates focus between Claude and Terminal, but only if
    /// the target section has at least one tab.
    func cycleFocusedSection() {
        let target: SectionKind = (focusedSectionKind == .claude) ? .terminal : .claude
        let targetSection = (target == .claude) ? claudeSection : terminalSection
        guard !targetSection.tabs.isEmpty else { return }
        focusedSectionKind = target
    }

    /// Placeholder for the empty-Claude visual state; v1 only flips focus
    /// back to Claude so the placeholder renders. No Space close here.
    func enterEmptyClaudeState() {
        focusedSectionKind = .claude
    }

    /// Explicit user-gesture close. If Terminal has live foreground
    /// processes and `confirm != nil`, awaits the closure. Only fires
    /// `onSpaceClose` when not cancelled.
    func requestSpaceClose(confirm: (([ForegroundProcessSummary]) async -> Bool)? = nil) async {
        let processes = enumerateForegroundProcesses()
        if !processes.isEmpty, let confirm {
            let ok = await confirm(processes)
            guard ok else { return }
        }
        onSpaceClose?()
    }

    // MARK: - Hierarchy / propagation

    func propagateWorkspaceID(_ id: UUID) {
        self.workspaceID = id
        for section in [claudeSection, terminalSection] {
            for tab in section.tabs {
                wireHierarchyContext(tab)
            }
        }
    }

    // MARK: - Private

    private func wireSectionCloseHandlers() {
        claudeSection.rewireTabCloseHandlers()
        terminalSection.rewireTabCloseHandlers()
        // Claude section empties → enter empty-Claude state. Space stays open.
        claudeSection.onEmpty = { [weak self] in
            self?.enterEmptyClaudeState()
        }
        // Terminal section empties → auto-hide. Space stays open.
        terminalSection.onEmpty = { [weak self] in
            self?.hideTerminal()
        }
    }

    /// Wire all SpaceModel-level closures on a newly-created or restored
    /// tab's PaneViewModel. Used both by `createTab(in:workingDirectory:)`
    /// and by restore paths that hand tabs in pre-built.
    func wireTab(_ tab: TabModel) {
        wireDirectoryFallback(tab)
        wireHierarchyContext(tab)
        wireGitContext(tab)
        wireCrossSectionFocus(tab)
    }

    private func wireCrossSectionFocus(_ tab: TabModel) {
        tab.paneViewModel.onFocusCrossSection = { [weak self, weak tab] direction in
            guard let self, let tab else { return false }
            return self.tryCrossSectionFocus(
                from: tab.paneViewModel.splitTree.focusedPaneID,
                in: tab.sectionKind,
                direction: direction
            )
        }
    }

    private func tryCrossSectionFocus(
        from sourcePaneID: UUID,
        in sourceKind: SectionKind,
        direction: NavigationDirection
    ) -> Bool {
        // Find the active tab's container size. Use the source tab's
        // paneViewModel.containerSize as a proxy for the section's frame
        // — combined with SectionLayout, this gives approximate global
        // frames. Full space-level container size would require the view
        // layer to propagate container geometry; for v1 we approximate.
        let sourceSection = (sourceKind == .claude) ? claudeSection : terminalSection
        guard let activeTab = sourceSection.activeTab else { return false }
        let sourceContainer = activeTab.paneViewModel.containerSize
        guard sourceContainer.width > 0, sourceContainer.height > 0 else { return false }

        // Reconstruct approximate global container size from the section
        // frame fraction (dock + ratio).
        let globalSize = approximateGlobalContainerSize(
            sectionContainerSize: sourceContainer,
            sectionKind: sourceKind
        )
        guard globalSize.width > 0, globalSize.height > 0 else { return false }

        let navigator = SpaceLevelSplitNavigation(space: self, containerSize: globalSize)
        guard let target = navigator.neighbor(
            from: sourcePaneID,
            in: sourceKind,
            direction: direction
        ) else { return false }

        // Cross-section result: switch focus.
        if target.sectionKind != focusedSectionKind {
            focusedSectionKind = target.sectionKind
        }
        let targetSection = (target.sectionKind == .claude) ? claudeSection : terminalSection
        targetSection.activeTab?.paneViewModel.focusPane(paneID: target.paneID)
        targetSection.lastFocusedPaneID = target.paneID
        return true
    }

    private func approximateGlobalContainerSize(
        sectionContainerSize: CGSize,
        sectionKind: SectionKind
    ) -> CGSize {
        let dividerThickness = SectionDividerView.thickness
        let ratio = splitRatio
        let fraction = (sectionKind == .claude) ? ratio : (1.0 - ratio)
        // Avoid div-by-zero; if fraction collapses, fall back to the
        // raw section size.
        guard fraction > 0.01 else { return sectionContainerSize }
        switch dockPosition {
        case .right:
            let totalWidth = sectionContainerSize.width / fraction + dividerThickness
            return CGSize(width: totalWidth, height: sectionContainerSize.height)
        case .bottom:
            let totalHeight = sectionContainerSize.height / fraction + dividerThickness
            return CGSize(width: sectionContainerSize.width, height: totalHeight)
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

    private func resolvedWorkingDirectoryForSpawn() -> String {
        if let defaultWorkingDirectory { return defaultWorkingDirectory.path }
        if let workspaceDefaultDirectory { return workspaceDefaultDirectory.path }
        return ProcessInfo.processInfo.environment["HOME"] ?? "~"
    }

    private func enumerateForegroundProcesses() -> [ForegroundProcessSummary] {
        // Placeholder for Phase 1 — the real enumeration hook lands with
        // the parent quit-time flow (PRD FR-22). Empty list means the
        // confirm closure is never invoked and the close proceeds.
        []
    }

    private static let cliPath: String = Bundle.main.executableURL!
        .deletingLastPathComponent()
        .appendingPathComponent("tian-cli")
        .path
}

// MARK: - Phase 1 compat: legacy `initialTab` initializer

extension SpaceModel {
    /// Phase 1 back-compat: legacy initializer taking a single "initial
    /// tab". The initial tab is routed into the Terminal section and a
    /// fresh Claude section is synthesised. Preserved during Phase 1 so
    /// existing call sites (IPC, sidebar, tests, Workspace constructor)
    /// keep working; will be removed when callers migrate to the primary
    /// section-aware initializer.
    convenience init(name: String, initialTab: TabModel) {
        let claudeTab = TabModel(workingDirectory: "~", sectionKind: .claude)
        let claudeSection = SectionModel(kind: .claude, initialTab: claudeTab)
        let terminalSection: SectionModel
        if initialTab.sectionKind == .terminal {
            terminalSection = SectionModel(
                id: UUID(),
                kind: .terminal,
                tabs: [initialTab],
                activeTabID: initialTab.id
            )
        } else {
            // The caller handed in a non-terminal-kind tab; fall back to
            // an empty Terminal section to preserve the precondition.
            terminalSection = SectionModel(
                id: UUID(),
                kind: .terminal,
                tabs: [],
                activeTabID: UUID()
            )
        }
        self.init(
            name: name,
            claudeSection: claudeSection,
            terminalSection: terminalSection
        )
    }
}

// MARK: - Phase 1 compat: restore-time initializer used by SessionRestorer shim

extension SpaceModel {
    /// Phase 1 back-compat constructor: accepts the legacy "flat tabs"
    /// shape from v3 state, synthesises a fresh Claude section in memory,
    /// and routes the restored tabs into the Terminal section. Removed
    /// at end of Phase 4 once SessionRestorer is v4-native.
    convenience init(
        id: UUID,
        name: String,
        tabs: [TabModel],
        activeTabID: UUID,
        defaultWorkingDirectory: URL?
    ) {
        // Synthesise a fresh Claude section (one Claude tab).
        let claudeWD = defaultWorkingDirectory?.path ?? (ProcessInfo.processInfo.environment["HOME"] ?? "~")
        let claudeTab = TabModel(workingDirectory: claudeWD, sectionKind: .claude)
        let claudeSection = SectionModel(kind: .claude, initialTab: claudeTab)

        // Route restored tabs into the Terminal section.
        let terminalSection: SectionModel
        if tabs.isEmpty {
            terminalSection = SectionModel(
                id: UUID(),
                kind: .terminal,
                tabs: [],
                activeTabID: UUID()
            )
        } else {
            terminalSection = SectionModel(
                id: UUID(),
                kind: .terminal,
                tabs: tabs,
                activeTabID: activeTabID
            )
        }

        self.init(
            id: id,
            name: name,
            claudeSection: claudeSection,
            terminalSection: terminalSection,
            terminalVisible: false,
            defaultWorkingDirectory: defaultWorkingDirectory
        )
    }
}

// MARK: - Foreground process summary (stub for Phase 1)

/// Placeholder summary of a running foreground process in a pane.
/// Full implementation lands with the parent PRD FR-22 quit-time flow.
struct ForegroundProcessSummary: Sendable, Equatable {
    let pid: Int32
    let name: String
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
