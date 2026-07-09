# Graph Report - feat+sidebar-overview-ux  (2026-07-09)

## Corpus Check
- 326 files · ~335,512 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4277 nodes · 10948 edges · 255 communities (177 shown, 78 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 1493 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c0e3c7ed`
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
- PollingRefresher
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
- OrchestratorTestError
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
- .requestSessionClose
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
- Bool
- CGRect
- Context
- Gesture
- CacheResult
- KeyView
- SessionGitContextBranchDirtyTests
- NSEvent
- Set
- UUID
- URL
- tian-hook-prompt.sh

## God Nodes (most connected - your core abstractions)
1. `String` - 590 edges
2. `Foundation` - 171 edges
3. `Session` - 152 edges
4. `PaneStatusManager` - 111 edges
5. `IPCCommandHandler` - 108 edges
6. `View` - 105 edges
7. `WorkspaceCollection` - 105 edges
8. `PaneViewModel` - 89 edges
9. `WindowCoordinator` - 85 edges
10. `Workspace` - 83 edges

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

## Communities (255 total, 78 thin omitted)

### Community 0 - "IPC Command Handling"
Cohesion: 0.13
Nodes (7): IPCCommandHandler, Int, WindowCoordinator, IPCCommandHandlerTests, IPCEnv, IPCRequest, IPCValue

### Community 1 - "Terminal Surface Input"
Cohesion: 0.22
Nodes (3): NSMenu, ghostty_surface_t, NSEvent

### Community 2 - "Session Git & PR Status"
Cohesion: 0.07
Nodes (9): Session, Bool, CGSize, ClaudeSessionState, Date, Int, Void, SessionModelTests (+1 more)

### Community 3 - "Split Layout & Navigation"
Cohesion: 0.07
Nodes (19): DividerInfo, SplitLayout, SplitLayoutResult, CGFloat, CGRect, PaneNode, SplitDirection, UUID (+11 more)

### Community 4 - "Session State Migration"
Cohesion: 0.09
Nodes (21): Migration, active, MigrationError, futureVersion, migrationFailed, missingVersion, SessionStateMigrator, Any (+13 more)

### Community 5 - "CLI Command Router"
Cohesion: 0.08
Nodes (37): ParsableCommand, ActivityGroup, ActivitySync, GitGroup, GitRefresh, handleCreateResponse(), handleVoidResponse(), NotifyCommand (+29 more)

### Community 6 - "Git Repo Watcher"
Cohesion: 0.10
Nodes (8): HierarchicalEntry, SessionCollection, Bool, Int, URL, UUID, SessionCollectionStressTests, SessionCollectionTests

### Community 7 - "Session Model"
Cohesion: 0.14
Nodes (10): SessionGitContext, Bool, Duration, Int, Never, Set, Task, URL (+2 more)

### Community 8 - "Session Collection"
Cohesion: 0.09
Nodes (42): bash_commands(), buckets(), child_branch(), child_hygiene(), count_tools(), failed_delegate_tasks(), file_path_tools(), filter_zombies() (+34 more)

### Community 9 - "SwiftUI View Components"
Cohesion: 0.17
Nodes (7): Bool, Int, IPCEnv, IPCRequest, IPCResponse, IPCValue, UUID

### Community 10 - "Config Auto-Set Runner"
Cohesion: 0.10
Nodes (21): Decodable, AutoSetPayload, ClaudeResultEnvelope, Bool, AutoSetPrompt, ClaudeInvoker, ProcessClaudeInvoker, URL (+13 more)

### Community 11 - "Session Overview Grid"
Cohesion: 0.07
Nodes (30): Hashable, Sendable, GitFileStatus, added, deleted, modified, renamed, unmerged (+22 more)

### Community 12 - "Sidebar Container"
Cohesion: 0.06
Nodes (31): Accessibility, Content, image, markdown, DefaultDirectoryMenu, URL, Void, InspectPanelTabsWiringModifier (+23 more)

### Community 13 - "Worktree Orchestrator"
Cohesion: 0.25
Nodes (4): Any, Void, WorktreeOrchestrator, WorktreeOrchestratorTests

### Community 14 - "Split Tree Model"
Cohesion: 0.16
Nodes (12): SessionState, Date, Int, makeClaudeSession(), makeWorkspaceState(), SessionRestorerBuildTests, SessionRestorerLoadTests, SessionRestorerMetricsTests (+4 more)

### Community 15 - "SSH Remote Execution"
Cohesion: 0.10
Nodes (11): Int8, GhosttyTerminalSurface, Optional, Bool, ghostty_input_key_s, ghostty_surface_t, T, UInt32 (+3 more)

### Community 16 - "Inspect File Tree Scanning"
Cohesion: 0.14
Nodes (5): Bool, WindowFrame, SessionSnapshotWindowGeometryTests, SessionSnapshotTests, SessionSnapshotWorktreePathTests

### Community 17 - "ANSI Stripper"
Cohesion: 0.12
Nodes (11): RemoveResult, lastPane, notFound, removed, SplitTree, Bool, Int, PaneNode (+3 more)

### Community 18 - "Workspace Model"
Cohesion: 0.11
Nodes (9): ANSIStripper, State, csi, escape, escapeIntermediate, normal, osc, oscEscape (+1 more)

### Community 19 - "Persistence State Models"
Cohesion: 0.08
Nodes (13): PaneStatus, UInt64, PaneViewModel, Bool, CGSize, ClaudeSessionState, NSObjectProtocol, Set (+5 more)

### Community 20 - "Command Logger"
Cohesion: 0.06
Nodes (36): CodingKey, Encodable, CodingKeys, isError, result, structuredOutput, subtype, CodingKeys (+28 more)

### Community 21 - "Workspace Collection"
Cohesion: 0.13
Nodes (3): Int, Int32, WorktreeServiceTests

### Community 22 - "Refresh Scheduling & Coalescing"
Cohesion: 0.10
Nodes (16): ghostty_action_color_change_s, ghostty_action_s, ghostty_app_t, ghostty_clipboard_e, ghostty_config_t, ghostty_surface_config_s, ghostty_target_s, NSPasteboard (+8 more)

### Community 23 - "Worktree Service"
Cohesion: 0.05
Nodes (42): additionalProperties, description, type, description, type, description, type, description (+34 more)

### Community 24 - "Off-Main Process Runner"
Cohesion: 0.09
Nodes (19): DispatchWorkItem, KillGuard, State, alive, dead, terminating, pid_t, TimeInterval (+11 more)

### Community 25 - "Decision Record Schema"
Cohesion: 0.26
Nodes (8): IPCServer, async, Bool, Data, Int32, IPCResponse, UInt64, Log

### Community 26 - "Git Status Service"
Cohesion: 0.09
Nodes (16): NSLayoutConstraint, NSWindowController, NSWindowDelegate, CGFloat, NSWindow, TrafficLightAligner, Bool, WindowFrame (+8 more)

### Community 27 - "Session State Fixtures"
Cohesion: 0.06
Nodes (20): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+12 more)

### Community 28 - "Worktree Service Tests"
Cohesion: 0.11
Nodes (11): PaneStatusManager, Bool, ClaudeSessionState, Duration, Never, Set, Task, UUID (+3 more)

### Community 29 - "Test Harness Utilities"
Cohesion: 0.07
Nodes (12): CoreGraphics, Testing, tian, CustomLaunchCommandTests, DockToggleDuringDragTests, EventCoalescerTests, RetryClaudeSpawnTests, SessionDividerViewTests (+4 more)

### Community 30 - "Workspace Reorder Logic"
Cohesion: 0.10
Nodes (4): CGFloat, Int, WorkspaceReorderGeometry, WorkspaceCollectionTests

### Community 31 - "Inspect File Tree ViewModel"
Cohesion: 0.08
Nodes (9): Date, InspectFileTreeViewModel, URL, UUID, Workspace, DefaultWorkingDirectoryTests, MainActor, git (+1 more)

### Community 32 - "Pane ViewModel"
Cohesion: 0.05
Nodes (35): Architecture, Build, Concepts, graphify, Keeping the record current (do this without being asked), Key Layers, Lifecycle, Logs (+27 more)

### Community 33 - "Error Types"
Cohesion: 0.25
Nodes (3): RemoteExecutionRegistry, Bool, RemoteExecutionRegistryTests

### Community 34 - "Ghostty App Core"
Cohesion: 0.35
Nodes (7): CharacterChord, KeyBinding, KeyBindingRegistry, KeyCodeChord, NSEvent, UInt16, UInt

### Community 35 - "Pane Status Manager"
Cohesion: 0.15
Nodes (15): GitRepoID, PRStatus, URL, CacheEntry, CacheKey, CacheResult, hit, miss (+7 more)

### Community 36 - "Session Git Context Tests"
Cohesion: 0.12
Nodes (15): InspectPanelHeader, Bool, CGFloat, DiffSummary, FilesContext, InspectPanelInfoStrip, Bool, CGFloat (+7 more)

### Community 37 - "Sidebar Drag Reorder"
Cohesion: 0.11
Nodes (12): CGFloat, DragGesture, Gesture, Int, Set, SidebarState, SidebarExpandedContentView, Workspace (+4 more)

### Community 38 - "Session Migration Encoding Tests"
Cohesion: 0.06
Nodes (10): JSONDecoder, SessionMigrationV4ToV5Tests, SessionMigrationV5ToV6Tests, SessionMigrationV7ToV8Tests, PaneNodeConversionTests, PaneNodeStateEncodingTests, RestoreCommandPaneViewModelTests, SessionRecordWorktreePathTests (+2 more)

### Community 39 - "Background Activity Store"
Cohesion: 0.14
Nodes (9): GitRepoWatcher, FSEventStreamRef, RepoLocation, CallbackTracker, GitRepoWatcherTests, PathRecorder, Bool, Duration (+1 more)

### Community 41 - "Session Divider Drag"
Cohesion: 0.23
Nodes (6): ClaudeSessionNotifier, Duration, NotificationManager, Bool, UUID, NotificationManagerTests

### Community 42 - "Framework Imports"
Cohesion: 0.08
Nodes (28): Binding, S, DiffBinaryPlaceholderRow, DiffFileHeaderRow, DiffHunkHeaderRow, DiffLineRow, DiffTruncatedRow, Bool (+20 more)

### Community 43 - "Markdown Reader"
Cohesion: 0.07
Nodes (23): MarkdownContent, MarkdownUI, ReaderFileSource, RemoteReaderFileSource, SessionReaderState, DiffColors, MarkdownDiffView, Rendered (+15 more)

### Community 44 - "Worktree Config Parser"
Cohesion: 0.15
Nodes (7): table, CopyRule, TimeInterval, URL, WorktreeConfigParser, WorktreeConfigParserTests, TOMLTable

### Community 45 - "Session Audit Analyzer"
Cohesion: 0.07
Nodes (12): BackgroundActivity, Kind, agent, bash, other, Bool, Date, TimeInterval (+4 more)

### Community 46 - "Git Types"
Cohesion: 0.07
Nodes (22): RemoteInspectFileScanner, RemoteScanError, commandFailed, Data, Duration, Int32, URL, Data (+14 more)

### Community 48 - "Working Tree Watcher"
Cohesion: 0.20
Nodes (9): DispatchSourceTimer, Box, Bool, DispatchQueue, Duration, FSEventStreamRef, Int, Void (+1 more)

### Community 49 - "Branch Graph Rendering"
Cohesion: 0.10
Nodes (15): Float, SIMD2, Color, BranchGraphCanvas, InspectBranchBody, Bool, CGFloat, ClaudeSessionState (+7 more)

### Community 50 - "Inspect File Scanner"
Cohesion: 0.11
Nodes (13): GitChangedFile, InspectChildEntry, InspectIgnoredEntries, Set, BlockingScanner, CountingScanner, FixedScanner, InspectFileTreeViewModel (+5 more)

### Community 51 - "CLI Output Formatting"
Cohesion: 0.18
Nodes (7): SessionSerializer, ClaudeSessionState, Data, URL, UUID, SessionSerializerWriteTests, URL

### Community 52 - "Claude Session State"
Cohesion: 0.05
Nodes (17): Comparable, ClaudeNotificationPolicy, ClaudeNotificationTrigger, done, needsAttention, Bool, ClaudeSessionState, ClaudeSessionState (+9 more)

### Community 53 - "Remote Connection & Workspace Create"
Cohesion: 0.19
Nodes (3): BranchListViewModelTests, Bool, Date

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
Cohesion: 0.13
Nodes (10): InspectFileScanner, ScannerError, decodeFailed, gitFailed, Bool, Data, Int32, URL (+2 more)

### Community 58 - "IPC Client CLI"
Cohesion: 0.19
Nodes (6): BranchEntry, Bool, Date, Kind, FakeService, FakingListService

### Community 59 - "Workspace Window Controller"
Cohesion: 0.14
Nodes (14): AnyObject, BranchGraphDirtyHost, InspectBranchViewModel, SessionGitContext, Bool, Never, Task, Void (+6 more)

### Community 60 - "Inspect Diff ViewModel"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 61 - "Inspect Panel View"
Cohesion: 0.11
Nodes (13): App, NSApplicationDelegate, NSObject, Scene, TianApp, Bool, NSApplication, TianAppDelegate (+5 more)

### Community 62 - "Create Session View"
Cohesion: 0.11
Nodes (20): Character, BranchRow, Bool, Date, CreateSessionView, CreateWorktreeSubmission, Field, dialog (+12 more)

### Community 63 - "Git Status Service Tests"
Cohesion: 0.26
Nodes (6): ClaudeSessionState, T, Item, SessionOverviewSortTests, ClaudeSessionState, Int

### Community 64 - "IPC Message Protocol"
Cohesion: 0.10
Nodes (15): LayoutNode, pane, split, ClosedRange, Int, SplitDirection, TimeInterval, WorktreeConfig (+7 more)

### Community 65 - "Session Split Navigation"
Cohesion: 0.07
Nodes (26): GitFileDiff, InspectDiffViewModel, Bool, Duration, Never, Set, Task, Void (+18 more)

### Community 67 - "Worktree Setup Progress"
Cohesion: 0.18
Nodes (4): RemoteCommandBuilder, ShellQuoting, SSHMultiplexing, RemoteCommandBuilderTests

### Community 68 - "Background Activity Sync"
Cohesion: 0.14
Nodes (7): PaneKind, claude, terminal, PaneNode, RemoteSpawnSpec, PaneSpawner, PaneViewModelRealizeSurfaceTests

### Community 69 - "Pane Node Building"
Cohesion: 0.13
Nodes (12): CustomStringConvertible, Error, NotificationError, permissionDenied, RestoreError, emptySessions, emptyWorkspaces, StringError (+4 more)

### Community 70 - "Pane Node Tree"
Cohesion: 0.13
Nodes (23): Identifiable, GitCommit, GitCommitGraph, GitDiffHunk, GitDiffLine, GitDiffSummary, GitLane, GitRepoStatus (+15 more)

### Community 71 - "Create Session Flow Tests"
Cohesion: 0.16
Nodes (8): SSHConnection, State, connected, connecting, idle, offline, SSHControlChannel, Bool

### Community 72 - "IPC Env Encoding"
Cohesion: 0.13
Nodes (14): Double, Snapshot, Duration, Never, Task, UInt32, UInt64, Void (+6 more)

### Community 73 - "Pane Status Aggregation Tests"
Cohesion: 0.15
Nodes (4): FuzzyMatch, Result, Int, FuzzyMatchTests

### Community 74 - "Session State Registry"
Cohesion: 0.16
Nodes (9): PaneNode, leaf, split, SplitDirection, horizontal, vertical, Bool, Int (+1 more)

### Community 75 - "Session Restorer"
Cohesion: 0.12
Nodes (18): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+10 more)

### Community 76 - "Session Restorer Tests"
Cohesion: 0.14
Nodes (21): Codable, Equatable, CopyEntry, SetupEntry, PaneLeafState, PaneNode, PaneNodeState, pane (+13 more)

### Community 78 - "Quit Flow Coordinator"
Cohesion: 0.23
Nodes (10): sockaddr_un, socklen_t, IPCServerTests, IPCTestError, connectionFailed, socketCreationFailed, writeFailed, Data (+2 more)

### Community 79 - "Pane Hierarchy Wiring"
Cohesion: 0.11
Nodes (18): A Session = one Claude pane + a toggleable terminal panel, Command reference, Core rules, Delegation orchestrator (bundled script — backs `/tian implement`), Discovery, Driving tian with the `tian` CLI, Gotchas, Long-session hygiene (+10 more)

### Community 80 - "Inspect Tab State"
Cohesion: 0.16
Nodes (6): GitStatusService, Bool, escaping, Int, Int32, T

### Community 81 - "IPC Server Socket"
Cohesion: 0.16
Nodes (11): ReaderOverlayView, Bool, CGFloat, Void, SessionContentView, Bool, CGFloat, CGSize (+3 more)

### Community 82 - "Key Binding Registry"
Cohesion: 0.08
Nodes (20): SidebarSessionRowMutationGate, SidebarSessionRowView, Bool, CGFloat, ClaudeSessionState, Date, URL, UUID (+12 more)

### Community 83 - "Session Content View"
Cohesion: 0.35
Nodes (3): GitStatusServiceCommitGraphTests, StringError, Bool

### Community 85 - "App Delegate Lifecycle"
Cohesion: 0.14
Nodes (4): RemoteConnectionState, RemoteConnection, Bool, RemoteConnectionTests

### Community 86 - "File Log Writer"
Cohesion: 0.18
Nodes (6): InspectPanelState, Bool, CGFloat, Bool, WorkspaceSnapshot, InspectPanelStateTests

### Community 87 - "Window Drag Blocker"
Cohesion: 0.22
Nodes (3): URL, WorkingDirectoryResolver, WorkingDirectoryResolverTests

### Community 88 - "Commit Graph Tests"
Cohesion: 0.29
Nodes (5): SkillInstaller, URL, UserDefaults, SkillInstallerTests, URL

### Community 89 - "IPC Message Tests"
Cohesion: 0.19
Nodes (10): CGRect, Context, NSEvent, NSView, PreferenceKey, KeyView, SidebarKeyboardResponder, Bool (+2 more)

### Community 90 - "Remote Command Builder"
Cohesion: 0.18
Nodes (9): SessionDividerClamper, Bool, CGFloat, SessionDividerView, Bool, CGFloat, CGSize, Gesture (+1 more)

### Community 91 - "Skill Installer"
Cohesion: 0.26
Nodes (5): BranchListService, Int32, Set, BranchListServiceTests, TestError

### Community 92 - "Branch List ViewModel"
Cohesion: 0.18
Nodes (4): ProcessDetector, RunningProcessInfo, UUID, ProcessDetectorTests

### Community 93 - "Branch List Service"
Cohesion: 0.10
Nodes (15): ArgumentParser, ConfigAutoSet, ConfigGroup, Bool, IPCClient, Int, Int32, IPCRequest (+7 more)

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
Cohesion: 0.17
Nodes (7): Coordinator, Bool, Context, NSView, SplitDirection, UUID, TerminalContentView

### Community 99 - "Terminal Content View"
Cohesion: 0.22
Nodes (8): CloseConfirmationDialog, CloseTarget, pane, Int, NSAlert, NSWindow, Void, CloseConfirmationDialogTests

### Community 100 - "Close Confirmation Dialog"
Cohesion: 0.27
Nodes (6): PollingRefresher, Duration, MainActor, Never, Task, Void

### Community 101 - "Image Reader"
Cohesion: 0.18
Nodes (9): ImageIO, NSImage, ImageDocument, Sendbox, Date, T, ImageReaderView, Bool (+1 more)

### Community 102 - "Session Serializer"
Cohesion: 0.13
Nodes (13): GridItem, CardEntry, KeyView, OverviewKeyboardResponder, SessionOverviewGridView, Bool, CGFloat, Context (+5 more)

### Community 103 - "Workspace Keyboard Navigation"
Cohesion: 0.13
Nodes (9): SessionGitContext, DockPosition, bottom, right, ClosedRange, URL, SessionDividerDragController, Bool (+1 more)

### Community 104 - "System Monitor (CPU/RAM)"
Cohesion: 0.14
Nodes (13): Architecture, Build, Concepts, Key Layers, Lifecycle, Logs, Scratch / Temporary Files, Source Layout (+5 more)

### Community 105 - "Check For Updates"
Cohesion: 0.09
Nodes (20): CaseIterable, ExpressibleByArgument, IPCError, handleListResponse(), PaneList, SessionList, IPCValue, WorktreeCreateOutput (+12 more)

### Community 106 - "Working Directory Resolver"
Cohesion: 0.27
Nodes (3): EnvironmentBuilder, UUID, EnvironmentBuilderTests

### Community 107 - "App Hero Screenshot (UI)"
Cohesion: 0.24
Nodes (13): Claude Pane (Claude Code v2.1.140), Claude Code Statusline (ctx/model/branch), File Explorer Panel (Files/Diff/Branch), Workspace -> Session -> Pane Hierarchy, New Workspace Action, Session Row (name + branch + git diff), Workspace/Session Sidebar, Bottom Status Bar (CPU/RAM) (+5 more)

### Community 108 - "Shipped Items Schema"
Cohesion: 0.21
Nodes (10): CGPoint, First, Second, SplitContainerView, SplitDividerView, CGFloat, CGRect, CGSize (+2 more)

### Community 109 - "Status Bar View"
Cohesion: 0.22
Nodes (9): CreateSessionRequest, Bool, CGFloat, Duration, Never, Task, URL, Void (+1 more)

### Community 110 - "SessionCloseFlow"
Cohesion: 0.15
Nodes (13): description, type, properties, commit, since, summary, target, description (+5 more)

### Community 111 - "NotificationManager"
Cohesion: 0.14
Nodes (5): SessionOverviewOverlayModifier, Int, UUID, Void, WorkspaceCollection

### Community 112 - "TianSettings"
Cohesion: 0.12
Nodes (5): DirectoryPicker, URL, URL, WorkspaceCreationFlow, WorkspaceCreationFlowTests

### Community 113 - "Row"
Cohesion: 0.24
Nodes (5): SessionCloseFlow, Bool, NSWindow, URL, Error

### Community 114 - "AppKit"
Cohesion: 0.18
Nodes (8): BlockerView, Bool, Context, NSEvent, NSTrackingArea, NSView, NSWindow, WindowDragBlocker

### Community 115 - "KeyboardLayoutTranslator"
Cohesion: 0.29
Nodes (5): Bool, UserDefaults, TianSettings, UserDefaults, TianSettingsTests

### Community 116 - "implement-log"
Cohesion: 0.17
Nodes (5): BranchListViewModel, Direction, down, up, BranchListProviding

### Community 117 - "socklen_t"
Cohesion: 0.09
Nodes (17): WorktreeError, baseWithExisting, branchAlreadyExists, closeInFlight, configParseError, gitError, invalidBaseRef, notAGitRepo (+9 more)

### Community 118 - "AutoSetPrompt"
Cohesion: 0.22
Nodes (5): ghostty_input_mods_e, NSScreen, ghostty_input_key_s, UInt32, TerminalSurfaceViewDelegate

### Community 120 - "InspectPanelState"
Cohesion: 0.67
Nodes (3): description, type, link

### Community 121 - "SidebarExpandedContentView"
Cohesion: 0.34
Nodes (5): CallbackTracker, Duration, Int, Sendable, WorkingTreeWatcherTests

### Community 122 - "SidebarSessionRowView"
Cohesion: 0.29
Nodes (10): items, additionalProperties, required, type, items, items, shipped, description (+2 more)

### Community 123 - "items"
Cohesion: 0.24
Nodes (5): SessionLayout, CGFloat, CGRect, CGSize, SessionLayoutTests

### Community 124 - "EnvironmentBuilderTests"
Cohesion: 0.36
Nodes (5): CFTimeInterval, CallbackBox, DispatchQueue, escaping, Void

### Community 125 - "WorktreeKindTests"
Cohesion: 0.15
Nodes (9): PaneHierarchyContext, UUID, SessionSplitNavigation, CGRect, CGSize, PaneNode, UUID, Target (+1 more)

### Community 126 - "SessionSplitNavigation"
Cohesion: 0.22
Nodes (7): PaneState, exited, running, spawnFailed, UInt32, PaneExitOverlay, Void

### Community 127 - "PollingRefresher"
Cohesion: 0.27
Nodes (5): Harness, Int, NSView, NSWindow, TerminalSurfaceViewFocusTests

### Community 130 - "implement"
Cohesion: 0.33
Nodes (4): InspectPanelTabRow, Bool, CGFloat, InspectTab

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
Cohesion: 0.18
Nodes (7): FileHandle, Logger, FileLogger, FileLogWriter, ISO8601DateFormatter, UInt64, URL

### Community 135 - "WorkspaceCreationFlowTests"
Cohesion: 0.33
Nodes (7): MarkdownCopyButton, MarkdownDiffToggleButton, ReaderCloseButton, CGFloat, Never, Task, Void

### Community 136 - "MockWorkspaceProvider"
Cohesion: 0.25
Nodes (4): NSAttributedString, NSRange, NSRangePointer, NSRect

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
Nodes (12): CoreServices, Darwin, os, OSLog, FileBaseline, committed, notInRepo, untracked (+4 more)

### Community 141 - ".makeHarness"
Cohesion: 0.15
Nodes (9): NSSize, NSTextInputClient, Selector, SurfaceCallbackContext, ghostty_surface_t, UUID, NSCoder, NSTrackingArea (+1 more)

### Community 142 - "AppMetrics"
Cohesion: 0.25
Nodes (7): How to read the output, Improvement catalog (map flags → fixes), Input, Litmus test to report, Run, session-audit — audit a tian orchestrator session, What to produce

### Community 143 - "InspectPanelFileRow"
Cohesion: 0.24
Nodes (7): QuitConfirmationDialog, Bool, Int, NSAlert, NSWindow, Void, NSApplication

### Community 144 - "Response"
Cohesion: 0.25
Nodes (5): sockaddr, blockingAwait(), escaping, T, UnsafePointer

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

### Community 149 - "BranchListService"
Cohesion: 0.39
Nodes (3): AppMetrics, Int, UInt64

### Community 150 - "RefreshSchedulerTests"
Cohesion: 0.32
Nodes (6): InspectPanelFileRow, Spacing, Bool, CGFloat, Int, Void

### Community 151 - "resolve_from_runlog"
Cohesion: 0.29
Nodes (6): Response, cancel, forceRemove, NSWindow, Void, WorktreeForceRemoveDialog

### Community 152 - "ContinuousClock"
Cohesion: 0.38
Nodes (5): NSViewRepresentable, Context, NSView, NSWindow, WindowAccessor

### Community 153 - "PaneState"
Cohesion: 0.29
Nodes (6): ShellReadinessWaiter, ShellReadyReason, osc7, timeout, TimeInterval, UUID

### Community 157 - "DebugOverlayView"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 158 - "InspectPanelTabRow"
Cohesion: 0.17
Nodes (9): Commands, ObservableObject, Sparkle, CheckForUpdatesView, CheckForUpdatesViewModel, SPUUpdater, SPUUpdater, WorkspaceCommands (+1 more)

### Community 159 - "ChangeBadgeView"
Cohesion: 0.29
Nodes (4): SessionOverviewSort, SessionOverviewSortMode, defaultOrder, sessionState

### Community 160 - "SidebarWorkspaceHeaderView"
Cohesion: 0.29
Nodes (4): BranchListServiceAdapter, Kind, local, remote

### Community 161 - "EventCoalescerTests"
Cohesion: 0.33
Nodes (5): Session, String, SidebarItem, sessionRow, workspaceHeader

### Community 162 - ".send"
Cohesion: 0.40
Nodes (3): Bool, ClaudeSessionState, UUID

### Community 163 - "DebugOverlayView"
Cohesion: 0.33
Nodes (3): DebugOverlayView, LabeledMetric, Timer

### Community 164 - "WorktreeConfig"
Cohesion: 0.47
Nodes (3): OverviewGridNavigation, Int, UUID

### Community 166 - ".startClaude"
Cohesion: 0.18
Nodes (7): WorktreeKind, linkedWorktree, mainCheckout, notARepo, noWorkingDirectory, StringError, WorktreeKindTests

### Community 167 - "AppMetrics"
Cohesion: 0.05
Nodes (28): SwiftUI, SettingsView, InspectPanelFileBrowser, InspectFileTreeViewModel, Void, InspectPanelRail, CGFloat, Void (+20 more)

### Community 170 - "SessionRestorer"
Cohesion: 0.20
Nodes (5): WorkspaceProviding, Box, MockWorkspaceProvider, OrchestratorTestError, T

### Community 171 - "resolve_from_runlog"
Cohesion: 0.67
Nodes (3): description, type, item

### Community 172 - "DebugOverlayView"
Cohesion: 0.67
Nodes (3): title, description, type

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

### Community 184 - "tian-hook-log"
Cohesion: 0.09
Nodes (9): Foundation, Observation, CLIError, T, WeakBox, Keys, BranchEntry.Kind, Bool (+1 more)

### Community 186 - "filter_zombies"
Cohesion: 0.83
Nodes (3): tian-bash-integration.bash script, _tian_fix_path(), _tian_install_claude_wrapper()

### Community 187 - "OrchestratorTestError"
Cohesion: 0.29
Nodes (7): SidebarWorkspaceHeaderView, Bool, Void, Workspace, WorkspaceDropIndicator, URL, View

### Community 188 - "ConfirmAlert"
Cohesion: 0.12
Nodes (7): AppKit, CGRect, WindowFrame, InspectPanelResizeHandle, CGFloat, SessionHeaderView, CGFloat

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

### Community 201 - "WorkingDirectoryResolver.swift"
Cohesion: 0.33
Nodes (5): Direction, down, left, right, up

### Community 202 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.67
Nodes (3): Mode, existingBranch, newBranch

### Community 214 - "T"
Cohesion: 0.20
Nodes (8): CreateWorkspaceView, Field, directory, host, name, Bool, Field, Void

## Knowledge Gaps
- **426 isolated node(s):** `workspaceHeader`, `sessionRow`, `$schema`, `$id`, `title` (+421 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **78 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `Git Types` to `IPC Command Handling`, `Session Git & PR Status`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `Session Model`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Sidebar Container`, `Worktree Orchestrator`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Workspace Collection`, `Refresh Scheduling & Coalescing`, `Off-Main Process Runner`, `Decision Record Schema`, `Session State Fixtures`, `Worktree Service Tests`, `Test Harness Utilities`, `Inspect File Tree ViewModel`, `Error Types`, `Ghostty App Core`, `Pane Status Manager`, `Session Git Context Tests`, `Background Activity Store`, `Graphify Pipeline Skill`, `Session Divider Drag`, `Framework Imports`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Working Tree Watcher`, `Branch Graph Rendering`, `Inspect File Scanner`, `CLI Output Formatting`, `Claude Session State`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `Branch List Tests`, `IPC Client CLI`, `Workspace Window Controller`, `Create Session View`, `IPC Message Protocol`, `Session Split Navigation`, `Fuzzy Match`, `Worktree Setup Progress`, `Background Activity Sync`, `Pane Node Building`, `Pane Node Tree`, `Create Session Flow Tests`, `IPC Env Encoding`, `Pane Status Aggregation Tests`, `Session State Registry`, `Session Restorer`, `Session Restorer Tests`, `Worktree Config Execution`, `Quit Flow Coordinator`, `Inspect Tab State`, `IPC Server Socket`, `Key Binding Registry`, `Session Content View`, `Branch List Fakes`, `App Delegate Lifecycle`, `File Log Writer`, `Window Drag Blocker`, `Commit Graph Tests`, `Skill Installer`, `Branch List ViewModel`, `Branch List Service`, `Key Chord Model`, `Process Detector`, `Image Reader`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `Status Bar View`, `NotificationManager`, `TianSettings`, `KeyboardLayoutTranslator`, `implement-log`, `socklen_t`, `AutoSetPrompt`, `GitStatusServiceUnifiedDiffTests`, `SidebarExpandedContentView`, `EnvironmentBuilderTests`, `WorktreeKindTests`, `SessionSplitNavigation`, `WorkspaceWindowContent`, `implement`, `os`, `Response`, `BusyDotView`, `blockingAwait`, `.makeHarness`, `InlineRenameView`, `BranchListService`, `RefreshSchedulerTests`, `resolve_from_runlog`, `.unifiedDiff`, `ChangeBadgeView`, `SidebarWorkspaceHeaderView`, `DebugOverlayView`, `.fromIPCError`, `.startClaude`, `AppMetrics`, `publish`, `SessionRestorer`, `EventCoalescerTests`, `tian-hook-log`, `ConfirmAlert`, `.requestSessionClose`, `T`?**
  _High betweenness centrality (0.553) - this node is a cross-community bridge._
- **Why does `Foundation` connect `tian-hook-log` to `Split Layout & Navigation`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `Config Auto-Set Runner`, `Session Overview Grid`, `Split Tree Model`, `Inspect File Tree Scanning`, `ANSI Stripper`, `Workspace Model`, `Command Logger`, `Off-Main Process Runner`, `Session State Fixtures`, `Test Harness Utilities`, `Inspect File Tree ViewModel`, `Error Types`, `Pane Status Manager`, `Session Migration Encoding Tests`, `Session Divider Drag`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Git Types`, `Inspect File Scanner`, `CLI Output Formatting`, `Claude Session State`, `Markdown Diff Segments`, `Branch List Tests`, `IPC Client CLI`, `Workspace Window Controller`, `Git Status Service Tests`, `IPC Message Protocol`, `Session Split Navigation`, `Fuzzy Match`, `Worktree Setup Progress`, `Background Activity Sync`, `Pane Node Building`, `Pane Node Tree`, `IPC Env Encoding`, `Pane Status Aggregation Tests`, `Session State Registry`, `Session Restorer`, `Session Restorer Tests`, `Quit Flow Coordinator`, `Key Binding Registry`, `Session Content View`, `Branch List Fakes`, `App Delegate Lifecycle`, `File Log Writer`, `Window Drag Blocker`, `Commit Graph Tests`, `Skill Installer`, `Branch List ViewModel`, `Branch List Service`, `Close Confirmation Dialog`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `TianSettings`, `KeyboardLayoutTranslator`, `socklen_t`, `SidebarExpandedContentView`, `items`, `WorktreeKindTests`, `.move`, `os`, `Response`, `.stopPreventsFurtherCallbacks`, `blockingAwait`, `Response`, `PaneState`, `HtmlFileType`, `ChangeBadgeView`, `SidebarWorkspaceHeaderView`, `.fromIPCError`, `.startClaude`, `SessionRestorer`, `ConfirmAlert`, `WorkingDirectoryResolver.swift`, `SessionGitContextBranchDirtyTests`?**
  _High betweenness centrality (0.064) - this node is a cross-community bridge._
- **Why does `TerminalSurfaceView` connect `.makeHarness` to `Status Doc Schema`, `WorkspaceWindowContent`, `Split Layout & Navigation`, `Background Activity Sync`, `.flagsChanged`, `Terminal Surface Input`, `Session Git & PR Status`, `MockWorkspaceProvider`, `Git Types`, `SSH Remote Execution`, `Persistence State Models`, `AutoSetPrompt`, `IPC Message Tests`, `PollingRefresher`?**
  _High betweenness centrality (0.062) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `String` (e.g. with `.run()` and `.resolveRepoRoot()`) actually correct?**
  _`String` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 61 inferred relationships involving `Session` (e.g. with `.buildWorkspaceCollection()` and `SessionReaderState`) actually correct?**
  _`Session` has 61 INFERRED edges - model-reasoned connections that need verification._
- **Are the 74 inferred relationships involving `PaneStatusManager` (e.g. with `.fireDoneIfStillIdle()` and `.handlePaneList()`) actually correct?**
  _`PaneStatusManager` has 74 INFERRED edges - model-reasoned connections that need verification._
- **Are the 62 inferred relationships involving `IPCCommandHandler` (e.g. with `.applicationDidFinishLaunching()` and `.activitySyncInvalidPaneUUIDReturnsError()`) actually correct?**
  _`IPCCommandHandler` has 62 INFERRED edges - model-reasoned connections that need verification._