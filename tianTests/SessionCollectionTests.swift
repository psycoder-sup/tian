import Testing
import Foundation
@testable import tian

@MainActor
struct SessionCollectionTests {

    // MARK: - Init

    @Test func initWithDefaultSession() {
        // A fresh collection seeds one session with no custom name (auto-derived)
        // plus a live Claude pane and no terminal panel yet.
        let collection = SessionCollection()
        #expect(collection.sessions.count == 1)
        #expect(collection.sessions[0].customName == nil)
        #expect(collection.sessions[0].hasLiveClaudePane)
        #expect(collection.sessions[0].terminalPanel == nil)
        #expect(collection.activeSessionID == collection.sessions[0].id)
    }

    // MARK: - Create

    @Test func createSessionAppendsAndActivates() {
        let collection = SessionCollection()
        collection.createSession()
        #expect(collection.sessions.count == 2)
        #expect(collection.activeSessionID == collection.sessions[1].id)
        // No explicit name → customName stays nil (auto-derived name).
        #expect(collection.sessions[1].customName == nil)
    }

    @Test func createSessionWithExplicitNameSetsCustomName() {
        let collection = SessionCollection()
        let named = collection.createSession(name: "release")
        #expect(named.customName == "release")
    }

    @Test func createSessionWithoutFocusKeepsActiveSession() {
        let collection = SessionCollection()
        let originalActiveID = collection.activeSessionID

        let newSession = collection.createSession(focusOnCreate: false)
        #expect(collection.sessions.count == 2)
        // The session is appended...
        #expect(collection.sessions[1].id == newSession.id)
        // ...but the active selection stays put (no autofocus).
        #expect(collection.activeSessionID == originalActiveID)
    }

    // MARK: - Remove

    @Test func removeSessionActivatesNearest() throws {
        let collection = SessionCollection()
        collection.createSession()
        collection.createSession()
        // active = Session 3 (index 2)
        let session3ID = try #require(collection.activeSessionID)
        let session2ID = collection.sessions[1].id

        collection.removeSession(id: session3ID)
        #expect(collection.sessions.count == 2)
        #expect(collection.activeSessionID == session2ID)
    }

    @Test func removeFirstSessionActivatesRight() {
        let collection = SessionCollection()
        collection.createSession()
        collection.activateSession(id: collection.sessions[0].id)
        let session1ID = collection.sessions[0].id
        let session2ID = collection.sessions[1].id

        collection.removeSession(id: session1ID)
        #expect(collection.sessions.count == 1)
        #expect(collection.activeSessionID == session2ID)
    }

    @Test func removeLastSessionLeavesCollectionEmpty() {
        // Closing the last session leaves the collection empty but alive — it
        // no longer signals a quit or closes the owning workspace. The content
        // area renders the create-session empty state instead.
        let collection = SessionCollection()
        let sessionID = collection.sessions[0].id
        collection.removeSession(id: sessionID)
        #expect(collection.sessions.isEmpty)
        #expect(collection.activeSessionID == nil)
    }

    @Test func removeNonexistentSessionIsNoOp() {
        let collection = SessionCollection()
        collection.removeSession(id: UUID())
        #expect(collection.sessions.count == 1)
    }

    // MARK: - Activate

    @Test func activateSessionChangesActiveID() {
        let collection = SessionCollection()
        let first = collection.sessions[0]
        collection.createSession()

        collection.activateSession(id: first.id)
        #expect(collection.activeSessionID == first.id)
    }

    @Test func activateNonexistentSessionIsNoOp() {
        let collection = SessionCollection()
        let original = collection.activeSessionID
        collection.activateSession(id: UUID())
        #expect(collection.activeSessionID == original)
    }

    // MARK: - Navigation

    @Test func nextSessionWraps() {
        let collection = SessionCollection()
        collection.createSession()
        // active = session 2 (last)
        collection.nextSession()
        #expect(collection.activeSessionID == collection.sessions[0].id)
    }

    @Test func previousSessionWraps() {
        let collection = SessionCollection()
        collection.createSession()
        collection.activateSession(id: collection.sessions[0].id)
        collection.previousSession()
        #expect(collection.activeSessionID == collection.sessions[1].id)
    }

    // MARK: - Reorder

    @Test func reorderSession() {
        let collection = SessionCollection()
        collection.createSession()
        let session1ID = collection.sessions[0].id
        let session2ID = collection.sessions[1].id

        collection.reorderSession(from: 0, to: 1)
        #expect(collection.sessions[0].id == session2ID)
        #expect(collection.sessions[1].id == session1ID)
    }

    // MARK: - Close cascades

