import Testing
import Foundation
@testable import tian

// MARK: - SessionState Round-Trip Tests

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

    @Test func roundTripSimpleLeaf() throws {
        let state = SessionState(
            version: 1,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "default",
                    activeSpaceId: UUID(),
                    defaultWorkingDirectory: "/Users/me/project",
                    spaces: [
                        SpaceState(
                            id: UUID(),
                            name: "default",
                            activeTabId: UUID(),
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: UUID(),
                                    name: "Tab 1",
                                    activePaneId: UUID(),
                                    root: .pane(PaneLeafState(
                                        paneID: UUID(),
                                        workingDirectory: "/Users/me/project"
                                    ))
                                )
                            ]
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

    @Test func roundTripNestedSplits() throws {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()

        let root: PaneNodeState = .split(PaneSplitState(
            direction: "horizontal",
            ratio: 0.5,
            first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp/a")),
            second: .split(PaneSplitState(
                direction: "vertical",
                ratio: 0.3,
                first: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp/b")),
                second: .pane(PaneLeafState(paneID: paneC, workingDirectory: "/tmp/c"))
            ))
        ))

        let state = SessionState(
            version: 1,
            savedAt: Date(timeIntervalSince1970: 2000000),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "project",
                    activeSpaceId: UUID(),
                    defaultWorkingDirectory: nil,
                    spaces: [
                        SpaceState(
                            id: UUID(),
                            name: "default",
                            activeTabId: UUID(),
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: paneA,
                                    name: nil,
                                    activePaneId: paneB,
                                    root: root
                                )
                            ]
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

    @Test func roundTripMultipleWorkspacesAndSpaces() throws {
        let wsID1 = UUID()
        let wsID2 = UUID()
        let spaceID1 = UUID()
        let spaceID2 = UUID()
        let tabID1 = UUID()
        let tabID2 = UUID()
        let paneID1 = UUID()
        let paneID2 = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(timeIntervalSince1970: 3000000),
            activeWorkspaceId: wsID1,
            workspaces: [
                WorkspaceState(
                    id: wsID1,
                    name: "Workspace 1",
                    activeSpaceId: spaceID1,
                    defaultWorkingDirectory: "/Users/me/ws1",
                    spaces: [
                        SpaceState(
                            id: spaceID1,
                            name: "Space 1",
                            activeTabId: tabID1,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tabID1,
                                    name: "Tab 1",
                                    activePaneId: paneID1,
                                    root: .pane(PaneLeafState(
                                        paneID: paneID1,
                                        workingDirectory: "/Users/me/ws1"
                                    ))
                                )
                            ]
                        )
                    ],
                    windowFrame: WindowFrame(x: 0, y: 0, width: 1920, height: 1080),
                    isFullscreen: true
                ),
                WorkspaceState(
                    id: wsID2,
                    name: "Workspace 2",
                    activeSpaceId: spaceID2,
                    defaultWorkingDirectory: nil,
                    spaces: [
                        SpaceState(
                            id: spaceID2,
                            name: "Space 2",
                            activeTabId: tabID2,
                            defaultWorkingDirectory: "/tmp/space2",
                            tabs: [
                                TabState(
                                    id: tabID2,
                                    name: nil,
                                    activePaneId: paneID2,
                                    root: .pane(PaneLeafState(
                                        paneID: paneID2,
                                        workingDirectory: "/tmp/space2"
                                    ))
                                )
                            ]
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

// MARK: - Snapshot from Live Model Tests

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
        #expect(ws.spaces.count == 1)
        #expect(ws.spaces[0].tabs.count == 1)
    }

    @Test func snapshotCapturesMultipleWorkspaces() {
        let collection = WorkspaceCollection()
        collection.createWorkspace(name: "second")

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces.count == 2)
        #expect(snapshot.workspaces[0].name == "default")
        #expect(snapshot.workspaces[1].name == "second")
    }

    @Test func snapshotCapturesActiveIDs() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let space = ws.spaceCollection.activeSpace!
        let tab = space.activeTab!
        let focusedPaneID = tab.paneViewModel.splitTree.focusedPaneID

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.activeWorkspaceId == ws.id)
        #expect(snapshot.workspaces[0].activeSpaceId == space.id)
        #expect(snapshot.workspaces[0].spaces[0].activeTabId == tab.id)
        #expect(snapshot.workspaces[0].spaces[0].tabs[0].activePaneId == focusedPaneID)
    }

    @Test func snapshotCapturesWorkingDirectory() {
        let dir = URL(filePath: "/tmp/project")
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        ws.setDefaultWorkingDirectory(dir)

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].defaultWorkingDirectory == "/tmp/project")
    }

    @Test func snapshotCapturesSpaceDefaultDirectory() {
        let collection = WorkspaceCollection()
        let space = collection.workspaces[0].spaceCollection.activeSpace!
        space.defaultWorkingDirectory = URL(filePath: "/tmp/space-dir")

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].spaces[0].defaultWorkingDirectory == "/tmp/space-dir")
    }

    @Test func snapshotNilDirectoriesEncodeAsNull() {
        let collection = WorkspaceCollection()

        let snapshot = SessionSerializer.snapshot(from: collection)

        // default workspace has a directory set from init, but space does not
        #expect(snapshot.workspaces[0].spaces[0].defaultWorkingDirectory == nil)
    }

    @Test func snapshotCapturesRestoreCommand() {
        let collection = WorkspaceCollection()
        let tab = collection.workspaces[0].spaceCollection.activeSpace!.activeTab!
        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        tab.paneViewModel.setRestoreCommand(paneID: paneID, command: "claude --resume test123")

        let snapshot = SessionSerializer.snapshot(from: collection)

        let root = snapshot.workspaces[0].spaces[0].tabs[0].root
        if case .pane(let leaf) = root {
            #expect(leaf.restoreCommand == "claude --resume test123")
        } else {
            Issue.record("Expected .pane")
        }
    }

    @Test func snapshotNilRestoreCommandForRegularPane() {
        let collection = WorkspaceCollection()

        let snapshot = SessionSerializer.snapshot(from: collection)

        let root = snapshot.workspaces[0].spaces[0].tabs[0].root
        if case .pane(let leaf) = root {
            #expect(leaf.restoreCommand == nil)
        } else {
            Issue.record("Expected .pane")
        }
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

// MARK: - SpaceState worktreePath Tests

struct SpaceStateWorktreePathTests {
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
        let space = SpaceState(
            id: UUID(),
            name: "feature-branch",
            activeTabId: paneID,
            defaultWorkingDirectory: "/tmp/repo/.worktrees/feature",
            worktreePath: "/tmp/repo/.worktrees/feature",
            tabs: [
                TabState(
                    id: paneID,
                    name: nil,
                    activePaneId: paneID,
                    root: .pane(PaneLeafState(paneID: paneID, workingDirectory: "/tmp/repo/.worktrees/feature"))
                )
            ]
        )

        let data = try Self.makeEncoder().encode(space)
        let decoded = try Self.makeDecoder().decode(SpaceState.self, from: data)

        #expect(decoded == space)
        #expect(decoded.worktreePath == "/tmp/repo/.worktrees/feature")
    }

    @Test func encodesAndDecodesWithNilWorktreePath() throws {
        let paneID = UUID()
        let space = SpaceState(
            id: UUID(),
            name: "default",
            activeTabId: paneID,
            defaultWorkingDirectory: "/tmp",
            tabs: [
                TabState(
                    id: paneID,
                    name: nil,
                    activePaneId: paneID,
                    root: .pane(PaneLeafState(paneID: paneID, workingDirectory: "/tmp"))
                )
            ]
        )

        let data = try Self.makeEncoder().encode(space)
        let decoded = try Self.makeDecoder().decode(SpaceState.self, from: data)

        #expect(decoded == space)
        #expect(decoded.worktreePath == nil)
    }

    @Test func decodesV1JSONWithMissingWorktreePath() throws {
        // Simulate a v1 JSON that has no worktreePath field at all
        let paneID = UUID()
        let json: [String: Any] = [
            "id": paneID.uuidString,
            "name": "default",
            "activeTabId": paneID.uuidString,
            "defaultWorkingDirectory": "/tmp",
            "tabs": [
                [
                    "id": paneID.uuidString,
                    "name": "Tab 1",
                    "activePaneId": paneID.uuidString,
                    "root": [
                        "type": "pane",
                        "paneID": paneID.uuidString,
                        "workingDirectory": "/tmp"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(SpaceState.self, from: data)

        #expect(decoded.worktreePath == nil)
        #expect(decoded.name == "default")
        #expect(decoded.tabs.count == 1)
    }
}

// MARK: - Snapshot worktreePath Tests

@MainActor
struct SessionSnapshotWorktreePathTests {
    @Test func snapshotIncludesWorktreePath() {
        let collection = WorkspaceCollection()
        let space = collection.workspaces[0].spaceCollection.activeSpace!
        let worktreeURL = URL(filePath: "/tmp/repo/.worktrees/feature-x")
        space.worktreePath = worktreeURL

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].spaces[0].worktreePath == "/tmp/repo/.worktrees/feature-x")
    }

    @Test func snapshotNilWorktreePathForRegularSpace() {
        let collection = WorkspaceCollection()

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].spaces[0].worktreePath == nil)
    }
}

