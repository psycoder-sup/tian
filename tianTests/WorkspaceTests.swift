import Testing
import Foundation
@testable import tian

// MARK: - Workspace Tests

@MainActor
struct WorkspaceTests {
    @Test func initCreatesOneSessionWithClaudePane() {
        // A fresh workspace seeds one session with a live Claude pane and no
        // terminal panel yet.
        let ws = Workspace(name: "project")
        #expect(ws.sessions.count == 1)
        #expect(ws.sessions[0].hasLiveClaudePane)
        #expect(ws.sessions[0].terminalPanel == nil)
        #expect(ws.name == "project")
    }

    @Test func initSeedsFirstSessionWithoutCustomName() {
        // The seeded first session has no custom name — it uses its auto-derived
        // name (Claude title / directory leaf) rather than a literal "default".
        let ws = Workspace(name: "project")
        #expect(ws.sessions[0].customName == nil)
    }

    @Test func initDefaultWorkingDirectoryIsNil() {
        let ws = Workspace(name: "project")
        #expect(ws.defaultWorkingDirectory == nil)
    }

    @Test func initWithWorkingDirectory() {
        let dir = URL(filePath: "/tmp/test-project")
        let ws = Workspace(name: "project", defaultWorkingDirectory: dir)
        #expect(ws.defaultWorkingDirectory == dir)
    }

    @Test func convenienceAccessorsDelegateToSessionCollection() {
        let ws = Workspace(name: "project")
        #expect(ws.sessions.map(\.id) == ws.sessionCollection.sessions.map(\.id))
        #expect(ws.activeSessionID == ws.sessionCollection.activeSessionID)
        #expect(ws.activeSession?.id == ws.sessionCollection.activeSession?.id)
    }

    @Test func lastSessionCloseLeavesWorkspaceAliveButEmpty() async {
        // Closing the last session no longer closes the workspace. The
        // workspace stays alive with an empty session collection (its content
        // area renders the create-session empty state), and can seed a new
        // session immediately.
        let ws = Workspace(name: "project")

        let session = ws.sessionCollection.sessions[0]
        await session.requestSessionClose()

        #expect(ws.sessionCollection.sessions.isEmpty)
        #expect(ws.activeSessionID == nil)

        // The workspace is still usable — a new session can be created.
        ws.sessionCollection.createSession()
        #expect(ws.sessionCollection.sessions.count == 1)
    }

