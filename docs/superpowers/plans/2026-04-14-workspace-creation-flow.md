# Unified Space Creation Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two separate space-creation paths (regular `+` button + worktree branch-icon button, and their two keybindings) with a single unified modal that contains a text field and a "Create worktree" checkbox. Branch list with arrow-key navigation reuses the existing `BranchListViewModel`.

**Architecture:** Refactor the existing `BranchNameInputView` into `CreateSpaceView`. Both the sidebar `+` button and the `⇧⌘T` keybinding post a single `Notification.Name.showCreateSpaceInput`; `WorkspaceWindowContent` listens and shows the modal as an overlay. The unchecked path uses a new `name:` parameter on `SpaceCollection.createSpace`. The checked path delegates to the existing `WorktreeOrchestrator.createWorktreeSpace`.

**Tech Stack:** Swift, SwiftUI, `@Observable` (Observation framework), Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen, ghostty embedding API.

**Spec:** `docs/superpowers/specs/2026-04-14-workspace-creation-flow-design.md`

**Conventions:**
- Build: `scripts/build.sh Debug` (runs xcodegen + xcodebuild). Always pass `-derivedDataPath .build` if invoking xcodebuild directly.
- After adding/removing/renaming Swift files: `xcodegen generate`.
- Run tests via `test-runner-slim` agent (project convention) — never raw `xcodebuild test` from this plan; use the agent or the slim wrapper. For this plan's purposes, treat each "Run tests" step as: dispatch the test-runner-slim agent with the relevant test target/file.
- Commit messages follow the repo style: emoji + conventional prefix, e.g. `✨ feat`, `🐛 fix`, `♻️ refactor`, `📝 docs`, `🚚 chore`. Sign-off line is not used in this repo (see recent commits).

---

## File Structure

**New files:**
- `tian/View/CreateSpace/CreateSpaceView.swift` — the unified modal (renamed/rewritten from `BranchNameInputView.swift`).
- `tian/View/CreateSpace/BranchListViewModel.swift` — existing view model, moved here. Behavior unchanged except for one tweak (no auto-highlight when query is empty).
- `tianTests/CreateSpaceFlowTests.swift` — new test file covering `SpaceCollection.createSpace(name:)`, `BranchListViewModel.recomputeRows` empty-query behavior, and the sanitization helper.

**Modified files:**
- `tian/Tab/SpaceCollection.swift` — add `name:` parameter.
- `tian/Workspace/Workspace.swift` — add transient `lastCreateWorktreeChoice` property.
- `tian/View/Sidebar/SidebarContainerView.swift` — rename notification + key constants.
- `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift` — remove worktree button, enlarge `+`.
- `tian/View/Sidebar/SidebarExpandedContentView.swift` — `addSpace(to:)` posts the unified notification; remove `onNewWorktreeSpace` plumbing.
- `tian/Input/KeyAction.swift` — remove `case newWorktreeSpace`.
- `tian/Input/KeyBindingRegistry.swift` — remove `.newWorktreeSpace` binding.
- `tian/WindowManagement/WorkspaceWindowController.swift` — remove worktree handler + key case; change `.newSpace` to post the notification.
- `tian/View/Workspace/WorkspaceWindowContent.swift` — listen for the unified notification, render `CreateSpaceView`.

**Removed files:**
- `tian/View/Worktree/BranchNameInputView.swift` (renamed/moved).
- `tian/View/Worktree/BranchListViewModel.swift` (moved).

---

## Task Order Rationale

Tasks are ordered to keep the project in a buildable state after every commit. Foundation changes (small, type-safe additions) come first; the notification rename happens as one atomic update across all callers; then the view migration; finally the trigger surfaces are switched over.

---

### Task 1: Add `name:` parameter to `SpaceCollection.createSpace`

**Files:**
- Modify: `tian/Tab/SpaceCollection.swift:56-69`
- Test: `tianTests/CreateSpaceFlowTests.swift` (create new)

- [ ] **Step 1: Write the failing test**

Create `tianTests/CreateSpaceFlowTests.swift` with this initial content:

```swift
import Testing
import Foundation
@testable import tian

@MainActor
struct CreateSpaceFlowTests {

    // MARK: - SpaceCollection.createSpace(name:)

    @Test func createSpaceWithoutNameUsesAutoName() {
        let collection = SpaceCollection(workingDirectory: "~")
        let space = collection.createSpace(workingDirectory: "~")
        #expect(space.name == "Space 2")
    }

    @Test func createSpaceWithNameUsesGivenName() {
        let collection = SpaceCollection(workingDirectory: "~")
        let space = collection.createSpace(name: "auth-refactor", workingDirectory: "~")
        #expect(space.name == "auth-refactor")
    }

    @Test func createSpaceWithNilNameStillAutoNames() {
        let collection = SpaceCollection(workingDirectory: "~")
        let space = collection.createSpace(name: nil, workingDirectory: "~")
        #expect(space.name == "Space 2")
    }

    @Test func createSpaceAllowsDuplicateNames() {
        let collection = SpaceCollection(workingDirectory: "~")
        let s1 = collection.createSpace(name: "feature/auth", workingDirectory: "~")
        let s2 = collection.createSpace(name: "feature/auth", workingDirectory: "~")
        #expect(s1.name == "feature/auth")
        #expect(s2.name == "feature/auth")
        #expect(s1.id != s2.id)
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

Run: `xcodegen generate`
Expected: regenerates `tian.xcodeproj` to include the new test file.

- [ ] **Step 3: Run the new tests and verify they fail to compile**

Use the test-runner-slim agent on test target `tianTests`, filtering to `CreateSpaceFlowTests`.
Expected: compile error — `createSpace` does not accept a `name:` parameter.

- [ ] **Step 4: Modify `createSpace` in `tian/Tab/SpaceCollection.swift`**

Replace the existing method body (lines 56-69) with:

```swift
    @discardableResult
    func createSpace(name: String? = nil, workingDirectory: String = "~") -> SpaceModel {
        spaceCounter += 1
        let tab = TabModel(workingDirectory: workingDirectory)
        let resolvedName = name ?? "Space \(spaceCounter)"
        let space = SpaceModel(name: resolvedName, initialTab: tab)
        space.workspaceDefaultDirectory = workspaceDefaultDirectory
        if let workspaceID {
            space.propagateWorkspaceID(workspaceID)
        }
        wireSpaceClose(space)
        spaces.append(space)
        activeSpaceID = space.id
        return space
    }
