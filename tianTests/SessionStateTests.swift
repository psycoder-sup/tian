import Testing
import Foundation
@testable import tian

// MARK: - SessionState Round-Trip Tests (v7)

struct SessionStateRoundTripTests {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func roundTripSingleSession() throws {
        let sessionID = UUID()
        let paneID = UUID()
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "default",
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: "/Users/me/project",
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "default",
                            defaultWorkingDirectory: "/Users/me/project",
                            claudePane: PaneLeafState(paneID: paneID, workingDirectory: "/Users/me/project"),
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude
                        )
                    ],
                    windowFrame: WindowFrame(x: 100, y: 200, width: 800, height: 600),
                    isFullscreen: false
                )
            ]
        )

        let data = try Self.makeEncoder().encode(state)
        let decoded = try Self.makeDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
    }

    @Test func roundTripSessionWithTerminalTree() throws {
        let sessionID = UUID()
        let claudePaneID = UUID()
        let termA = UUID()
        let termB = UUID()
        let termC = UUID()

        let terminalRoot: PaneNodeState = .split(PaneSplitState(
            direction: "horizontal",
            ratio: 0.5,
            first: .pane(PaneLeafState(paneID: termA, workingDirectory: "/tmp/a")),
            second: .split(PaneSplitState(
                direction: "vertical",
                ratio: 0.3,
                first: .pane(PaneLeafState(paneID: termB, workingDirectory: "/tmp/b")),
                second: .pane(PaneLeafState(paneID: termC, workingDirectory: "/tmp/c"))
            ))
        ))

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 2000000),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "project",
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: nil,
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "with-terminal",
                            defaultWorkingDirectory: nil,
                            worktreePath: nil,
                            claudePane: PaneLeafState(paneID: claudePaneID, workingDirectory: "/tmp"),
                            terminalRoot: terminalRoot,
                            terminalFocusedPaneId: termB,
                            terminalVisible: true,
                            dockPosition: .right,
                            splitRatio: 0.6,
                            focusedArea: .terminal
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let data = try Self.makeEncoder().encode(state)
        let decoded = try Self.makeDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
    }

    @Test func roundTripNilClaudePane() throws {
        // The empty-Claude placeholder persists as a nil claudePane. It stays
        // legal even when the session still carries a terminal tree.
        let sessionID = UUID()
        let termID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 2500000),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "empty-claude",
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: nil,
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "empty",
                            defaultWorkingDirectory: nil,
                            claudePane: nil,
                            terminalRoot: .pane(PaneLeafState(paneID: termID, workingDirectory: "/tmp")),
                            terminalFocusedPaneId: termID,
                            terminalVisible: true,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .terminal
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let data = try Self.makeEncoder().encode(state)
        let decoded = try Self.makeDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.workspaces[0].sessions[0].claudePane == nil)
    }

    @Test func roundTripMultipleWorkspacesAndSessions() throws {
        let wsID1 = UUID()
        let wsID2 = UUID()
        let sessionID1 = UUID()
        let sessionID2 = UUID()
        let siblingID = UUID()
        let paneID1 = UUID()
        let paneID2 = UUID()
        let siblingPaneID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 3000000),
            activeWorkspaceId: wsID1,
            workspaces: [
                WorkspaceState(
                    id: wsID1,
                    name: "Workspace 1",
                    activeSessionId: sessionID1,
                    defaultWorkingDirectory: "/Users/me/ws1",
                    sessions: [
                        SessionRecord(
                            id: sessionID1,
                            customName: "Session 1",
                            defaultWorkingDirectory: "/Users/me/ws1",
                            claudePane: PaneLeafState(paneID: paneID1, workingDirectory: "/Users/me/ws1"),
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude
                        ),
                        // A sibling nested under the primary via parentSessionID.
                        SessionRecord(
                            id: siblingID,
                            customName: "Session 1 (2)",
                            defaultWorkingDirectory: "/Users/me/ws1",
                            claudePane: PaneLeafState(paneID: siblingPaneID, workingDirectory: "/Users/me/ws1"),
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude,
                            parentSessionID: sessionID1
                        )
                    ],
                    windowFrame: WindowFrame(x: 0, y: 0, width: 1920, height: 1080),
                    isFullscreen: true
                ),
                WorkspaceState(
                    id: wsID2,
                    name: "Workspace 2",
                    activeSessionId: sessionID2,
                    defaultWorkingDirectory: nil,
                    sessions: [
                        SessionRecord(
                            id: sessionID2,
                            customName: "Session 2",
                            defaultWorkingDirectory: "/tmp/ws2",
                            claudePane: PaneLeafState(paneID: paneID2, workingDirectory: "/tmp/ws2"),
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let data = try Self.makeEncoder().encode(state)
        let decoded = try Self.makeDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.workspaces[0].sessions[1].parentSessionID == sessionID1)
    }

    @Test func nilOptionalsDecodeAsNil() throws {
        // A session with nil default directory / worktree path round-trips with
        // those fields nil (encoder omits them; decoder restores nil).
        let sessionID = UUID()
        let paneID = UUID()
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 4000000),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "ws",
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: nil,
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "s",
                            defaultWorkingDirectory: nil,
                            worktreePath: nil,
                            claudePane: PaneLeafState(paneID: paneID, workingDirectory: "/tmp"),
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let data = try Self.makeEncoder().encode(state)
        let decoded = try Self.makeDecoder().decode(SessionState.self, from: data)

        #expect(decoded.workspaces[0].sessions[0].defaultWorkingDirectory == nil)
        #expect(decoded.workspaces[0].sessions[0].worktreePath == nil)
        #expect(decoded.workspaces[0].sessions[0].terminalRoot == nil)
        #expect(decoded.workspaces[0].sessions[0].terminalFocusedPaneId == nil)
    }
}

