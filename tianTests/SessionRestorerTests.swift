import Testing
import Foundation
@testable import tian

// MARK: - Shared v7 fixture builders

/// Builds a single-Claude-pane session record (no terminal panel by default).
private func makeClaudeSession(
    id: UUID = UUID(),
    paneID: UUID = UUID(),
    name: String = "default",
    workingDirectory: String = "/tmp",
    defaultWorkingDirectory: String? = nil,
    worktreePath: String? = nil,
    claudePane: PaneLeafState? = nil,
    terminalRoot: PaneNodeState? = nil,
    terminalFocusedPaneId: UUID? = nil,
    terminalVisible: Bool = false,
    dockPosition: DockPosition = .bottom,
    splitRatio: Double = 0.7,
    focusedArea: PaneKind = .claude,
    parentSessionID: UUID? = nil
) -> SessionRecord {
    SessionRecord(
        id: id,
        customName: name,
        defaultWorkingDirectory: defaultWorkingDirectory,
        worktreePath: worktreePath,
        claudePane: claudePane ?? PaneLeafState(paneID: paneID, workingDirectory: workingDirectory),
        terminalRoot: terminalRoot,
        terminalFocusedPaneId: terminalFocusedPaneId,
        terminalVisible: terminalVisible,
        dockPosition: dockPosition,
        splitRatio: splitRatio,
        focusedArea: focusedArea,
        parentSessionID: parentSessionID
    )
}

private func makeWorkspaceState(
    id: UUID = UUID(),
    name: String = "ws",
    activeSessionId: UUID,
    defaultWorkingDirectory: String? = "/tmp",
    sessions: [SessionRecord]
) -> WorkspaceState {
    WorkspaceState(
        id: id,
        name: name,
        activeSessionId: activeSessionId,
        defaultWorkingDirectory: defaultWorkingDirectory,
        sessions: sessions,
        windowFrame: nil,
        isFullscreen: nil
    )
}

// MARK: - Decode Tests

struct SessionRestorerDecodeTests {
    private static func makeState(
        workspaceCount: Int = 1,
        activeWorkspaceIndex: Int = 0
    ) -> SessionState {
        let workspaces = (0..<workspaceCount).map { i -> WorkspaceState in
            let sessionID = UUID()
            return makeWorkspaceState(
                name: "Workspace \(i + 1)",
                activeSessionId: sessionID,
                sessions: [makeClaudeSession(id: sessionID)]
            )
        }

        return SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: workspaces[activeWorkspaceIndex].id,
            workspaces: workspaces
        )
    }

    @Test func decodeValidState() throws {
        let original = Self.makeState()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoded = try SessionRestorer.decode(from: data)
        #expect(decoded == original)
    }

    @Test func decodeMultipleWorkspaces() throws {
        let original = Self.makeState(workspaceCount: 3, activeWorkspaceIndex: 1)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoded = try SessionRestorer.decode(from: data)
        #expect(decoded.workspaces.count == 3)
        #expect(decoded.activeWorkspaceId == original.activeWorkspaceId)
    }

    @Test func decodeInvalidJSONThrows() {
        let data = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try SessionRestorer.decode(from: data)
        }
    }

    @Test func decodeWithTerminalSplitTree() throws {
        // The Claude side is a single leaf; the terminal panel holds the split.
        let paneA = UUID()
        let paneB = UUID()
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSessionId: sessionID,
                    sessions: [
                        makeClaudeSession(
                            id: sessionID,
                            terminalRoot: .split(PaneSplitState(
                                direction: "horizontal",
                                ratio: 0.6,
                                first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp")),
                                second: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp"))
                            )),
                            terminalFocusedPaneId: paneA,
                            terminalVisible: true,
                            focusedArea: .terminal
                        )
                    ]
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoded = try SessionRestorer.decode(from: data)

        if case .split(let split) = decoded.workspaces[0].sessions[0].terminalRoot {
            #expect(split.ratio == 0.6)
            #expect(split.direction == "horizontal")
        } else {
            Issue.record("Expected split node")
        }
    }
}

// MARK: - Validation Tests

struct SessionRestorerValidationTests {
    @Test func emptyWorkspacesThrows() {
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: UUID(),
            workspaces: []
        )