```

- [ ] **Step 5: Run tests and verify they pass**

Use the test-runner-slim agent on `CreateSpaceFlowTests` and `SpaceCollectionTests` (existing tests must not regress).
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tian/Tab/SpaceCollection.swift tianTests/CreateSpaceFlowTests.swift tian.xcodeproj
git commit -m "✨ feat(SpaceCollection): accept optional name parameter in createSpace"
```

---

### Task 2: Add `lastCreateWorktreeChoice` to `Workspace`

**Files:**
- Modify: `tian/Workspace/Workspace.swift:17-27` (the property block of `Workspace`)

- [ ] **Step 1: Edit `Workspace` to add the transient property**

In `tian/Workspace/Workspace.swift`, after the `let createdAt: Date` line (currently line 21) and before `let spaceCollection: SpaceCollection` (line 23), add:

```swift
    /// Remembers the last "Create worktree" checkbox state in the unified
    /// space-creation modal. Transient — not persisted in `WorkspaceSnapshot`,
    /// resets on app relaunch.
    var lastCreateWorktreeChoice: Bool?
```

- [ ] **Step 2: Build to verify nothing else broke**

Run: `scripts/build.sh Debug`
Expected: build succeeds (purely additive change).

- [ ] **Step 3: Commit**

```bash
git add tian/Workspace/Workspace.swift
git commit -m "✨ feat(Workspace): add transient lastCreateWorktreeChoice"
```

---

### Task 3: Tweak `BranchListViewModel.recomputeRows` to skip auto-highlight when query is empty

**Files:**
- Modify: `tian/View/Worktree/BranchListViewModel.swift:106-122`
- Modify: `tianTests/BranchListViewModelTests.swift` (add a new `@Test`)

- [ ] **Step 1: Write the failing test**

Append the following inside the existing `BranchListViewModelTests` struct in `tianTests/BranchListViewModelTests.swift`. (If the closing `}` of the struct is at the end of the file, insert above it.)

```swift
    @Test func emptyQueryDoesNotAutoHighlight() async {
        let viewModel = BranchListViewModel(service: StubService(entries: [
            entry(local: "main",         date: Date()),
            entry(local: "feature/auth", date: Date().addingTimeInterval(-3600)),
        ]))
        await viewModel.load(repoRoot: "/tmp/fake-repo")
        // Query starts empty; rows are populated; highlight must be nil.
        #expect(!viewModel.rows.isEmpty)
        #expect(viewModel.highlightedID == nil)
    }

    @Test func nonEmptyQueryAutoHighlightsFirstRow() async {
        let viewModel = BranchListViewModel(service: StubService(entries: [
            entry(local: "main",         date: Date()),
            entry(local: "feature/auth", date: Date().addingTimeInterval(-3600)),
        ]))
        await viewModel.load(repoRoot: "/tmp/fake-repo")
        viewModel.query = "fea"
        #expect(viewModel.highlightedID != nil)
        #expect(viewModel.rows.first?.displayName == "feature/auth")
    }
```

The `StubService` and `entry` helpers already exist in this file (from the existing tests). If `StubService` does not yet exist, search the file for any in-file fake implementation of `BranchListProviding` and reuse it; if none exists, add this minimal stub at the top of the struct (after the `entry(...)` helper):

```swift
    private struct StubService: BranchListProviding {
        let entries: [BranchEntry]
        func listBranches(repoRoot: String) async throws -> [BranchEntry] { entries }
        func fetchRemotes(repoRoot: String) async throws { /* no-op */ }
    }
```