    @Test func explicitSessionCloseEmptiesCollection() async {
        // A user-gesture close on the last session fires `onSessionClose` →
        // removeSession → collection empties. It does not quit or close the
        // workspace; the collection simply becomes empty.
        let collection = SessionCollection()
        let session = collection.sessions[0]
        await session.requestSessionClose()

        #expect(collection.sessions.isEmpty)
        #expect(collection.activeSessionID == nil)
    }

    @Test func terminalPaneCloseDoesNotCloseSession() throws {
        // Closing the last terminal pane drops the panel and auto-hides, but
        // leaves the session (and the collection) alive.
        let collection = SessionCollection()
        let session = collection.sessions[0]
        session.showTerminal()

        let panel = try #require(session.terminalPanel)
        let paneID = panel.splitTree.focusedPaneID
        panel.closePane(paneID: paneID)

        #expect(session.terminalPanel == nil)
        #expect(session.terminalVisible == false)
        #expect(collection.sessions.count == 1)
    }

    @Test func claudePaneCloseClosesSession() throws {
        // Closing the Claude pane now closes the session (the Claude process
        // exited). As the collection's last session, this empties the collection
        // but leaves it (and the owning workspace) alive.
        let collection = SessionCollection()
        let session = collection.sessions[0]

        let claude = try #require(session.claudePane)
        let paneID = claude.splitTree.focusedPaneID
        claude.closePane(paneID: paneID)

        #expect(collection.sessions.isEmpty)
        #expect(collection.activeSessionID == nil)
    }

    @Test func claudePaneCloseRemovesOnlyThatSessionWhenOthersRemain() throws {
        let collection = SessionCollection()
        collection.createSession()   // 2 sessions
        let first = collection.sessions[0]

        let claude = try #require(first.claudePane)
        claude.closePane(paneID: claude.splitTree.focusedPaneID)

        #expect(collection.sessions.count == 1)
    }

    // MARK: - Hierarchical ordering

    /// `hierarchicalOrder()` groups each parent's children immediately after it,
    /// regardless of raw array position, and flags the parent as orchestrator.
    @Test func hierarchicalOrderGroupsChildrenUnderParent() {
        let parent = Session(customName: "orchestrator", workingDirectory: "/tmp")
        let childA = Session(customName: "impl-a", workingDirectory: "/tmp")
        let childB = Session(customName: "impl-b", workingDirectory: "/tmp")
        let unrelated = Session(customName: "other", workingDirectory: "/tmp")
        childA.parentSessionID = parent.id
        childB.parentSessionID = parent.id

        // Raw order interleaves an unrelated top-level Session between the children.
        let collection = SessionCollection(
            sessions: [parent, childA, unrelated, childB],
            activeSessionID: parent.id,
            workspaceDefaultDirectory: nil
        )

        let order = collection.hierarchicalOrder()
        #expect(order.map { $0.session.id } == [parent.id, childA.id, childB.id, unrelated.id])
        #expect(order[0].isChild == false)
        #expect(order[0].isOrchestrator == true)
        #expect(order[1].isChild == true)
        #expect(order[2].isChild == true)
        #expect(order[3].isChild == false)
        #expect(order[3].isOrchestrator == false)
        #expect(collection.childCount(of: parent.id) == 2)
    }

    /// An orphan (its `parentSessionID` points to a Session not in the collection,
    /// e.g. the orchestrator was closed) renders flat at top level — never dropped.
    @Test func hierarchicalOrderTreatsOrphanAsTopLevel() {
        let orphan = Session(customName: "orphan", workingDirectory: "/tmp")
        orphan.parentSessionID = UUID() // parent not present in this collection

        let collection = SessionCollection(
            sessions: [orphan],
            activeSessionID: orphan.id,
            workspaceDefaultDirectory: nil
        )

        let order = collection.hierarchicalOrder()
        #expect(order.count == 1)
        #expect(order[0].session.id == orphan.id)
        #expect(order[0].isChild == false)
        #expect(order[0].isOrchestrator == false)
        #expect(collection.childCount(of: orphan.id) == 0)
    }