        #expect(throws: SessionRestorer.RestoreError.self) {
            try SessionRestorer.validate(state)
        }
    }

    @Test func emptySessionsThrows() {
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: UUID(),
            workspaces: [
                makeWorkspaceState(activeSessionId: UUID(), sessions: [])
            ]
        )

        #expect(throws: SessionRestorer.RestoreError.self) {
            try SessionRestorer.validate(state)
        }
    }

    @Test func nilClaudePaneIsAllowed() throws {
        // v7 — a nil Claude pane is fully legal at the persistence layer
        // (validation keeps the session and its nil pane). It is re-seeded as a
        // fresh Claude pane only later, when the live model is built.
        let sessionID = UUID()
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: UUID(),
            workspaces: [
                makeWorkspaceState(
                    activeSessionId: sessionID,
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "empty",
                            defaultWorkingDirectory: nil,
                            claudePane: nil,
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude
                        )
                    ]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].sessions.count == 1)
        #expect(validated.workspaces[0].sessions[0].claudePane == nil)
    }

    @Test func staleActiveWorkspaceIdIsFixed() throws {
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: UUID(), // stale — does not match any workspace
            workspaces: [
                makeWorkspaceState(id: wsID, activeSessionId: sessionID, sessions: [makeClaudeSession(id: sessionID)])
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.activeWorkspaceId == wsID)
    }

    @Test func staleActiveSessionIdIsFixed() throws {
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: UUID(), // stale
                    sessions: [makeClaudeSession(id: sessionID)]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].activeSessionId == sessionID)
    }

    @Test func staleTerminalFocusedPaneIdIsFixedToFirstLeaf() throws {
        let paneA = UUID()
        let paneB = UUID()
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [
                        makeClaudeSession(
                            id: sessionID,
                            terminalRoot: .split(PaneSplitState(
                                direction: "horizontal",
                                ratio: 0.5,
                                first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp")),
                                second: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp"))
                            )),
                            terminalFocusedPaneId: UUID(), // stale — not in the tree
                            terminalVisible: true,
                            focusedArea: .terminal
                        )
                    ]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        // Falls back to the depth-first first leaf.
        #expect(validated.workspaces[0].sessions[0].terminalFocusedPaneId == paneA)
    }

    @Test func terminalVisibleCoercedFalseWhenNoTerminal() throws {
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [
                        makeClaudeSession(
                            id: sessionID,
                            terminalRoot: nil,
                            terminalVisible: true, // impossible without a terminal
                            focusedArea: .claude
                        )
                    ]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].sessions[0].terminalVisible == false)
    }

    @Test func focusedAreaCoercedToClaudeWhenNoTerminal() throws {
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [
                        makeClaudeSession(
                            id: sessionID,
                            terminalRoot: nil,
                            focusedArea: .terminal // can't focus an absent terminal
                        )
                    ]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].sessions[0].focusedArea == .claude)
    }

    @Test func staleWorktreePathIsNulledOut() throws {
        let sessionID = UUID()
        let wsID = UUID()
        let nonExistentPath = "/tmp/tian-wt-nonexistent-\(UUID().uuidString)"

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [makeClaudeSession(id: sessionID, name: "stale-feature", worktreePath: nonExistentPath)]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].sessions[0].worktreePath == nil)
    }

    @Test func validWorktreePathIsPreserved() throws {
        let sessionID = UUID()
        let wsID = UUID()
        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-wt-valid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktreeDir) }

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [makeClaudeSession(id: sessionID, name: "valid-feature", worktreePath: worktreeDir.path)]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].sessions[0].worktreePath == worktreeDir.path)
    }

    @Test func danglingParentSessionIDIsDropped() throws {
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [
                        // parentSessionID points at a session not in the workspace.
                        makeClaudeSession(id: sessionID, parentSessionID: UUID())
                    ]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].sessions[0].parentSessionID == nil)
    }

    @Test func selfParentSessionIDIsDropped() throws {
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [makeClaudeSession(id: sessionID, parentSessionID: sessionID)]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].sessions[0].parentSessionID == nil)
    }

    @Test func validParentSessionIDIsPreserved() throws {
        let parentID = UUID()
        let childID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: parentID,
                    sessions: [
                        makeClaudeSession(id: parentID, name: "orchestrator"),
                        makeClaudeSession(id: childID, name: "impl", parentSessionID: parentID)
                    ]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        let child = validated.workspaces[0].sessions.first { $0.id == childID }
        #expect(child?.parentSessionID == parentID)
    }

    @Test func missingWorkingDirectoryFallsBackToHome() throws {
        let paneID = UUID()
        let sessionID = UUID()
        let wsID = UUID()
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "~"

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: "/nonexistent/path/that/does/not/exist",
                    sessions: [makeClaudeSession(id: sessionID, paneID: paneID, workingDirectory: "/also/nonexistent")]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        // Workspace default dir should be nil (nonexistent)
        #expect(validated.workspaces[0].defaultWorkingDirectory == nil)
        // Claude pane working directory should fall back to $HOME
        #expect(validated.workspaces[0].sessions[0].claudePane?.workingDirectory == home)
    }

    @Test func existingWorkingDirectoryIsPreserved() throws {
        let paneID = UUID()
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    defaultWorkingDirectory: "/tmp",
                    sessions: [makeClaudeSession(id: sessionID, paneID: paneID, workingDirectory: "/tmp")]
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].defaultWorkingDirectory == "/tmp")
        #expect(validated.workspaces[0].sessions[0].claudePane?.workingDirectory == "/tmp")
    }
}

