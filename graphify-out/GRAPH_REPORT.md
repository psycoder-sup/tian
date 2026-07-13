# Graph Report - tian  (2026-07-13)

## Corpus Check
- 330 files · ~345,330 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4359 nodes · 11340 edges · 242 communities (164 shown, 78 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 1550 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5030c9d5`
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
- GitStatusService
- PaneState
- KeyAction
- HtmlFileType
- ImageFileType
- DebugOverlayView
- IPCMessageTests
- GitRepoWatcherBranchGraphTests
- SidebarWorkspaceHeaderView
- StatusBarView
- CheckForUpdatesView
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
- .unifiedDiff
- date
- done
- item
- TianApp
- tian-hook-prompt-test.sh
- Glowing Vertical Cursor Bar Motif
- WeakBox
- tian-hook-activity
- Serena project config
- filter_zombies
- PollingRefresher
- ConfirmAlert
- install
- release
- claude
- Token reduction benchmark
- FalkorDB export
- dev scratch space
- graphify knowledge graph
- NetworkImage
- CLIError+IPC.swift
- .from
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
- SessionGitContextBranchDirtyTests
- RetryClaudeSpawnTests
- .claudePreviewText
- Swift Argument Parser
- TOMLKit
- tian-hook-prompt.sh

## God Nodes (most connected - your core abstractions)
1. `String` - 604 edges
2. `Foundation` - 173 edges
3. `Session` - 155 edges
4. `PaneStatusManager` - 141 edges
5. `WorkspaceCollection` - 114 edges
6. `IPCCommandHandler` - 113 edges
7. `View` - 108 edges
8. `Workspace` - 95 edges
9. `PaneViewModel` - 93 edges
10. `WindowCoordinator` - 85 edges

## Surprising Connections (you probably didn't know these)
- `CommandContext` --references--> `String`  [EXTRACTED]
  tian-cli/main.swift → tianTests/InspectFileTreeViewModelTests.swift
- `BranchEntry.Kind` --references--> `String`  [EXTRACTED]
  tian/View/CreateSession/BranchListViewModel.swift → tianTests/InspectFileTreeViewModelTests.swift
- `InspectTab` --references--> `String`  [EXTRACTED]
  tian/View/InspectPanel/InspectPanelStatusStrip.swift → tianTests/InspectFileTreeViewModelTests.swift
- `AutoSetPayload` --references--> `String`  [EXTRACTED]
  tian-cli/AutoSetPayload.swift → tianTests/InspectFileTreeViewModelTests.swift
- `SetupEntry` --references--> `String`  [EXTRACTED]
  tian-cli/AutoSetPayload.swift → tianTests/InspectFileTreeViewModelTests.swift

## Import Cycles
- None detected.

## Communities (242 total, 78 thin omitted)

### Community 0 - "IPC Command Handling"
Cohesion: 0.06
Nodes (24): ClaudeSessionNotifier, Bool, ClaudeSessionState, Duration, UUID, IPCCommandHandler, Bool, Int (+16 more)

### Community 1 - "Terminal Surface Input"
Cohesion: 0.25
Nodes (12): GitFileDiff, InspectDiffViewModel, Bool, Duration, Never, Set, Task, Void (+4 more)

### Community 2 - "Session Git & PR Status"
Cohesion: 0.07
Nodes (11): SessionGitContext, Session, CGSize, ClaudeSessionState, Date, URL, UUID, Void (+3 more)

### Community 3 - "Split Layout & Navigation"
Cohesion: 0.05
Nodes (30): CGPoint, First, Second, DividerInfo, SplitLayout, SplitLayoutResult, CGFloat, CGRect (+22 more)

### Community 4 - "Session State Migration"
Cohesion: 0.10
Nodes (20): Migration, MigrationError, futureVersion, migrationFailed, missingVersion, SessionStateMigrator, Any, Bool (+12 more)

### Community 5 - "CLI Command Router"
Cohesion: 0.07
Nodes (42): ParsableCommand, IPCError, ActivityBegin, ActivityClear, ActivityEnd, ActivityGroup, ActivityReconcile, ActivityResetLifecycle (+34 more)

### Community 6 - "Git Repo Watcher"
Cohesion: 0.09
Nodes (9): HierarchicalEntry, SessionCollection, Bool, Int, URL, UUID, DockToggleDuringDragTests, SessionCollectionStressTests (+1 more)

### Community 7 - "Session Model"
Cohesion: 0.11
Nodes (4): JSONDecoder, SessionMigrationV4ToV5Tests, SessionMigrationV5ToV6Tests, SessionMigrationV7ToV8Tests

### Community 8 - "Session Collection"
Cohesion: 0.09
Nodes (42): bash_commands(), buckets(), child_branch(), child_hygiene(), count_tools(), failed_delegate_tasks(), file_path_tools(), filter_zombies() (+34 more)

### Community 9 - "SwiftUI View Components"
Cohesion: 0.09
Nodes (20): CaseIterable, ExpressibleByArgument, handleListResponse(), PaneList, SessionList, IPCValue, WorkspaceList, WorktreeCreateOutput (+12 more)

### Community 10 - "Config Auto-Set Runner"
Cohesion: 0.16
Nodes (15): Decodable, AutoSetPayload, ClaudeResultEnvelope, Bool, ConfigAutoSetResult, ConfigAutoSetRunner, Bool, Int (+7 more)

### Community 11 - "Session Overview Grid"
Cohesion: 0.08
Nodes (18): FileTreeNode, Kind, directory, file, Bool, Int, Kind, InspectFileScanning (+10 more)

### Community 12 - "Sidebar Container"
Cohesion: 0.11
Nodes (13): Accessibility, InspectPanelTabsWiringModifier, InspectPanelWiringModifier, Notification, Notification.Name, SidebarContainerView, CGFloat, CGSize (+5 more)

### Community 13 - "Worktree Orchestrator"
Cohesion: 0.24
Nodes (5): Any, Void, WorktreeOrchestrator, MockWorkspaceProvider, WorktreeOrchestratorTests

### Community 14 - "Split Tree Model"
Cohesion: 0.15
Nodes (15): RestoreMetrics, Bool, Int, SessionState, Date, Int, makeClaudeSession(), makeWorkspaceState() (+7 more)

### Community 15 - "SSH Remote Execution"
Cohesion: 0.12
Nodes (18): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+10 more)

### Community 16 - "Inspect File Tree Scanning"
Cohesion: 0.16
Nodes (5): Bool, WindowFrame, SessionSnapshotWindowGeometryTests, SessionSnapshotTests, SessionSnapshotWorktreePathTests

### Community 17 - "ANSI Stripper"
Cohesion: 0.10
Nodes (12): RemoveResult, lastPane, notFound, removed, SplitTree, Bool, Int, PaneNode (+4 more)

### Community 18 - "Workspace Model"
Cohesion: 0.11
Nodes (9): ANSIStripper, State, csi, escape, escapeIntermediate, normal, osc, oscEscape (+1 more)

### Community 19 - "Persistence State Models"
Cohesion: 0.06
Nodes (19): Int8, GhosttyTerminalSurface, Optional, Bool, ghostty_input_key_s, ghostty_surface_t, T, UInt32 (+11 more)

### Community 20 - "Command Logger"
Cohesion: 0.09
Nodes (28): CodingKey, Encodable, CodingKeys, isError, result, structuredOutput, subtype, CodingKeys (+20 more)

### Community 21 - "Workspace Collection"
Cohesion: 0.13
Nodes (4): Int, Int32, WorktreeServiceTests, WorktreeServiceTestsRunner

### Community 22 - "Refresh Scheduling & Coalescing"
Cohesion: 0.10
Nodes (19): ghostty_action_color_change_s, ghostty_action_s, ghostty_app_t, ghostty_clipboard_e, ghostty_config_t, ghostty_surface_config_s, ghostty_target_s, NSPasteboard (+11 more)

### Community 23 - "Worktree Service"
Cohesion: 0.05
Nodes (42): additionalProperties, description, type, description, type, description, type, description (+34 more)

### Community 24 - "Off-Main Process Runner"
Cohesion: 0.10
Nodes (19): DispatchWorkItem, KillGuard, State, alive, dead, terminating, pid_t, TimeInterval (+11 more)

### Community 25 - "Decision Record Schema"
Cohesion: 0.24
Nodes (8): IPCServer, async, Bool, Data, Int32, IPCResponse, UInt64, Log

### Community 26 - "Git Status Service"
Cohesion: 0.10
Nodes (12): NSWindowController, NSWindowDelegate, Bool, WindowFrame, Any, Bool, NSCoder, NSObjectProtocol (+4 more)

### Community 27 - "Session State Fixtures"
Cohesion: 0.05
Nodes (40): Codable, Equatable, Sendable, CopyEntry, SetupEntry, IPCEnv, IPCError, IPCRequest (+32 more)

### Community 28 - "Worktree Service Tests"
Cohesion: 0.25
Nodes (3): RemoteExecutionRegistry, Bool, RemoteExecutionRegistryTests

### Community 29 - "Test Harness Utilities"
Cohesion: 0.08
Nodes (3): Foundation, Testing, tian

### Community 30 - "Workspace Reorder Logic"
Cohesion: 0.07
Nodes (6): Bool, Int, UUID, Void, WorkspaceCollection, WorkspaceCollectionTests

### Community 31 - "Inspect File Tree ViewModel"
Cohesion: 0.10
Nodes (6): InspectFileTreeViewModel, URL, Workspace, DefaultWorkingDirectoryTests, MainActor, WorkspaceTests

### Community 32 - "Pane ViewModel"
Cohesion: 0.05
Nodes (35): Architecture, Build, Concepts, graphify, Keeping the record current (do this without being asked), Key Layers, Lifecycle, Logs (+27 more)

### Community 33 - "Error Types"
Cohesion: 0.14
Nodes (3): ClaudeSessionState, PaneStatusManagerTests, UUID

### Community 34 - "Ghostty App Core"
Cohesion: 0.13
Nodes (11): Bool, SessionGitContext, Bool, Duration, Int, Never, Set, Task (+3 more)

### Community 35 - "Pane Status Manager"
Cohesion: 0.16
Nodes (15): GitRepoID, PRStatus, URL, CacheEntry, CacheKey, CacheResult, hit, miss (+7 more)

### Community 36 - "Session Git Context Tests"
Cohesion: 0.12
Nodes (15): InspectPanelHeader, Bool, CGFloat, DiffSummary, FilesContext, InspectPanelInfoStrip, Bool, CGFloat (+7 more)

### Community 37 - "Sidebar Drag Reorder"
Cohesion: 0.10
Nodes (13): DragGesture, PreferenceKey, SidebarExpandedContentView, SidebarItem, sessionRow, workspaceHeader, CGFloat, CGRect (+5 more)

### Community 38 - "Session Migration Encoding Tests"
Cohesion: 0.13
Nodes (6): BackgroundActivity, Bool, Date, TimeInterval, BackgroundActivityLifecycleTests, TimeInterval

### Community 39 - "Background Activity Store"
Cohesion: 0.10
Nodes (15): CFTimeInterval, CallbackBox, GitRepoWatcher, Bool, DispatchQueue, escaping, FSEventStreamRef, Void (+7 more)

### Community 41 - "Session Divider Drag"
Cohesion: 0.20
Nodes (8): Kind, added, removed, unchanged, MarkdownDiffSegment, MarkdownInlineDiff, Int, MarkdownInlineDiffTests

### Community 42 - "Framework Imports"
Cohesion: 0.15
Nodes (13): SessionOverviewOverlayModifier, SidebarNotificationModifier, Bool, SidebarPanelView, SidebarFocusTarget, sidebar, terminal, SidebarMode (+5 more)

### Community 43 - "Markdown Reader"
Cohesion: 0.06
Nodes (28): MarkdownContent, MarkdownUI, ReaderFileSource, RemoteReaderFileSource, Data, Date, Content, image (+20 more)

### Community 44 - "Worktree Config Parser"
Cohesion: 0.14
Nodes (7): table, TimeInterval, URL, WorktreeConfigParser, WorktreeConfigParserTests, TOMLKit, TOMLTable

### Community 46 - "Git Types"
Cohesion: 0.08
Nodes (30): CustomStringConvertible, Error, Logger, NotificationError, permissionDenied, RestoreError, emptySessions, emptyWorkspaces (+22 more)

### Community 48 - "Working Tree Watcher"
Cohesion: 0.13
Nodes (15): CoreServices, DispatchSourceTimer, Box, Bool, DispatchQueue, Duration, FSEventStreamRef, Int (+7 more)

### Community 49 - "Branch Graph Rendering"
Cohesion: 0.10
Nodes (16): Float, SIMD2, Color, BranchCommitRow, Bool, CGFloat, BranchGraphCanvas, InspectBranchBody (+8 more)

### Community 50 - "Inspect File Scanner"
Cohesion: 0.10
Nodes (14): GitChangedFile, InspectChildEntry, InspectIgnoredEntries, Bool, Set, BlockingScanner, CountingScanner, FixedScanner (+6 more)

### Community 51 - "CLI Output Formatting"
Cohesion: 0.18
Nodes (7): SessionSerializer, ClaudeSessionState, Data, URL, UUID, SessionSerializerWriteTests, URL

### Community 52 - "Claude Session State"
Cohesion: 0.06
Nodes (18): Comparable, ClaudeNotificationPolicy, ClaudeNotificationTrigger, done, needsAttention, Bool, ClaudeSessionState, ClaudeSessionState (+10 more)

### Community 53 - "Remote Connection & Workspace Create"
Cohesion: 0.12
Nodes (6): Direction, down, up, BranchListViewModelTests, Bool, Date

### Community 54 - "Inspect Branch ViewModel"
Cohesion: 0.18
Nodes (7): SessionRestorer, Bool, Data, URL, UUID, SessionRestorerDecodeTests, Int

### Community 55 - "Markdown Diff Segments"
Cohesion: 0.08
Nodes (27): build_manifest(), Handler, iter_json_files(), main(), Every *.json under ROOT (used both for the manifest and the mtime watch)., Map of json path -> mtime, for change detection., Describe what exists so the dashboard can discover docs and ADRs., serve() (+19 more)

### Community 56 - "Ghostty Terminal Surface"
Cohesion: 0.20
Nodes (4): RemoteCommandBuilder, ShellQuoting, SSHMultiplexing, RemoteCommandBuilderTests

### Community 57 - "Branch List Tests"
Cohesion: 0.15
Nodes (8): InspectFileScanner, ScannerError, decodeFailed, gitFailed, Data, Int32, URL, InspectFileScannerTests

### Community 58 - "IPC Client CLI"
Cohesion: 0.15
Nodes (9): BranchListViewModel, BranchEntry, BranchListProviding, BranchListServiceAdapter, Bool, Date, Kind, FakeService (+1 more)

### Community 60 - "Inspect Diff ViewModel"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 61 - "Inspect Panel View"
Cohesion: 0.09
Nodes (14): App, NSApplicationDelegate, NSObject, Scene, TianApp, Bool, NSApplication, TianAppDelegate (+6 more)

### Community 62 - "Create Session View"
Cohesion: 0.19
Nodes (11): Character, BranchRow, Bool, Date, CreateSessionView, CreateWorktreeSubmission, Bool, Field (+3 more)

### Community 63 - "Git Status Service Tests"
Cohesion: 0.23
Nodes (7): SessionOverviewSort, ClaudeSessionState, T, Item, SessionOverviewSortTests, ClaudeSessionState, Int

### Community 64 - "IPC Message Protocol"
Cohesion: 0.08
Nodes (35): Identifiable, GitCommit, GitCommitGraph, GitDiffHunk, GitDiffLine, GitDiffSummary, GitFileStatus, added (+27 more)

### Community 65 - "Session Split Navigation"
Cohesion: 0.07
Nodes (18): InspectTabState, Bool, InspectTab, InspectDiffBody, Row, binary, divider, fileHeader (+10 more)

### Community 67 - "Worktree Setup Progress"
Cohesion: 0.19
Nodes (11): escaping, T, Double, Snapshot, Duration, Never, Task, UInt32 (+3 more)

### Community 68 - "Background Activity Sync"
Cohesion: 0.29
Nodes (5): FileHandle, FileLogWriter, ISO8601DateFormatter, UInt64, URL

### Community 69 - "Pane Node Building"
Cohesion: 0.20
Nodes (7): Coordinator, Bool, Context, NSView, SplitDirection, UUID, TerminalContentView

### Community 70 - "Pane Node Tree"
Cohesion: 0.11
Nodes (15): WorkspaceProviding, CopyRule, LayoutNode, pane, split, ClosedRange, Int, SplitDirection (+7 more)

### Community 71 - "Create Session Flow Tests"
Cohesion: 0.16
Nodes (9): PaneNode, leaf, split, SplitDirection, horizontal, vertical, Bool, Int (+1 more)

### Community 72 - "IPC Env Encoding"
Cohesion: 0.23
Nodes (3): BackgroundActivityBadgeView, Int, BackgroundActivityBadgeTests

### Community 73 - "Pane Status Aggregation Tests"
Cohesion: 0.16
Nodes (4): FuzzyMatch, Result, Int, FuzzyMatchTests

### Community 74 - "Session State Registry"
Cohesion: 0.16
Nodes (3): CGFloat, Int, WorkspaceReorderGeometry

### Community 75 - "Session Restorer"
Cohesion: 0.22
Nodes (8): NSView, KeyView, OverviewKeyboardResponder, Bool, Context, KeyView, NSEvent, Void

### Community 76 - "Session Restorer Tests"
Cohesion: 0.10
Nodes (21): PaneLeafState, PaneNode, PaneNodeState, pane, split, PaneSplitState, SessionRecord, Bool (+13 more)

### Community 78 - "Quit Flow Coordinator"
Cohesion: 0.17
Nodes (9): ImageIO, NSImage, ImageDocument, Sendbox, Date, T, ImageReaderView, Bool (+1 more)

### Community 79 - "Pane Hierarchy Wiring"
Cohesion: 0.11
Nodes (18): A Session = one Claude pane + a toggleable terminal panel, Command reference, Core rules, Delegation orchestrator (bundled script — backs `/tian implement`), Discovery, Driving tian with the `tian` CLI, Gotchas, Long-session hygiene (+10 more)

### Community 80 - "Inspect Tab State"
Cohesion: 0.18
Nodes (10): 1. Settle the tree (graphify churn), 2. (Confirmed) — proceed once the version and a clean tree are both settled., 3. Publish, 4. Update the release record — `docs/pm/status.json`, 5. Verify, Cutting a tian release with `/release`, Escape hatches (env vars, forwarded to publish.sh), Gotchas (+2 more)

### Community 81 - "IPC Server Socket"
Cohesion: 0.13
Nodes (13): ReaderOverlayView, Bool, CGFloat, Void, SessionContentView, Bool, CGFloat, CGSize (+5 more)

### Community 82 - "Key Binding Registry"
Cohesion: 0.09
Nodes (20): SidebarSessionRowMutationGate, SidebarSessionRowView, Bool, CGFloat, ClaudeSessionState, Date, URL, UUID (+12 more)

### Community 83 - "Session Content View"
Cohesion: 0.30
Nodes (7): PRState, closed, draft, merged, open, GitStatusServiceCommitGraphTests, Bool

### Community 84 - "Branch List Fakes"
Cohesion: 0.27
Nodes (7): KeyView, SidebarKeyboardResponder, Bool, Context, KeyView, NSEvent, Void

### Community 86 - "File Log Writer"
Cohesion: 0.17
Nodes (8): InspectPanelState, Bool, CGFloat, Bool, Date, UUID, WorkspaceSnapshot, InspectPanelStateTests

### Community 87 - "Window Drag Blocker"
Cohesion: 0.24
Nodes (3): URL, WorkingDirectoryResolver, WorkingDirectoryResolverTests

### Community 88 - "Commit Graph Tests"
Cohesion: 0.32
Nodes (5): SkillInstaller, URL, UserDefaults, SkillInstallerTests, URL

### Community 89 - "IPC Message Tests"
Cohesion: 0.25
Nodes (5): sockaddr, blockingAwait(), escaping, T, UnsafePointer

### Community 90 - "Remote Command Builder"
Cohesion: 0.20
Nodes (8): Direction, down, left, right, up, OverviewGridNavigation, Int, UUID

### Community 91 - "Skill Installer"
Cohesion: 0.31
Nodes (4): BranchListService, Int32, Set, BranchListServiceTests

### Community 92 - "Branch List ViewModel"
Cohesion: 0.14
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
Cohesion: 0.12
Nodes (11): SSHConnection, State, connected, connecting, idle, offline, CommandResult, SSHControlChannel (+3 more)

### Community 97 - "Status Doc Schema"
Cohesion: 0.23
Nodes (7): RemoteInspectFileScanner, RemoteScanError, commandFailed, Data, Duration, Int32, URL

### Community 99 - "Terminal Content View"
Cohesion: 0.24
Nodes (8): CloseConfirmationDialog, CloseTarget, pane, Int, NSAlert, NSWindow, Void, CloseConfirmationDialogTests

### Community 100 - "Close Confirmation Dialog"
Cohesion: 0.43
Nodes (4): NSLayoutConstraint, CGFloat, NSWindow, TrafficLightAligner

### Community 101 - "Image Reader"
Cohesion: 0.20
Nodes (9): Field, dialog, name, SubmitAction, blocked, checkoutExisting, claudeWorktree, createBranch (+1 more)

### Community 102 - "Session Serializer"
Cohesion: 0.16
Nodes (9): GridItem, SessionOverviewSortMode, defaultOrder, sessionState, CardEntry, SessionOverviewGridView, CGFloat, Int (+1 more)

### Community 103 - "Workspace Keyboard Navigation"
Cohesion: 0.21
Nodes (6): DockPosition, bottom, right, SessionDividerDragController, Bool, Void

### Community 104 - "System Monitor (CPU/RAM)"
Cohesion: 0.14
Nodes (13): Architecture, Build, Concepts, Key Layers, Lifecycle, Logs, Scratch / Temporary Files, Source Layout (+5 more)

### Community 105 - "Check For Updates"
Cohesion: 0.22
Nodes (8): LocalizedError, CLIError, closeInFlight, connection, general, permissionDenied, processSafety, Int32

### Community 106 - "Working Directory Resolver"
Cohesion: 0.18
Nodes (5): EnvironmentBuilder, UUID, PaneHierarchyContext, UUID, EnvironmentBuilderTests

### Community 107 - "App Hero Screenshot (UI)"
Cohesion: 0.24
Nodes (13): Claude Pane (Claude Code v2.1.140), Claude Code Statusline (ctx/model/branch), File Explorer Panel (Files/Diff/Branch), Workspace -> Session -> Pane Hierarchy, New Workspace Action, Session Row (name + branch + git diff), Workspace/Session Sidebar, Bottom Status Bar (CPU/RAM) (+5 more)

### Community 108 - "Shipped Items Schema"
Cohesion: 0.25
Nodes (10): sockaddr_un, socklen_t, IPCServerTests, IPCTestError, connectionFailed, socketCreationFailed, writeFailed, Data (+2 more)

### Community 109 - "Status Bar View"
Cohesion: 0.22
Nodes (9): CreateSessionRequest, Bool, CGFloat, Duration, Never, Task, URL, Void (+1 more)

### Community 110 - "SessionCloseFlow"
Cohesion: 0.15
Nodes (13): description, type, properties, commit, since, summary, target, description (+5 more)

### Community 111 - "NotificationManager"
Cohesion: 0.05
Nodes (27): ghostty_input_mods_e, NSAttributedString, NSMenu, NSPoint, NSRange, NSRangePointer, NSRect, NSSize (+19 more)

### Community 112 - "TianSettings"
Cohesion: 0.25
Nodes (3): URL, WorkspaceCreationFlow, WorkspaceCreationFlowTests

### Community 114 - "AppKit"
Cohesion: 0.12
Nodes (13): NSViewRepresentable, Context, NSView, NSWindow, WindowAccessor, BlockerView, Bool, Context (+5 more)

### Community 115 - "KeyboardLayoutTranslator"
Cohesion: 0.29
Nodes (5): Bool, UserDefaults, TianSettings, UserDefaults, TianSettingsTests

### Community 116 - "implement-log"
Cohesion: 0.33
Nodes (5): PaneState, exited, running, spawnFailed, UInt32

### Community 118 - "AutoSetPrompt"
Cohesion: 0.24
Nodes (5): SessionCloseFlow, Bool, NSWindow, URL, Error

### Community 119 - "GitStatusServiceUnifiedDiffTests"
Cohesion: 0.67
Nodes (3): description, type, blocked

### Community 120 - "InspectPanelState"
Cohesion: 0.67
Nodes (3): description, type, date

### Community 121 - "SidebarExpandedContentView"
Cohesion: 0.18
Nodes (9): SessionSplitNavigation, CGRect, CGSize, PaneNode, UUID, Target, ForegroundProcessSummary, Bool (+1 more)

### Community 122 - "SidebarSessionRowView"
Cohesion: 0.29
Nodes (10): items, additionalProperties, required, type, items, items, shipped, description (+2 more)

### Community 123 - "items"
Cohesion: 0.15
Nodes (6): AnyObject, Observation, BranchGraphDirtyHost, SessionGitContext, Keys, BranchEntry.Kind

### Community 124 - "EnvironmentBuilderTests"
Cohesion: 0.67
Nodes (3): Mode, existingBranch, newBranch

### Community 125 - "WorktreeKindTests"
Cohesion: 0.19
Nodes (7): PaneKind, claude, terminal, PaneNode, RemoteSpawnSpec, PaneSpawner, RestoreCommandPaneViewModelTests

### Community 127 - "PollingRefresher"
Cohesion: 0.67
Nodes (3): description, type, done

### Community 129 - "WorkspaceWindowContent"
Cohesion: 0.67
Nodes (3): description, type, link

### Community 130 - "implement"
Cohesion: 0.09
Nodes (12): PaneStatus, PaneStatusManager, Bool, Duration, Never, Set, T, Task (+4 more)

### Community 132 - "MarkdownCopyButton"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 133 - "Response"
Cohesion: 0.42
Nodes (7): emit_block(), err(), log_run(), need_val(), implement.sh script, log(), usage()

### Community 134 - "Response"
Cohesion: 0.50
Nodes (4): Badge, local, localAndOrigin, origin

### Community 135 - "WorkspaceCreationFlowTests"
Cohesion: 0.33
Nodes (7): MarkdownCopyButton, MarkdownDiffToggleButton, ReaderCloseButton, CGFloat, Never, Task, Void

### Community 136 - "MockWorkspaceProvider"
Cohesion: 0.10
Nodes (15): ClosedRange, SessionDividerClamper, Bool, CGFloat, SessionDividerView, Bool, CGFloat, CGSize (+7 more)

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
Cohesion: 0.12
Nodes (7): Darwin, os, OSLog, BranchDeleteOutcome, deleted, keptUnmerged, notFound

### Community 141 - ".makeHarness"
Cohesion: 0.39
Nodes (3): AppMetrics, Int, UInt64

### Community 142 - "AppMetrics"
Cohesion: 0.25
Nodes (7): How to read the output, Improvement catalog (map flags → fixes), Input, Litmus test to report, Run, session-audit — audit a tian orchestrator session, What to produce

### Community 143 - "InspectPanelFileRow"
Cohesion: 0.21
Nodes (8): NSAlert, ConfirmAlert, QuitConfirmationDialog, Bool, Int, NSAlert, NSWindow, Void

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

### Community 152 - "GitStatusService"
Cohesion: 0.18
Nodes (7): FileBaseline, committed, notInRepo, untracked, GitStatusService, Int, Int32

### Community 153 - "PaneState"
Cohesion: 0.29
Nodes (6): ShellReadinessWaiter, ShellReadyReason, osc7, timeout, TimeInterval, UUID

### Community 154 - "KeyAction"
Cohesion: 0.11
Nodes (17): KeyAction, closeWorkspace, cycleFocusArea, focusSidebar, goToSession, newSession, newWorkspace, nextSession (+9 more)

### Community 157 - "DebugOverlayView"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 160 - "SidebarWorkspaceHeaderView"
Cohesion: 0.23
Nodes (11): Hashable, CharacterChord, KeyBinding, KeyBindingRegistry, KeyCodeChord, NSEvent, UInt16, Kind (+3 more)

### Community 161 - "StatusBarView"
Cohesion: 0.17
Nodes (7): SparklineView, CGFloat, StatusBarPalette, StatusBarView, CGFloat, UInt64, Value

### Community 162 - "CheckForUpdatesView"
Cohesion: 0.23
Nodes (8): Commands, ObservableObject, Sparkle, CheckForUpdatesView, CheckForUpdatesViewModel, SPUUpdater, SPUUpdater, WorkspaceCommands

### Community 164 - "WorktreeConfig"
Cohesion: 0.47
Nodes (3): HtmlFileType, Bool, Set

### Community 166 - ".startClaude"
Cohesion: 0.22
Nodes (6): WorktreeKind, linkedWorktree, mainCheckout, notARepo, noWorkingDirectory, WorktreeKindTests

### Community 167 - "AppMetrics"
Cohesion: 0.03
Nodes (62): S, SwiftUI, SettingsView, DebugOverlayView, LabeledMetric, DefaultDirectoryMenu, URL, Void (+54 more)

### Community 170 - "SessionRestorer"
Cohesion: 0.27
Nodes (5): Carbon.HIToolbox, KeyboardLayoutTranslator, Data, UInt16, UInt32

### Community 171 - "resolve_from_runlog"
Cohesion: 0.67
Nodes (3): description, type, item

### Community 172 - "DebugOverlayView"
Cohesion: 0.67
Nodes (3): title, description, type

### Community 173 - "EventCoalescerTests"
Cohesion: 0.09
Nodes (17): WorktreeError, baseWithExisting, branchAlreadyExists, closeInFlight, configParseError, gitError, invalidBaseRef, notAGitRepo (+9 more)

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

### Community 187 - "PollingRefresher"
Cohesion: 0.27
Nodes (6): PollingRefresher, Duration, MainActor, Never, Task, Void

### Community 188 - "ConfirmAlert"
Cohesion: 0.14
Nodes (5): AppKit, CGRect, WindowFrame, DirectoryPicker, URL

### Community 200 - "CLIError+IPC.swift"
Cohesion: 0.80
Nodes (4): assert_call(), assert_no_call(), run_hook(), tian-hook-activity-test.sh script

### Community 203 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.83
Nodes (3): log_raw_payload(), run_tian(), tian-hook-activity.sh script

### Community 214 - "T"
Cohesion: 0.12
Nodes (13): Binding, SessionOverviewCardView, Bool, Void, WorkspaceChip, CreateWorkspaceView, Field, directory (+5 more)

## Knowledge Gaps
- **433 isolated node(s):** `$schema`, `$id`, `title`, `description`, `type` (+428 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **78 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `Git Types` to `IPC Command Handling`, `Terminal Surface Input`, `Session Git & PR Status`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Sidebar Container`, `Worktree Orchestrator`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Workspace Collection`, `Refresh Scheduling & Coalescing`, `Off-Main Process Runner`, `Decision Record Schema`, `Session State Fixtures`, `Worktree Service Tests`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Error Types`, `Ghostty App Core`, `Pane Status Manager`, `Session Git Context Tests`, `Sidebar Drag Reorder`, `Session Migration Encoding Tests`, `Background Activity Store`, `Graphify Pipeline Skill`, `Session Divider Drag`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Working Tree Watcher`, `Branch Graph Rendering`, `Inspect File Scanner`, `CLI Output Formatting`, `Claude Session State`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `Ghostty Terminal Surface`, `Branch List Tests`, `IPC Client CLI`, `Create Session View`, `IPC Message Protocol`, `Session Split Navigation`, `Fuzzy Match`, `Background Activity Sync`, `Pane Node Tree`, `Create Session Flow Tests`, `IPC Env Encoding`, `Pane Status Aggregation Tests`, `Session Restorer Tests`, `Worktree Config Execution`, `Quit Flow Coordinator`, `IPC Server Socket`, `Key Binding Registry`, `Session Content View`, `App Delegate Lifecycle`, `File Log Writer`, `Window Drag Blocker`, `Commit Graph Tests`, `Skill Installer`, `Branch List ViewModel`, `Branch List Service`, `Key Chord Model`, `Process Detector`, `Status Doc Schema`, `Image Reader`, `Session Serializer`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `Shipped Items Schema`, `Status Bar View`, `NotificationManager`, `TianSettings`, `KeyboardLayoutTranslator`, `SidebarExpandedContentView`, `items`, `WorktreeKindTests`, `SessionSplitNavigation`, `implement`, `Response`, `BusyDotView`, `.makeHarness`, `InlineRenameView`, `RefreshSchedulerTests`, `resolve_from_runlog`, `GitStatusService`, `IPCMessageTests`, `SidebarWorkspaceHeaderView`, `StatusBarView`, `WorktreeConfig`, `.fromIPCError`, `.startClaude`, `AppMetrics`, `SessionRestorer`, `EventCoalescerTests`, `.unifiedDiff`, `ConfirmAlert`, `FalkorDB export`, `.from`, `T`, `.claudePreviewText`?**
  _High betweenness centrality (0.559) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Harness Utilities` to `IPC Command Handling`, `implement`, `os`, `Split Layout & Navigation`, `CLI Command Router`, `Session State Migration`, `Git Repo Watcher`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `blockingAwait`, `.stopPreventsFurtherCallbacks`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Command Logger`, `BranchListService`, `Off-Main Process Runner`, `PaneState`, `Git Status Service`, `Session State Fixtures`, `Worktree Service Tests`, `HtmlFileType`, `GitRepoWatcherBranchGraphTests`, `Pane Status Manager`, `WorktreeConfig`, `.fromIPCError`, `.startClaude`, `Background Activity Store`, `Session Divider Drag`, `Markdown Reader`, `Worktree Config Parser`, `EventCoalescerTests`, `Git Types`, `Working Tree Watcher`, `Inspect File Scanner`, `CLI Output Formatting`, `Claude Session State`, `Markdown Diff Segments`, `Ghostty Terminal Surface`, `Branch List Tests`, `IPC Client CLI`, `PollingRefresher`, `ConfirmAlert`, `Git Status Service Tests`, `IPC Message Protocol`, `FalkorDB export`, `Background Activity Sync`, `Pane Node Tree`, `Create Session Flow Tests`, `Pane Status Aggregation Tests`, `Session Restorer Tests`, `Key Binding Registry`, `File Log Writer`, `Window Drag Blocker`, `Commit Graph Tests`, `IPC Message Tests`, `Remote Command Builder`, `Branch List ViewModel`, `Branch List Service`, `Process Detector`, `Status Doc Schema`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `TianSettings`, `Row`, `KeyboardLayoutTranslator`, `SidebarExpandedContentView`, `items`, `WorktreeKindTests`, `SessionSplitNavigation`?**
  _High betweenness centrality (0.081) - this node is a cross-community bridge._
- **Why does `Session` connect `Session Git & PR Status` to `IPC Command Handling`, `.claudePreviewText`, `implement`, `Git Repo Watcher`, `MockWorkspaceProvider`, `Sidebar Container`, `Split Tree Model`, `Persistence State Models`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Error Types`, `.fromIPCError`, `Session Migration Encoding Tests`, `Sidebar Drag Reorder`, `NSView`, `Markdown Reader`, `Session Audit Analyzer`, `Git Types`, `CLI Output Formatting`, `IPC Message Protocol`, `Worktree Setup Progress`, `IPC Server Socket`, `Key Binding Registry`, `T`, `RetryClaudeSpawnTests`, `Process Detector`, `Session Serializer`, `Workspace Keyboard Navigation`, `socklen_t`, `AutoSetPrompt`, `SidebarExpandedContentView`, `items`, `WorktreeKindTests`?**
  _High betweenness centrality (0.065) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `String` (e.g. with `.run()` and `.resolveRepoRoot()`) actually correct?**
  _`String` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 62 inferred relationships involving `Session` (e.g. with `.buildWorkspaceCollection()` and `SessionReaderState`) actually correct?**
  _`Session` has 62 INFERRED edges - model-reasoned connections that need verification._
- **Are the 96 inferred relationships involving `PaneStatusManager` (e.g. with `.fireDoneIfStillIdle()` and `.handlePaneList()`) actually correct?**
  _`PaneStatusManager` has 96 INFERRED edges - model-reasoned connections that need verification._
- **Are the 26 inferred relationships involving `WorkspaceCollection` (e.g. with `.defaultSelection()` and `.body()`) actually correct?**
  _`WorkspaceCollection` has 26 INFERRED edges - model-reasoned connections that need verification._