    /// The two-level cap: a grandchild (child of a child) is beyond the walk, but
    /// the safety net appends it as a flat top-level row so no Session is dropped.
    @Test func hierarchicalOrderAppendsGrandchildPastCap() {
        let top = Session(customName: "top", workingDirectory: "/tmp")
        let child = Session(customName: "child", workingDirectory: "/tmp")
        let grandchild = Session(customName: "grandchild", workingDirectory: "/tmp")
        child.parentSessionID = top.id
        grandchild.parentSessionID = child.id

        let collection = SessionCollection(
            sessions: [top, child, grandchild],
            activeSessionID: top.id,
            workspaceDefaultDirectory: nil
        )

        let order = collection.hierarchicalOrder()
        // All three appear — the grandchild is never dropped.
        #expect(order.count == 3)
        #expect(order.map { $0.session.id } == [top.id, child.id, grandchild.id])
        #expect(order[0].isChild == false)
        #expect(order[0].isOrchestrator == true)   // top has a child
        #expect(order[1].isChild == true)          // child nested under top
        // Grandchild past the two-level cap → appended flat, not nested.
        #expect(order[2].isChild == false)
        #expect(order[2].isOrchestrator == false)
        #expect(collection.childCount(of: top.id) == 1)
        #expect(collection.childCount(of: child.id) == 1)
    }

    // MARK: - Working directory resolution

    /// A new session resolves to the workspace default (the workspace root).
    @Test func resolveWorkingDirectoryUsesWorkspaceDefault() {
        let session = Session(customName: "empty", claudePane: nil, terminalPanel: nil)
        let collection = SessionCollection(
            sessions: [session],
            activeSessionID: session.id,
            workspaceDefaultDirectory: URL(filePath: "/tmp/workspace")
        )
        #expect(collection.resolveWorkingDirectory() == "/tmp/workspace")
    }

    /// A new session launches at the workspace root even when the active session
    /// carries its own default (e.g. a worktree session whose default is the
    /// linked-worktree path). The active session's cwd must never leak into a
    /// fresh session — otherwise creating a normal session while a worktree
    /// session is active would inherit the worktree path.
    @Test func resolveWorkingDirectoryUsesWorkspaceRootEvenWhenActiveSessionHasOwnDefault() {
        let session = Session(
            customName: "empty",
            claudePane: nil,
            terminalPanel: nil,
            defaultWorkingDirectory: URL(filePath: "/tmp/some-worktree")
        )
        let collection = SessionCollection(
            sessions: [session],
            activeSessionID: session.id,
            workspaceDefaultDirectory: URL(filePath: "/tmp/workspace")
        )
        #expect(collection.resolveWorkingDirectory() == "/tmp/workspace")
    }

    /// With no workspace default, resolution falls to `$HOME` — not the active
    /// session's own default — proving the active session's cwd never leaks in.
    @Test func resolveWorkingDirectoryFallsToHomeNotActiveSessionDefault() {
        let session = Session(
            customName: "empty",
            claudePane: nil,
            terminalPanel: nil,
            defaultWorkingDirectory: URL(filePath: "/tmp/some-worktree")
        )
        let collection = SessionCollection(
            sessions: [session],
            activeSessionID: session.id,
            workspaceDefaultDirectory: nil
        )
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "~"
        #expect(collection.resolveWorkingDirectory() == home)
    }
}

// MARK: - Stress Tests

@MainActor
struct SessionCollectionStressTests {

    @Test func createAndSwitchManySessions() {
        let collection = SessionCollection()

        // Create 20 sessions total (1 seeded + 19 more).
        for _ in 1..<20 {
            collection.createSession()
        }
        #expect(collection.sessions.count == 20)

        // Rapid next/previous cycling stays consistent.
        for _ in 0..<50 {
            collection.nextSession()
        }
        #expect(collection.activeSession != nil)

        for _ in 0..<50 {
            collection.previousSession()
        }
        #expect(collection.activeSession != nil)

        // Invariant: activeSessionID always references an existing session.
        #expect(collection.sessions.contains { $0.id == collection.activeSessionID })
    }

    @Test func closeAllSessionsEmptiesCollection() {
        let collection = SessionCollection()

        for _ in 1..<10 {
            collection.createSession()
        }
        #expect(collection.sessions.count == 10)

        // Close sessions from the end via explicit removeSession.
        while !collection.sessions.isEmpty {
            let lastID = collection.sessions.last!.id
            collection.removeSession(id: lastID)
        }
        // Emptying the collection is a stable state — no quit signal, and the
        // active id clears out.
        #expect(collection.sessions.isEmpty)
        #expect(collection.activeSessionID == nil)
    }

    @Test func reorderSessionsRepeatedly() {
        let collection = SessionCollection()
        for _ in 1..<10 {
            collection.createSession()
        }

        let originalIDs = collection.sessions.map(\.id)

        // Shuffle by moving first to last repeatedly.
        for _ in 0..<30 {
            collection.reorderSession(from: 0, to: collection.sessions.count - 1)
        }

        let currentIDs = Set(collection.sessions.map(\.id))
        #expect(currentIDs == Set(originalIDs))
        #expect(collection.sessions.count == 10)
    }
}
