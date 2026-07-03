import Foundation
import Observation

/// Serializable snapshot of a workspace's persisted fields.
struct WorkspaceSnapshot: Sendable, Codable {
    let id: UUID
    let name: String
    let defaultWorkingDirectory: URL?
    let createdAt: Date
    /// Added in schema v5. Optional for back-compat with older snapshots.
    let inspectPanelVisible: Bool?
    let inspectPanelWidth: Double?
    /// Added in schema v6. Optional for back-compat. Encodes the active
    /// inspect-panel tab (`InspectTab.rawValue`).
    let activeTab: String?
}

/// The top-level organizational unit in tian's flattened hierarchy
/// (Workspace > Session). Each workspace maps to a project and owns a
/// collection of sessions.
@MainActor @Observable
final class Workspace: Identifiable {
    let id: UUID
    var name: String
    var defaultWorkingDirectory: URL?
    let createdAt: Date

    /// Remembers the last "Create worktree" checkbox state in the unified
    /// session-creation modal. Transient — not persisted in `WorkspaceSnapshot`,
    /// resets on app relaunch.
    var lastCreateWorktreeChoice: Bool?

    let sessionCollection: SessionCollection

    /// Inspect panel visibility and width for this workspace's window.
    let inspectPanelState: InspectPanelState

    /// Workspace-scoped file tree view model for the inspect panel.
    /// Kept alive for the workspace lifetime so reopening the rail is
    /// instant — only `setRoot(_:)` is re-called when the active session
    /// changes. Torn down via `cleanup()` on workspace close.
    let inspectFileTreeViewModel: InspectFileTreeViewModel

    /// Holds the inspect panel's active tab + per-tab view-models
    /// (Diff / Branch). Lives above SwiftUI so the active tab survives
    /// session switches and the view-models survive panel hide/show.
    /// Persisted via `WorkspaceSnapshot.activeTab`.
    let inspectTabState: InspectTabState

    /// Called when the workspace's last session is closed.
    var onEmpty: (() -> Void)?

    // MARK: - Init

    convenience init(name: String, defaultWorkingDirectory: URL? = nil) {
        self.init(
            id: UUID(),
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            createdAt: Date(),
            inspectPanelState: InspectPanelState(),
            inspectTabState: InspectTabState()
        )
    }

    private init(
        id: UUID,
        name: String,
        defaultWorkingDirectory: URL?,
        createdAt: Date,
        inspectPanelState: InspectPanelState = InspectPanelState(),
        inspectTabState: InspectTabState = InspectTabState()
    ) {
        self.id = id
        self.name = name
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.createdAt = createdAt
        self.inspectPanelState = inspectPanelState
        self.inspectTabState = inspectTabState
        self.inspectFileTreeViewModel = InspectFileTreeViewModel()

        let workingDir = defaultWorkingDirectory?.path
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "~"
        self.sessionCollection = SessionCollection(
            sessions: [],
            activeSessionID: nil,
            workspaceDefaultDirectory: defaultWorkingDirectory
        )
        self.sessionCollection.propagateWorkspaceID(id)
        // Seed the workspace's first session (a fresh Claude session). No custom
        // name — it uses its auto-derived name (Claude title / directory leaf).
        self.sessionCollection.createSession(workingDirectory: workingDir)

        self.sessionCollection.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    /// Restore a workspace with a pre-built SessionCollection.
    init(
        id: UUID,
        name: String,
        defaultWorkingDirectory: URL?,
        sessionCollection: SessionCollection,
        inspectPanelState: InspectPanelState = InspectPanelState(),
        inspectTabState: InspectTabState = InspectTabState()
    ) {
        self.id = id
        self.name = name
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.createdAt = Date()
        self.inspectPanelState = inspectPanelState
        self.inspectTabState = inspectTabState
        self.inspectFileTreeViewModel = InspectFileTreeViewModel()
        self.sessionCollection = sessionCollection
        self.sessionCollection.propagateWorkspaceDefault(defaultWorkingDirectory)
        self.sessionCollection.propagateWorkspaceID(id)

        self.sessionCollection.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    /// Updates the default working directory and propagates to all sessions.
    func setDefaultWorkingDirectory(_ url: URL?) {
        defaultWorkingDirectory = url
        sessionCollection.propagateWorkspaceDefault(url)
    }

    // MARK: - Convenience Accessors

    var sessions: [Session] { sessionCollection.sessions }
    var activeSessionID: UUID? { sessionCollection.activeSessionID }
    var activeSession: Session? { sessionCollection.activeSession }

    // MARK: - Lifecycle

    func cleanup() {
        inspectFileTreeViewModel.teardown()
        inspectTabState.diffViewModel.teardown()
        inspectTabState.branchViewModel.teardown()
        for session in sessionCollection.sessions {
            session.allPanes.forEach { $0.cleanup() }
        }
    }

    // MARK: - Inspect Panel

    /// Resolves the root directory the inspect panel should display for the
    /// given session. Per FR-10, the chain is session-level configured working
    /// directory → workspace's default working directory. Worktree-backed
    /// sessions (FR-10's "linked worktree") use `worktreePath` as their
    /// session-level directory. Returns `nil` when neither level has a
    /// configured directory — the panel renders the FR-18 empty state in
    /// that case (no `$HOME` fallback).
    func inspectPanelRoot(for session: Session?) -> URL? {
        guard let session else { return defaultWorkingDirectory }
        // Prefer the worktree the Claude pane is actively working in, so the
        // panel follows Claude after an EnterWorktree without waiting on a
        // persisted `worktreePath`.
        if let root = session.claudeWorktreeRoot {
            return root
        }
        if let worktreePath = session.worktreePath {
            return worktreePath
        }
        if let sessionDir = session.defaultWorkingDirectory {
            return sessionDir
        }
        return defaultWorkingDirectory
    }

    // MARK: - Serialization

    var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: id,
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            createdAt: createdAt,
            inspectPanelVisible: inspectPanelState.isVisible,
            inspectPanelWidth: Double(inspectPanelState.width),
            activeTab: inspectTabState.activeTab.rawValue
        )
    }

    static func from(snapshot: WorkspaceSnapshot) -> Workspace {
        let initialTab: InspectTab = snapshot.activeTab
            .flatMap { InspectTab(rawValue: $0) } ?? .files
        return Workspace(
            id: snapshot.id,
            name: snapshot.name,
            defaultWorkingDirectory: snapshot.defaultWorkingDirectory,
            createdAt: snapshot.createdAt,
            inspectPanelState: InspectPanelState.restore(
                visible: snapshot.inspectPanelVisible,
                width: snapshot.inspectPanelWidth
            ),
            inspectTabState: InspectTabState(activeTab: initialTab)
        )
    }
}