// MARK: - Load Tests (File I/O)

struct SessionRestorerLoadTests {
    private func sampleState() -> SessionState {
        let sessionID = UUID()
        let wsID = UUID()
        return SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(id: wsID, name: "default", activeSessionId: sessionID, sessions: [makeClaudeSession(id: sessionID)])
            ]
        )
    }

    @Test func decodeAndValidateRoundTrip() throws {
        let state = sampleState()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let decoded = try SessionRestorer.decode(from: data)
        let validated = try SessionRestorer.validate(decoded)

        #expect(validated.workspaces.count == 1)
        #expect(validated.workspaces[0].name == "default")
    }
}

// MARK: - WindowFrame Offscreen Detection Tests

struct WindowFrameOffscreenTests {
    @Test func frameOnScreenReturnsTrue() {
        let frame = WindowFrame(x: 100, y: 100, width: 800, height: 600)
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        #expect(frame.isOnScreen(screenFrames: screens))
    }

    @Test func frameCompletelyOffScreenReturnsFalse() {
        let frame = WindowFrame(x: 5000, y: 5000, width: 800, height: 600)
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        #expect(!frame.isOnScreen(screenFrames: screens))
    }

    @Test func framePartiallyOnScreenReturnsTrue() {
        let frame = WindowFrame(x: 1900, y: 1060, width: 800, height: 600)
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        #expect(frame.isOnScreen(screenFrames: screens))
    }

    @Test func frameOnSecondScreen() {
        let frame = WindowFrame(x: 2000, y: 100, width: 800, height: 600)
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        ]
        #expect(frame.isOnScreen(screenFrames: screens))
    }

    @Test func noScreensReturnsFalse() {
        let frame = WindowFrame(x: 100, y: 100, width: 800, height: 600)
        #expect(!frame.isOnScreen(screenFrames: []))
    }

    @Test func negativeCoordinates() {
        let frame = WindowFrame(x: -100, y: -50, width: 800, height: 600)
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        // Frame starts at (-100, -50), extends to (700, 550) — overlaps screen
        #expect(frame.isOnScreen(screenFrames: screens))
    }
}

// MARK: - Build Hierarchy Tests

