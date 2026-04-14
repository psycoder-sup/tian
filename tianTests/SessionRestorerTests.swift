import Testing
import Foundation
@testable import tian

// MARK: - Decode Tests

struct SessionRestorerDecodeTests {
    private static func makeState(
        workspaceCount: Int = 1,
        activeWorkspaceIndex: Int = 0
    ) -> SessionState {
        let workspaces = (0..<workspaceCount).map { i in
            let paneID = UUID()
            let tabID = UUID()
            let spaceID = UUID()
            return WorkspaceState(
                id: UUID(),
                name: "Workspace \(i + 1)",
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
                                name: "Tab 1",
                                activePaneId: paneID,
                                root: .pane(PaneLeafState(
                                    paneID: paneID,
                                    workingDirectory: "/tmp"
                                ))
                            )
                        ]
                    )
                ],
                windowFrame: nil,
                isFullscreen: nil
            )
        }

        return SessionState(
            version: 1,
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

    @Test func decodeWithSplitTree() throws {
        let paneA = UUID()
        let paneB = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
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
                                    name: "Tab 1",
                                    activePaneId: paneA,
                                    root: .split(PaneSplitState(
                                        direction: "horizontal",
                                        ratio: 0.6,
                                        first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp")),
                                        second: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp"))
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

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoded = try SessionRestorer.decode(from: data)

        if case .split(let split) = decoded.workspaces[0].spaces[0].tabs[0].root {
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
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: UUID(),
            workspaces: []
        )

        #expect(throws: SessionRestorer.RestoreError.self) {
            try SessionRestorer.validate(state)
        }
    }

    @Test func emptySpacesThrows() {
        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "ws",
                    activeSpaceId: UUID(),
                    defaultWorkingDirectory: nil,
                    spaces: [],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        #expect(throws: SessionRestorer.RestoreError.self) {
            try SessionRestorer.validate(state)
        }
    }

    @Test func emptyTabsThrows() {
        let spaceID = UUID()
        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: UUID(),
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "ws",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: nil,
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "space",
                            activeTabId: UUID(),
                            defaultWorkingDirectory: nil,
                            tabs: []
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        #expect(throws: SessionRestorer.RestoreError.self) {
            try SessionRestorer.validate(state)
        }
    }

    @Test func staleActiveWorkspaceIdIsFixed() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: UUID(), // stale — does not match any workspace
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
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
                                    name: "Tab 1",
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
        #expect(validated.activeWorkspaceId == wsID)
    }

    @Test func staleActiveSpaceIdIsFixed() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
                    activeSpaceId: UUID(), // stale
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
                                    name: "Tab 1",
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
        #expect(validated.workspaces[0].activeSpaceId == spaceID)
    }

    @Test func staleActiveTabIdIsFixed() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "default",
                            activeTabId: UUID(), // stale
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tabID,
                                    name: "Tab 1",
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
        #expect(validated.workspaces[0].spaces[0].activeTabId == tabID)
    }

    @Test func staleActivePaneIdIsFixed() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
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
                                    name: "Tab 1",
                                    activePaneId: UUID(), // stale
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
        #expect(validated.workspaces[0].spaces[0].tabs[0].activePaneId == paneID)
    }

    @Test func missingWorkingDirectoryFallsBackToHome() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "~"

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/nonexistent/path/that/does/not/exist",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "default",
                            activeTabId: tabID,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tabID,
                                    name: "Tab 1",
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(
                                        paneID: paneID,
                                        workingDirectory: "/also/nonexistent"
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

        let validated = try SessionRestorer.validate(state)
        // Workspace default dir should be nil (nonexistent)
        #expect(validated.workspaces[0].defaultWorkingDirectory == nil)
        // Pane working directory should fall back to $HOME
        if case .pane(let leaf) = validated.workspaces[0].spaces[0].tabs[0].root {
            #expect(leaf.workingDirectory == home)
        } else {
            Issue.record("Expected pane leaf")
        }
    }

    @Test func existingWorkingDirectoryIsPreserved() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
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
                                    name: "Tab 1",
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(
                                        paneID: paneID,
                                        workingDirectory: "/tmp"
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

        let validated = try SessionRestorer.validate(state)
        #expect(validated.workspaces[0].defaultWorkingDirectory == "/tmp")
        if case .pane(let leaf) = validated.workspaces[0].spaces[0].tabs[0].root {
            #expect(leaf.workingDirectory == "/tmp")
        } else {
            Issue.record("Expected pane leaf")
        }
    }
}

