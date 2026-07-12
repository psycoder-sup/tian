import Foundation
import Observation

/// Owns the ordered list of sessions for one workspace.
///
/// Emptying the collection (closing the last session) is a supported, stable
/// state: the owning workspace stays alive and its content area renders the
/// create-session empty state. Closing a workspace is a separate, explicit user
/// gesture (see `WorkspaceCollection.removeWorkspace`).
@MainActor @Observable
final class SessionCollection {
    private(set) var sessions: [Session]

    /// The active session's id, or `nil` when the collection is empty.
    var activeSessionID: UUID?

    /// The owning workspace's default directory. Propagated to new sessions.
    var workspaceDefaultDirectory: URL?

    /// The owning workspace's ID. Propagated to all sessions.
    var workspaceID: UUID?

    /// Non-nil for a remote (SSH) workspace. Set by `Workspace.configureRemote`
    /// before the first session is seeded, so every session created here spawns
    /// remotely. Propagated to existing sessions via `propagateRemoteChannel`.
    var remoteChannel: SSHControlChannel?

    /// Sets the remote channel and pushes it into every existing session (their
    /// reader + future panes go remote). New sessions pick it up in
    /// `createSession`.
    func propagateRemoteChannel(_ channel: SSHControlChannel?) {
        remoteChannel = channel
        for session in sessions {
            session.applyRemoteChannel(channel)
        }
    }

    init(workingDirectory: String = "~") {
        // No custom name — the seeded session uses its auto-derived name.
        let initialSession = Session(workingDirectory: workingDirectory)
        self.sessions = [initialSession]
        self.activeSessionID = initialSession.id

        wireSessionClose(initialSession)
    }

    /// Restore a session collection with pre-built sessions.
    init(sessions: [Session], activeSessionID: UUID?, workspaceDefaultDirectory: URL?) {
        self.sessions = sessions
        if let activeSessionID, sessions.contains(where: { $0.id == activeSessionID }) {
            self.activeSessionID = activeSessionID
        } else {
            self.activeSessionID = sessions.first?.id
        }
        self.workspaceDefaultDirectory = workspaceDefaultDirectory

        for session in sessions {
            session.workspaceDefaultDirectory = workspaceDefaultDirectory
            wireSessionClose(session)
        }
    }

    // MARK: - Computed

    var activeSession: Session? {
        guard let activeSessionID else { return nil }
        return sessions.first(where: { $0.id == activeSessionID })
    }

    // MARK: - Session Operations

    /// - Parameter focusOnCreate: when `true` (the default) the new session
    ///   becomes the active session. Pass `false` to append it without changing
    ///   the selection (used by worktree creation to honour the user's
    ///   preference).
    @discardableResult
    func createSession(name: String? = nil, workingDirectory: String? = nil, focusOnCreate: Bool = true) -> Session {
        // A nil name leaves `customName` nil, so the session uses its auto name.
        // `remoteChannel` (set before the first seed) makes the session's Claude
        // pane spawn over SSH.
        let session = Session(customName: name, workingDirectory: workingDirectory ?? "~", remoteChannel: remoteChannel)
        session.workspaceDefaultDirectory = workspaceDefaultDirectory
        if let workspaceID {
            session.propagateWorkspaceID(workspaceID)
        }
        wireSessionClose(session)
        sessions.append(session)
        if focusOnCreate {
            activeSessionID = session.id
        }
        return session
    }

    func removeSession(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        // Cleanup all panes (Claude + terminal panel).
        for pvm in session.allPanes {
            pvm.cleanup()
        }
        session.gitContext.teardown()
        sessions.remove(at: index)

        if sessions.isEmpty {
            // Closing the last session leaves the collection (and the owning
            // workspace) alive but empty; the content area shows the
            // create-session empty state. It does NOT close the workspace.
            activeSessionID = nil
            return
        }

        // If we removed the active session, activate nearest (prefer left, else right)
        if activeSessionID == id {
            let newIndex = index > 0 ? index - 1 : 0
            activeSessionID = sessions[newIndex].id
        }
    }