@MainActor
struct SessionRestorerBuildTests {
    @Test func buildSingleWorkspace() throws {
        let paneID = UUID()
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    name: "my-workspace",
                    activeSessionId: sessionID,
                    sessions: [makeClaudeSession(id: sessionID, paneID: paneID, name: "my-session")]
                )
            ]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)

        #expect(collection.workspaces.count == 1)
        #expect(collection.activeWorkspaceID == wsID)

        let ws = collection.workspaces[0]
        #expect(ws.id == wsID)
        #expect(ws.name == "my-workspace")
        #expect(ws.defaultWorkingDirectory?.path == "/tmp")

        let session = ws.sessionCollection.sessions[0]
        #expect(session.id == sessionID)
        #expect(session.customName == "my-session")
        #expect(session.claudePane != nil)
        #expect(session.claudePaneID == paneID)
    }

    @Test func buildSetsWorktreePathOnSession() throws {
        let sessionID = UUID()
        let wsID = UUID()
        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-wt-build-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktreeDir) }

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [makeClaudeSession(id: sessionID, name: "feature", worktreePath: worktreeDir.path)]
                )
            ]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)
        let session = collection.workspaces[0].sessionCollection.sessions[0]
        #expect(session.worktreePath == worktreeDir)
    }

    @Test func buildNilClaudePaneSeedsFreshClaudePane() {
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [
                        SessionRecord(
                            id: sessionID,
                            customName: "empty",
                            defaultWorkingDirectory: nil,
                            claudePane: nil,
                            terminalVisible: false,
                            dockPosition: .bottom,
                            splitRatio: 0.7,
                            focusedArea: .claude
                        )
                    ]
                )
            ]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)
        let session = collection.workspaces[0].sessionCollection.sessions[0]
        // A nil persisted Claude pane is re-seeded as a fresh, live Claude pane
        // (rather than restoring the removed empty-Claude placeholder state).
        #expect(session.claudePane != nil)
        #expect(session.hasLiveClaudePane)
    }

    @Test func buildMultipleWorkspaces() {
        let ws1ID = UUID()
        let ws2ID = UUID()

        func makeWorkspace(id: UUID, name: String) -> WorkspaceState {
            let sessionID = UUID()
            return makeWorkspaceState(id: id, name: name, activeSessionId: sessionID, sessions: [makeClaudeSession(id: sessionID)])
        }

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: ws2ID,
            workspaces: [makeWorkspace(id: ws1ID, name: "first"), makeWorkspace(id: ws2ID, name: "second")]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)

        #expect(collection.workspaces.count == 2)
        #expect(collection.activeWorkspaceID == ws2ID)
        #expect(collection.workspaces[0].name == "first")
        #expect(collection.workspaces[1].name == "second")
    }

    @Test func buildWithTerminalSplitPanes() {
        let claudePaneID = UUID()
        let paneA = UUID()
        let paneB = UUID()
        let sessionID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [
                        makeClaudeSession(
                            id: sessionID,
                            paneID: claudePaneID,
                            terminalRoot: .split(PaneSplitState(
                                direction: "horizontal",
                                ratio: 0.6,
                                first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp")),
                                second: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp"))
                            )),
                            terminalFocusedPaneId: paneB,
                            terminalVisible: true,
                            focusedArea: .terminal
                        )
                    ]
                )
            ]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)
        let session = collection.workspaces[0].sessionCollection.sessions[0]

        #expect(session.claudePane?.splitTree.leafCount == 1)
        let terminalPanel = session.terminalPanel
        #expect(terminalPanel?.splitTree.leafCount == 2)
        #expect(terminalPanel?.splitTree.focusedPaneID == paneB)
        #expect(terminalPanel?.surface(for: paneA) != nil)
        #expect(terminalPanel?.surface(for: paneB) != nil)
    }

    @Test func buildPreservesActiveSessionID() {
        let session1ID = UUID()
        let session2ID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: session2ID,
                    sessions: [
                        makeClaudeSession(id: session1ID, name: "Session 1"),
                        makeClaudeSession(id: session2ID, name: "Session 2")
                    ]
                )
            ]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)
        let ws = collection.workspaces[0]

        #expect(ws.sessionCollection.activeSessionID == session2ID)
        #expect(ws.sessionCollection.sessions.count == 2)
    }

    @Test func buildPreservesParentSessionID() {
        let parentID = UUID()
        let childID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: parentID,
                    sessions: [
                        makeClaudeSession(id: parentID, name: "orchestrator"),
                        makeClaudeSession(id: childID, name: "impl", parentSessionID: parentID)
                    ]
                )
            ]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)
        let child = collection.workspaces[0].sessionCollection.sessions.first { $0.id == childID }
        #expect(child?.parentSessionID == parentID)
    }
}

// MARK: - SplitTree Restore Init Tests

struct SplitTreeRestoreTests {
    @Test func restoreWithValidFocusedPaneID() {
        let paneA = UUID()
        let paneB = UUID()
        let root = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(paneID: paneA, workingDirectory: "/tmp"),
            second: .leaf(paneID: paneB, workingDirectory: "/tmp")
        )

        let tree = SplitTree(root: root, focusedPaneID: paneB)
        #expect(tree.focusedPaneID == paneB)
    }

    @Test func restoreWithStaleFocusedPaneIDFallsBack() {
        let paneA = UUID()
        let paneB = UUID()
        let root = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(paneID: paneA, workingDirectory: "/tmp"),
            second: .leaf(paneID: paneB, workingDirectory: "/tmp")
        )

        let tree = SplitTree(root: root, focusedPaneID: UUID()) // stale ID
        #expect(tree.focusedPaneID == paneA) // falls back to firstLeaf
    }
}