// MARK: - Load Tests (File I/O)

struct SessionRestorerLoadTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-restorer-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleState() -> SessionState {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        return SessionState(
            version: 1,
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
                                    name: "Tab 1",
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
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "my-workspace",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "my-space",
                            activeTabId: tabID,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tabID,
                                    name: "Tab 1",
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

        #expect(collection.workspaces.count == 1)
        #expect(collection.activeWorkspaceID == wsID)

        let ws = collection.workspaces[0]
        #expect(ws.id == wsID)
        #expect(ws.name == "my-workspace")
        #expect(ws.defaultWorkingDirectory?.path == "/tmp")

        let space = ws.spaceCollection.spaces[0]
        #expect(space.id == spaceID)
        #expect(space.name == "my-space")

        let tab = space.tabs[0]
        #expect(tab.id == tabID)
        #expect(tab.paneViewModel.splitTree.focusedPaneID == paneID)
    }

    @Test func buildMultipleWorkspaces() {
        let ws1ID = UUID()
        let ws2ID = UUID()

        func makeWorkspace(id: UUID, name: String) -> WorkspaceState {
            let paneID = UUID()
            let tabID = UUID()
            let spaceID = UUID()
            return WorkspaceState(
                id: id,
                name: name,
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
                                name: "Tab 1",
                                activePaneId: paneID,
                                root: .pane(PaneLeafState(paneID: paneID, workingDirectory: "/tmp"))
                            )
                        ]
                    )
                ],
                windowFrame: nil,
                isFullscreen: nil
            )
        }

        let state = SessionState(
            version: 1,
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

    @Test func buildWithSplitPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
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
                                    name: "Tab 1",
                                    activePaneId: paneB,
                                    root: .split(PaneSplitState(
                                        direction: "horizontal",
                                        ratio: 0.6,
                                        first: .pane(PaneLeafState(paneID: paneA, workingDirectory: "/tmp")),
                                        second: .pane(PaneLeafState(paneID: paneB, workingDirectory: "/tmp"))
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

        let collection = SessionRestorer.buildWorkspaceCollection(from: state)
        let tab = collection.workspaces[0].spaceCollection.spaces[0].tabs[0]

        #expect(tab.paneViewModel.splitTree.leafCount == 2)
        #expect(tab.paneViewModel.splitTree.focusedPaneID == paneB)
        #expect(tab.paneViewModel.surface(for: paneA) != nil)
        #expect(tab.paneViewModel.surface(for: paneB) != nil)
    }

    @Test func buildPreservesActiveIDs() {
        let paneID = UUID()
        let tab1ID = UUID()
        let tab2ID = UUID()
        let space1ID = UUID()
        let space2ID = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
                    activeSpaceId: space2ID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: space1ID,
                            name: "Space 1",
                            activeTabId: tab1ID,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tab1ID,
                                    name: "Tab 1",
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(paneID: paneID, workingDirectory: "/tmp"))
                                )
                            ]
                        ),
                        SpaceState(
                            id: space2ID,
                            name: "Space 2",
                            activeTabId: tab2ID,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tab2ID,
                                    name: "Tab 1",
                                    activePaneId: UUID(),
                                    root: .pane(PaneLeafState(paneID: UUID(), workingDirectory: "/tmp"))
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
        let ws = collection.workspaces[0]

        #expect(ws.spaceCollection.activeSpaceID == space2ID)
        #expect(ws.spaceCollection.spaces.count == 2)
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
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        return SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
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
                                    name: "Tab 1",
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
        #expect(metrics.spaceCount == 1)
        #expect(metrics.tabCount == 1)
        #expect(metrics.paneCount == 1)
    }

    // MARK: - Stale ID Counting

    @Test func staleWorkspaceIdIsCounted() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: UUID(), // stale
            workspaces: [
                WorkspaceState(
                    id: UUID(),
                    name: "ws",
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
                                    name: "Tab 1",
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

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.staleWorkspaceIdFixes == 1)
        #expect(metrics.totalStaleIdFixes == 1)
    }

    @Test func staleSpaceIdIsCounted() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
                    activeSpaceId: UUID(), // stale
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
                                    name: "Tab 1",
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

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.staleSpaceIdFixes == 1)
    }

    @Test func staleTabIdIsCounted() throws {
        let paneID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
                    activeSpaceId: spaceID,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: spaceID,
                            name: "default",
                            activeTabId: UUID(), // stale
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: UUID(),
                                    name: "Tab 1",
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

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.staleTabIdFixes == 1)
    }

    @Test func stalePaneIdIsCounted() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
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
                                    name: "Tab 1",
                                    activePaneId: UUID(), // stale
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

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.stalePaneIdFixes == 1)
    }

    // MARK: - Directory Fallback Counting

    @Test func missingDirectoryIsCounted() throws {
        let paneID = UUID()
        let tabID = UUID()
        let spaceID = UUID()
        let wsID = UUID()
        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
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
                                    name: "Tab 1",
                                    activePaneId: paneID,
                                    root: .pane(PaneLeafState(
                                        paneID: paneID,
                                        workingDirectory: "/nonexistent/path/that/does/not/exist"
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

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)
        #expect(metrics.directoryFallbacks == 1)
    }

    // MARK: - Multi-Entity Counting

    @Test func multipleEntitiesAreCounted() throws {
        let pane1 = UUID(), pane2 = UUID(), pane3 = UUID()
        let tab1 = UUID(), tab2 = UUID()
        let space1 = UUID(), space2 = UUID()
        let wsID = UUID()

        let state = SessionState(
            version: 1,
            savedAt: Date(),
            activeWorkspaceId: wsID,
            workspaces: [
                WorkspaceState(
                    id: wsID,
                    name: "ws",
                    activeSpaceId: space1,
                    defaultWorkingDirectory: "/tmp",
                    spaces: [
                        SpaceState(
                            id: space1,
                            name: "space1",
                            activeTabId: tab1,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tab1,
                                    name: "Tab 1",
                                    activePaneId: pane1,
                                    root: .split(PaneSplitState(
                                        direction: "horizontal",
                                        ratio: 0.5,
                                        first: .pane(PaneLeafState(paneID: pane1, workingDirectory: "/tmp")),
                                        second: .pane(PaneLeafState(paneID: pane2, workingDirectory: "/tmp"))
                                    ))
                                )
                            ]
                        ),
                        SpaceState(
                            id: space2,
                            name: "space2",
                            activeTabId: tab2,
                            defaultWorkingDirectory: nil,
                            tabs: [
                                TabState(
                                    id: tab2,
                                    name: "Tab 2",
                                    activePaneId: pane3,
                                    root: .pane(PaneLeafState(paneID: pane3, workingDirectory: "/tmp"))
                                )
                            ]
                        )
                    ],
                    windowFrame: nil,
                    isFullscreen: nil
                )
            ]
        )

        var metrics = RestoreMetrics()
        _ = try SessionRestorer.validate(state, metrics: &metrics)

        #expect(metrics.workspaceCount == 1)
        #expect(metrics.spaceCount == 2)
        #expect(metrics.tabCount == 2)
        #expect(metrics.paneCount == 3)
        #expect(metrics.totalStaleIdFixes == 0)
    }

    // MARK: - Total Stale ID Fixes

    @Test func totalStaleIdFixesAggregatesAll() {
        var metrics = RestoreMetrics()
        metrics.staleWorkspaceIdFixes = 1
        metrics.staleSpaceIdFixes = 2
        metrics.staleTabIdFixes = 3
        metrics.stalePaneIdFixes = 4
        #expect(metrics.totalStaleIdFixes == 10)
    }
}
