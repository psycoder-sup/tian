import Testing
import Foundation
@testable import aterm

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
}

// MARK: - Atomic Write Tests

struct SessionSerializerWriteTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleState() -> SessionState {
        SessionState(
            version: 1,
            savedAt: Date(timeIntervalSince1970: 1000000),
            activeWorkspaceId: UUID(),
            workspaces: []
        )
    }

    @Test func encodeProducesValidJSON() throws {
        let state = sampleState()
        let data = try SessionSerializer.encode(state)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(dict["version"] as? Int == 1)
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