(Confirm `BranchListProviding`'s real protocol shape by reading `tian/View/Worktree/BranchListServiceAdapter.swift` — match its method signatures exactly; if the protocol differs, adjust the stub.)

- [ ] **Step 2: Run the new tests and verify the empty-query test fails**

Use test-runner-slim on `BranchListViewModelTests`.
Expected: `emptyQueryDoesNotAutoHighlight` FAILS (current code auto-highlights even when query is empty); `nonEmptyQueryAutoHighlightsFirstRow` PASSES.

- [ ] **Step 3: Modify `recomputeRows` in `tian/View/Worktree/BranchListViewModel.swift`**

Replace the body of `recomputeRows()` (lines 106-122) with:

```swift
    private func recomputeRows() {
        let deduped = Self.dedup(rawEntries)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [BranchRow]
        if q.isEmpty {
            filtered = deduped
        } else {
            filtered = deduped.filter { $0.displayName.lowercased().contains(q) }
        }
        rows = filtered
        // Auto-highlight only when the user has typed something. In browse mode
        // (empty query) we leave highlight nil so Enter doesn't silently
        // checkout the most-recent branch.
        if !q.isEmpty, let first = filtered.first(where: { !$0.isInUse }) {
            highlightedID = first.id
        } else {
            highlightedID = nil
        }
    }
```

- [ ] **Step 4: Run tests and verify all pass**

Use test-runner-slim on `BranchListViewModelTests`.
Expected: PASS (both new tests + all existing tests).

- [ ] **Step 5: Commit**

```bash
git add tian/View/Worktree/BranchListViewModel.swift tianTests/BranchListViewModelTests.swift
git commit -m "♻️ refactor(BranchListViewModel): skip auto-highlight on empty query"
```

---

### Task 4: Rename `Notification.Name.showWorktreeBranchInput` and userInfo keys

This task renames the existing notification (and supporting userInfo keys) to a name that no longer implies "worktree only". The old userInfo working-directory key is dropped; the new listener resolves the working directory itself from the workspace.

**Files:**
- Modify: `tian/View/Sidebar/SidebarContainerView.swift:5-15`
- Modify: `tian/View/Sidebar/SidebarExpandedContentView.swift:37-46`
- Modify: `tian/View/Workspace/WorkspaceWindowContent.swift:75-98`
- Modify: `tian/WindowManagement/WorkspaceWindowController.swift:179-186`

- [ ] **Step 1: Update `SidebarContainerView.swift` extensions**

Replace lines 5-15 of `tian/View/Sidebar/SidebarContainerView.swift` with:

```swift
extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let focusSidebar = Notification.Name("focusSidebar")
    static let toggleDebugOverlay = Notification.Name("toggleDebugOverlay")
    static let showCreateSpaceInput = Notification.Name("showCreateSpaceInput")
}

extension Notification {
    static let createSpaceWorkspaceIDKey = "createSpaceWorkspaceID"
}
```

(The `worktreeWorkingDirectoryKey` is removed entirely. The old `worktreeWorkspaceIDKey` is replaced by `createSpaceWorkspaceIDKey`. The old notification name is removed.)

- [ ] **Step 2: Update `SidebarExpandedContentView.swift` to post the renamed notification**

This will be replaced more substantially in Task 9; for now, just rename the symbols inline so the file still compiles. Replace the `onNewWorktreeSpace:` closure at lines 37-46 with:

```swift
                        onNewWorktreeSpace: {
                            NotificationCenter.default.post(
                                name: .showCreateSpaceInput,
                                object: workspaceCollection,
                                userInfo: [
                                    Notification.createSpaceWorkspaceIDKey: workspace.id
                                ]
                            )
                        },
```

(Working directory key removed from userInfo.)

- [ ] **Step 3: Update `WorkspaceWindowContent.swift` to listen for the renamed notification**

Replace the `.onReceive(NotificationCenter.default.publisher(for: .showWorktreeBranchInput))` block (lines 75-98) with this transitional version (it preserves the existing `BranchNameInputView` modal — it'll be replaced by `CreateSpaceView` in Task 7):

```swift
        .onReceive(NotificationCenter.default.publisher(for: .showCreateSpaceInput)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            let workspaceID = notification.userInfo?[Notification.createSpaceWorkspaceIDKey] as? UUID
            // Resolve working directory from the workspace itself rather than
            // expecting it in userInfo.
            let workspace: Workspace? = {
                guard let id = workspaceID else { return workspaceCollection.activeWorkspace }
                return workspaceCollection.workspaces.first { $0.id == id }
            }()
            let wd = workspace?.spaceCollection.resolveWorkingDirectory() ?? ""
            Task {
                guard let repoRoot = try? await WorktreeService.resolveRepoRoot(from: wd) else {
                    return
                }
                let repoURL = URL(filePath: repoRoot)
                let configURL = WorktreeService.resolveConfigFile(repoRoot: repoURL)
                let config: WorktreeConfig
                if let configURL, let parsed = try? WorktreeConfigParser.parse(fileURL: configURL) {
                    config = parsed
                } else {
                    config = WorktreeConfig()
                }
                branchInputContext = BranchInputContext(
                    repoRoot: repoURL,
                    worktreeDir: config.worktreeDir,
                    workspaceID: workspaceID
                )
            }
        }
```

- [ ] **Step 4: Update `WorkspaceWindowController.swift`'s worktree handler**

Replace `handleNewWorktreeSpace()` at lines 179-186 with:

```swift
    private func handleNewWorktreeSpace() {
        let workspaceID = workspaceCollection.activeWorkspaceID
        var userInfo: [AnyHashable: Any] = [:]
        if let id = workspaceID {
            userInfo[Notification.createSpaceWorkspaceIDKey] = id
        }
        NotificationCenter.default.post(
            name: .showCreateSpaceInput,
            object: workspaceCollection,
            userInfo: userInfo
        )
    }
```

(The function name stays `handleNewWorktreeSpace` for now; it'll be removed entirely in Task 10.)

- [ ] **Step 5: Build to confirm everything still compiles**

Run: `scripts/build.sh Debug`
Expected: build succeeds. The old `worktreeWorkingDirectoryKey` and `worktreeWorkspaceIDKey` constants are now gone — the build acts as a grep, surfacing any stragglers. If any are reported, locate and update them (most likely just the four files above).

- [ ] **Step 6: Run tests to confirm no regressions**

Use test-runner-slim on the full `tianTests` target.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add tian/View/Sidebar/SidebarContainerView.swift \
        tian/View/Sidebar/SidebarExpandedContentView.swift \
        tian/View/Workspace/WorkspaceWindowContent.swift \
        tian/WindowManagement/WorkspaceWindowController.swift
git commit -m "♻️ refactor(notifications): rename showWorktreeBranchInput to showCreateSpaceInput"
```

---

### Task 5: Move `BranchListViewModel.swift` to `tian/View/CreateSpace/`

**Files:**
- Move: `tian/View/Worktree/BranchListViewModel.swift` → `tian/View/CreateSpace/BranchListViewModel.swift`

- [ ] **Step 1: Create the new directory and move the file**

```bash
mkdir -p tian/View/CreateSpace
git mv tian/View/Worktree/BranchListViewModel.swift tian/View/CreateSpace/BranchListViewModel.swift
```

- [ ] **Step 2: Update the file's leading comment to reflect the new path**

In the moved file, the first line is currently `// tian/View/Worktree/BranchListViewModel.swift`. Edit it to:

```swift
// tian/View/CreateSpace/BranchListViewModel.swift
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: `tian.xcodeproj` updates to reference the new path. (XcodeGen scans by directory pattern, so the move is automatic.)

- [ ] **Step 4: Build to confirm everything still resolves**

Run: `scripts/build.sh Debug`
Expected: build succeeds. (No imports change — Swift modules are flat.)

- [ ] **Step 5: Run tests**

Use test-runner-slim on the full `tianTests` target.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A tian/View/Worktree tian/View/CreateSpace tian.xcodeproj
git commit -m "🚚 chore(CreateSpace): relocate BranchListViewModel to new directory"
```

---

### Task 6: Replace `BranchNameInputView` with `CreateSpaceView`

This is the largest task. The existing file is renamed to a new path with substantially-rewritten contents.

**Files:**
- Move + rewrite: `tian/View/Worktree/BranchNameInputView.swift` → `tian/View/CreateSpace/CreateSpaceView.swift`

- [ ] **Step 1: Move the file**

```bash
git mv tian/View/Worktree/BranchNameInputView.swift tian/View/CreateSpace/CreateSpaceView.swift
```

- [ ] **Step 2: Replace the file contents**

Overwrite `tian/View/CreateSpace/CreateSpaceView.swift` with:

```swift
import SwiftUI

/// Unified modal for creating a space — with or without an associated git worktree.
/// Replaces the old `BranchNameInputView`.
struct CreateSpaceView: View {
    let workspace: Workspace
    let repoRoot: URL?           // nil when the workspace's working directory isn't a git repo
    let worktreeDir: String
    let onSubmitPlain: (String) -> Void
    let onSubmitWorktree: (CreateWorktreeSubmission) -> Void
    let onCancel: () -> Void

    @State private var inputText: String = ""
    @State private var worktreeEnabled: Bool
    @State private var viewModel = BranchListViewModel()
    @FocusState private var isFocused: Bool

    init(
        workspace: Workspace,
        repoRoot: URL?,
        worktreeDir: String,
        onSubmitPlain: @escaping (String) -> Void,
        onSubmitWorktree: @escaping (CreateWorktreeSubmission) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.repoRoot = repoRoot
        self.worktreeDir = worktreeDir
        self.onSubmitPlain = onSubmitPlain
        self.onSubmitWorktree = onSubmitWorktree
        self.onCancel = onCancel
        // Initial checkbox state: last-used per workspace, defaulting to false.
        // If the workspace isn't a git repo, force false regardless of memory.
        let remembered = workspace.lastCreateWorktreeChoice ?? false
        self._worktreeEnabled = State(initialValue: repoRoot != nil && remembered)
    }

    private var isGitRepo: Bool { repoRoot != nil }

    private var sanitizedInput: String {
        worktreeEnabled ? Self.sanitizeBranchName(inputText) : inputText
    }

    private var invalidCharsInBranchName: Bool {
        guard worktreeEnabled else { return false }
        return Self.containsInvalidBranchChars(sanitizedInput)
    }

    private var resolvedWorktreeRow: BranchRow? {
        // Only relevant in worktree mode. If a row is highlighted (user typed
        // or arrow-keyed to one), submit will checkout that existing branch.
        guard worktreeEnabled else { return nil }
        return viewModel.selectedRow()
    }

    private var canSubmit: Bool {
        guard !sanitizedInput.isEmpty else { return false }
        if worktreeEnabled {
            guard isGitRepo else { return false }
            if invalidCharsInBranchName { return false }
            // Block submit if the typed name matches an in-use worktree branch.
            if let collision = viewModel.collision(for: sanitizedInput), collision.isInUse {
                return false
            }
        }
        return true
    }

    private var resolvedPath: String {
        guard let repoRoot else { return "" }
        let base = WorktreeService.resolveWorktreeBase(
            repoRoot: repoRoot.path, worktreeDir: worktreeDir
        )
        let name = sanitizedInput.isEmpty ? "<branch>" : sanitizedInput
        return (base as NSString).appendingPathComponent(name)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { onCancel() }

            VStack(spacing: 12) {
                Text("New space")
                    .font(.system(size: 15, weight: .semibold))

                TextField(worktreeEnabled ? "Branch name" : "Space name", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onChange(of: inputText) { _, new in
                        // Live sanitization (worktree mode only).
                        if worktreeEnabled {
                            let cleaned = Self.sanitizeBranchName(new)
                            if cleaned != new {
                                inputText = cleaned
                            }
                            viewModel.query = cleaned
                        }
                    }
                    .onSubmit(handleSubmit)
                    .onExitCommand { onCancel() }
                    .onKeyPress(.upArrow) {
                        guard worktreeEnabled else { return .ignored }
                        viewModel.moveHighlight(.up); return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard worktreeEnabled else { return .ignored }
                        viewModel.moveHighlight(.down); return .handled
                    }

                Toggle(isOn: $worktreeEnabled) {
                    Text("Create worktree")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .disabled(!isGitRepo)
                .help(isGitRepo ? "" : "Workspace is not a git repository")
                .onChange(of: worktreeEnabled) { _, new in
                    workspace.lastCreateWorktreeChoice = new
                    if new {
                        // Push current input through sanitization & feed the list filter.
                        let cleaned = Self.sanitizeBranchName(inputText)
                        if cleaned != inputText { inputText = cleaned }
                        viewModel.query = cleaned
                    } else {
                        viewModel.query = ""
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if worktreeEnabled {
                    branchList
                }

                footer

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Create", action: handleSubmit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSubmit)
                }
            }
            .padding(20)
            .frame(width: 360)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .task {
            guard let repoRoot else { return }
            // Match what's in the field when the modal opens (usually empty).
            viewModel.query = sanitizedInput
            await viewModel.load(repoRoot: repoRoot.path)
        }
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }

    // MARK: - Subviews

    private var branchList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.rows.isEmpty {
                        Text(viewModel.loadError ?? "No matching branches")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.rows) { row in
                            branchRow(row).id(row.id)
                        }
                    }
                }
            }
            .onChange(of: viewModel.highlightedID) { _, new in
                guard let new else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func branchRow(_ row: BranchRow) -> some View {
        let highlighted = row.id == viewModel.highlightedID
        HStack(spacing: 8) {
            badge(row.badge)
                .frame(width: 52, alignment: .leading)
            Text(row.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            if row.isCurrent {
                Text("(current)")
                    .font(.system(size: 10).italic())
                    .foregroundStyle(.secondary)
            } else if row.isInUse {
                Text("(in use)")
                    .font(.system(size: 10).italic())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.relativeDate)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(highlighted ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(highlighted ? Color.accentColor : .clear)
                .frame(width: 2)
        }
        .opacity(row.isInUse ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !row.isInUse else { return }
            submit(branch: row.displayName, existing: true, remoteRef: row.remoteRef)
        }
    }

    @ViewBuilder
    private func badge(_ b: BranchRow.Badge) -> some View {
        switch b {
        case .local:
            Text("local")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
        case .origin(let name):
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.orange)
        case .localAndOrigin:
            Text("local")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if !worktreeEnabled {
                if !sanitizedInput.isEmpty {
                    Text("Will create plain space \u{201C}\(sanitizedInput)\u{201D}")
                }
            } else if !isGitRepo {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Workspace is not a git repository")
            } else if invalidCharsInBranchName {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Branch name contains invalid characters")
            } else if let collision = viewModel.collision(for: sanitizedInput), collision.isInUse {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\u{201C}\(collision.displayName)\u{201D} is already in use as a worktree")
            } else if viewModel.isFetching {
                ProgressView().controlSize(.mini)
                Text("Syncing remotes…")
            } else if viewModel.usedCachedRemotes {
                Text("Using cached remotes")
            } else {
                Text(resolvedPath)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private func handleSubmit() {
        guard canSubmit else { return }
        if worktreeEnabled {
            if let row = resolvedWorktreeRow {
                submit(branch: row.displayName, existing: true, remoteRef: row.remoteRef)
            } else {
                submit(branch: sanitizedInput, existing: false, remoteRef: nil)
            }
        } else {
            onSubmitPlain(sanitizedInput)
        }
    }

    private func submit(branch: String, existing: Bool, remoteRef: String?) {
        onSubmitWorktree(
            CreateWorktreeSubmission(
                branchName: branch,
                existingBranch: existing,
                remoteRef: remoteRef
            )
        )
    }

    // MARK: - Sanitization

    /// Live sanitization rule: replace ASCII space with `-`. Other characters
    /// pass through untouched; invalid ones are flagged via `containsInvalidBranchChars`.
    static func sanitizeBranchName(_ raw: String) -> String {
        raw.replacingOccurrences(of: " ", with: "-")
    }

    /// Returns true if the given (already-sanitized) branch name contains
    /// characters git rejects in ref names. The list is conservative — git's
    /// real rules are more nuanced (see `git check-ref-format`), but blocking
    /// these covers the cases users will hit.
    static func containsInvalidBranchChars(_ name: String) -> Bool {
        if name.isEmpty { return false }
        let banned: Set<Character> = ["~", "^", ":", "?", "*", "[", "\\"]
        if name.first == "-" { return true }
        if name.contains("..") { return true }
        return name.contains(where: { banned.contains($0) })
    }
}

/// Submission payload from the modal to the orchestrator.
struct CreateWorktreeSubmission {
    let branchName: String
    let existingBranch: Bool
    let remoteRef: String?
}
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: project includes `tian/View/CreateSpace/CreateSpaceView.swift` and no longer references `BranchNameInputView.swift`.

- [ ] **Step 4: Build (it will fail — `WorkspaceWindowContent` still references `BranchNameInputView`)**

Run: `scripts/build.sh Debug`
Expected: FAIL with "cannot find 'BranchNameInputView' in scope" inside `WorkspaceWindowContent.swift`. This is intentional and gets fixed in Task 7.

- [ ] **Step 5: Add sanitization tests**

Append the following inside the `CreateSpaceFlowTests` struct in `tianTests/CreateSpaceFlowTests.swift`:

```swift
    // MARK: - Branch name sanitization

    @Test func sanitizeReplacesSpacesWithDashes() {
        #expect(CreateSpaceView.sanitizeBranchName("foo bar baz") == "foo-bar-baz")
        #expect(CreateSpaceView.sanitizeBranchName(" leading") == "-leading")
        #expect(CreateSpaceView.sanitizeBranchName("trailing ") == "trailing-")
        #expect(CreateSpaceView.sanitizeBranchName("no-spaces") == "no-spaces")
    }

    @Test func sanitizeLeavesInvalidCharsAlone() {
        #expect(CreateSpaceView.sanitizeBranchName("foo~bar") == "foo~bar")
        #expect(CreateSpaceView.sanitizeBranchName("a:b") == "a:b")
    }

    @Test func invalidCharsDetected() {
        #expect(CreateSpaceView.containsInvalidBranchChars("good-name") == false)
        #expect(CreateSpaceView.containsInvalidBranchChars("nope~") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("a^b") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("a:b") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("a..b") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("-leading") == true)
        #expect(CreateSpaceView.containsInvalidBranchChars("") == false)
    }
```

- [ ] **Step 6: Don't run tests yet (build is broken)**

Note in the commit message that the build is intentionally broken at this commit; the fix lands in Task 7. (Alternative: defer this commit and bundle with Task 7. Either is acceptable, but separate commits make later review easier.)

- [ ] **Step 7: Commit**

```bash
git add tian/View/Worktree tian/View/CreateSpace tian.xcodeproj tianTests/CreateSpaceFlowTests.swift
git commit -m "✨ feat(CreateSpace): introduce CreateSpaceView (build broken until Task 7)"
```

---

### Task 7: Wire `CreateSpaceView` into `WorkspaceWindowContent`

**Files:**
- Modify: `tian/View/Workspace/WorkspaceWindowContent.swift` (entire file rewrite of the relevant sections)

- [ ] **Step 1: Replace the file with the updated version**

Overwrite `tian/View/Workspace/WorkspaceWindowContent.swift` with:

```swift
import SwiftUI

struct WorkspaceWindowContent: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator

    @State private var showDebugOverlay = false
    @State private var createSpaceRequest: CreateSpaceRequest?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SidebarContainerView(
                workspaceCollection: workspaceCollection,
                worktreeOrchestrator: worktreeOrchestrator
            )

            if worktreeOrchestrator.isCreating {
                SetupCancelButton { worktreeOrchestrator.cancelSetup() }
                    .padding(12)
                    .transition(.opacity)
            }

            if showDebugOverlay {
                DebugOverlayView()
                    .padding(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .overlay {
            if let req = createSpaceRequest, let workspace = req.workspace {
                CreateSpaceView(
                    workspace: workspace,
                    repoRoot: req.repoRoot,
                    worktreeDir: req.worktreeDir,
                    onSubmitPlain: { name in
                        let captured = req
                        createSpaceRequest = nil
                        let wd = captured.workspace?.spaceCollection.resolveWorkingDirectory() ?? "~"
                        captured.workspace?.spaceCollection.createSpace(
                            name: name,
                            workingDirectory: wd
                        )
                    },
                    onSubmitWorktree: { submission in
                        let captured = req
                        createSpaceRequest = nil
                        guard let repoRoot = captured.repoRoot else { return }
                        Task {
                            do {
                                _ = try await worktreeOrchestrator.createWorktreeSpace(
                                    branchName: submission.branchName,
                                    existingBranch: submission.existingBranch,
                                    remoteRef: submission.remoteRef,
                                    repoPath: repoRoot.path,
                                    workspaceID: captured.workspace?.id
                                )
                            } catch {
                                worktreeOrchestrator.presentError(error)
                            }
                        }
                    },
                    onCancel: { createSpaceRequest = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .alert(
            "Worktree error",
            isPresented: Binding(
                get: { worktreeOrchestrator.lastError != nil },
                set: { if !$0 { worktreeOrchestrator.lastError = nil } }
            ),
            presenting: worktreeOrchestrator.lastError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { err in
            Text(String(describing: err))   // WorktreeError conforms to CustomStringConvertible
        }
        .animation(.easeInOut(duration: 0.15), value: showDebugOverlay)
        .animation(.easeInOut(duration: 0.15), value: createSpaceRequest != nil)
        .animation(.easeInOut(duration: 0.15), value: worktreeOrchestrator.isCreating)
        .onReceive(NotificationCenter.default.publisher(for: .toggleDebugOverlay)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            showDebugOverlay.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCreateSpaceInput)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            let workspaceID = notification.userInfo?[Notification.createSpaceWorkspaceIDKey] as? UUID
            let workspace: Workspace? = {
                if let id = workspaceID,
                   let ws = workspaceCollection.workspaces.first(where: { $0.id == id }) {
                    return ws
                }
                return workspaceCollection.activeWorkspace
            }()
            guard let workspace else { return }
            let wd = workspace.spaceCollection.resolveWorkingDirectory()
            Task {
                let repoURL: URL?
                let configRepo: URL
                if let repoRootPath = try? await WorktreeService.resolveRepoRoot(from: wd) {
                    repoURL = URL(filePath: repoRootPath)
                    configRepo = repoURL!
                } else {
                    repoURL = nil
                    configRepo = URL(filePath: wd.isEmpty ? NSHomeDirectory() : wd)
                }
                let configURL = WorktreeService.resolveConfigFile(repoRoot: configRepo)
                let config: WorktreeConfig
                if let configURL, let parsed = try? WorktreeConfigParser.parse(fileURL: configURL) {
                    config = parsed
                } else {
                    config = WorktreeConfig()
                }
                createSpaceRequest = CreateSpaceRequest(
                    workspace: workspace,
                    repoRoot: repoURL,
                    worktreeDir: config.worktreeDir
                )
            }
        }
    }
}

// MARK: - Create Space Request

private struct CreateSpaceRequest: Equatable {
    weak var workspace: Workspace?
    let repoRoot: URL?
    let worktreeDir: String

    static func == (lhs: CreateSpaceRequest, rhs: CreateSpaceRequest) -> Bool {
        lhs.workspace?.id == rhs.workspace?.id
            && lhs.repoRoot == rhs.repoRoot
            && lhs.worktreeDir == rhs.worktreeDir
    }
}
```

Notes:
- The `BranchInputContext` struct is removed.
- `req.workspace` is `weak` to avoid retain cycles; in the unlikely case the workspace was closed mid-flight, the modal silently no-ops.
- `repoRoot == nil` represents "not a git repo" — `CreateSpaceView` disables the worktree checkbox accordingly.

- [ ] **Step 2: Build to confirm the project compiles again**

Run: `scripts/build.sh Debug`
Expected: build succeeds. (Resolves the breakage from Task 6.)

- [ ] **Step 3: Run the full test suite**

Use test-runner-slim on `tianTests`.
Expected: PASS. The new `CreateSpaceFlowTests` sanitization tests now run.

- [ ] **Step 4: Commit**

```bash
git add tian/View/Workspace/WorkspaceWindowContent.swift
git commit -m "✨ feat(CreateSpace): wire CreateSpaceView into WorkspaceWindowContent"
```

---

### Task 8: Enlarge sidebar `+` button and remove the worktree button

**Files:**
- Modify: `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift` (whole file)

- [ ] **Step 1: Replace the file**

Overwrite `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift` with:

```swift
import SwiftUI

struct SidebarWorkspaceHeaderView: View {
    let workspace: Workspace
    let isExpanded: Bool
    let isActive: Bool
    let isKeyboardSelected: Bool
    let isCreatingWorktree: Bool
    let onToggleDisclosure: () -> Void
    let onAddSpace: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            InlineRenameView(
                text: workspace.name,
                isRenaming: $isRenaming,
                onCommit: { workspace.name = $0 }
            )
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

            Spacer()

            if isCreatingWorktree {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }

            Button(action: onAddSpace) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.4, opacity: 1))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-space-\(workspace.id)")
            .accessibilityLabel("New space in \(workspace.name)")
            .help("New space (⇧⌘T)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .onHover { isHovering = $0 }
        .background {
            if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleDisclosure() }
        .draggable(WorkspaceDragItem(workspaceID: workspace.id))
        .contextMenu {
            Button("Rename") { isRenaming = true }
            Divider()
            DefaultDirectoryMenu(
                name: workspace.name,
                currentDirectory: workspace.defaultWorkingDirectory,
                onSet: onSetDirectory
            )
            Divider()
            Button("New Space...", action: onAddSpace)
            Divider()
            Button("Close Workspace", action: onClose)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workspace-header-\(workspace.id)")
        .accessibilityLabel("\(workspace.name), \(workspace.spaceCollection.spaces.count) spaces, \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityHint("Double-tap to expand or collapse")
    }
}
```

Changes vs. previous version:
- `onNewWorktreeSpace` parameter removed.
- The `arrow.triangle.branch` button (and its `Image(systemName:)`) removed.
- The `Text("+")` `+` button is replaced with `Image(systemName: "plus")` at font size 14 (was 12) inside an explicit 20×20 hit area.
- Tooltip added: `New space (⇧⌘T)`.
- Context-menu entry "New Worktree Space..." replaced by "New Space...".

- [ ] **Step 2: Build (will fail — `SidebarExpandedContentView` still passes `onNewWorktreeSpace:`)**

Run: `scripts/build.sh Debug`
Expected: FAIL — `extra argument 'onNewWorktreeSpace' in call`. Fixed in Task 9.

- [ ] **Step 3: Don't commit yet — fold this into Task 9's commit, OR commit with build broken (your call). For this plan we commit with the broken build to keep tasks independent.**

```bash
git add tian/View/Sidebar/SidebarWorkspaceHeaderView.swift
git commit -m "💄 ui(sidebar): collapse worktree button into enlarged + (build broken until Task 9)"
```

---

### Task 9: Update `SidebarExpandedContentView` to drop `onNewWorktreeSpace`

**Files:**
- Modify: `tian/View/Sidebar/SidebarExpandedContentView.swift` (only the `SidebarWorkspaceHeaderView` call site and the `addSpace(to:)` helper)

- [ ] **Step 1: Remove `onNewWorktreeSpace` from the `SidebarWorkspaceHeaderView` call**

In `tian/View/Sidebar/SidebarExpandedContentView.swift`, find the `SidebarWorkspaceHeaderView(...)` call (currently spanning lines 29-51 after Task 4's edit). Replace the `onNewWorktreeSpace:` closure block (the whole `onNewWorktreeSpace: { ... },` argument including its braces and trailing comma) with nothing — i.e., delete those lines so the call becomes:

```swift
                    SidebarWorkspaceHeaderView(
                        workspace: workspace,
                        isExpanded: disclosedWorkspaces.contains(workspace.id),
                        isActive: workspace.id == workspaceCollection.activeWorkspaceID,
                        isKeyboardSelected: selectedIndex == flatIndex(for: .workspaceHeader(workspace)),
                        isCreatingWorktree: worktreeOrchestrator.isCreating,
                        onToggleDisclosure: { toggleDisclosure(workspace.id) },
                        onAddSpace: { addSpace(to: workspace) },
                        onSetDirectory: { url in
                            workspace.setDefaultWorkingDirectory(url)
                        },
                        onClose: { workspaceCollection.removeWorkspace(id: workspace.id) }
                    )
```

- [ ] **Step 2: Change `addSpace(to:)` to post the unified notification**

Replace the existing `addSpace(to:)` helper (currently lines 154-158) with:

```swift
    private func addSpace(to workspace: Workspace) {
        NotificationCenter.default.post(
            name: .showCreateSpaceInput,
            object: workspaceCollection,
            userInfo: [
                Notification.createSpaceWorkspaceIDKey: workspace.id
            ]
        )
        disclosedWorkspaces.insert(workspace.id)
    }
```

- [ ] **Step 3: Build to confirm the project compiles**

Run: `scripts/build.sh Debug`
Expected: build succeeds.

- [ ] **Step 4: Run the full test suite**

Use test-runner-slim on `tianTests`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tian/View/Sidebar/SidebarExpandedContentView.swift
git commit -m "♻️ refactor(sidebar): + button now opens unified create-space modal"
```

---

### Task 10: Remove `KeyAction.newWorktreeSpace` and update the keybinding handler

**Files:**
- Modify: `tian/Input/KeyAction.swift:5-29` (remove one case)
- Modify: `tian/Input/KeyBindingRegistry.swift:74-75` (remove one binding)
- Modify: `tian/WindowManagement/WorkspaceWindowController.swift:137-159` (remove worktree case, change newSpace case)

- [ ] **Step 1: Remove `case newWorktreeSpace` from `KeyAction.swift`**

In `tian/Input/KeyAction.swift`, delete line 16 (`case newWorktreeSpace`). The enum should now have `case newSpace` immediately followed by the `// Workspace navigation` comment block.

- [ ] **Step 2: Remove the `.newWorktreeSpace` binding from `KeyBindingRegistry.swift`**

In `tian/Input/KeyBindingRegistry.swift`, delete the two-line block (currently lines 74-75):

```swift
        registry.bindings[.newWorktreeSpace] = [KeyBinding(
            characters: "b", keyCode: nil, modifiers: [.command, .shift])]
```

- [ ] **Step 3: Update `WorkspaceWindowController.swift`'s `.newSpace` case and remove `.newWorktreeSpace` case + helper**

In `tian/WindowManagement/WorkspaceWindowController.swift`:

(a) Delete lines 137-139 (the `.newWorktreeSpace` case):

```swift
            case .newWorktreeSpace:
                self.handleNewWorktreeSpace()
                return nil
```

(b) Replace the `.newSpace` case (currently lines 157-159) with one that posts the unified notification:

```swift
            case .newSpace:
                let workspaceID = self.workspaceCollection.activeWorkspaceID
                var userInfo: [AnyHashable: Any] = [:]
                if let id = workspaceID {
                    userInfo[Notification.createSpaceWorkspaceIDKey] = id
                }
                NotificationCenter.default.post(
                    name: .showCreateSpaceInput,
                    object: self.workspaceCollection,
                    userInfo: userInfo
                )
                return nil
```

(Note the early `return nil` — the case no longer falls through to `collection.createSpace(...)`. The rest of the switch (newTab, nextTab, etc.) is unaffected.)

(c) Delete the `handleNewWorktreeSpace()` helper (currently lines 179-186, which Task 4 already simplified). The whole function block is removed.

- [ ] **Step 4: Build to confirm everything still compiles**

Run: `scripts/build.sh Debug`
Expected: build succeeds. `KeyAction.newWorktreeSpace` is now gone — anything referencing it (e.g., docs comments in code, future tests) would surface as a compile error.

- [ ] **Step 5: Run the full test suite**

Use test-runner-slim on `tianTests`.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tian/Input/KeyAction.swift \
        tian/Input/KeyBindingRegistry.swift \
        tian/WindowManagement/WorkspaceWindowController.swift
git commit -m "✨ feat(keybindings): unify space creation under ⇧⌘T (retire ⇧⌘B)"
```

---

### Task 11: End-to-end manual smoke + final verification

This task has no code changes — it verifies the full flow works.

- [ ] **Step 1: Clean build and run**

```bash
scripts/build.sh Debug
open -W .build/Build/Products/Debug/tian.app
```

(If `open -W` blocks the shell, omit the `-W`. Also acceptable: launch via Xcode.)

- [ ] **Step 2: Verify each scenario in the running app**

For each, write a one-line note in the commit message of Step 4 about pass/fail.

- Open a workspace whose default directory is **not** a git repo.
  - Press ⇧⌘T → modal opens. Title is "New space". Checkbox is **disabled** with "Workspace is not a git repository" in the footer or tooltip.
  - Type `notes`, press Enter → modal dismisses, a new space named "notes" appears in the sidebar.
- Open a workspace inside a git repo with multiple branches.
  - Press ⇧⌘T → modal opens. Checkbox enabled. Toggle on → branch list appears, recency-sorted, no row highlighted.
  - Press ↓ → first selectable row highlights. Press Enter → existing branch checked out as a worktree, modal dismisses, new space appears.
  - Re-open modal → checkbox is **checked** (last-used remembered for this workspace).
  - Type a new branch name `feature exp` → live sanitization rewrites to `feature-exp`. Press Enter → new worktree branch created.
  - Type `feature/auth` (assuming this branch exists) → list narrows to one row, that row auto-highlights, footer shows the resolved worktree path. Enter → checks out existing.
  - Type `bad~name` → footer shows "Branch name contains invalid characters", Create button disabled.
  - Open modal, leave input empty, press Enter → nothing happens (Create disabled).
- Click the sidebar `+` button → same modal opens.
- Verify ⇧⌘B does **nothing** (no key handler).
- Right-click workspace header → context menu shows "New Space..." (no "New Worktree Space..." entry).

- [ ] **Step 3: Run the full test suite once more**

Use test-runner-slim on `tianTests`.
Expected: PASS.

- [ ] **Step 4: Commit any minor fixes discovered during smoke**

If smoke surfaces small bugs, fix them in the relevant file and commit with descriptive message. If everything passes cleanly, no commit is needed for this task — proceed to wrap up.

---

## Self-review checklist

Before declaring the plan complete, the executing agent should verify:

- [ ] Spec coverage: each section of `2026-04-14-workspace-creation-flow-design.md` maps to at least one task above.
- [ ] No `BranchNameInputView` references anywhere in the codebase (`grep -rn BranchNameInputView tian tianTests` returns zero hits).
- [ ] No `showWorktreeBranchInput`, `worktreeWorkingDirectoryKey`, `worktreeWorkspaceIDKey`, or `newWorktreeSpace` references anywhere (same grep approach).
- [ ] `tian/View/Worktree/` directory is empty (or removed if XcodeGen tolerates it).
- [ ] `xcodebuild` clean build passes with `-derivedDataPath .build`.
- [ ] All `tianTests` tests pass.