// MARK: - Migration v1→v2 Tests

struct SessionMigrationV1ToV2Tests {
    @Test func migratesV1ToV2Successfully() throws {
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

// MARK: - SessionRestorer worktreePath Tests

@MainActor
struct SessionRestorerWorktreePathTests {
    @Test func setsWorktreePathFromSpaceState() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-wt-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktreeDir) }

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "feature",
                            activeTabId: tabID,
                            defaultWorkingDirectory: "/tmp",
                            worktreePath: worktreeDir.path,
                            tabs: [
                                TabState(
                                    id: tabID,
                                    name: nil,
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(paneID: paneID, workingDirectory: "/tmp"))
                                )
                            ]
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)
        let space = collection.workspaces[0].spaceCollection.spaces[0]

        #expect(space.worktreePath == worktreeDir)
    }

    @Test func clearsStaleWorktreePathDuringValidation() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        let nonExistentPath = "/tmp/tian-wt-nonexistent-\(UUID().uuidString)"

        let state = SessionState(
            version: SessionSerializer.currentVersion,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "stale-feature",
                            activeTabId: tabID,
                            defaultWorkingDirectory: "/tmp",
                            worktreePath: nonExistentPath,
                            tabs: [
                                TabState(
                                    id: tabID,
                                    name: nil,
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(paneID: paneID, workingDirectory: "/tmp"))
                                )
                            ]
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].spaces[0].worktreePath == nil)
    }

    @Test func preservesValidWorktreePathDuringValidation() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
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
                WorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "valid-feature",
                            activeTabId: tabID,
                            defaultWorkingDirectory: "/tmp",
                            worktreePath: worktreeDir.path,
                            tabs: [
                                TabState(
                                    id: tabID,
                                    name: nil,
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(paneID: paneID, workingDirectory: "/tmp"))
                                )
                            ]
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].spaces[0].worktreePath == worktreeDir.path)
    }
}