// MARK: - Metrics Tests

struct SessionRestorerMetricsTests {

    // MARK: - Helpers

    private static func makeCleanState() -> SessionState {
        let sessionID = UUID()
        let wsID = UUID()
        return SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(id: wsID, activeSessionId: sessionID, sessions: [makeClaudeSession(id: sessionID)])
            ]
        )
    }

    // MARK: - Clean State Baseline

    @Test func cleanStateProducesZeroCorrections() throws {
        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(Self.makeCleanState(), metrics: &metrics)

        #expect(metrics.totalStaleIdFixes == 0)
        #expect(metrics.directoryFallbacks == 0)
    }

    @Test func cleanStateCountsEntities() throws {
        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(Self.makeCleanState(), metrics: &metrics)

        #expect(metrics.workspaceCount == 1)
        #expect(metrics.sessionCount == 1)
        // A clean session has one Claude leaf and no terminal panel.
        #expect(metrics.paneCount == 1)
    }

    // MARK: - Stale ID Counting

    @Test func staleWorkspaceIdIsCounted() throws {
        let sessionID = UUID()
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: UUID(), // stale
            workspaces: [
                makeWorkspaceState(activeSessionId: sessionID, sessions: [makeClaudeSession(id: sessionID)])
            ]
        )

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.staleWorkspaceIdFixes == 1)
        #expect(metrics.totalStaleIdFixes == 1)
    }

    @Test func staleSessionIdIsCounted() throws {
        let sessionID = UUID()
        let wsID = UUID()
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(id: wsID, activeSessionId: UUID(), sessions: [makeClaudeSession(id: sessionID)])
            ]
        )

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.staleSessionIdFixes == 1)
    }

    @Test func staleTerminalPaneIdIsCounted() throws {
        let paneA = UUID()
        let sessionID = UUID()
        let wsID = UUID()
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [
                        makeClaudeSession(
                            id: sessionID,
                            terminalRoot: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp")),
                            terminalFocusedPaneId: UUID(), // stale
                            terminalVisible: true,
                            focusedArea: .terminal
                        )
                    ]
                )
            ]
        )

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.stalePaneIdFixes == 1)
    }

    // MARK: - Directory Fallback Counting

    @Test func missingDirectoryIsCounted() throws {
        let sessionID = UUID()
        let wsID = UUID()
        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: sessionID,
                    sessions: [makeClaudeSession(id: sessionID, workingDirectory: "/nonexistent/path/that/does/not/exist")]
                )
            ]
        )

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.directoryFallbacks == 1)
    }

    // MARK: - Multi-Entity Counting

    @Test func multipleEntitiesAreCounted() throws {
        let claudePane1 = UUID(), termA = UUID(), termB = UUID()
        let claudePane2 = UUID()
        let session1 = UUID(), session2 = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                makeWorkspaceState(
                    id: wsID,
                    activeSessionId: session1,
                    sessions: [
                        // Session 1: one Claude leaf + a two-pane terminal panel = 3 panes.
                        makeClaudeSession(
                            id: session1,
                            paneID: claudePane1,
                            terminalRoot: .split(PaneSplitState(
                                direction: "horizontal",
                                ratio: 0.5,
                                first: .pane(PaneLeafState(paneID: termA, workingDirectory: "/tmp")),
                                second: .pane(PaneLeafState(paneID: termB, workingDirectory: "/tmp"))
                            )),
                            terminalFocusedPaneId: termA,
                            terminalVisible: true,
                            focusedArea: .terminal
                        ),
                        // Session 2: one Claude leaf = 1 pane.
                        makeClaudeSession(id: session2, paneID: claudePane2)
                    ]
                )
            ]
        )

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)

        #expect(metrics.workspaceCount == 1)
        #expect(metrics.sessionCount == 2)
        #expect(metrics.paneCount == 4)
        #expect(metrics.totalStaleIdFixes == 0)
    }

    // MARK: - Total Stale ID Fixes

    @Test func totalStaleIdFixesAggregatesAll() {
        var metrics = RestoreMetrics()
        metrics.staleWorkspaceIdFixes = 1
        metrics.staleSessionIdFixes = 2
        metrics.stalePaneIdFixes = 4
        #expect(metrics.totalStaleIdFixes == 7)
    }
}