    @Test func snapshotProducesValidJSON() throws {
        let ws = Workspace(name: "my project")
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["name"] as? String == "my project")
        #expect(dict["id"] != nil)
        #expect(dict["createdAt"] != nil)
    }

    @Test func snapshotExcludesRuntimeState() throws {
        let ws = Workspace(name: "test")
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["sessionCollection"] == nil)
        #expect(dict["onEmpty"] == nil)
    }

    @Test func snapshotIncludesWorkingDirectory() throws {
        let dir = URL(filePath: "/Users/me/projects")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["defaultWorkingDirectory"] != nil)
    }

    @Test func snapshotOmitsNilWorkingDirectory() throws {
        let ws = Workspace(name: "test")
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["defaultWorkingDirectory"] == nil)
    }

    @Test func snapshotRoundTrips() throws {
        let dir = URL(filePath: "/Users/me/projects")
        let ws = Workspace(name: "my project", defaultWorkingDirectory: dir)
        let data = try JSONEncoder().encode(ws.snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        #expect(decoded.id == ws.id)
        #expect(decoded.name == "my project")
        #expect(decoded.defaultWorkingDirectory == dir)
    }

    @Test func restoreFromSnapshot() throws {
        let dir = URL(filePath: "/Users/me/projects")
        let ws = Workspace(name: "original", defaultWorkingDirectory: dir)
        let snap = ws.snapshot
        let restored = Workspace.from(snapshot: snap)
        #expect(restored.id == ws.id)
        #expect(restored.name == "original")
        #expect(restored.defaultWorkingDirectory == dir)
        #expect(restored.sessions.count == 1)
    }

    // MARK: - Inspect panel root

    /// With no live Claude worktree, `inspectPanelRoot` walks the fallback chain:
    /// session worktreePath → session default → workspace default → nil session
    /// yields the workspace default.
    @Test func inspectPanelRootFallsBackThroughWorktreeAndDefaults() {
        let ws = Workspace(
            name: "project",
            defaultWorkingDirectory: URL(fileURLWithPath: "/tmp/ws")
        )
        let withWorktree = Session(
            customName: "s", claudePane: nil, terminalPanel: nil,
            defaultWorkingDirectory: URL(fileURLWithPath: "/tmp/sess"),
            worktreePath: "/tmp/wt"
        )
        #expect(ws.inspectPanelRoot(for: withWorktree)?.path == "/tmp/wt")

        let withoutWorktree = Session(
            customName: "s", claudePane: nil, terminalPanel: nil,
            defaultWorkingDirectory: URL(fileURLWithPath: "/tmp/sess")
        )
        #expect(ws.inspectPanelRoot(for: withoutWorktree)?.path == "/tmp/sess")

        #expect(ws.inspectPanelRoot(for: nil)?.path == "/tmp/ws")
    }

    /// The Claude pane's live worktree takes precedence over every other root, so
    /// the inspect panel follows Claude after an EnterWorktree.
    @Test func inspectPanelRootPrefersClaudeWorktreeRoot() async throws {
        let repo = try makeTempGitRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        let ws = Workspace(
            name: "project",
            defaultWorkingDirectory: URL(fileURLWithPath: "/tmp/ws")
        )
        let session = Session(customName: "s", workingDirectory: repo)
        let paneID = try #require(session.claudePaneID)
        try await pollUntil(timeout: 5.0) {
            session.gitContext.paneWorktreeRoot[paneID] != nil
        }

        let expected = try #require(session.claudeWorktreeRoot).path
        #expect(ws.inspectPanelRoot(for: session)?.path == expected)
    }

    // MARK: - Git test helpers

    private func pollUntil(timeout: Double, condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for condition after \(timeout)s")
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readmePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)
        return dir
    }

    private func runGitSync(_ args: [String], in dir: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(filePath: dir)
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw WorkspaceTestError.git("git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    private enum WorkspaceTestError: Error { case git(String) }
}

// MARK: - WorkspaceCollection Tests

@MainActor
struct WorkspaceCollectionTests {
    // MARK: - Init

    @Test func initCreatesOneDefaultWorkspace() {
        let collection = WorkspaceCollection()
        #expect(collection.workspaces.count == 1)
        #expect(collection.workspaces[0].name == "default")
        #expect(collection.activeWorkspaceID == collection.workspaces[0].id)
    }

    // MARK: - Empty Collection

    @Test func emptyCollectionHasNoWorkspaces() {
        let collection = WorkspaceCollection.empty()
        #expect(collection.workspaces.isEmpty)
        #expect(collection.activeWorkspaceID == nil)
        #expect(collection.activeWorkspace == nil)
        #expect(collection.activeSessionCollection == nil)
    }

    @Test func emptyCollectionCreateWorkspaceActivates() {
        let collection = WorkspaceCollection.empty()
        let ws = collection.createWorkspace(name: "first", workingDirectory: "/tmp/proj")
        #expect(ws != nil)
        #expect(collection.workspaces.count == 1)
        #expect(collection.activeWorkspaceID == ws?.id)
        #expect(collection.activeWorkspace?.id == ws?.id)
    }

    // MARK: - Creation

    @Test func createWorkspaceStoresWorkingDirectory() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "first", workingDirectory: "/tmp/proj")
        #expect(ws?.defaultWorkingDirectory?.path == "/tmp/proj")
    }

    @Test func createWorkspaceAppendsAndActivates() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "project")
        #expect(ws != nil)
        #expect(collection.workspaces.count == 2)
        #expect(collection.activeWorkspaceID == ws?.id)
    }

    @Test func createMultipleWorkspaces() {
        let collection = WorkspaceCollection()
        let ws2 = collection.createWorkspace(name: "second")
        let ws3 = collection.createWorkspace(name: "third")
        #expect(collection.workspaces.count == 3)
        #expect(collection.activeWorkspaceID == ws3?.id)
        #expect(collection.workspaces[1].id == ws2?.id)
        #expect(collection.workspaces[2].id == ws3?.id)
    }

    @Test func createWorkspaceRejectsEmptyName() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "")
        #expect(ws == nil)
        #expect(collection.workspaces.count == 1)
    }

    @Test func createWorkspaceRejectsWhitespaceOnlyName() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "   \t\n  ")
        #expect(ws == nil)
        #expect(collection.workspaces.count == 1)
    }

    @Test func createWorkspaceTrimsWhitespace() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "  my project  ")
        #expect(ws?.name == "my project")
    }

    // MARK: - Rename

    @Test func renameWorkspaceUpdatesName() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let result = collection.renameWorkspace(id: ws.id, newName: "new")
        #expect(result)
        #expect(ws.name == "new")
    }

    @Test func renameWorkspaceRejectsEmptyName() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let result = collection.renameWorkspace(id: ws.id, newName: "")
        #expect(!result)
        #expect(ws.name == "default")
    }

    @Test func renameWorkspaceTrimsWhitespace() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        collection.renameWorkspace(id: ws.id, newName: "  new name  ")
        #expect(ws.name == "new name")
    }

    @Test func renameNonexistentWorkspaceReturnsFalse() {
        let collection = WorkspaceCollection()
        let result = collection.renameWorkspace(id: UUID(), newName: "name")
        #expect(!result)
    }

    // MARK: - Remove

    @Test func removeWorkspaceRemovesFromList() {
        let collection = WorkspaceCollection()
        let ws2 = collection.createWorkspace(name: "second")!
        collection.removeWorkspace(id: ws2.id)
        #expect(collection.workspaces.count == 1)
        #expect(collection.workspaces[0].name == "default")
    }

    @Test func removeWorkspaceActivatesNearest() {
        let collection = WorkspaceCollection()
        collection.createWorkspace(name: "second")
        let ws3 = collection.createWorkspace(name: "third")!
        let ws2ID = collection.workspaces[1].id

        collection.removeWorkspace(id: ws3.id)
        #expect(collection.activeWorkspaceID == ws2ID)
    }

    @Test func removeFirstWorkspaceActivatesRight() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        let ws2 = collection.createWorkspace(name: "second")!
        collection.activateWorkspace(id: ws1.id)

        collection.removeWorkspace(id: ws1.id)
        #expect(collection.activeWorkspaceID == ws2.id)
    }

    @Test func removeLastWorkspaceCallsOnEmpty() {
        let collection = WorkspaceCollection()
        var emptyCalled = false
        collection.onEmpty = { emptyCalled = true }
        let ws = collection.workspaces[0]

        collection.removeWorkspace(id: ws.id)
        #expect(collection.workspaces.isEmpty)
        #expect(emptyCalled)
    }

    @Test func removeLastWorkspaceEmptiesCollectionWhenNoCallback() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]

        collection.removeWorkspace(id: ws.id)
        #expect(collection.workspaces.isEmpty)
        #expect(collection.activeWorkspaceID == nil)
        #expect(collection.activeWorkspace == nil)
    }

    @Test func removeNonexistentWorkspaceIsNoOp() {
        let collection = WorkspaceCollection()
        collection.removeWorkspace(id: UUID())
        #expect(collection.workspaces.count == 1)
    }

    // MARK: - Activate

    @Test func activateWorkspaceChangesActiveID() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")

        collection.activateWorkspace(id: ws1.id)
        #expect(collection.activeWorkspaceID == ws1.id)
    }

    @Test func activateNonexistentWorkspaceIsNoOp() {
        let collection = WorkspaceCollection()
        let originalID = collection.activeWorkspaceID
        collection.activateWorkspace(id: UUID())
        #expect(collection.activeWorkspaceID == originalID)
    }

    // MARK: - Navigation

    @Test func nextWorkspaceWraps() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")

        collection.activateWorkspace(id: ws1.id)
        collection.nextWorkspace()
        #expect(collection.activeWorkspaceID == collection.workspaces[1].id)

        collection.nextWorkspace()
        #expect(collection.activeWorkspaceID == ws1.id)
    }

    @Test func previousWorkspaceWraps() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")

        collection.activateWorkspace(id: ws1.id)
        collection.previousWorkspace()
        #expect(collection.activeWorkspaceID == collection.workspaces[1].id)
    }

    // MARK: - Reorder

    @Test func reorderWorkspace() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        let ws2 = collection.createWorkspace(name: "second")!

        collection.reorderWorkspace(from: 0, to: 1)
        #expect(collection.workspaces[0].id == ws2.id)
        #expect(collection.workspaces[1].id == ws1.id)
    }

    @Test func reorderOutOfBoundsIsNoOp() {
        let collection = WorkspaceCollection()
        collection.reorderWorkspace(from: 0, to: 5)
        #expect(collection.workspaces.count == 1)
    }

    @Test func reorderSameIndexIsNoOp() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        collection.reorderWorkspace(from: 0, to: 0)
        #expect(collection.workspaces[0].id == ws.id)
    }

    // MARK: - Reorder Destination Index (slot → destination mapping)

    @Test func reorderDestinationMovesDown() {
        // Dropping row 0 into the slot before row 2 lands at index 1 after the
        // remove-then-insert shift.
        #expect(WorkspaceCollection.reorderDestinationIndex(source: 0, targetSlot: 2) == 1)
    }

    @Test func reorderDestinationMovesUp() {
        // Moving up doesn't shift: the slot before row 0 is destination 0.
        #expect(WorkspaceCollection.reorderDestinationIndex(source: 2, targetSlot: 0) == 0)
    }

    @Test func reorderDestinationDropsAtEnd() {
        // The end-of-list slot (count) for a 3-item list maps to the last index.
        #expect(WorkspaceCollection.reorderDestinationIndex(source: 0, targetSlot: 3) == 2)
    }

    @Test func reorderDestinationJustBelowSelfIsNoOp() {
        // The slot immediately below the item resolves back to its own index.
        #expect(WorkspaceCollection.reorderDestinationIndex(source: 1, targetSlot: 2) == 1)
    }

    @Test func reorderDestinationOntoSelfIsNoOp() {
        // The slot immediately above the item (its own row) resolves to itself.
        #expect(WorkspaceCollection.reorderDestinationIndex(source: 1, targetSlot: 1) == 1)
    }

    @Test func reorderToEndSlotProducesExpectedOrder() {
        // Integration: dropping the first workspace into the end slot leaves it
        // last, with the other two shifted up one — matching the visual drop.
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        let ws2 = collection.createWorkspace(name: "second")!
        let ws3 = collection.createWorkspace(name: "third")!

        let dest = WorkspaceCollection.reorderDestinationIndex(source: 0, targetSlot: 3)
        collection.reorderWorkspace(from: 0, to: dest)

        #expect(collection.workspaces.map(\.id) == [ws2.id, ws3.id, ws1.id])
    }

    // MARK: - Insertion Slot (drag pointer-Y → slot mapping)

    @Test func insertionSlotAboveFirstRowIsZero() {
        // A pointer above the first row's midpoint lands in the top slot.
        #expect(WorkspaceReorderGeometry.insertionSlot(forY: 5, rowMidYs: [10, 30, 50]) == 0)
    }

    @Test func insertionSlotBetweenRowsCountsRowsAbove() {
        // The slot equals the number of row midpoints strictly above the pointer.
        #expect(WorkspaceReorderGeometry.insertionSlot(forY: 20, rowMidYs: [10, 30, 50]) == 1)
        #expect(WorkspaceReorderGeometry.insertionSlot(forY: 40, rowMidYs: [10, 30, 50]) == 2)
    }

    @Test func insertionSlotBelowLastRowIsCount() {
        // A pointer past the last midpoint lands in the end-of-list slot (count).
        #expect(WorkspaceReorderGeometry.insertionSlot(forY: 100, rowMidYs: [10, 30, 50]) == 3)
    }

    @Test func insertionSlotOnMidpointExcludesThatRow() {
        // Boundary: the filter is strict `<`, so a pointer exactly on a row's
        // midpoint does NOT count that row as above — only the rows strictly
        // above it (here just midY 10) contribute, yielding slot 1.
        #expect(WorkspaceReorderGeometry.insertionSlot(forY: 30, rowMidYs: [10, 30, 50]) == 1)
    }

    @Test func insertionSlotEmptyRowsIsZero() {
        // With no rows measured yet, every pointer maps to slot 0.
        #expect(WorkspaceReorderGeometry.insertionSlot(forY: 42, rowMidYs: []) == 0)
    }

    // MARK: - Reorder Shuffle Offset (live-gap offsets during drag)

    @Test func shuffleOffsetDragDownShiftsInterveningRowsUp() {
        // Dragging row 0 down to slot 3: the rows it passes (1, 2) slide up by the
        // dragged height to open the gap; the row at the target slot (3) and the
        // dragged row's own origin (0) stay put.
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 1, source: 0, slot: 3, draggedHeight: 10) == -10)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 2, source: 0, slot: 3, draggedHeight: 10) == -10)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 3, source: 0, slot: 3, draggedHeight: 10) == 0)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 0, source: 0, slot: 3, draggedHeight: 10) == 0)
    }

    @Test func shuffleOffsetDragUpShiftsInterveningRowsDown() {
        // Dragging row 3 up to slot 1: the rows now below the gap (1, 2) slide down
        // by the dragged height; rows outside the span (0, 3) stay put.
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 1, source: 3, slot: 1, draggedHeight: 10) == 10)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 2, source: 3, slot: 1, draggedHeight: 10) == 10)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 0, source: 3, slot: 1, draggedHeight: 10) == 0)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 3, source: 3, slot: 1, draggedHeight: 10) == 0)
    }

    @Test func shuffleOffsetNoOpZoneOpensNoGap() {
        // The two no-op slots (its own row and the slot just below it) shift nothing.
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 0, source: 1, slot: 1, draggedHeight: 10) == 0)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 2, source: 1, slot: 1, draggedHeight: 10) == 0)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 0, source: 1, slot: 2, draggedHeight: 10) == 0)
        #expect(WorkspaceReorderGeometry.reorderShuffleOffset(index: 2, source: 1, slot: 2, draggedHeight: 10) == 0)
    }

    // MARK: - Computed Properties

    @Test func activeWorkspaceReturnsCorrectWorkspace() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        #expect(collection.activeWorkspace?.id == ws.id)
    }

    @Test func activeSessionCollectionReturnsCorrectCollection() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        #expect(collection.activeSessionCollection === ws.sessionCollection)
    }

    // MARK: - Session Close (workspace survives)

    @Test func explicitSessionCloseLeavesWorkspaceAlive() async {
        // An explicit `requestSessionClose` on the last session empties the
        // workspace's session collection but does NOT remove the workspace or
        // empty the collection — the workspace stays alive with a create-session
        // empty state.
        let collection = WorkspaceCollection()
        var emptyCalled = false
        collection.onEmpty = { emptyCalled = true }
        let ws = collection.workspaces[0]
        let session = ws.sessionCollection.sessions[0]

        await session.requestSessionClose()

        #expect(ws.sessionCollection.sessions.isEmpty)
        #expect(collection.workspaces.count == 1)
        #expect(!emptyCalled)
    }

    @Test func terminalPaneCloseDoesNotCascade() throws {
        // Closing the last terminal pane drops the panel; the session and the
        // owning workspace both stay alive.
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let session = ws.sessionCollection.sessions[0]
        session.showTerminal()

        let panel = try #require(session.terminalPanel)
        panel.closePane(paneID: panel.splitTree.focusedPaneID)

        #expect(session.terminalPanel == nil)
        #expect(ws.sessionCollection.sessions.count == 1)
        #expect(collection.workspaces.count == 1)
    }

    @Test func claudePaneCloseClosesSessionButKeepsWorkspace() throws {
        // Closing the Claude pane closes the whole session (the Claude process
        // already exited). As the workspace's last session, this empties the
        // session collection but the workspace itself stays in the collection.
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let session = ws.sessionCollection.sessions[0]

        let claude = try #require(session.claudePane)
        claude.closePane(paneID: claude.splitTree.focusedPaneID)

        #expect(ws.sessionCollection.sessions.isEmpty)
        #expect(collection.workspaces.count == 1)
    }

    @Test func cascadeStopsWhenSessionsRemain() async {
        // Explicitly closing one session when another remains leaves the
        // workspace (and collection) alive.
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        ws.sessionCollection.createSession()  // 2 sessions
        let session0 = ws.sessionCollection.sessions[0]

        await session0.requestSessionClose()

        #expect(ws.sessionCollection.sessions.count == 1)
        #expect(collection.workspaces.count == 1)
    }

    @Test func closingWorkspacesLastSessionKeepsBothWorkspaces() async {
        // Closing workspace 1's last session empties it but does NOT remove it,
        // so both workspaces remain in the collection.
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")
        let session = ws1.sessionCollection.sessions[0]

        await session.requestSessionClose()

        #expect(collection.workspaces.count == 2)
        #expect(ws1.sessionCollection.sessions.isEmpty)
    }
}
