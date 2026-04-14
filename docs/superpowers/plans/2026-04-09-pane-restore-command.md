# Pane Restore Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist an optional restore command per pane so that Claude Code sessions auto-resume on session restore using ghostty's `initial_input`.

**Architecture:** Add `restoreCommand: String?` to `PaneLeafState` and a runtime `restoreCommands` dict on `PaneViewModel`. A new `pane.set-restore-command` IPC command lets Claude Code's SessionStart hook register itself. On restore, panes with a restore command pass it as `initialInput` to `GhosttyTerminalSurface.createSurface()`, which sets `config.initial_input`.

**Tech Stack:** Swift, SwiftUI, ghostty C API, ArgumentParser (CLI), Swift Testing

---

### Task 1: Add `restoreCommand` to `PaneLeafState`

**Files:**
- Modify: `tian/Persistence/SessionState.swift:80-83`

- [ ] **Step 1: Write the failing test — `PaneLeafState` round-trips with `restoreCommand`**

In `tianTests/SessionStateTests.swift`, add this test inside the `PaneNodeStateEncodingTests` struct:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/PaneNodeStateEncodingTests/leafEncodesRestoreCommand 2>&1 | tail -20`
Expected: Compilation error — `PaneLeafState` has no `restoreCommand` parameter.

- [ ] **Step 3: Add `restoreCommand` to `PaneLeafState`**

In `tian/Persistence/SessionState.swift`, change `PaneLeafState`:

```swift
struct PaneLeafState: Codable, Sendable, Equatable {
    let paneID: UUID
    let workingDirectory: String
    let restoreCommand: String?

    init(paneID: UUID, workingDirectory: String, restoreCommand: String? = nil) {
        self.paneID = paneID
        self.workingDirectory = workingDirectory
        self.restoreCommand = restoreCommand
    }
}
```

The default `nil` ensures all existing call sites (creating `PaneLeafState` without `restoreCommand`) still compile. `Codable` auto-synthesizes the optional field — missing keys in JSON decode as `nil`.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/PaneNodeStateEncodingTests/leafEncodesRestoreCommand 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Write test — `PaneLeafState` decodes without `restoreCommand` (backward compat)**

In `tianTests/SessionStateTests.swift`, add to `PaneNodeStateEncodingTests`:

```swift
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/PaneNodeStateEncodingTests/leafDecodesWithoutRestoreCommand 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add tian/Persistence/SessionState.swift tianTests/SessionStateTests.swift
git commit -m "feat(persistence): add optional restoreCommand to PaneLeafState"
```

---

### Task 2: Add `restoreCommands` dict to `PaneViewModel`

**Files:**
- Modify: `tian/Pane/PaneViewModel.swift:9-17`

- [ ] **Step 1: Add `restoreCommands` property to `PaneViewModel`**

In `tian/Pane/PaneViewModel.swift`, add after the `paneStates` property (line 17):

```swift
/// Per-pane restore commands registered via IPC. Persisted across sessions.
private(set) var restoreCommands: [UUID: String] = [:]
```

- [ ] **Step 2: Add `setRestoreCommand` and `restoreCommand(for:)` methods**

In `tian/Pane/PaneViewModel.swift`, add in the `// MARK: - Operations` section after `updateRatio`:

```swift
func setRestoreCommand(paneID: UUID, command: String) {
    restoreCommands[paneID] = command
}

func restoreCommand(for paneID: UUID) -> String? {
    restoreCommands[paneID]
}
```

- [ ] **Step 3: Clean up `restoreCommands` in `closePane`**

In `tian/Pane/PaneViewModel.swift`, inside `closePane(paneID:)` (around line 236), add after `bellNotifications.remove(paneID)`:

```swift
restoreCommands.removeValue(forKey: paneID)
```

- [ ] **Step 4: Clean up `restoreCommands` in `cleanup()`**

In `tian/Pane/PaneViewModel.swift`, inside `cleanup()` (around line 305), add after `paneStates.removeAll()`:

```swift
restoreCommands.removeAll()
```

- [ ] **Step 5: Populate `restoreCommands` in `fromState`**

In `tian/Pane/PaneViewModel.swift`, modify the `fromState` method to pass restore commands through. Change the method:

```swift
static func fromState(_ root: PaneNodeState, focusedPaneID: UUID) -> PaneViewModel {
    var surfaces: [UUID: GhosttyTerminalSurface] = [:]
    var surfaceViews: [UUID: TerminalSurfaceView] = [:]
    var restoreCommands: [UUID: String] = [:]
    let paneNode = Self.buildPaneNode(from: root, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands)
    let splitTree = SplitTree(root: paneNode, focusedPaneID: focusedPaneID)
    let pvm = PaneViewModel(splitTree: splitTree, surfaces: surfaces, surfaceViews: surfaceViews)
    pvm.restoreCommands = restoreCommands
    return pvm
}
```