    func activateSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
    }

    // MARK: - Navigation

    func nextSession() {
        guard let currentIndex = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let nextIndex = (currentIndex + 1) % sessions.count
        activeSessionID = sessions[nextIndex].id
    }

    func previousSession() {
        guard let currentIndex = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let prevIndex = (currentIndex - 1 + sessions.count) % sessions.count
        activeSessionID = sessions[prevIndex].id
    }

    // MARK: - Reorder

    func reorderSession(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < sessions.count,
              destinationIndex >= 0, destinationIndex < sessions.count else { return }
        let session = sessions.remove(at: sourceIndex)
        sessions.insert(session, at: destinationIndex)
    }

    // MARK: - Hierarchy (orchestrator → implementer nesting)

    /// One entry in `hierarchicalOrder()` — a Session plus its render flags.
    struct HierarchicalEntry {
        let session: Session
        /// `true` when this Session is nested under an orchestrator (indented row).
        let isChild: Bool
        /// `true` when this Session has ≥1 child nested under it (shows the `⌂` marker).
        let isOrchestrator: Bool
    }

    /// Display order for the sidebar: each top-level Session immediately followed
    /// by its children (Sessions whose `parentSessionID` points at it), regardless
    /// of raw array position. This keeps implementers visually attached to their
    /// orchestrator even after a drag-reorder mutates the raw `sessions` array.
    ///
    /// A Session is top-level when `parentSessionID` is nil *or* points to a
    /// Session not in this collection (an orphan whose orchestrator was closed) —
    /// so a dangling link degrades to a flat top-level row rather than vanishing.
    /// As a final safety net any Session not reached by the two-level walk (e.g. a
    /// deeper descendant beyond the cap) is appended top-level, so no Session is
    /// ever dropped.
    func hierarchicalOrder() -> [HierarchicalEntry] {
        let idSet = Set(sessions.map { $0.id })
        func isTopLevel(_ session: Session) -> Bool {
            guard let parent = session.parentSessionID else { return true }
            return !idSet.contains(parent)
        }

        var result: [HierarchicalEntry] = []
        var emitted = Set<UUID>()
        for session in sessions where isTopLevel(session) {
            let children = sessions.filter { $0.parentSessionID == session.id }
            result.append(HierarchicalEntry(session: session, isChild: false, isOrchestrator: !children.isEmpty))
            emitted.insert(session.id)
            for child in children {
                result.append(HierarchicalEntry(session: child, isChild: true, isOrchestrator: false))
                emitted.insert(child.id)
            }
        }
        // Safety net: never drop a Session (e.g. a grandchild past the two-level cap).
        for session in sessions where !emitted.contains(session.id) {
            result.append(HierarchicalEntry(session: session, isChild: false, isOrchestrator: false))
        }
        return result
    }

    /// Number of Sessions nested directly under `sessionID`.
    func childCount(of sessionID: UUID) -> Int {
        sessions.filter { $0.parentSessionID == sessionID }.count
    }

    // MARK: - Working Directory

    /// Resolves the working directory for a **new session** — always the
    /// workspace root (the main worktree in a git repo), falling back to `$HOME`.
    ///
    /// A new session deliberately ignores every pane's live OSC 7 cwd *and* the
    /// active session's own default: a terminal panel that `cd`'d elsewhere, or
    /// an active worktree session whose default is a linked-worktree path, must
    /// never leak into where a fresh session launches. (Terminal-panel *splits*
    /// still inherit their source pane's cwd — that path lives in
    /// `PaneViewModel.resolveWorkingDirectory(for:)`, not here.)
    func resolveWorkingDirectory() -> String {
        WorkingDirectoryResolver.resolve(
            sourcePaneDirectory: nil,
            sessionDefault: nil,
            workspaceDefault: workspaceDefaultDirectory
        )
    }

    /// Updates the workspace ID on this collection and all owned sessions.
    func propagateWorkspaceID(_ id: UUID) {
        workspaceID = id
        for session in sessions {
            session.propagateWorkspaceID(id)
        }
    }

    /// Updates the workspace default directory on this collection and all owned sessions.
    func propagateWorkspaceDefault(_ url: URL?) {
        workspaceDefaultDirectory = url
        for session in sessions {
            session.workspaceDefaultDirectory = url
        }
    }

    // MARK: - Private

    private func wireSessionClose(_ session: Session) {
        // A session closes only on explicit user gesture (Cmd+W on empty Claude
        // placeholder, sidebar Close, etc.). Pane/panel emptiness never
        // triggers auto-close.
        session.onSessionClose = { [weak self, sessionID = session.id] in
            self?.removeSession(id: sessionID)
        }
    }
}
