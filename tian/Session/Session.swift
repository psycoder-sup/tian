import CoreGraphics
import Foundation
import Observation

/// A single Claude session. Owns exactly one Claude pane (never splittable) plus
/// a toggleable, splittable terminal panel (dock right/bottom, draggable divider)
/// and the layout/git metadata around them.
///
/// Collapses the former Space → Section → Tab layers: the Claude area and the
/// terminal area are now just two `PaneViewModel`s owned directly here.
@MainActor @Observable
final class Session: Identifiable {
    let id: UUID

    /// User-assigned name, or `nil` to fall back to the auto-derived name.
    /// Setting it to an empty/whitespace-only string normalizes back to `nil`
    /// (clearing the rename field returns the session to its auto name).
    var customName: String? {
        didSet {
            if let name = customName,
               name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customName = nil
            }
        }
    }

    /// The name shown in the UI: the custom name if set, else the auto name.
    var displayName: String { customName ?? autoName }

    /// Auto-derived name for a session without a custom name: the Claude pane's
    /// terminal title if non-empty, else the worktree / working-directory leaf,
    /// else a generic fallback.
    private var autoName: String {
        if let title = claudePane?.title, !title.isEmpty { return title }
        if let leaf = worktreePath?.lastPathComponent, !leaf.isEmpty { return leaf }
        if let leaf = defaultWorkingDirectory?.lastPathComponent, !leaf.isEmpty { return leaf }
        return "session"
    }

    let createdAt: Date
    var defaultWorkingDirectory: URL?

    // MARK: - Panes

    /// The Claude pane. `nil` while the session is in the empty-Claude
    /// placeholder state (before first `startClaude` or after the Claude pane
    /// exits). Single leaf — splits are blocked (`PaneViewModel.allowsSplits`).
    private(set) var claudePane: PaneViewModel?

    var hasLiveClaudePane: Bool { claudePane != nil }

    var claudePaneID: UUID? { claudePane?.splitTree.focusedPaneID }

    /// The git worktree root the Claude pane is currently working in, as tracked
    /// by `SessionGitContext` (written by both the OSC 7 cwd path and the Claude
    /// hook's `set-directory` IPC). `nil` until the pane reports a git worktree.
    /// Drives worktree-follow: the inspect panel root and the terminal panel's
    /// initial spawn directory both prefer it.
    var claudeWorktreeRoot: URL? {
        claudePaneID
            .flatMap { gitContext.paneWorktreeRoot[$0] }
            .map { URL(fileURLWithPath: $0) }
    }

    /// The command the Claude pane launched with — a custom command ("Run
    /// Custom Claude" / preset) or the user's configured default. Drives
    /// `claudeLaunchBadge`. In-memory only: a restored session resumes via
    /// `claude --resume <id>` (bare claude), so the original variant no longer
    /// applies and the badge is intentionally not persisted.
    var claudeLaunchCommand: String?

    /// The attached terminal panel. `nil` until the first `showTerminal`, and
    /// reset to `nil` when its last pane closes. Panes here CAN split.
    private(set) var terminalPanel: PaneViewModel?

    var terminalVisible: Bool
    var dockPosition: DockPosition
    var splitRatio: Double

    /// Which area the user last drove input into. Kept in sync with the
    /// actually-focused pane via `onPaneFocused`.
    var focusedArea: PaneKind

    /// `focusedArea` with a Claude fallback when the terminal area can't
    /// actually receive focus (hidden, or no terminal panel). Single source of
    /// truth for "which area currently owns focus".
    var effectiveFocusedArea: PaneKind {
        if focusedArea == .terminal, terminalVisible, terminalPanel != nil {
            return .terminal
        }
        return .claude
    }

    /// The `PaneViewModel` for `effectiveFocusedArea`. `nil` when the effective
    /// area is Claude but the Claude pane is in its empty state.
    var effectiveFocusedPane: PaneViewModel? {
        switch effectiveFocusedArea {
        case .claude: return claudePane
        case .terminal: return terminalPanel
        }
    }

    /// Coordinates live divider-drag state + FR-15 mid-drag dock queueing.
    let dividerDragController: SessionDividerDragController

    /// The size of the whole session content area, pushed by the view layer
    /// (`SessionContentView`). Used to reconstruct global pane frames for
    /// cross-area spatial navigation. Zero until the first layout pass.
    var contentContainerSize: CGSize = .zero

    /// Backing state for the single reader overlay layered over the Claude
    /// region.
    let readerState = SessionReaderState()

    // MARK: - Git

    /// Filesystem path of the associated git worktree.
    var worktreePath: URL? {
        didSet {
            if let worktreePath {
                gitContext.setWorktreePath(worktreePath.path)
            }
        }
    }

    let gitContext: SessionGitContext

    /// The Session that spawned this one (orchestrator → implementer link).
    /// Set automatically at worktree-create time from the calling pane's
    /// Session; `nil` for top-level Sessions. Capped at two levels — an
    /// implementer's children attach to the top orchestrator, not the
    /// implementer (see `WorktreeOrchestrator.continueCreation`). Drives the
    /// sidebar's nested hierarchy render only; no status roll-up.
    var parentSessionID: UUID? = nil

    /// The owning workspace's default directory.
    var workspaceDefaultDirectory: URL?

    /// The owning workspace's ID.
    var workspaceID: UUID?

    /// Called when the user explicitly asks to close this Session
    /// (Cmd+W on empty Claude placeholder, sidebar close, etc.).
    var onSessionClose: (() -> Void)?

    // MARK: - Init (primary / restore)

    /// Designated initializer. Accepts pre-built panes (used by
    /// `SessionRestorer`); pass `nil` panes for an empty session that seeds
    /// its Claude pane later via `startClaude`.
    init(
        id: UUID = UUID(),
        customName: String? = nil,
        claudePane: PaneViewModel?,
        terminalPanel: PaneViewModel?,
        terminalVisible: Bool = false,
        dockPosition: DockPosition = .bottom,
        splitRatio: Double = 0.7,
        focusedArea: PaneKind = .claude,
        defaultWorkingDirectory: URL? = nil,
        worktreePath: String? = nil
    ) {
        self.id = id
        self.customName = customName
        self.createdAt = Date()
        self.claudePane = claudePane
        self.terminalPanel = terminalPanel
        self.terminalVisible = terminalVisible
        self.dockPosition = dockPosition
        self.splitRatio = splitRatio.clamped(to: 0.1...0.9)
        self.focusedArea = focusedArea
        self.defaultWorkingDirectory = defaultWorkingDirectory
        let worktreeURL = worktreePath.map { URL(fileURLWithPath: $0) }
        self.worktreePath = worktreeURL
        self.gitContext = SessionGitContext(worktreePath: worktreeURL)
        self.dividerDragController = SessionDividerDragController()

        // FR-15 — apply any dock toggle queued mid-drag once the gesture ends.
        // Weak self to avoid retaining the session via its own controller.
        self.dividerDragController.onDragEnd = { [weak self] queued in
            guard let self, let queued else { return }
            self.dockPosition = queued
        }

        for pvm in [claudePane, terminalPanel].compactMap({ $0 }) {
            wirePane(pvm)
        }
    }

    /// Convenience — a fresh session with a live Claude pane rooted at
    /// `workingDirectory` and no terminal panel yet.
    ///
    /// A concrete path becomes the session default so `startClaude` (and any
    /// later terminal panel) spawns there. A bare `"~"` / empty path is left as
    /// no default, so spawning falls through to the workspace default or `$HOME`
    /// rather than a literal `~` directory.
    convenience init(customName: String? = nil, workingDirectory: String) {
        let defaultDir: URL? = (workingDirectory.isEmpty || workingDirectory == "~")
            ? nil
            : URL(fileURLWithPath: workingDirectory)
        self.init(
            customName: customName,
            claudePane: nil,
            terminalPanel: nil,
            defaultWorkingDirectory: defaultDir
        )
        startClaude()
    }

    // MARK: - Claude pane

    /// Seeds (or respawns) the Claude pane, tearing down any existing one
    /// first. Resolves the working directory (session default → workspace
    /// default → `$HOME`), applies a one-off `customCommand` when given, wires
    /// the pane, and focuses the Claude area.
    @discardableResult
    func startClaude(customCommand: String? = nil) -> PaneViewModel {
        claudePane?.cleanup()

        let wd = resolvedWorkingDirectoryForSpawn()
        let pvm = PaneViewModel(workingDirectory: wd, kind: .claude)
        wirePane(pvm)

        let initialPaneID = pvm.splitTree.focusedPaneID
        if let customCommand {
            pvm.applyCustomLaunchCommand(customCommand, toPaneID: initialPaneID)
        }
        // Record the command this Claude pane launched with so its
        // launch-variant badge can distinguish it. A default pane records the
        // resolved default so it's badged when that default is itself a variant
        // (e.g. the user set the default to `claude --chrome`).
        claudeLaunchCommand = customCommand ?? PaneSpawner.claudeAutostartCommand

        claudePane = pvm
        focusedArea = .claude
        return pvm
    }

    /// Leading badge distinguishing which Claude variant this session runs, or
    /// `nil` for plain `claude` and the empty-Claude state.
    var claudeLaunchBadge: ClaudeLaunchBadge? {
        guard claudePane != nil, let claudeLaunchCommand else { return nil }
        return ClaudeLaunchBadge.forCommand(claudeLaunchCommand)
    }

    // MARK: - Terminal panel

    /// Reveals the terminal panel, lazily creating it (one pane) if absent.
    ///
    /// When `background` is true the panel is still created (so the session has
    /// a usable terminal pane), but focus is left untouched — this keeps a
    /// background-created session (e.g. `worktree create --background`) from
    /// stealing focus from the session the user is currently in.
    func showTerminal(background: Bool = false) {
        let wasNil = terminalPanel == nil
        if wasNil {
            // Follow the Claude pane into its current worktree so a lazily-created
            // terminal starts where Claude is actually working, falling back to
            // the session/workspace defaults.
            let wd = resolvedWorkingDirectoryForSpawn(sourcePaneDirectory: claudeWorktreeRoot?.path)
            let pvm = PaneViewModel(workingDirectory: wd, kind: .terminal)
            wirePane(pvm)
            terminalPanel = pvm
        }
        terminalVisible = true
        if !background {
            focusedArea = .terminal
        }
        Log.lifecycle.info("Terminal panel shown (session=\(self.displayName), spawnedFresh=\(wasNil), background=\(background))")
    }

    func hideTerminal() {
        // Visibility only — never mutates panes or focusedArea.
        terminalVisible = false
        Log.lifecycle.info("Terminal panel hidden (session=\(self.displayName))")
    }

    func toggleTerminal() {
        if terminalVisible {
            hideTerminal()
        } else {
            showTerminal()
        }
    }

    func setDockPosition(_ position: DockPosition) {
        if dividerDragController.isDragging {
            dividerDragController.enqueueDockPosition(position)
        } else {
            dockPosition = position
        }
    }

    func setSplitRatio(_ ratio: Double) {
        splitRatio = ratio.clamped(to: 0.1...0.9)
    }

    /// Explicit user-initiated teardown — kills the terminal panel (SIGHUP each
    /// shell) and returns the session to no-terminal state.
    func resetTerminalPanel() {
        terminalPanel?.cleanup()
        terminalPanel = nil
        terminalVisible = false
        focusedArea = .claude
    }

    /// FR-20 — alternates focus between the Claude and terminal areas, but only
    /// if the target area can actually take focus: Claude needs a live pane, and
    /// the terminal needs a live panel that is currently visible (a hidden panel
    /// must never become the focused area).
    func cycleFocusedArea() {
        let target: PaneKind = (focusedArea == .claude) ? .terminal : .claude
        let canFocusTarget = (target == .claude)
            ? claudePane != nil
            : terminalPanel != nil && terminalVisible
        guard canFocusTarget else { return }
        focusedArea = target
    }

    // MARK: - Aggregates

    var allPanes: [PaneViewModel] {
        [claudePane, terminalPanel].compactMap { $0 }
    }

    var isEffectivelyEmpty: Bool {
        claudePane == nil && terminalPanel == nil
    }

    /// Every leaf pane ID across this session's Claude pane and terminal panel,
    /// in `allPanes` order.
    var allPaneIDs: [UUID] { allPanes.flatMap { $0.splitTree.allLeaves() } }

    /// Aggregate Claude session state across this session's panes, read from the
    /// per-PVM mirrors (not `PaneStatusManager.shared`) so observation stays
    /// scoped. Highest-priority non-inactive state wins — same ranking as
    /// `PaneStatusManager.aggregateSessionState(in:)`.
    var aggregateClaudeState: ClaudeSessionState? {
        var top: ClaudeSessionState?
        for pvm in allPanes {
            for paneID in pvm.splitTree.allLeaves() {
                guard let state = pvm.sessionStates[paneID], state != .inactive else { continue }
                // `>` compares by priority (needsAttention is greatest).
                if top == nil || state > top! {
                    top = state
                }
            }
        }
        return top
    }

    /// Latest free-form status across this session's panes, read from the
    /// per-PVM mirrors. Highest write-sequence wins — same ordering as
    /// `PaneStatusManager.latestStatus(in:)`.
    var latestPaneStatus: PaneStatus? {
        var latest: PaneStatus?
        for pvm in allPanes {
            for paneID in pvm.splitTree.allLeaves() {
                guard let status = pvm.paneStatuses[paneID] else { continue }
                if latest == nil || status.sequence > latest!.sequence {
                    latest = status
                }
            }
        }
        return latest
    }

    // MARK: - Close

    /// Explicit user-gesture close. If any pane has live foreground processes
    /// and `confirm != nil`, awaits the closure. Only fires `onSessionClose`
    /// when not cancelled.
    func requestSessionClose(confirm: (([ForegroundProcessSummary]) async -> Bool)? = nil) async {
        let processes = enumerateForegroundProcesses()
        if !processes.isEmpty, let confirm {
            let ok = await confirm(processes)
            guard ok else { return }
        }
        onSessionClose?()
    }

    // MARK: - Hierarchy / propagation

    func propagateWorkspaceID(_ id: UUID) {
        self.workspaceID = id
        for pvm in allPanes {
            wireHierarchyContext(pvm)
        }
    }

    // MARK: - Private

    /// Wires every `Session`-level closure on a newly-created or restored pane:
    /// directory fallback, hierarchy context (env vars), git-context callbacks,
    /// cross-area focus, focus sync, and `onEmpty` routing.
    private func wirePane(_ pvm: PaneViewModel) {
        wireDirectoryFallback(pvm)
        wireHierarchyContext(pvm)
        wireGitContext(pvm)

        pvm.onFocusCrossArea = { [weak self, weak pvm] direction in
            guard let self, let pvm else { return false }
            return self.tryCrossAreaFocus(from: pvm.splitTree.focusedPaneID, direction: direction)
        }

        // Keep `focusedArea` aligned with the pane the user is actually typing
        // into — otherwise clicking a Claude pane while the model still thinks
        // Terminal is focused would route area-scoped keys to the wrong area.
        pvm.onPaneFocused = { [weak self, weak pvm] _ in
            guard let self, let pvm else { return }
            if self.focusedArea != pvm.kind {
                self.focusedArea = pvm.kind
            }
        }

        // onEmpty routing: the Claude pane emptying closes the whole session
        // (the Claude process already exited — no confirm needed); the terminal
        // panel emptying drops the panel and auto-hides, leaving the session open.
        if pvm.kind == .claude {
            pvm.onEmpty = { [weak self] in
                self?.onSessionClose?()
            }
        } else {
            pvm.onEmpty = { [weak self] in
                guard let self else { return }
                self.terminalPanel = nil
                self.hideTerminal()
            }
        }
    }

    private func wireDirectoryFallback(_ pvm: PaneViewModel) {
        pvm.directoryFallback = { [weak self] in
            guard let self,
                  self.defaultWorkingDirectory != nil || self.workspaceDefaultDirectory != nil
            else { return nil }
            return WorkingDirectoryResolver.resolve(
                sourcePaneDirectory: nil,
                sessionDefault: self.defaultWorkingDirectory,
                workspaceDefault: self.workspaceDefaultDirectory
            )
        }
    }

    private func wireGitContext(_ pvm: PaneViewModel) {
        pvm.onPaneDirectoryChanged = { [weak self] paneID, directory in
            self?.gitContext.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: directory)
        }
        pvm.onPaneRemoved = { [weak self] paneID in
            self?.gitContext.paneRemoved(paneID: paneID)
        }
        for (paneID, wd) in pvm.splitTree.allLeafInfo() {
            gitContext.paneAdded(paneID: paneID, workingDirectory: wd)
        }
    }

    /// Wires the pane's TIAN_* hierarchy env. Guarded on `workspaceID`; a no-op
    /// until the session is attached to a workspace (`propagateWorkspaceID`),
    /// which re-invokes this for every live pane.
    private func wireHierarchyContext(_ pvm: PaneViewModel) {
        guard let workspaceID else { return }
        let context = PaneHierarchyContext(
            socketPath: IPCServer.socketPath,
            workspaceID: workspaceID,
            sessionID: id,
            cliPath: Self.cliPath
        )
        pvm.hierarchyContext = context
        pvm.applyEnvironmentVariables()
    }

    /// FR-19 — attempt to move focus across the Claude/terminal divider using
    /// concrete global pane frames. Requires `contentContainerSize` to have been
    /// pushed by the view layer; before the first layout pass it no-ops rather
    /// than approximating.
    private func tryCrossAreaFocus(from sourcePaneID: UUID, direction: NavigationDirection) -> Bool {
        let containerSize = contentContainerSize
        guard containerSize.width > 0, containerSize.height > 0 else { return false }

        let navigator = SessionSplitNavigation(session: self, containerSize: containerSize)
        guard let target = navigator.neighbor(from: sourcePaneID, direction: direction) else {
            return false
        }

        if target.kind != focusedArea {
            focusedArea = target.kind
        }
        let targetPane = (target.kind == .claude) ? claudePane : terminalPanel
        targetPane?.focusPane(paneID: target.paneID)
        return true
    }

    /// Resolves a spawn directory for a new pane. `startClaude` passes `nil`
    /// (session-anchored respawn); `showTerminal` passes the Claude worktree root
    /// so the terminal follows Claude into its current worktree.
    private func resolvedWorkingDirectoryForSpawn(sourcePaneDirectory: String? = nil) -> String {
        WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: sourcePaneDirectory,
            sessionDefault: defaultWorkingDirectory,
            workspaceDefault: workspaceDefaultDirectory
        )
    }

    private func enumerateForegroundProcesses() -> [ForegroundProcessSummary] {
        // Placeholder — the real enumeration hook lands with the parent
        // quit-time flow (PRD FR-22). Empty list means the confirm closure is
        // never invoked and the close proceeds.
        []
    }

    // The CLI ships as `tian` inside the bundle's Resources directory (it
    // shadows the GUI executable, `Contents/MacOS/tian`, on the pane PATH).
    private static let cliPath: String = Bundle.main.resourceURL!
        .appendingPathComponent("tian")
        .path
}

// MARK: - Foreground process summary (stub)

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