- [ ] **Step 6: Update `buildPaneNode` to extract `restoreCommand`**

In `tian/Pane/PaneViewModel.swift`, update the `buildPaneNode` method signature and leaf case:

```swift
private static func buildPaneNode(
    from state: PaneNodeState,
    surfaces: inout [UUID: GhosttyTerminalSurface],
    surfaceViews: inout [UUID: TerminalSurfaceView],
    restoreCommands: inout [UUID: String]
) -> PaneNode {
    switch state {
    case .pane(let leaf):
        let surface = GhosttyTerminalSurface()
        let surfaceView = TerminalSurfaceView()
        surfaceView.terminalSurface = surface
        surfaceView.initialWorkingDirectory = leaf.workingDirectory
        surfaces[leaf.paneID] = surface
        surfaceViews[leaf.paneID] = surfaceView
        if let cmd = leaf.restoreCommand {
            restoreCommands[leaf.paneID] = cmd
        }
        return .leaf(paneID: leaf.paneID, workingDirectory: leaf.workingDirectory)

    case .split(let split):
        guard let direction = SplitDirection.from(stateValue: split.direction) else {
            return buildPaneNode(from: split.first, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands)
        }
        let first = buildPaneNode(from: split.first, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands)
        let second = buildPaneNode(from: split.second, surfaces: &surfaces, surfaceViews: &surfaceViews, restoreCommands: &restoreCommands)
        return .split(id: UUID(), direction: direction, ratio: split.ratio, first: first, second: second)
    }
}
```