// MARK: - PaneNodeState JSON Format Tests

struct PaneNodeStateEncodingTests {
    @Test func leafEncodesWithTypePane() throws {
        let leaf = PaneNodeState.pane(PaneLeafState(
            paneID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            workingDirectory: "/tmp/test"
        ))
        let data = try JSONEncoder().encode(leaf)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["type"] as? String == "pane")
        #expect(dict["paneID"] as? String == "11111111-1111-1111-1111-111111111111")
        #expect(dict["workingDirectory"] as? String == "/tmp/test")
    }

    @Test func splitEncodesWithTypeSplit() throws {
        let split = PaneNodeState.split(PaneSplitState(
            direction: "horizontal",
            ratio: 0.6,
            first: .pane(PaneLeafState(
                paneID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                workingDirectory: "/tmp/a"
            )),
            second: .pane(PaneLeafState(
                paneID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                workingDirectory: "/tmp/b"
            ))
        ))
        let data = try JSONEncoder().encode(split)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["type"] as? String == "split")
        #expect(dict["direction"] as? String == "horizontal")
        #expect(dict["ratio"] as? Double == 0.6)
        #expect(dict["first"] != nil)
        #expect(dict["second"] != nil)
    }

    @Test func leafEncodesRestoreCommand() throws {
        let leaf = PaneNodeState.pane(PaneLeafState(
            paneID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            workingDirectory: "/tmp/test",
            restoreCommand: "claude --resume abc123"
        ))
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(PaneNodeState.self, from: data)
        #expect(decoded == leaf)

        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["restoreCommand"] as? String == "claude --resume abc123")
    }

    @Test func leafDecodesWithoutRestoreCommand() throws {
        let json = """
        {"type": "pane", "paneID": "11111111-1111-1111-1111-111111111111", "workingDirectory": "/tmp/test"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PaneNodeState.self, from: data)

        if case .pane(let leaf) = decoded {
            #expect(leaf.restoreCommand == nil)
            #expect(leaf.workingDirectory == "/tmp/test")
        } else {
            Issue.record("Expected .pane")
        }
    }

    @Test func unknownTypeThrowsDecodingError() throws {
        let json = """
        {"type": "unknown", "paneID": "11111111-1111-1111-1111-111111111111"}
        """
        let data = json.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PaneNodeState.self, from: data)
        }
    }
}

// MARK: - PaneNode → PaneNodeState Conversion Tests

struct PaneNodeConversionTests {
    @Test func leafConversion() {
        let paneID = UUID()
        let node = PaneNode.leaf(paneID: paneID, workingDirectory: "/tmp/test")
        let state = node.toState()

        if case .pane(let leaf) = state {
            #expect(leaf.paneID == paneID)
            #expect(leaf.workingDirectory == "/tmp/test")
        } else {
            Issue.record("Expected .pane, got .split")
        }
    }

    @Test func splitConversion() {
        let paneA = UUID()
        let paneB = UUID()
        let node = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            ratio: 0.4,
            first: .leaf(paneID: paneA, workingDirectory: "/a"),
            second: .leaf(paneID: paneB, workingDirectory: "/b")
        )
        let state = node.toState()

        if case .split(let split) = state {
            #expect(split.direction == "horizontal")
            #expect(split.ratio == 0.4)
            if case .pane(let first) = split.first {
                #expect(first.paneID == paneA)
            } else {
                Issue.record("Expected first to be .pane")
            }
            if case .pane(let second) = split.second {
                #expect(second.paneID == paneB)
            } else {
                Issue.record("Expected second to be .pane")
            }
        } else {
            Issue.record("Expected .split, got .pane")
        }
    }

    @Test func nestedSplitConversion() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let node = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(paneID: paneA, workingDirectory: "/a"),
            second: .split(
                id: UUID(),
                direction: .vertical,
                ratio: 0.7,
                first: .leaf(paneID: paneB, workingDirectory: "/b"),
                second: .leaf(paneID: paneC, workingDirectory: "/c")
            )
        )
        let state = node.toState()

        if case .split(let outer) = state {
            #expect(outer.direction == "horizontal")
            if case .split(let inner) = outer.second {
                #expect(inner.direction == "vertical")
                #expect(inner.ratio == 0.7)
            } else {
                Issue.record("Expected nested .split")
            }
        } else {
            Issue.record("Expected .split")
        }
    }
}

// MARK: - SplitDirection Conversion Tests

struct SplitDirectionConversionTests {
    @Test func horizontalStateValue() {
        #expect(SplitDirection.horizontal.stateValue == "horizontal")
    }

    @Test func verticalStateValue() {
        #expect(SplitDirection.vertical.stateValue == "vertical")
    }

    @Test func fromHorizontal() {
        #expect(SplitDirection.from(stateValue: "horizontal") == .horizontal)
    }

    @Test func fromVertical() {
        #expect(SplitDirection.from(stateValue: "vertical") == .vertical)
    }

    @Test func fromInvalidReturnsNil() {
        #expect(SplitDirection.from(stateValue: "diagonal") == nil)
    }
}

// MARK: - Snapshot from Live Model Tests (v7)

@MainActor
struct SessionSnapshotTests {
    @Test func snapshotCapturesWorkspaceHierarchy() {
        let collection = WorkspaceCollection()
        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.version == SessionSerializer.currentVersion)
        #expect(snapshot.activeWorkspaceId == collection.activeWorkspaceID)
        #expect(snapshot.workspaces.count == 1)

        let ws = snapshot.workspaces[0]
        #expect(ws.name == "default")
        // v7: a fresh workspace seeds exactly one session with a live Claude
        // pane and no terminal panel yet.
        #expect(ws.sessions.count == 1)
        #expect(ws.sessions[0].claudePane != nil)
        #expect(ws.sessions[0].terminalRoot == nil)
        #expect(ws.sessions[0].terminalVisible == false)
        #expect(ws.sessions[0].focusedArea == .claude)
    }

    @Test func snapshotCapturesMultipleWorkspaces() {
        let collection = WorkspaceCollection()
        collection.createWorkspace(name: "second")

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces.count == 2)
        #expect(snapshot.workspaces[0].name == "default")
        #expect(snapshot.workspaces[1].name == "second")
    }

    @Test func snapshotDropsEmptyWorkspaces() {
        // Closing a workspace's last session leaves it alive in-app but with no
        // sessions. Persisting an empty workspace would make
        // `SessionRestorer.validate` throw on read and discard the ENTIRE state
        // file, so the snapshot must exclude zero-session workspaces.
        let collection = WorkspaceCollection()
        let populated = collection.workspaces[0]
        let empty = collection.createWorkspace(name: "empty")!
        empty.sessionCollection.removeSession(id: empty.sessionCollection.sessions[0].id)
        #expect(empty.sessionCollection.sessions.isEmpty)

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces.count == 1)
        #expect(snapshot.workspaces[0].id == populated.id)
        #expect(snapshot.workspaces.allSatisfy { !$0.sessions.isEmpty })
    }

    @Test func snapshotCapturesActiveIDs() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let session = ws.sessionCollection.activeSession!
        let focusedPaneID = session.claudePane!.splitTree.focusedPaneID

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.activeWorkspaceId == ws.id)
        #expect(snapshot.workspaces[0].activeSessionId == session.id)
        #expect(snapshot.workspaces[0].sessions[0].claudePane?.paneID == focusedPaneID)
    }

    @Test func snapshotCapturesWorkingDirectory() {
        let dir = URL(filePath: "/tmp/project")
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        ws.setDefaultWorkingDirectory(dir)

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].defaultWorkingDirectory == "/tmp/project")
    }

    @Test func snapshotCapturesSessionDefaultDirectory() {
        let collection = WorkspaceCollection()
        let session = collection.workspaces[0].sessionCollection.activeSession!
        session.defaultWorkingDirectory = URL(filePath: "/tmp/session-dir")

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].sessions[0].defaultWorkingDirectory == "/tmp/session-dir")
    }

    @Test func snapshotCapturesTerminalPanel() {
        let collection = WorkspaceCollection()
        let session = collection.workspaces[0].sessionCollection.activeSession!
        session.showTerminal()

        let snapshot = SessionSerializer.snapshot(from: collection)

        let record = snapshot.workspaces[0].sessions[0]
        #expect(record.terminalRoot != nil)
        #expect(record.terminalFocusedPaneId != nil)
        #expect(record.terminalVisible == true)
        // showTerminal moves focus to the terminal area.
        #expect(record.focusedArea == .terminal)
        // The Claude side stays a single leaf.
        #expect(record.claudePane != nil)
    }

    @Test func snapshotCapturesRestoreCommand() {
        let collection = WorkspaceCollection()
        let session = collection.workspaces[0].sessionCollection.activeSession!
        let pvm = session.claudePane!
        let paneID = pvm.splitTree.focusedPaneID
        pvm.setRestoreCommand(paneID: paneID, command: "claude --resume test123")

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].sessions[0].claudePane?.restoreCommand == "claude --resume test123")
    }

    @Test func snapshotNilRestoreCommandForFreshSession() {
        let collection = WorkspaceCollection()

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].sessions[0].claudePane?.restoreCommand == nil)
    }

    /// The Claude side is always a single leaf. If a stray split ever slipped
    /// into the Claude pane's tree, the serializer collapses it to the
    /// depth-first first leaf rather than dropping the session.
    @Test func snapshotCollapsesStraySplitClaudePaneToFirstLeaf() {
        let leafA = UUID()
        let leafB = UUID()
        let split: PaneNodeState = .split(PaneSplitState(
            direction: "horizontal",
            ratio: 0.5,
            first: .pane(PaneLeafState(paneID: leafA, workingDirectory: "/tmp/a")),
            second: .pane(PaneLeafState(paneID: leafB, workingDirectory: "/tmp/b"))
        ))
        let claudePVM = PaneViewModel.fromState(split, focusedPaneID: leafA, kind: .claude)
        let session = Session(
            id: UUID(),
            customName: "stray-split",
            claudePane: claudePVM,
            terminalPanel: nil,
            focusedArea: .claude
        )
        let sessionCollection = SessionCollection(
            sessions: [session],
            activeSessionID: session.id,
            workspaceDefaultDirectory: nil
        )
        let workspace = Workspace(
            id: UUID(),
            name: "ws",
            defaultWorkingDirectory: nil,
            sessionCollection: sessionCollection
        )
        let collection = WorkspaceCollection(workspaces: [workspace], activeWorkspaceID: workspace.id)

        let snapshot = SessionSerializer.snapshot(from: collection)

        let record = snapshot.workspaces[0].sessions[0]
        #expect(record.claudePane?.paneID == leafA)
        #expect(record.claudePane?.workingDirectory == "/tmp/a")
    }
}

// MARK: - Atomic Write Tests

struct SessionSerializerWriteTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleState() -> SessionState {
        SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: UUID(),
            workspaces: []
        )
    }

    @Test func encodeProducesValidJSON() throws {
        let state = sampleState()
        let data = try SessionSerializer.encode(state)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["version"] as? Int == SessionSerializer.currentVersion)
        #expect(dict["savedAt"] != nil)
        #expect(dict["activeWorkspaceId"] != nil)
        #expect(dict["workspaces"] as? [Any] != nil)
    }

    @Test func encodeDateIsISO8601() throws {
        let state = sampleState()
        let data = try SessionSerializer.encode(state)
        let json = String(data: data, encoding: .utf8)!

        // ISO 8601 dates contain "T" separator and end with "Z" or timezone
        #expect(json.contains("1970-01-12T"))
    }
}

// MARK: - SessionStateMigrator Tests

struct SessionStateMigratorTests {
    @Test func currentVersionPassesThrough() throws {
        let json: [String: Any] = [
            "version": SessionStateMigrator.currentVersion,
            "savedAt": "2026-01-01T00:00:00Z",
            "activeWorkspaceId": UUID().uuidString,
            "workspaces": []
        ]

        let result = try SessionStateMigrator.migrateIfNeeded(json: json)
        #expect(result["version"] as? Int == SessionStateMigrator.currentVersion)
    }

    @Test func futureVersionThrows() {
        let json: [String: Any] = [
            "version": SessionStateMigrator.currentVersion + 1,
            "savedAt": "2026-01-01T00:00:00Z",
            "activeWorkspaceId": UUID().uuidString,
            "workspaces": []
        ]

        #expect(throws: SessionStateMigrator.MigrationError.self) {
            try SessionStateMigrator.migrateIfNeeded(json: json)
        }
    }

    @Test func missingVersionThrows() {
        let json: [String: Any] = [
            "savedAt": "2026-01-01T00:00:00Z",
            "workspaces": []
        ]

        #expect(throws: SessionStateMigrator.MigrationError.self) {
            try SessionStateMigrator.migrateIfNeeded(json: json)
        }
    }

    @Test func futureVersionDataReturnsNil() throws {
        let json: [String: Any] = [
            "version": 999,
            "savedAt": "2026-01-01T00:00:00Z",
            "activeWorkspaceId": UUID().uuidString,
            "workspaces": []
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try SessionStateMigrator.migrateIfNeeded(data: data)
        #expect(result == nil)
    }

    @Test func currentVersionDataPassesThrough() throws {
        let json: [String: Any] = [
            "version": SessionStateMigrator.currentVersion,
            "savedAt": "2026-01-01T00:00:00Z",
            "activeWorkspaceId": UUID().uuidString,
            "workspaces": []
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try SessionStateMigrator.migrateIfNeeded(data: data)
        #expect(result != nil)
    }
}

// MARK: - WindowFrame Tests

struct WindowFrameTests {
    @Test func roundTrip() throws {
        let frame = WindowFrame(x: 100.5, y: 200.0, width: 1920.0, height: 1080.0)
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(WindowFrame.self, from: data)
        #expect(decoded == frame)
    }

    @Test func encodesToExpectedKeys() throws {
        let frame = WindowFrame(x: 10, y: 20, width: 800, height: 600)
        let data = try JSONEncoder().encode(frame)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["x"] as? Double == 10)
        #expect(dict["y"] as? Double == 20)
        #expect(dict["width"] as? Double == 800)
        #expect(dict["height"] as? Double == 600)
    }
}

// MARK: - SessionRecord worktreePath Tests

struct SessionRecordWorktreePathTests {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func encodesAndDecodesWithWorktreePath() throws {
        let paneID = UUID()
        let record = SessionRecord(
            id: UUID(),
            customName: "feature-branch",
            defaultWorkingDirectory: "/tmp/repo/.worktrees/feature",
            worktreePath: "/tmp/repo/.worktrees/feature",
            claudePane: PaneLeafState(paneID: paneID, workingDirectory: "/tmp/repo/.worktrees/feature"),
            terminalVisible: false,
            dockPosition: .right,
            splitRatio: 0.7,
            focusedArea: .claude
        )

        let data = try Self.makeEncoder().encode(record)
        let decoded = try Self.makeDecoder().decode(SessionRecord.self, from: data)

        #expect(decoded == record)
        #expect(decoded.worktreePath == "/tmp/repo/.worktrees/feature")
    }

    @Test func encodesAndDecodesWithNilWorktreePath() throws {
        let paneID = UUID()
        let record = SessionRecord(
            id: UUID(),
            customName: "default",
            defaultWorkingDirectory: "/tmp",
            claudePane: PaneLeafState(paneID: paneID, workingDirectory: "/tmp"),
            terminalVisible: false,
            dockPosition: .bottom,
            splitRatio: 0.7,
            focusedArea: .claude
        )

        let data = try Self.makeEncoder().encode(record)
        let decoded = try Self.makeDecoder().decode(SessionRecord.self, from: data)

        #expect(decoded == record)
        #expect(decoded.worktreePath == nil)
    }
}

// MARK: - Snapshot worktreePath Tests (v7)

@MainActor
struct SessionSnapshotWorktreePathTests {
    @Test func snapshotIncludesWorktreePath() {
        let collection = WorkspaceCollection()
        let session = collection.workspaces[0].sessionCollection.activeSession!
        let worktreeURL = URL(filePath: "/tmp/repo/.worktrees/feature-x")
        session.worktreePath = worktreeURL

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].sessions[0].worktreePath == "/tmp/repo/.worktrees/feature-x")
    }

    @Test func snapshotNilWorktreePathForRegularSession() {
        let collection = WorkspaceCollection()

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].sessions[0].worktreePath == nil)
    }
}

// MARK: - Migration v1→v7 Chain Tests

struct SessionMigrationV1ChainTests {
    @Test func migratesV1ToCurrentVersionSuccessfully() throws {
        let json: [String: Any] = [
            "version": 1,
            "savedAt": "2026-01-01T00:00:00Z",
            "activeWorkspaceId": UUID().uuidString,
            "workspaces": [
                [
                    "id": UUID().uuidString,
                    "name": "default",
                    "activeSpaceId": UUID().uuidString,
                    "defaultWorkingDirectory": "/tmp",
                    "spaces": [] as [[String: Any]],
                    "windowFrame": NSNull(),
                    "isFullscreen": NSNull()
                ] as [String: Any]
            ]
        ]

        let result = try SessionStateMigrator.migrateIfNeeded(json: json)
        #expect(result["version"] as? Int == SessionStateMigrator.currentVersion)
    }

    @Test func v1DataMigratesToCurrentVersion() throws {
        let json: [String: Any] = [
            "version": 1,
            "savedAt": "2026-01-01T00:00:00Z",
            "activeWorkspaceId": UUID().uuidString,
            "workspaces": []
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try SessionStateMigrator.migrateIfNeeded(data: data)
        #expect(result != nil)

        let migrated = try JSONSerialization.jsonObject(with: result!) as! [String: Any]
        #expect(migrated["version"] as? Int == SessionStateMigrator.currentVersion)
    }
}

// MARK: - Restore Command Round-Trip Tests (v7)

struct SessionRecordRestoreCommandRoundTripTests {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func roundTripClaudePaneRestoreCommand() throws {
        let paneID = UUID()
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: "/tmp",
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "default",
                            defaultWorkingDirectory: nil,
                            claudePane: PaneLeafState(
                                paneID: paneID,
                                workingDirectory: "/tmp",
                                restoreCommand: "claude --resume abc123"
                            ),
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let data = try Self.makeEncoder().encode(state)
        let decoded = try Self.makeDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.workspaces[0].sessions[0].claudePane?.restoreCommand == "claude --resume abc123")
    }

    @Test func roundTripTerminalTreeMixedRestoreCommands() throws {
        let paneA = UUID()
        let paneB = UUID()
        let claudePaneID = UUID()
        let sessionID = UUID()
        let wsID = UUID()

        let terminalRoot: PaneNodeState = .split(PaneSplitState(
            direction: "horizontal",
            ratio: 0.5,
            first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp/a", restoreCommand: "claude --resume sess1")),
            second: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp/b"))
        ))

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 2000000),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: nil,
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "default",
                            defaultWorkingDirectory: nil,
                            claudePane: PaneLeafState(paneID: claudePaneID, workingDirectory: "/tmp"),
                            terminalRoot: terminalRoot,
                            terminalFocusedPaneId: paneA,
                            terminalVisible: true,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .terminal
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let data = try Self.makeEncoder().encode(state)
        let decoded = try Self.makeDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
        if case .split(let split) = decoded.workspaces[0].sessions[0].terminalRoot {
            if case .pane(let first) = split.first {
                #expect(first.restoreCommand == "claude --resume sess1")
            } else {
                Issue.record("Expected .pane for first")
            }
            if case .pane(let second) = split.second {
                #expect(second.restoreCommand == nil)
            } else {
                Issue.record("Expected .pane for second")
            }
        } else {
            Issue.record("Expected .split")
        }
    }
}

// MARK: - PaneViewModel Restore Command Tests

@MainActor
struct RestoreCommandPaneViewModelTests {
    @Test func fromStatePopulatesRestoreCommands() {
        let paneID = UUID()
        let root: PaneNodeState = .pane(PaneLeafState(
            paneID: paneID,
            workingDirectory: "/tmp",
            restoreCommand: "claude --resume xyz"
        ))

        let pvm = PaneViewModel.fromState(root, focusedPaneID: paneID)

        #expect(pvm.restoreCommand(for: paneID) == "claude --resume xyz")
    }

    @Test func fromStateWithoutRestoreCommandHasNilRestoreCommand() {
        let paneID = UUID()
        let root: PaneNodeState = .pane(PaneLeafState(
            paneID: paneID,
            workingDirectory: "/tmp"
        ))

        let pvm = PaneViewModel.fromState(root, focusedPaneID: paneID)

        #expect(pvm.restoreCommand(for: paneID) == nil)
    }
}