// MARK: - Restore Command Round-Trip Tests

struct RestoreCommandRoundTripTests {
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

    @Test func roundTripWithRestoreCommand() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 2,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "default",
                            activeTabId: tabID,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tabID,
                                    name: nil,
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(
                                        paneID: paneID,
                                        workingDirectory: "/tmp",
                                        restoreCommand: "claude --resume abc123"
                                    ))
                                )
                            ]
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
        if case .pane(let leaf) = decoded.workspaces[0].spaces[0].tabs[0].root {
            #expect(leaf.restoreCommand == "claude --resume abc123")
        } else {
            Issue.record("Expected .pane")
        }
    }

    @Test func roundTripMixedPanesWithAndWithoutRestoreCommand() throws {
        let paneA = UUID()
        let paneB = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let root: PaneNodeState = .split(PaneSplitState(
            direction: "horizontal",
            ratio: 0.5,
            first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp/a", restoreCommand: "claude --resume sess1")),
            second: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp/b"))
        ))

        let state = SessionState(
            version: 2,
            savedAt: Date(timeIntervalSince1970: 2000000),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "default",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: nil,
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "default",
                            activeTabId: tabID,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(id: tabID, name: nil, activePaneId: paneA, root: root)
                            ]
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
        if case .split(let split) = decoded.workspaces[0].spaces[0].tabs[0].root {
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