- [ ] **Step 7: Verify all tests still pass**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add tian/Pane/PaneViewModel.swift
git commit -m "feat(pane): add restoreCommands dict to PaneViewModel"
```

---

### Task 3: Add `initialInput` parameter to `GhosttyTerminalSurface.createSurface()`

**Files:**
- Modify: `tian/Core/GhosttyTerminalSurface.swift:19`
- Modify: `tian/View/TerminalSurfaceView.swift:23-27,57`

- [ ] **Step 1: Add `initialInput` parameter to `createSurface`**

In `tian/Core/GhosttyTerminalSurface.swift`, change the `createSurface` signature (line 19):

```swift
func createSurface(view: TerminalSurfaceView, workingDirectory: String? = nil, environmentVariables: [String: String] = [:], initialInput: String? = nil) {
```

- [ ] **Step 2: Set `config.initial_input` before `ghostty_surface_new`**

In `tian/Core/GhosttyTerminalSurface.swift`, change the surface creation block (lines 63-70) to also handle `initialInput`:

```swift
let created: ghostty_surface_t? = envVars.withUnsafeMutableBufferPointer { envBuffer in
    config.env_vars = envBuffer.baseAddress
    config.env_var_count = envBuffer.count
    return workingDirectory.withCString { cWd in
        config.working_directory = cWd
        return initialInput.withCString { cInput in
            config.initial_input = cInput
            return ghostty_surface_new(ghosttyApp, &config)
        }
    }
}
```

This uses the existing `Optional<String>.withCString` extension (line 185) — when `initialInput` is `nil`, it passes `nil` to `config.initial_input`.

- [ ] **Step 3: Add `initialInput` property to `TerminalSurfaceView`**

In `tian/View/TerminalSurfaceView.swift`, add after the `environmentVariables` property (line 26):

```swift
/// Restore command to replay into the shell on surface creation (e.g. "claude --resume <id>").
var initialInput: String?
```

- [ ] **Step 4: Pass `initialInput` through in `viewDidMoveToWindow`**

In `tian/View/TerminalSurfaceView.swift`, change the `createSurface` call (line 57):

```swift
terminalSurface.createSurface(view: self, workingDirectory: initialWorkingDirectory, environmentVariables: environmentVariables, initialInput: initialInput)
```

- [ ] **Step 5: Verify all tests still pass**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -20`
Expected: All tests PASS (no callers of `createSurface` broke since the new param has a default)

- [ ] **Step 6: Commit**

```bash
git add tian/Core/GhosttyTerminalSurface.swift tian/View/TerminalSurfaceView.swift
git commit -m "feat(ghostty): add initialInput parameter to createSurface for command replay"
```

---

### Task 4: Wire `initialInput` through `PaneViewModel` restore path

**Files:**
- Modify: `tian/Pane/PaneViewModel.swift:156-169`

- [ ] **Step 1: Set `initialInput` on surface views during `buildPaneNode`**

In `tian/Pane/PaneViewModel.swift`, in the `buildPaneNode` method's `.pane` case, the `restoreCommands` dict is already populated (Task 2 Step 6). Now add `initialInput` to the surface view. Change the existing block:

```swift
if let cmd = leaf.restoreCommand {
    restoreCommands[leaf.paneID] = cmd
    surfaceView.initialInput = cmd + "\n"
}
```

The `+ "\n"` simulates pressing Enter so the shell executes the command. This replaces the previous `restoreCommands`-only block from Task 2.

- [ ] **Step 2: Verify all tests still pass**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add tian/Pane/PaneViewModel.swift
git commit -m "feat(pane): wire initialInput from restoreCommand during session restore"
```

---

### Task 5: Add `pane.set-restore-command` IPC handler

**Files:**
- Modify: `tian/Core/IPCCommandHandler.swift:31,58-59`
- Test: `tianTests/IPCCommandHandlerTests.swift`

- [ ] **Step 1: Write failing tests for the new IPC command**

In `tianTests/IPCCommandHandlerTests.swift`, add these tests:

```swift
// MARK: - Pane Restore Command

@Test @MainActor func setRestoreCommandMissingCommandReturnsError() async {
    let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
    let request = IPCRequest(version: 1, command: "pane.set-restore-command", params: [:], env: dummyEnv)
    let response = await handler.handle(request)
    #expect(response.ok == false)
    #expect(response.error?.code == 1)
    #expect(response.error?.message.contains("Missing required parameter: command") == true)
}

@Test @MainActor func setRestoreCommandInvalidPaneUUIDReturnsError() async {
    let invalidEnv = IPCEnv(
        paneId: "not-a-uuid",
        tabId: "00000000-0000-0000-0000-000000000000",
        spaceId: "00000000-0000-0000-0000-000000000000",
        workspaceId: "00000000-0000-0000-0000-000000000000"
    )
    let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
    let request = IPCRequest(
        version: 1,
        command: "pane.set-restore-command",
        params: ["command": .string("claude --resume abc")],
        env: invalidEnv
    )
    let response = await handler.handle(request)
    #expect(response.ok == false)
    #expect(response.error?.code == 1)
    #expect(response.error?.message.contains("Invalid pane UUID") == true)
}

@Test @MainActor func setRestoreCommandNonexistentPaneReturnsError() async {
    let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
    let request = IPCRequest(
        version: 1,
        command: "pane.set-restore-command",
        params: ["command": .string("claude --resume abc")],
        env: dummyEnv
    )
    let response = await handler.handle(request)
    #expect(response.ok == false)
    #expect(response.error?.code == 1)
    #expect(response.error?.message.contains("Pane not found") == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/IPCCommandHandlerTests/setRestoreCommandMissingCommandReturnsError 2>&1 | tail -20`
Expected: FAIL — "Unknown command: pane.set-restore-command"

- [ ] **Step 3: Add the command case to the handler dispatch**

In `tian/Core/IPCCommandHandler.swift`, add in the `switch request.command` block after the `pane.focus` case (around line 58):

```swift
case "pane.set-restore-command": return handleSetRestoreCommand(request)
```

- [ ] **Step 4: Implement the handler method**

In `tian/Core/IPCCommandHandler.swift`, add in the `// MARK: - Pane Commands` section after `handlePaneFocus`:

```swift
private func handleSetRestoreCommand(_ request: IPCRequest) -> IPCResponse {
    guard let command = stringParam("command", from: request.params) else {
        return .failure(code: 1, message: "Missing required parameter: command")
    }

    guard let paneId = UUID(uuidString: request.env.paneId) else {
        return .failure(code: 1, message: "Invalid pane UUID: \(request.env.paneId)")
    }

    guard let (_, paneViewModel, _) = resolvePane(id: paneId, tabId: nil) else {
        return .failure(code: 1, message: "Pane not found: \(request.env.paneId)")
    }

    paneViewModel.setRestoreCommand(paneID: paneId, command: command)
    return .success()
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/IPCCommandHandlerTests 2>&1 | tail -20`
Expected: All IPCCommandHandler tests PASS

- [ ] **Step 6: Commit**

```bash
git add tian/Core/IPCCommandHandler.swift tianTests/IPCCommandHandlerTests.swift
git commit -m "feat(ipc): add pane.set-restore-command handler"
```

---

### Task 6: Add CLI subcommand `pane set-restore-command`

**Files:**
- Modify: `tian-cli/CommandRouter.swift:410-416`

- [ ] **Step 1: Add `PaneSetRestoreCommand` struct**

In `tian-cli/CommandRouter.swift`, add after the `PaneFocus` struct (around line 512):

```swift
struct PaneSetRestoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-restore-command",
        abstract: "Set a command to replay when this pane is restored."
    )

    @Option(name: .long, help: "Command to replay on restore.")
    var command: String

    func run() throws {
        let response = try sendRequest(command: "pane.set-restore-command", params: ["command": .string(command)])
        try handleVoidResponse(response)
    }
}
```

- [ ] **Step 2: Register the subcommand in `PaneGroup`**

In `tian-cli/CommandRouter.swift`, add `PaneSetRestoreCommand.self` to the `PaneGroup` subcommands array (line 410-416):

```swift
struct PaneGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pane",
        abstract: "Manage panes within a tab.",
        subcommands: [
            PaneSplit.self,
            PaneList.self,
            PaneClose.self,
            PaneFocus.self,
            PaneSetRestoreCommand.self,
        ]
    )
}
```

- [ ] **Step 3: Verify the project builds**

Run: `xcodebuild build -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add tian-cli/CommandRouter.swift
git commit -m "feat(cli): add pane set-restore-command subcommand"
```

---

### Task 7: Include `restoreCommand` in session serialization

**Files:**
- Modify: `tian/Persistence/SessionState.swift:131-146` (PaneNode.toState)
- Modify: `tian/Persistence/SessionSerializer.swift:29-56`
- Test: `tianTests/SessionStateTests.swift`

- [ ] **Step 1: Write failing test — snapshot captures restoreCommand**

In `tianTests/SessionStateTests.swift`, add to the `SessionSnapshotTests` struct:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/SessionSnapshotTests/snapshotCapturesRestoreCommand 2>&1 | tail -20`
Expected: FAIL — `restoreCommand` is always `nil` because `toState()` doesn't include it.

- [ ] **Step 3: Update `PaneNode.toState()` to accept restore commands**

In `tian/Persistence/SessionState.swift`, change the `PaneNode.toState()` extension (lines 131-146):

```swift
extension PaneNode {
    /// Converts the runtime PaneNode to its Codable state representation.
    func toState(restoreCommands: [UUID: String] = [:]) -> PaneNodeState {
        switch self {
        case .leaf(let paneID, let workingDirectory):
            return .pane(PaneLeafState(
                paneID: paneID,
                workingDirectory: workingDirectory,
                restoreCommand: restoreCommands[paneID]
            ))
        case .split(_, let direction, let ratio, let first, let second):
            return .split(PaneSplitState(
                direction: direction.stateValue,
                ratio: ratio,
                first: first.toState(restoreCommands: restoreCommands),
                second: second.toState(restoreCommands: restoreCommands)
            ))
        }
    }
}
```

- [ ] **Step 4: Update `SessionSerializer.snapshot` to pass restore commands**

In `tian/Persistence/SessionSerializer.swift`, change the line that calls `toState()` (inside the tabs map, line 48):

```swift
root: tab.paneViewModel.splitTree.root.toState(restoreCommands: tab.paneViewModel.restoreCommands)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/SessionSnapshotTests 2>&1 | tail -20`
Expected: All PASS

- [ ] **Step 6: Run full test suite to ensure nothing broke**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add tian/Persistence/SessionState.swift tian/Persistence/SessionSerializer.swift tianTests/SessionStateTests.swift
git commit -m "feat(persistence): include restoreCommand in session serialization"
```

---

### Task 8: End-to-end restore test

**Files:**
- Test: `tianTests/SessionStateTests.swift`

- [ ] **Step 1: Write round-trip test — serialize with restoreCommand, restore it**

In `tianTests/SessionStateTests.swift`, add a new test struct:

```swift
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/RestoreCommandRoundTripTests 2>&1 | tail -20`
Expected: All PASS

- [ ] **Step 3: Write test — `PaneViewModel.fromState` populates `restoreCommands`**

In `tianTests/SessionStateTests.swift`, add:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build -only-testing:tianTests/RestoreCommandPaneViewModelTests 2>&1 | tail -20`
Expected: All PASS

- [ ] **Step 5: Run full test suite**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add tianTests/SessionStateTests.swift
git commit -m "test: add end-to-end round-trip and PaneViewModel restore command tests"
```

---

### Task 9: Run `xcodegen generate` if needed

**Files:**
- No new files were added, only existing files modified.

- [ ] **Step 1: Check if xcodegen is needed**

Since no files were added or removed (only existing files modified), xcodegen is not needed. Verify:

Run: `git diff --name-only --diff-filter=A HEAD~8`
Expected: No new source files listed (only modifications)

- [ ] **Step 2: Final full test suite run**

Run: `xcodebuild test -scheme tian -destination 'platform=macOS' -derivedDataPath .build 2>&1 | tail -30`
Expected: All tests PASS, BUILD SUCCEEDED
