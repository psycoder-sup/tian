# Graph Report - tian  (2026-07-10)

## Corpus Check
- 326 files · ~337,386 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4267 nodes · 10992 edges · 246 communities (167 shown, 79 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1464 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `80ba00d8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- IPC Command Handling
- Terminal Surface Input
- Session Git & PR Status
- Split Layout & Navigation
- Session State Migration
- CLI Command Router
- Git Repo Watcher
- Session Model
- Session Collection
- SwiftUI View Components
- Config Auto-Set Runner
- Session Overview Grid
- Sidebar Container
- Worktree Orchestrator
- Split Tree Model
- SSH Remote Execution
- Inspect File Tree Scanning
- ANSI Stripper
- Workspace Model
- Persistence State Models
- Command Logger
- Workspace Collection
- Refresh Scheduling & Coalescing
- Worktree Service
- Off-Main Process Runner
- Decision Record Schema
- Git Status Service
- Session State Fixtures
- Worktree Service Tests
- Test Harness Utilities
- Workspace Reorder Logic
- Inspect File Tree ViewModel
- Pane ViewModel
- Error Types
- Ghostty App Core
- Pane Status Manager
- Session Git Context Tests
- Sidebar Drag Reorder
- Session Migration Encoding Tests
- Background Activity Store
- Graphify Pipeline Skill
- Session Divider Drag
- Framework Imports
- Markdown Reader
- Worktree Config Parser
- Session Audit Analyzer
- Git Types
- Tian Skills & Delegation
- Working Tree Watcher
- Branch Graph Rendering
- Inspect File Scanner
- CLI Output Formatting
- Claude Session State
- Remote Connection & Workspace Create
- Inspect Branch ViewModel
- Markdown Diff Segments
- Ghostty Terminal Surface
- Branch List Tests
- IPC Client CLI
- Workspace Window Controller
- Inspect Diff ViewModel
- Inspect Panel View
- Create Session View
- Git Status Service Tests
- IPC Message Protocol
- Session Split Navigation
- Fuzzy Match
- Worktree Setup Progress
- Background Activity Sync
- Pane Node Building
- Pane Node Tree
- Create Session Flow Tests
- IPC Env Encoding
- Pane Status Aggregation Tests
- Session State Registry
- Session Restorer
- Session Restorer Tests
- Worktree Config Execution
- Quit Flow Coordinator
- Pane Hierarchy Wiring
- Inspect Tab State
- IPC Server Socket
- Key Binding Registry
- Session Content View
- Branch List Fakes
- App Delegate Lifecycle
- File Log Writer
- Window Drag Blocker
- Commit Graph Tests
- IPC Message Tests
- Remote Command Builder
- Skill Installer
- Branch List ViewModel
- Branch List Service
- Key Chord Model
- Key Actions
- Process Detector
- Status Doc Schema
- XcodeGen Build Config
- Terminal Content View
- Close Confirmation Dialog
- Image Reader
- Session Serializer
- Workspace Keyboard Navigation
- System Monitor (CPU/RAM)
- Check For Updates
- Working Directory Resolver
- App Hero Screenshot (UI)
- Shipped Items Schema
- Status Bar View
- SessionCloseFlow
- NotificationManager
- TianSettings
- Row
- AppKit
- KeyboardLayoutTranslator
- implement-log
- socklen_t
- AutoSetPrompt
- GitStatusServiceUnifiedDiffTests
- InspectPanelState
- SidebarExpandedContentView
- SidebarSessionRowView
- items
- EnvironmentBuilderTests
- WorktreeKindTests
- SessionSplitNavigation
- .move
- WorkspaceWindowContent
- implement
- os
- MarkdownCopyButton
- Response
- Response
- WorkspaceCreationFlowTests
- MockWorkspaceProvider
- status.schema
- BusyDotView
- .stopPreventsFurtherCallbacks
- blockingAwait
- .makeHarness
- AppMetrics
- InspectPanelFileRow
- Response
- ShellReadyReason
- InlineRenameView
- NSViewRepresentable
- os
- BranchListService
- RefreshSchedulerTests
- resolve_from_runlog
- ContinuousClock
- PaneState
- .unifiedDiff
- HtmlFileType
- ImageFileType
- DebugOverlayView
- InspectPanelTabRow
- ChangeBadgeView
- SidebarWorkspaceHeaderView
- EventCoalescerTests
- .send
- DebugOverlayView
- WorktreeConfig
- .fromIPCError
- .startClaude
- AppMetrics
- NSView
- publish
- SessionRestorer
- resolve_from_runlog
- DebugOverlayView
- EventCoalescerTests
- .makeTempGitRepo
- ConfirmAlert
- date
- done
- item
- TianApp
- tian-hook-prompt-test.sh
- Glowing Vertical Cursor Bar Motif
- WeakBox
- tian-hook-activity
- tian-hook-log
- Serena project config
- filter_zombies
- ConfirmAlert
- install
- release
- claude
- tian-hook-pr-refresh
- date
- Token reduction benchmark
- FalkorDB export
- .flagsChanged
- dev scratch space
- graphify knowledge graph
- NetworkImage
- CLIError+IPC.swift
- WorkingDirectoryResolver.swift
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- CLIError+IPC.swift
- CacheResult
- SessionDividerViewTests.swift
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- .applyRemoteChannel
- DockToggleDuringDragTests.swift
- RetryClaudeSpawnTests
- OrchestratorTestError
- CLAUDE.md
- T
- .claudePreviewText
- analyze.py session analyzer
- Orchestrator-implementer inversion check
- Orchestrator/implementer role hygiene
- session-audit skill
- implement-log.py run-log reviewer
- /tian implement delegation mode
- implement.sh delegation orchestrator
- implement-wait.sh await primitive
- implement-runs.jsonl run log
- TIAN SELF-VERIFY coda
- Single-writer worktree / anti-freelance rule
- TIAN_SOCKET IPC gate
- Workspace-Space-Tab-Pane hierarchy (legacy)
- ADR 0002: binary scope, orchestration in skill
- ADR 0003: accept context duplication, defer token opt
- ADR 0004: flatten hierarchy to Workspace-Session
- Claude Code hooks integration
- Session sidebar
- Worktree-backed sessions
- build-ghostty.sh
- build.sh
- install.sh
- publish.sh
- release.sh
- Ghostty (libghostty/GhosttyKit)
- IPCValue
- CGFloat
- Context
- tian-hook-prompt.sh

## God Nodes (most connected - your core abstractions)
1. `String` - 592 edges
2. `Foundation` - 171 edges
3. `Session` - 154 edges
4. `WorkspaceCollection` - 114 edges
5. `PaneStatusManager` - 111 edges
6. `IPCCommandHandler` - 108 edges
7. `View` - 108 edges
8. `Workspace` - 95 edges
9. `PaneViewModel` - 89 edges
10. `WindowCoordinator` - 85 edges

## Surprising Connections (you probably didn't know these)
- `CommandContext` --references--> `String`  [EXTRACTED]
  tian-cli/main.swift → tianTests/InspectFileTreeViewModelTests.swift
- `BranchEntry.Kind` --references--> `String`  [EXTRACTED]
  tian/View/CreateSession/BranchListViewModel.swift → tianTests/InspectFileTreeViewModelTests.swift
- `InspectTab` --references--> `String`  [EXTRACTED]
  tian/View/InspectPanel/InspectPanelStatusStrip.swift → tianTests/InspectFileTreeViewModelTests.swift
- `XcodeGen project.yml` --references--> `Swift Argument Parser`  [INFERRED]
  project.yml → THIRD-PARTY-NOTICES.md
- `XcodeGen project.yml` --references--> `TOMLKit`  [INFERRED]
  project.yml → THIRD-PARTY-NOTICES.md

## Import Cycles
- None detected.

## Communities (246 total, 79 thin omitted)

### Community 0 - "IPC Command Handling"
Cohesion: 0.13
Nodes (7): IPCCommandHandler, Int, WindowCoordinator, IPCCommandHandlerTests, IPCEnv, IPCRequest, IPCValue

### Community 1 - "Terminal Surface Input"
Cohesion: 0.11
Nodes (10): ghostty_input_mods_e, NSSize, NSTextInputClient, Selector, Any, Bool, NSCoder, NSTrackingArea (+2 more)

### Community 2 - "Session Git & PR Status"
Cohesion: 0.08
Nodes (8): Session, CGSize, ClaudeSessionState, Date, Void, CustomLaunchCommandTests, SessionModelTests, MainActor

### Community 3 - "Split Layout & Navigation"
Cohesion: 0.05
Nodes (30): CGPoint, First, Second, DividerInfo, SplitLayout, SplitLayoutResult, CGFloat, CGRect (+22 more)

### Community 4 - "Session State Migration"
Cohesion: 0.08
Nodes (22): Migration, MigrationError, futureVersion, migrationFailed, missingVersion, SessionStateMigrator, Any, Bool (+14 more)

### Community 5 - "CLI Command Router"
Cohesion: 0.06
Nodes (52): ExpressibleByArgument, ParsableCommand, IPCError, ActivityGroup, ActivitySync, GitGroup, GitRefresh, handleCreateResponse() (+44 more)

### Community 6 - "Git Repo Watcher"
Cohesion: 0.10
Nodes (8): HierarchicalEntry, SessionCollection, Bool, Int, URL, UUID, SessionCollectionStressTests, SessionCollectionTests

### Community 7 - "Session Model"
Cohesion: 0.13
Nodes (12): GitRepoStatus, SessionGitContext, Bool, Duration, Int, Never, Set, Task (+4 more)

### Community 8 - "Session Collection"
Cohesion: 0.09
Nodes (42): bash_commands(), buckets(), child_branch(), child_hygiene(), count_tools(), failed_delegate_tasks(), file_path_tools(), filter_zombies() (+34 more)

### Community 9 - "SwiftUI View Components"
Cohesion: 0.19
Nodes (6): Bool, IPCEnv, IPCRequest, IPCResponse, IPCValue, UUID

### Community 10 - "Config Auto-Set Runner"
Cohesion: 0.13
Nodes (18): Decodable, AutoSetPayload, ClaudeResultEnvelope, CopyEntry, SetupEntry, Bool, ConfigAutoSetResult, ConfigAutoSetRunner (+10 more)

### Community 11 - "Session Overview Grid"
Cohesion: 0.11
Nodes (11): InspectFileScanning, InspectFileTreeViewModel, LiveInspectFileScanner, async, Bool, Duration, Never, Set (+3 more)

### Community 12 - "Sidebar Container"
Cohesion: 0.07
Nodes (26): Accessibility, InspectPanelTabsWiringModifier, InspectPanelWiringModifier, Notification, Notification.Name, SessionOverviewOverlayModifier, SidebarContainerView, SidebarNotificationModifier (+18 more)

### Community 13 - "Worktree Orchestrator"
Cohesion: 0.24
Nodes (5): Any, Void, WorktreeOrchestrator, MockWorkspaceProvider, WorktreeOrchestratorTests

### Community 14 - "Split Tree Model"
Cohesion: 0.16
Nodes (12): SessionState, Date, Int, makeClaudeSession(), makeWorkspaceState(), SessionRestorerBuildTests, SessionRestorerLoadTests, SessionRestorerMetricsTests (+4 more)

### Community 15 - "SSH Remote Execution"
Cohesion: 0.11
Nodes (11): ghostty_surface_config_s, Int8, GhosttyTerminalSurface, Optional, Bool, ghostty_input_key_s, ghostty_surface_t, T (+3 more)

### Community 16 - "Inspect File Tree Scanning"
Cohesion: 0.10
Nodes (8): Bool, WindowFrame, UUID, Void, WorkspaceCollection, SessionSnapshotWindowGeometryTests, SessionSnapshotTests, SessionSnapshotWorktreePathTests

### Community 17 - "ANSI Stripper"
Cohesion: 0.11
Nodes (11): RemoveResult, lastPane, notFound, removed, SplitTree, Bool, Int, PaneNode (+3 more)

### Community 18 - "Workspace Model"
Cohesion: 0.11
Nodes (9): ANSIStripper, State, csi, escape, escapeIntermediate, normal, osc, oscEscape (+1 more)

### Community 19 - "Persistence State Models"
Cohesion: 0.08
Nodes (16): Bool, ClaudeSessionState, UUID, PaneViewModel, Bool, CGSize, ClaudeSessionState, NSObjectProtocol (+8 more)

### Community 20 - "Command Logger"
Cohesion: 0.09
Nodes (28): CodingKey, Encodable, CodingKeys, isError, result, structuredOutput, subtype, CodingKeys (+20 more)

### Community 21 - "Workspace Collection"
Cohesion: 0.14
Nodes (3): Int32, WorktreeServiceTests, WorktreeServiceTestsRunner

### Community 22 - "Refresh Scheduling & Coalescing"
Cohesion: 0.10
Nodes (18): ghostty_action_color_change_s, ghostty_action_s, ghostty_app_t, ghostty_clipboard_e, ghostty_config_t, ghostty_target_s, NSPasteboard, GhosttyApp (+10 more)

### Community 23 - "Worktree Service"
Cohesion: 0.05
Nodes (42): additionalProperties, description, type, description, type, description, type, description (+34 more)

### Community 24 - "Off-Main Process Runner"
Cohesion: 0.08
Nodes (24): DispatchWorkItem, FileHandle, FileLogWriter, ISO8601DateFormatter, UInt64, URL, KillGuard, State (+16 more)

### Community 25 - "Decision Record Schema"
Cohesion: 0.28
Nodes (7): IPCServer, async, Bool, Data, Int32, IPCResponse, UInt64

### Community 26 - "Git Status Service"
Cohesion: 0.07
Nodes (16): NSLayoutConstraint, NSWindowController, NSWindowDelegate, CGFloat, NSWindow, TrafficLightAligner, Bool, WindowFrame (+8 more)

### Community 27 - "Session State Fixtures"
Cohesion: 0.06
Nodes (20): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+12 more)

### Community 29 - "Test Harness Utilities"
Cohesion: 0.09
Nodes (3): Foundation, Testing, tian

### Community 30 - "Workspace Reorder Logic"
Cohesion: 0.07
Nodes (7): ForegroundProcessSummary, Int32, CGFloat, Int, WorkspaceReorderGeometry, Bool, WorkspaceCollectionTests

### Community 31 - "Inspect File Tree ViewModel"
Cohesion: 0.08
Nodes (10): Bool, Date, InspectFileTreeViewModel, URL, UUID, Workspace, WorkspaceSnapshot, DefaultWorkingDirectoryTests (+2 more)

### Community 32 - "Pane ViewModel"
Cohesion: 0.05
Nodes (35): Architecture, Build, Concepts, graphify, Keeping the record current (do this without being asked), Key Layers, Lifecycle, Logs (+27 more)

### Community 33 - "Error Types"
Cohesion: 0.13
Nodes (8): PaneStatusManager, Bool, ClaudeSessionState, Duration, Never, Void, PaneStatusManagerTests, UUID

### Community 34 - "Ghostty App Core"
Cohesion: 0.35
Nodes (7): CharacterChord, KeyBinding, KeyBindingRegistry, KeyCodeChord, NSEvent, UInt16, UInt

### Community 35 - "Pane Status Manager"
Cohesion: 0.13
Nodes (16): GitRepoID, PRStatus, URL, CacheEntry, CacheKey, CacheResult, hit, miss (+8 more)

### Community 36 - "Session Git Context Tests"
Cohesion: 0.09
Nodes (20): WorktreeKind, linkedWorktree, mainCheckout, notARepo, noWorkingDirectory, InspectPanelHeader, Bool, CGFloat (+12 more)

### Community 37 - "Sidebar Drag Reorder"
Cohesion: 0.09
Nodes (14): DragGesture, PreferenceKey, SidebarExpandedContentView, SidebarItem, sessionRow, workspaceHeader, CGFloat, CGRect (+6 more)

### Community 38 - "Session Migration Encoding Tests"
Cohesion: 0.16
Nodes (6): NSMenu, NSScreen, ghostty_input_key_s, ghostty_surface_t, NSEvent, UInt32

### Community 39 - "Background Activity Store"
Cohesion: 0.07
Nodes (17): CFTimeInterval, CoreServices, CallbackBox, GitRepoWatcher, Bool, DispatchQueue, escaping, FSEventStreamRef (+9 more)

### Community 41 - "Session Divider Drag"
Cohesion: 0.12
Nodes (13): Binding, SessionOverviewCardView, Bool, Void, WorkspaceChip, CreateWorkspaceView, Field, directory (+5 more)

### Community 42 - "Framework Imports"
Cohesion: 0.10
Nodes (23): S, DiffBinaryPlaceholderRow, DiffFileHeaderRow, DiffHunkHeaderRow, DiffLineRow, DiffTruncatedRow, Bool, CGFloat (+15 more)

### Community 43 - "Markdown Reader"
Cohesion: 0.07
Nodes (24): MarkdownContent, MarkdownUI, ReaderFileSource, RemoteReaderFileSource, Data, Date, DiffColors, MarkdownDiffView (+16 more)

### Community 44 - "Worktree Config Parser"
Cohesion: 0.12
Nodes (12): table, CopyRule, LayoutNode, pane, split, Int, SplitDirection, TimeInterval (+4 more)

### Community 45 - "Session Audit Analyzer"
Cohesion: 0.07
Nodes (11): BackgroundActivity, Kind, agent, bash, other, Bool, Date, TimeInterval (+3 more)

### Community 46 - "Git Types"
Cohesion: 0.06
Nodes (36): CustomStringConvertible, Error, Logger, NotificationError, permissionDenied, RestoreError, emptySessions, emptyWorkspaces (+28 more)

### Community 48 - "Working Tree Watcher"
Cohesion: 0.14
Nodes (14): DispatchSourceTimer, Box, Bool, DispatchQueue, Duration, FSEventStreamRef, Int, Void (+6 more)

### Community 49 - "Branch Graph Rendering"
Cohesion: 0.11
Nodes (13): Float, SIMD2, Color, BranchGraphCanvas, InspectBranchBody, Bool, CGFloat, ClaudeSessionState (+5 more)

### Community 50 - "Inspect File Scanner"
Cohesion: 0.16
Nodes (7): GitChangedFile, BlockingScanner, FixedScanner, InspectFileTreeViewModel, InspectFileTreeViewModelTests, Bool, URL

### Community 51 - "CLI Output Formatting"
Cohesion: 0.18
Nodes (7): SessionSerializer, ClaudeSessionState, Data, URL, UUID, SessionSerializerWriteTests, URL

### Community 52 - "Claude Session State"
Cohesion: 0.08
Nodes (8): ClaudeNotificationPolicy, ClaudeNotificationTrigger, done, needsAttention, Bool, ClaudeSessionState, ClaudeNotificationPolicyTests, ClaudeSessionStateTests

### Community 53 - "Remote Connection & Workspace Create"
Cohesion: 0.15
Nodes (3): Date, BranchListViewModelTests, Date

### Community 54 - "Inspect Branch ViewModel"
Cohesion: 0.11
Nodes (14): RestoreMetrics, RestoreResult, Source, backup, primary, Bool, Int, SessionRestorer (+6 more)

### Community 55 - "Markdown Diff Segments"
Cohesion: 0.08
Nodes (27): build_manifest(), Handler, iter_json_files(), main(), Every *.json under ROOT (used both for the manifest and the mtime watch)., Map of json path -> mtime, for change detection., Describe what exists so the dashboard can discover docs and ADRs., serve() (+19 more)

### Community 56 - "Ghostty Terminal Surface"
Cohesion: 0.11
Nodes (17): KeyAction, closeWorkspace, cycleFocusArea, focusSidebar, goToSession, newSession, newWorkspace, nextSession (+9 more)

### Community 57 - "Branch List Tests"
Cohesion: 0.15
Nodes (8): InspectFileScanner, ScannerError, decodeFailed, gitFailed, Data, Int32, URL, InspectFileScannerTests

### Community 58 - "IPC Client CLI"
Cohesion: 0.13
Nodes (9): BranchEntry, BranchListProviding, BranchListServiceAdapter, Bool, Date, Kind, FakeService, FakingListService (+1 more)

### Community 59 - "Workspace Window Controller"
Cohesion: 0.15
Nodes (14): GitCommitGraph, BranchGraphDirtyHost, InspectBranchViewModel, SessionGitContext, Bool, Never, Task, Void (+6 more)

### Community 60 - "Inspect Diff ViewModel"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 61 - "Inspect Panel View"
Cohesion: 0.14
Nodes (10): NSApplicationDelegate, NSObject, Bool, NSApplication, TianAppDelegate, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse (+2 more)

### Community 62 - "Create Session View"
Cohesion: 0.13
Nodes (17): Character, CreateSessionView, CreateWorktreeSubmission, Field, dialog, name, SubmitAction, blocked (+9 more)

### Community 63 - "Git Status Service Tests"
Cohesion: 0.23
Nodes (7): SessionOverviewSort, ClaudeSessionState, T, Item, SessionOverviewSortTests, ClaudeSessionState, Int

### Community 64 - "IPC Message Protocol"
Cohesion: 0.19
Nodes (8): Kind, added, removed, unchanged, MarkdownDiffSegment, MarkdownInlineDiff, Int, MarkdownInlineDiffTests

### Community 65 - "Session Split Navigation"
Cohesion: 0.25
Nodes (12): GitFileDiff, InspectDiffViewModel, Bool, Duration, Never, Set, Task, Void (+4 more)

### Community 67 - "Worktree Setup Progress"
Cohesion: 0.14
Nodes (14): escaping, T, Double, AppMetrics, Int, UInt64, Snapshot, Duration (+6 more)

### Community 69 - "Pane Node Building"
Cohesion: 0.14
Nodes (4): InspectTabState, Bool, InspectTab, InspectTabStateTests

### Community 70 - "Pane Node Tree"
Cohesion: 0.12
Nodes (22): Identifiable, GitCommit, GitDiffHunk, GitDiffLine, GitDiffSummary, GitFileStatus, added, deleted (+14 more)

### Community 71 - "Create Session Flow Tests"
Cohesion: 0.05
Nodes (25): RemoteInspectFileScanner, RemoteScanError, commandFailed, Data, Duration, Int32, URL, RemoteCommandBuilder (+17 more)

### Community 72 - "IPC Env Encoding"
Cohesion: 0.17
Nodes (7): SparklineView, CGFloat, StatusBarPalette, StatusBarView, CGFloat, UInt64, Value

### Community 73 - "Pane Status Aggregation Tests"
Cohesion: 0.16
Nodes (4): FuzzyMatch, Result, Int, FuzzyMatchTests

### Community 74 - "Session State Registry"
Cohesion: 0.16
Nodes (9): PaneNode, leaf, split, SplitDirection, horizontal, vertical, Bool, Int (+1 more)

### Community 75 - "Session Restorer"
Cohesion: 0.13
Nodes (19): Codable, IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool (+11 more)

### Community 76 - "Session Restorer Tests"
Cohesion: 0.10
Nodes (16): JSONDecoder, PaneLeafState, SessionRecord, Bool, ClaudeSessionState, UUID, WindowFrame, WorkspaceState (+8 more)

### Community 77 - "Worktree Config Execution"
Cohesion: 0.14
Nodes (5): GitStatusService, Bool, Int, Int32, GitStatusServiceTests

### Community 78 - "Quit Flow Coordinator"
Cohesion: 0.25
Nodes (4): NSAttributedString, NSRange, NSRangePointer, NSRect

### Community 79 - "Pane Hierarchy Wiring"
Cohesion: 0.11
Nodes (18): A Session = one Claude pane + a toggleable terminal panel, Command reference, Core rules, Delegation orchestrator (bundled script — backs `/tian implement`), Discovery, Driving tian with the `tian` CLI, Gotchas, Long-session hygiene (+10 more)

### Community 80 - "Inspect Tab State"
Cohesion: 0.26
Nodes (6): ClaudeSessionNotifier, Duration, NotificationManager, Bool, UUID, NotificationManagerTests

### Community 81 - "IPC Server Socket"
Cohesion: 0.19
Nodes (9): SessionContentView, Bool, CGFloat, CGSize, SessionHeaderView, CGFloat, SplitTreeView, Bool (+1 more)

### Community 82 - "Key Binding Registry"
Cohesion: 0.09
Nodes (19): SidebarSessionRowMutationGate, SidebarSessionRowView, Bool, CGFloat, Date, URL, UUID, Void (+11 more)

### Community 84 - "Branch List Fakes"
Cohesion: 0.20
Nodes (10): InspectDiffBody, Row, binary, divider, fileHeader, hunkHeader, line, truncated (+2 more)

### Community 85 - "App Delegate Lifecycle"
Cohesion: 0.29
Nodes (5): Harness, Int, NSView, NSWindow, TerminalSurfaceViewFocusTests

### Community 86 - "File Log Writer"
Cohesion: 0.33
Nodes (4): InspectPanelState, Bool, CGFloat, InspectPanelStateTests

### Community 88 - "Commit Graph Tests"
Cohesion: 0.32
Nodes (5): SkillInstaller, URL, UserDefaults, SkillInstallerTests, URL

### Community 89 - "IPC Message Tests"
Cohesion: 0.29
Nodes (7): FileTreeNode, Kind, directory, file, Bool, Int, Kind

### Community 90 - "Remote Command Builder"
Cohesion: 0.20
Nodes (8): Direction, down, left, right, up, OverviewGridNavigation, Int, UUID

### Community 91 - "Skill Installer"
Cohesion: 0.31
Nodes (4): BranchListService, Int32, Set, BranchListServiceTests

### Community 92 - "Branch List ViewModel"
Cohesion: 0.13
Nodes (6): ProcessDetector, RunningProcessInfo, Bool, Int, UUID, ProcessDetectorTests

### Community 93 - "Branch List Service"
Cohesion: 0.08
Nodes (18): ArgumentParser, ClaudeInvoker, ProcessClaudeInvoker, URL, ConfigAutoSet, ConfigGroup, Bool, IPCClient (+10 more)

### Community 94 - "Key Chord Model"
Cohesion: 0.23
Nodes (4): KeyBindingRegistryPhase3Tests, KeyBindingRegistryTests, NSEvent, UInt16

### Community 95 - "Key Actions"
Cohesion: 0.12
Nodes (16): description, type, description, type, description, type, description, type (+8 more)

### Community 96 - "Process Detector"
Cohesion: 0.27
Nodes (5): Carbon.HIToolbox, KeyboardLayoutTranslator, Data, UInt16, UInt32

### Community 97 - "Status Doc Schema"
Cohesion: 0.18
Nodes (7): Coordinator, Bool, Context, NSView, SplitDirection, UUID, TerminalContentView

### Community 99 - "Terminal Content View"
Cohesion: 0.24
Nodes (8): CloseConfirmationDialog, CloseTarget, pane, Int, NSAlert, NSWindow, Void, CloseConfirmationDialogTests

### Community 100 - "Close Confirmation Dialog"
Cohesion: 0.27
Nodes (6): PollingRefresher, Duration, MainActor, Never, Task, Void

### Community 101 - "Image Reader"
Cohesion: 0.18
Nodes (9): ImageIO, NSImage, ImageDocument, Sendbox, Date, T, ImageReaderView, Bool (+1 more)

### Community 102 - "Session Serializer"
Cohesion: 0.16
Nodes (9): GridItem, SessionOverviewSortMode, defaultOrder, sessionState, CardEntry, SessionOverviewGridView, CGFloat, Int (+1 more)

### Community 103 - "Workspace Keyboard Navigation"
Cohesion: 0.22
Nodes (3): SessionDividerDragController, Bool, Void

### Community 104 - "System Monitor (CPU/RAM)"
Cohesion: 0.14
Nodes (13): Architecture, Build, Concepts, Key Layers, Lifecycle, Logs, Scratch / Temporary Files, Source Layout (+5 more)

### Community 105 - "Check For Updates"
Cohesion: 0.06
Nodes (36): CaseIterable, Comparable, Equatable, Sendable, ClaudeSessionState, active, busy, failed (+28 more)

### Community 106 - "Working Directory Resolver"
Cohesion: 0.18
Nodes (5): EnvironmentBuilder, UUID, PaneHierarchyContext, UUID, EnvironmentBuilderTests

### Community 107 - "App Hero Screenshot (UI)"
Cohesion: 0.24
Nodes (13): Claude Pane (Claude Code v2.1.140), Claude Code Statusline (ctx/model/branch), File Explorer Panel (Files/Diff/Branch), Workspace -> Session -> Pane Hierarchy, New Workspace Action, Session Row (name + branch + git diff), Workspace/Session Sidebar, Bottom Status Bar (CPU/RAM) (+5 more)

### Community 108 - "Shipped Items Schema"
Cohesion: 0.40
Nodes (6): sockaddr_un, socklen_t, IPCServerTests, connectionFailed, Data, Int

### Community 109 - "Status Bar View"
Cohesion: 0.22
Nodes (9): CreateSessionRequest, Bool, CGFloat, Duration, Never, Task, URL, Void (+1 more)

### Community 110 - "SessionCloseFlow"
Cohesion: 0.15
Nodes (13): description, type, properties, commit, since, summary, target, description (+5 more)

### Community 111 - "NotificationManager"
Cohesion: 0.20
Nodes (6): InspectChildEntry, InspectIgnoredEntries, Bool, Set, CountingScanner, Int

### Community 112 - "TianSettings"
Cohesion: 0.17
Nodes (5): DirectoryPicker, URL, URL, WorkspaceCreationFlow, WorkspaceCreationFlowTests

### Community 113 - "Row"
Cohesion: 0.18
Nodes (5): SessionCloseFlow, Bool, NSWindow, URL, Error

### Community 114 - "AppKit"
Cohesion: 0.08
Nodes (21): NSView, NSViewRepresentable, Context, NSView, NSWindow, WindowAccessor, KeyView, SidebarKeyboardResponder (+13 more)

### Community 115 - "KeyboardLayoutTranslator"
Cohesion: 0.33
Nodes (5): Bool, UserDefaults, TianSettings, UserDefaults, TianSettingsTests

### Community 116 - "implement-log"
Cohesion: 0.11
Nodes (11): Content, image, markdown, SessionReaderState, DefaultDirectoryMenu, URL, Void, ReaderOverlayView (+3 more)

### Community 117 - "socklen_t"
Cohesion: 0.10
Nodes (13): Log, ClosedRange, TimeInterval, WorktreeConfig, Bool, T, URL, UUID (+5 more)

### Community 118 - "AutoSetPrompt"
Cohesion: 0.25
Nodes (7): KeyView, OverviewKeyboardResponder, Bool, Context, KeyView, NSEvent, Void

### Community 120 - "InspectPanelState"
Cohesion: 0.67
Nodes (3): description, type, link

### Community 121 - "SidebarExpandedContentView"
Cohesion: 0.20
Nodes (6): ClosedRange, SessionDividerView, Bool, CGFloat, CGSize, Gesture

### Community 122 - "SidebarSessionRowView"
Cohesion: 0.29
Nodes (10): items, additionalProperties, required, type, items, items, shipped, description (+2 more)

### Community 123 - "items"
Cohesion: 0.11
Nodes (10): CoreGraphics, SessionDividerClamper, Bool, CGFloat, SessionLayout, CGFloat, CGRect, CGSize (+2 more)

### Community 124 - "EnvironmentBuilderTests"
Cohesion: 0.19
Nodes (9): BranchListViewModel, BranchRow, Direction, down, up, Mode, existingBranch, newBranch (+1 more)

### Community 125 - "WorktreeKindTests"
Cohesion: 0.14
Nodes (10): SessionGitContext, SessionSplitNavigation, CGRect, CGSize, PaneNode, UUID, Target, Bool (+2 more)

### Community 129 - "WorkspaceWindowContent"
Cohesion: 0.25
Nodes (5): sockaddr, blockingAwait(), escaping, T, UnsafePointer

### Community 130 - "implement"
Cohesion: 0.40
Nodes (4): PaneStatus, T, UInt64, WeakBox

### Community 131 - "os"
Cohesion: 0.22
Nodes (8): LocalizedError, CLIError, closeInFlight, connection, general, permissionDenied, processSafety, Int32

### Community 132 - "MarkdownCopyButton"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 133 - "Response"
Cohesion: 0.42
Nodes (7): emit_block(), err(), log_run(), need_val(), implement.sh script, log(), usage()

### Community 134 - "Response"
Cohesion: 0.33
Nodes (3): DebugOverlayView, LabeledMetric, Timer

### Community 135 - "WorkspaceCreationFlowTests"
Cohesion: 0.33
Nodes (7): MarkdownCopyButton, MarkdownDiffToggleButton, ReaderCloseButton, CGFloat, Never, Task, Void

### Community 136 - "MockWorkspaceProvider"
Cohesion: 0.33
Nodes (4): InspectPanelTabRow, Bool, CGFloat, InspectTab

### Community 137 - "status.schema"
Cohesion: 0.25
Nodes (7): Response, cancel, skipTeardown, SkipTeardownConfirmationDialog, Int, NSWindow, Void

### Community 138 - "BusyDotView"
Cohesion: 0.25
Nodes (7): Response, cancel, closeOnly, removeWorktreeAndClose, NSWindow, Void, WorktreeCloseDialog

### Community 139 - ".stopPreventsFurtherCallbacks"
Cohesion: 0.40
Nodes (5): ContinuousClock, PollTimeoutError, pollUntil(), Duration, MainActor

### Community 140 - "blockingAwait"
Cohesion: 0.11
Nodes (8): Darwin, os, OSLog, BranchDeleteOutcome, deleted, keptUnmerged, notFound, State

### Community 141 - ".makeHarness"
Cohesion: 0.33
Nodes (5): SidebarWorkspaceHeaderView, Bool, URL, Void, WorkspaceDropIndicator

### Community 142 - "AppMetrics"
Cohesion: 0.25
Nodes (7): How to read the output, Improvement catalog (map flags → fixes), Input, Litmus test to report, Run, session-audit — audit a tian orchestrator session, What to produce

### Community 143 - "InspectPanelFileRow"
Cohesion: 0.21
Nodes (8): NSAlert, ConfirmAlert, QuitConfirmationDialog, Bool, Int, NSAlert, NSWindow, Void

### Community 144 - "Response"
Cohesion: 0.33
Nodes (5): ChangeBadgeView, Int, Never, Task, Void

### Community 145 - "ShellReadyReason"
Cohesion: 0.25
Nodes (7): additionalProperties, description, $id, required, $schema, title, type

### Community 146 - "InlineRenameView"
Cohesion: 0.33
Nodes (4): Font, InlineRenameView, Bool, Void

### Community 147 - "NSViewRepresentable"
Cohesion: 0.25
Nodes (7): Cutting a release, Day-to-day, Environment, Examples, scripts, Versioning, What's here

### Community 148 - "os"
Cohesion: 0.35
Nodes (10): commit_count(), committed(), dedup(), delegation_key(), load(), main(), pct(), rank() (+2 more)

### Community 150 - "RefreshSchedulerTests"
Cohesion: 0.32
Nodes (6): InspectPanelFileRow, Spacing, Bool, CGFloat, Int, Void

### Community 151 - "resolve_from_runlog"
Cohesion: 0.29
Nodes (6): Response, cancel, forceRemove, NSWindow, Void, WorktreeForceRemoveDialog

### Community 152 - "ContinuousClock"
Cohesion: 0.40
Nodes (4): InspectPanelStatusStrip, InspectTab, CGFloat, InspectTab

### Community 153 - "PaneState"
Cohesion: 0.29
Nodes (6): ShellReadinessWaiter, ShellReadyReason, osc7, timeout, TimeInterval, UUID

### Community 157 - "DebugOverlayView"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 158 - "InspectPanelTabRow"
Cohesion: 0.17
Nodes (9): Commands, ObservableObject, Sparkle, CheckForUpdatesView, CheckForUpdatesViewModel, SPUUpdater, SPUUpdater, WorkspaceCommands (+1 more)

### Community 160 - "SidebarWorkspaceHeaderView"
Cohesion: 0.40
Nodes (3): App, Scene, TianApp

### Community 161 - "EventCoalescerTests"
Cohesion: 0.40
Nodes (5): PRState, closed, draft, merged, open

### Community 162 - ".send"
Cohesion: 0.25
Nodes (8): Hashable, Badge, local, localAndOrigin, origin, Kind, local, remote

### Community 167 - "AppMetrics"
Cohesion: 0.04
Nodes (28): Observation, SwiftUI, SettingsView, Keys, BranchEntry.Kind, InspectPanelFileBrowser, InspectFileTreeViewModel, Void (+20 more)

### Community 169 - "publish"
Cohesion: 0.50
Nodes (4): FileBaseline, committed, notInRepo, untracked

### Community 171 - "resolve_from_runlog"
Cohesion: 0.67
Nodes (3): description, type, item

### Community 172 - "DebugOverlayView"
Cohesion: 0.67
Nodes (3): title, description, type

### Community 173 - "EventCoalescerTests"
Cohesion: 0.08
Nodes (18): AnyObject, WorkspaceProviding, Bool, UUID, WorktreeCreateResult, WorktreeError, baseWithExisting, branchAlreadyExists (+10 more)

### Community 176 - "date"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 177 - "done"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 178 - "item"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 180 - "tian-hook-prompt-test.sh"
Cohesion: 0.80
Nodes (4): assert_forwarded(), assert_rejected(), run_hook(), tian-hook-prompt-test.sh script

### Community 181 - "Glowing Vertical Cursor Bar Motif"
Cohesion: 1.00
Nodes (3): Glowing Vertical Cursor Bar Motif, tian App Icon (macOS AppIcon), Terminal Emulator Symbolism

### Community 182 - "WeakBox"
Cohesion: 0.50
Nodes (4): description, items, type, now

### Community 186 - "filter_zombies"
Cohesion: 0.83
Nodes (3): tian-bash-integration.bash script, _tian_fix_path(), _tian_install_claude_wrapper()

### Community 188 - "ConfirmAlert"
Cohesion: 0.20
Nodes (3): AppKit, CGRect, WindowFrame

### Community 192 - "tian-hook-pr-refresh"
Cohesion: 0.67
Nodes (3): description, type, blocked

### Community 193 - "date"
Cohesion: 0.67
Nodes (3): description, type, date

### Community 195 - "FalkorDB export"
Cohesion: 0.67
Nodes (3): description, type, done

### Community 198 - "graphify knowledge graph"
Cohesion: 0.25
Nodes (9): Bundle tian CLI build phase, Bundled Claude hook scripts, tian-cli tool target, tian app target, tianTests target, XcodeGen project.yml, MarkdownUI, Swift Argument Parser (+1 more)

### Community 214 - "T"
Cohesion: 0.16
Nodes (4): RemoteConnectionState, RemoteConnection, Bool, RemoteConnectionTests

## Knowledge Gaps
- **426 isolated node(s):** `$schema`, `$id`, `title`, `description`, `type` (+421 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **79 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `Git Types` to `IPC Command Handling`, `Terminal Surface Input`, `Session Git & PR Status`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `Session Model`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Sidebar Container`, `Worktree Orchestrator`, `Split Tree Model`, `SSH Remote Execution`, `Inspect File Tree Scanning`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Workspace Collection`, `Refresh Scheduling & Coalescing`, `Off-Main Process Runner`, `Decision Record Schema`, `Git Status Service`, `Session State Fixtures`, `Worktree Service Tests`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Error Types`, `Ghostty App Core`, `Pane Status Manager`, `Session Git Context Tests`, `Sidebar Drag Reorder`, `Background Activity Store`, `Graphify Pipeline Skill`, `Session Divider Drag`, `Framework Imports`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Working Tree Watcher`, `Branch Graph Rendering`, `Inspect File Scanner`, `CLI Output Formatting`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `Branch List Tests`, `IPC Client CLI`, `Workspace Window Controller`, `Create Session View`, `IPC Message Protocol`, `Session Split Navigation`, `Fuzzy Match`, `Worktree Setup Progress`, `Background Activity Sync`, `Pane Node Building`, `Pane Node Tree`, `Create Session Flow Tests`, `IPC Env Encoding`, `Pane Status Aggregation Tests`, `Session State Registry`, `Session Restorer`, `Session Restorer Tests`, `Worktree Config Execution`, `Inspect Tab State`, `IPC Server Socket`, `Key Binding Registry`, `Session Content View`, `Branch List Fakes`, `Window Drag Blocker`, `Commit Graph Tests`, `IPC Message Tests`, `Skill Installer`, `Branch List ViewModel`, `Branch List Service`, `Key Chord Model`, `Process Detector`, `Image Reader`, `Session Serializer`, `Check For Updates`, `Working Directory Resolver`, `Shipped Items Schema`, `Status Bar View`, `NotificationManager`, `TianSettings`, `KeyboardLayoutTranslator`, `implement-log`, `socklen_t`, `GitStatusServiceUnifiedDiffTests`, `EnvironmentBuilderTests`, `WorktreeKindTests`, `SessionSplitNavigation`, `PollingRefresher`, `implement`, `os`, `Response`, `MockWorkspaceProvider`, `BusyDotView`, `blockingAwait`, `InlineRenameView`, `RefreshSchedulerTests`, `resolve_from_runlog`, `ContinuousClock`, `.unifiedDiff`, `EventCoalescerTests`, `.send`, `.fromIPCError`, `.startClaude`, `AppMetrics`, `publish`, `EventCoalescerTests`, `.makeTempGitRepo`, `tian-hook-log`, `T`, `CGFloat`, `Context`?**
  _High betweenness centrality (0.553) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Harness Utilities` to `WorkspaceWindowContent`, `implement`, `os`, `Split Layout & Navigation`, `CLI Command Router`, `Session State Migration`, `Git Repo Watcher`, `Config Auto-Set Runner`, `.stopPreventsFurtherCallbacks`, `blockingAwait`, `Split Tree Model`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `BranchListService`, `Off-Main Process Runner`, `PaneState`, `Git Status Service`, `Session State Fixtures`, `HtmlFileType`, `Inspect File Tree ViewModel`, `Pane Status Manager`, `Session Git Context Tests`, `.fromIPCError`, `Background Activity Store`, `AppMetrics`, `SessionRestorer`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Git Types`, `EventCoalescerTests`, `Working Tree Watcher`, `CLI Output Formatting`, `Claude Session State`, `Markdown Diff Segments`, `tian-hook-log`, `Branch List Tests`, `IPC Client CLI`, `Workspace Window Controller`, `ConfirmAlert`, `Git Status Service Tests`, `IPC Message Protocol`, `Pane Node Building`, `Pane Node Tree`, `Create Session Flow Tests`, `CLIError+IPC.swift`, `Pane Status Aggregation Tests`, `Session State Registry`, `Session Restorer`, `WorkingDirectoryResolver.swift`, `Session Restorer Tests`, `Key Binding Registry`, `T`, `Commit Graph Tests`, `IPC Message Tests`, `Remote Command Builder`, `Branch List ViewModel`, `Branch List Service`, `Close Confirmation Dialog`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `TianSettings`, `implement-log`, `items`, `SessionSplitNavigation`?**
  _High betweenness centrality (0.087) - this node is a cross-community bridge._
- **Why does `TerminalSurfaceView` connect `Terminal Surface Input` to `Status Doc Schema`, `Session Git & PR Status`, `Split Layout & Navigation`, `Session Migration Encoding Tests`, `Quit Flow Coordinator`, `SSH Remote Execution`, `ConfirmAlert`, `ANSI Stripper`, `AppKit`, `Persistence State Models`, `Git Types`, `App Delegate Lifecycle`, `Refresh Scheduling & Coalescing`?**
  _High betweenness centrality (0.064) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `String` (e.g. with `.run()` and `.resolveRepoRoot()`) actually correct?**
  _`String` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 61 inferred relationships involving `Session` (e.g. with `.buildWorkspaceCollection()` and `SessionReaderState`) actually correct?**
  _`Session` has 61 INFERRED edges - model-reasoned connections that need verification._
- **Are the 26 inferred relationships involving `WorkspaceCollection` (e.g. with `.defaultSelection()` and `.body()`) actually correct?**
  _`WorkspaceCollection` has 26 INFERRED edges - model-reasoned connections that need verification._
- **Are the 74 inferred relationships involving `PaneStatusManager` (e.g. with `.fireDoneIfStillIdle()` and `.handlePaneList()`) actually correct?**
  _`PaneStatusManager` has 74 INFERRED edges - model-reasoned connections that need verification._