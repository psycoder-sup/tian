# Graph Report - git-watch-redesign-adr  (2026-07-16)

## Corpus Check
- 347 files · ~366,544 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4727 nodes · 12366 edges · 278 communities (197 shown, 81 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 1716 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8314dac6`
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
- .updateSurfaceSize
- PaneState
- PaneState
- HtmlFileType
- ImageFileType
- DebugOverlayView
- SessionSplitNavigation
- GitRepoWatcherBranchGraphTests
- SidebarWorkspaceHeaderView
- PollingRefresher
- CheckForUpdatesView
- DebugOverlayView
- WorktreeConfig
- .fromIPCError
- .startClaude
- AppMetrics
- NSView
- NSRange
- handleListResponse
- resolve_from_runlog
- DebugOverlayView
- EventCoalescerTests
- .unifiedDiff
- .from
- date
- done
- item
- TianApp
- tian-hook-prompt-test.sh
- Glowing Vertical Cursor Bar Motif
- WeakBox
- tian-hook-activity
- .reorderDestinationIndex
- Serena project config
- filter_zombies
- .makeEmpty
- ConfirmAlert
- install
- release
- claude
- BusyDotView
- OverviewGridNavigation
- Token reduction benchmark
- PRState
- ImageFileType
- dev scratch space
- graphify knowledge graph
- NetworkImage
- CLIError+IPC.swift
- MarkdownFileType
- InspectPanelStatusStrip
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
- .insertionSlot
- CharacterChord
- Row
- .makeHarness
- .continueCreation
- .unifiedDiff
- .write
- .resolve
- Git-watch redesign — implementation plan
- .makeSession
- NSRange
- PaneState
- CoreGraphics
- ChangeBadgeView
- ClaudeEventOrigin
- Swift Argument Parser
- TOMLKit
- ProcessClaudeInvoker
- GitFileStatus
- .makeEmpty
- .claudePreviewText
- OptionAsAltSetting
- DebugOverlayView
- .detect
- InspectPanelStatusStrip
- GitRepoWatcher.swift
- ConcurrencyTracker
- .openRestoredWindow
- Kind
- CFTimeInterval
- DispatchQueue
- FSEventStreamRef
- T
- tian-hook-prompt.sh

## God Nodes (most connected - your core abstractions)
1. `String` - 578 edges
2. `Foundation` - 184 edges
3. `PaneStatusManager` - 173 edges
4. `Session` - 155 edges
5. `IPCCommandHandler` - 114 edges
6. `WorkspaceCollection` - 114 edges
7. `View` - 110 edges
8. `PaneViewModel` - 95 edges
9. `Workspace` - 95 edges
10. `Testing` - 87 edges

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

## Communities (278 total, 81 thin omitted)

### Community 0 - "IPC Command Handling"
Cohesion: 0.06
Nodes (24): ClaudeSessionNotifier, Bool, ClaudeSessionState, Duration, UUID, IPCCommandHandler, Bool, ClaudeSessionState (+16 more)

### Community 1 - "Terminal Surface Input"
Cohesion: 0.25
Nodes (12): GitFileDiff, InspectDiffViewModel, Bool, Duration, Never, Set, Task, Void (+4 more)

### Community 2 - "Session Git & PR Status"
Cohesion: 0.07
Nodes (8): Session, CGSize, ClaudeSessionState, Date, Void, CustomLaunchCommandTests, SessionModelTests, MainActor

### Community 3 - "Split Layout & Navigation"
Cohesion: 0.07
Nodes (19): DividerInfo, SplitLayout, SplitLayoutResult, CGFloat, CGRect, PaneNode, SplitDirection, UUID (+11 more)

### Community 4 - "Session State Migration"
Cohesion: 0.08
Nodes (23): Migration, active, MigrationError, futureVersion, migrationFailed, missingVersion, SessionStateMigrator, Any (+15 more)

### Community 5 - "CLI Command Router"
Cohesion: 0.07
Nodes (42): ParsableCommand, IPCError, ActivityBegin, ActivityClear, ActivityEnd, ActivityGroup, ActivityReconcile, ActivityResetLifecycle (+34 more)

### Community 6 - "Git Repo Watcher"
Cohesion: 0.09
Nodes (9): HierarchicalEntry, SessionCollection, Bool, Int, URL, UUID, DockToggleDuringDragTests, SessionCollectionStressTests (+1 more)

### Community 7 - "Session Model"
Cohesion: 0.11
Nodes (6): JSONDecoder, SessionMigrationV7ToV8Tests, PaneNodeStateEncodingTests, SessionRecordWorktreePathTests, JSONEncoder, WindowFrameTests

### Community 8 - "Session Collection"
Cohesion: 0.09
Nodes (42): bash_commands(), buckets(), child_branch(), child_hygiene(), count_tools(), failed_delegate_tasks(), file_path_tools(), filter_zombies() (+34 more)

### Community 9 - "SwiftUI View Components"
Cohesion: 0.09
Nodes (20): CaseIterable, ExpressibleByArgument, handleListResponse(), PaneList, SessionList, IPCValue, WorkspaceList, WorktreeCreateOutput (+12 more)

### Community 10 - "Config Auto-Set Runner"
Cohesion: 0.14
Nodes (18): Decodable, AutoSetPayload, ClaudeResultEnvelope, CopyEntry, SetupEntry, Bool, ConfigAutoSetResult, ConfigAutoSetRunner (+10 more)

### Community 11 - "Session Overview Grid"
Cohesion: 0.10
Nodes (13): InspectFileTreeViewModel, async, Bool, Never, Set, Task, URL, Void (+5 more)

### Community 12 - "Sidebar Container"
Cohesion: 0.07
Nodes (25): Accessibility, InspectPanelTabsWiringModifier, InspectPanelWiringModifier, Notification, Notification.Name, SidebarContainerView, SidebarNotificationModifier, Bool (+17 more)

### Community 13 - "Worktree Orchestrator"
Cohesion: 0.24
Nodes (5): Any, Void, WorktreeOrchestrator, MockWorkspaceProvider, WorktreeOrchestratorTests

### Community 14 - "Split Tree Model"
Cohesion: 0.16
Nodes (12): SessionState, Date, Int, makeClaudeSession(), makeWorkspaceState(), SessionRestorerBuildTests, SessionRestorerLoadTests, SessionRestorerMetricsTests (+4 more)

### Community 15 - "SSH Remote Execution"
Cohesion: 0.12
Nodes (18): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+10 more)

### Community 16 - "Inspect File Tree Scanning"
Cohesion: 0.15
Nodes (5): Bool, WindowFrame, SessionSnapshotWindowGeometryTests, SessionSnapshotTests, SessionSnapshotWorktreePathTests

### Community 17 - "ANSI Stripper"
Cohesion: 0.12
Nodes (11): RemoveResult, lastPane, notFound, removed, SplitTree, Bool, Int, PaneNode (+3 more)

### Community 18 - "Workspace Model"
Cohesion: 0.11
Nodes (9): ANSIStripper, State, csi, escape, escapeIntermediate, normal, osc, oscEscape (+1 more)

### Community 19 - "Persistence State Models"
Cohesion: 0.09
Nodes (14): PaneStatus, UInt64, PaneViewModel, Bool, CGSize, ClaudeSessionState, NSObjectProtocol, Set (+6 more)

### Community 20 - "Command Logger"
Cohesion: 0.06
Nodes (37): CodingKey, Encodable, CodingKeys, isError, result, structuredOutput, subtype, CodingKeys (+29 more)

### Community 21 - "Workspace Collection"
Cohesion: 0.13
Nodes (3): Int32, WorktreeServiceTests, WorktreeServiceTestsRunner

### Community 22 - "Refresh Scheduling & Coalescing"
Cohesion: 0.09
Nodes (17): ghostty_action_color_change_s, ghostty_action_s, ghostty_app_t, ghostty_clipboard_e, ghostty_config_t, ghostty_surface_config_s, ghostty_target_s, NSPasteboard (+9 more)

### Community 23 - "Worktree Service"
Cohesion: 0.05
Nodes (42): additionalProperties, description, type, description, type, description, type, description (+34 more)

### Community 24 - "Off-Main Process Runner"
Cohesion: 0.10
Nodes (19): DispatchWorkItem, KillGuard, State, alive, dead, terminating, pid_t, TimeInterval (+11 more)

### Community 25 - "Decision Record Schema"
Cohesion: 0.26
Nodes (8): IPCServer, async, Bool, Data, Int32, IPCResponse, UInt64, Log

### Community 26 - "Git Status Service"
Cohesion: 0.22
Nodes (5): NSWindowController, NSWindowDelegate, Any, NSObjectProtocol, WorkspaceWindowController

### Community 27 - "Session State Fixtures"
Cohesion: 0.11
Nodes (18): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+10 more)

### Community 29 - "Test Harness Utilities"
Cohesion: 0.07
Nodes (3): Foundation, Testing, tian

### Community 30 - "Workspace Reorder Logic"
Cohesion: 0.07
Nodes (7): SessionOverviewOverlayModifier, Bool, Int, UUID, Void, WorkspaceCollection, WorkspaceCollectionTests

### Community 31 - "Inspect File Tree ViewModel"
Cohesion: 0.09
Nodes (7): SessionEmptyStateView, InspectFileTreeViewModel, URL, Workspace, DefaultWorkingDirectoryTests, MainActor, WorkspaceTests

### Community 32 - "Pane ViewModel"
Cohesion: 0.05
Nodes (35): Architecture, Build, Concepts, graphify, Keeping the record current (do this without being asked), Key Layers, Lifecycle, Logs (+27 more)

### Community 33 - "Error Types"
Cohesion: 0.11
Nodes (7): PaneStatusManager, Duration, Never, Set, Task, UUID, Void

### Community 34 - "Ghostty App Core"
Cohesion: 0.12
Nodes (21): async, GitRepoStatus, Never, PollingRefresher, Set, Task, GitMonitor, PRBackoffKey (+13 more)

### Community 35 - "Pane Status Manager"
Cohesion: 0.07
Nodes (29): GitRepoID, CacheEntry, CacheKey, CacheResult, hit, miss, PRStatusCache, Bool (+21 more)

### Community 36 - "Session Git Context Tests"
Cohesion: 0.12
Nodes (15): InspectPanelHeader, Bool, CGFloat, DiffSummary, FilesContext, InspectPanelInfoStrip, Bool, CGFloat (+7 more)

### Community 37 - "Sidebar Drag Reorder"
Cohesion: 0.09
Nodes (14): DragGesture, PreferenceKey, SidebarExpandedContentView, SidebarItem, sessionRow, workspaceHeader, CGFloat, CGRect (+6 more)

### Community 39 - "Background Activity Store"
Cohesion: 0.10
Nodes (17): CFTimeInterval, DispatchQueue, FSEventStreamRef, CallbackBox, GitRepoWatcher, escaping, String, Void (+9 more)

### Community 41 - "Session Divider Drag"
Cohesion: 0.10
Nodes (12): InspectChildEntry, InspectIgnoredEntries, Set, InspectFileScanning, InspectScanOutcome, normal, rootTooBroad, truncated (+4 more)

### Community 42 - "Framework Imports"
Cohesion: 0.10
Nodes (13): Int8, SurfaceCallbackContext, ghostty_surface_t, UUID, GhosttyTerminalSurface, Optional, Bool, ghostty_input_key_s (+5 more)

### Community 43 - "Markdown Reader"
Cohesion: 0.10
Nodes (17): MarkdownUI, ReaderFileSource, RemoteReaderFileSource, DiffOutcome, notInRepo, segments, MarkdownDocument, Sendbox (+9 more)

### Community 44 - "Worktree Config Parser"
Cohesion: 0.11
Nodes (8): table, SplitDirection, TimeInterval, URL, WorktreeConfigParser, SplitDirectionConversionTests, WorktreeConfigParserTests, TOMLTable

### Community 45 - "Session Audit Analyzer"
Cohesion: 0.08
Nodes (6): BackgroundActivity, Bool, Date, TimeInterval, BackgroundActivityStoreTests, ClaudeSessionState

### Community 46 - "Git Types"
Cohesion: 0.11
Nodes (23): CustomStringConvertible, Error, Logger, NotificationError, permissionDenied, RestoreError, emptySessions, emptyWorkspaces (+15 more)

### Community 48 - "Working Tree Watcher"
Cohesion: 0.13
Nodes (15): CoreServices, DispatchSourceTimer, Box, Bool, DispatchQueue, Duration, FSEventStreamRef, Int (+7 more)

### Community 49 - "Branch Graph Rendering"
Cohesion: 0.29
Nodes (7): FileTreeNode, Kind, directory, file, Bool, Int, Kind

### Community 50 - "Inspect File Scanner"
Cohesion: 0.14
Nodes (8): GitChangedFile, BlockingScanner, Counts, FixedScanner, InspectFileTreeViewModel, InspectFileTreeViewModelTests, State, Bool

### Community 51 - "CLI Output Formatting"
Cohesion: 0.18
Nodes (7): SessionSerializer, ClaudeSessionState, Data, URL, UUID, SessionSerializerWriteTests, URL

### Community 52 - "Claude Session State"
Cohesion: 0.17
Nodes (10): ProcessCPUMonitor, Bool, ContinuousClock, Duration, Int, Never, Task, UInt64 (+2 more)

### Community 53 - "Remote Connection & Workspace Create"
Cohesion: 0.14
Nodes (3): BranchListViewModelTests, Bool, Date

### Community 54 - "Inspect Branch ViewModel"
Cohesion: 0.11
Nodes (13): RestoreMetrics, RestoreResult, Source, backup, primary, Bool, Int, SessionRestorer (+5 more)

### Community 55 - "Markdown Diff Segments"
Cohesion: 0.08
Nodes (27): build_manifest(), Handler, iter_json_files(), main(), Every *.json under ROOT (used both for the manifest and the mtime watch)., Map of json path -> mtime, for change detection., Describe what exists so the dashboard can discover docs and ADRs., serve() (+19 more)

### Community 56 - "Ghostty Terminal Surface"
Cohesion: 0.10
Nodes (14): RemoteExecutionRegistry, Bool, SSHConnection, State, connected, connecting, idle, offline (+6 more)

### Community 57 - "Branch List Tests"
Cohesion: 0.22
Nodes (4): ScanCancellationFlag, Counter, InspectFileScannerTests, Int

### Community 58 - "IPC Client CLI"
Cohesion: 0.15
Nodes (8): BranchEntry, BranchListProviding, BranchListServiceAdapter, Bool, Date, Kind, FakeService, FakingListService

### Community 59 - "Workspace Window Controller"
Cohesion: 0.35
Nodes (10): commit_count(), committed(), dedup(), delegation_key(), load(), main(), pct(), rank() (+2 more)

### Community 60 - "Inspect Diff ViewModel"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 61 - "Inspect Panel View"
Cohesion: 0.15
Nodes (10): NSApplicationDelegate, NSObject, Bool, NSApplication, TianAppDelegate, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse (+2 more)

### Community 62 - "Create Session View"
Cohesion: 0.12
Nodes (17): Character, CreateSessionView, CreateWorktreeSubmission, Field, dialog, name, SubmitAction, blocked (+9 more)

### Community 63 - "Git Status Service Tests"
Cohesion: 0.28
Nodes (6): ClaudeSessionState, T, Item, SessionOverviewSortTests, ClaudeSessionState, Int

### Community 64 - "IPC Message Protocol"
Cohesion: 0.17
Nodes (12): AnyObject, BranchGraphDirtyHost, InspectBranchViewModel, SessionGitContext, Bool, Never, Task, Void (+4 more)

### Community 65 - "Session Split Navigation"
Cohesion: 0.14
Nodes (10): InspectScanResult, InspectScanTruncation, depthCap, entryCap, examinedCap, Bool, Int, GatedScanner (+2 more)

### Community 67 - "Worktree Setup Progress"
Cohesion: 0.11
Nodes (28): Identifiable, Sendable, GitCommit, GitCommitGraph, GitDiffHunk, GitDiffLine, GitDiffSummary, GitLane (+20 more)

### Community 68 - "Background Activity Sync"
Cohesion: 0.29
Nodes (6): InspectPanelFileBrowser, InspectPanelTruncationBanner, CGFloat, InspectFileTreeViewModel, Int, Void

### Community 69 - "Pane Node Building"
Cohesion: 0.12
Nodes (12): PaneState, exited, running, spawnFailed, UInt32, Coordinator, Bool, Context (+4 more)

### Community 70 - "Pane Node Tree"
Cohesion: 0.16
Nodes (4): RemoteConnectionState, RemoteConnection, Bool, RemoteConnectionTests

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
Cohesion: 0.18
Nodes (5): Bool, NSCoder, NSWindow, UUID, WorkspaceManager

### Community 75 - "Session Restorer"
Cohesion: 0.07
Nodes (27): Double, ClosedRange, Snapshot, SessionDividerClamper, Bool, CGFloat, SessionDividerView, Bool (+19 more)

### Community 76 - "Session Restorer Tests"
Cohesion: 0.14
Nodes (22): Codable, Equatable, PaneLeafState, PaneNode, PaneNodeState, pane, split, PaneSplitState (+14 more)

### Community 78 - "Quit Flow Coordinator"
Cohesion: 0.09
Nodes (17): ImageIO, NSImage, Content, image, markdown, SessionReaderState, ImageDocument, Sendbox (+9 more)

### Community 79 - "Pane Hierarchy Wiring"
Cohesion: 0.11
Nodes (18): A Session = one Claude pane + a toggleable terminal panel, Command reference, Core rules, Delegation orchestrator (bundled script — backs `/tian implement`), Discovery, Driving tian with the `tian` CLI, Gotchas, Long-session hygiene (+10 more)

### Community 80 - "Inspect Tab State"
Cohesion: 0.17
Nodes (11): 1. Settle the tree (graphify churn), 2. (Confirmed) — proceed once the version and a clean tree are both settled., 3. Publish, 4. Update the release record — `docs/pm/status.json`, 5. Verify, Cutting a tian release with `/release`, Escape hatches (env vars, forwarded to publish.sh), Execution: delegate to a subagent (+3 more)

### Community 81 - "IPC Server Socket"
Cohesion: 0.10
Nodes (15): ghostty_input_mods_e, NSMenu, NSTextInputClient, NSScreen, Any, Bool, ghostty_input_key_s, ghostty_surface_t (+7 more)

### Community 82 - "Key Binding Registry"
Cohesion: 0.18
Nodes (9): Phase, cleanup, removing, setup, SetupProgress, Bool, Int, UUID (+1 more)

### Community 83 - "Session Content View"
Cohesion: 0.26
Nodes (8): Hashable, MainActor, SubscriptionToken, GitMonitorTests, StringError, Double, String, UUID

### Community 84 - "Branch List Fakes"
Cohesion: 0.27
Nodes (7): KeyView, SidebarKeyboardResponder, Bool, Context, KeyView, NSEvent, Void

### Community 85 - "App Delegate Lifecycle"
Cohesion: 0.14
Nodes (4): ScanRootGuard, Bool, URL, ScanRootGuardTests

### Community 86 - "File Log Writer"
Cohesion: 0.07
Nodes (22): GitChangedFile, GitCommitGraph, GitDiffSummary, GitFileDiff, Int32, SSHControlChannel, T, FileBaseline (+14 more)

### Community 87 - "Window Drag Blocker"
Cohesion: 0.27
Nodes (5): EnvironmentValues, Bool, NSWindow, WindowVisibilityState, WindowVisibilityStateTests

### Community 88 - "Commit Graph Tests"
Cohesion: 0.32
Nodes (5): SkillInstaller, URL, UserDefaults, SkillInstallerTests, URL

### Community 89 - "IPC Message Tests"
Cohesion: 0.06
Nodes (17): Comparable, ClaudeNotificationPolicy, ClaudeNotificationTrigger, done, needsAttention, Bool, ClaudeSessionState, ClaudeSessionState (+9 more)

### Community 90 - "Remote Command Builder"
Cohesion: 0.38
Nodes (3): OverviewGridNavigation, Int, UUID

### Community 91 - "Skill Installer"
Cohesion: 0.31
Nodes (4): BranchListService, Int32, Set, BranchListServiceTests

### Community 92 - "Branch List ViewModel"
Cohesion: 0.18
Nodes (4): ProcessDetector, RunningProcessInfo, UUID, ProcessDetectorTests

### Community 94 - "Key Chord Model"
Cohesion: 0.25
Nodes (4): KeyBindingRegistryPhase3Tests, KeyBindingRegistryTests, NSEvent, UInt16

### Community 95 - "Key Actions"
Cohesion: 0.12
Nodes (16): description, type, description, type, description, type, description, type (+8 more)

### Community 96 - "Process Detector"
Cohesion: 0.29
Nodes (5): FileHandle, FileLogWriter, ISO8601DateFormatter, UInt64, URL

### Community 97 - "Status Doc Schema"
Cohesion: 0.10
Nodes (15): ArgumentParser, ConfigAutoSet, ConfigGroup, Bool, IPCClient, Int, Int32, IPCRequest (+7 more)

### Community 99 - "Terminal Content View"
Cohesion: 0.24
Nodes (8): CloseConfirmationDialog, CloseTarget, pane, Int, NSAlert, NSWindow, Void, CloseConfirmationDialogTests

### Community 100 - "Close Confirmation Dialog"
Cohesion: 0.18
Nodes (5): SessionCloseFlow, Bool, NSWindow, URL, Error

### Community 101 - "Image Reader"
Cohesion: 0.16
Nodes (11): DefaultDirectoryMenu, URL, Void, SidebarSessionRowMutationGate, SidebarSessionRowView, Bool, CGFloat, Date (+3 more)

### Community 102 - "Session Serializer"
Cohesion: 0.15
Nodes (10): GridItem, CardEntry, KeyView, SessionOverviewGridView, Bool, CGFloat, Int, NSEvent (+2 more)

### Community 103 - "Workspace Keyboard Navigation"
Cohesion: 0.22
Nodes (3): SessionDividerDragController, Bool, Void

### Community 104 - "System Monitor (CPU/RAM)"
Cohesion: 0.14
Nodes (13): Architecture, Build, Concepts, Key Layers, Lifecycle, Logs, Scratch / Temporary Files, Source Layout (+5 more)

### Community 105 - "Check For Updates"
Cohesion: 0.17
Nodes (8): InspectPanelState, Bool, CGFloat, Bool, Date, UUID, WorkspaceSnapshot, InspectPanelStateTests

### Community 106 - "Working Directory Resolver"
Cohesion: 0.18
Nodes (5): EnvironmentBuilder, UUID, PaneHierarchyContext, UUID, EnvironmentBuilderTests

### Community 107 - "App Hero Screenshot (UI)"
Cohesion: 0.24
Nodes (13): Claude Pane (Claude Code v2.1.140), Claude Code Statusline (ctx/model/branch), File Explorer Panel (Files/Diff/Branch), Workspace -> Session -> Pane Hierarchy, New Workspace Action, Session Row (name + branch + git diff), Workspace/Session Sidebar, Bottom Status Bar (CPU/RAM) (+5 more)

### Community 109 - "Status Bar View"
Cohesion: 0.22
Nodes (9): CreateSessionRequest, Bool, CGFloat, Duration, Never, Task, URL, Void (+1 more)

### Community 110 - "SessionCloseFlow"
Cohesion: 0.15
Nodes (13): description, type, properties, commit, since, summary, target, description (+5 more)

### Community 112 - "TianSettings"
Cohesion: 0.24
Nodes (3): URL, WorkspaceCreationFlow, WorkspaceCreationFlowTests

### Community 113 - "Row"
Cohesion: 0.14
Nodes (5): Observation, OSLog, T, WeakBox, Keys

### Community 114 - "AppKit"
Cohesion: 0.05
Nodes (34): CGPoint, First, NSNumber, NSView, NSViewRepresentable, Second, RainbowBorderLayer, RainbowBorderNSView (+26 more)

### Community 115 - "KeyboardLayoutTranslator"
Cohesion: 0.23
Nodes (3): GhosttyConfigLoadOrderTests, URL, GhosttyConfigOverridesTests

### Community 117 - "socklen_t"
Cohesion: 0.29
Nodes (8): sockaddr, sockaddr_un, socklen_t, UnsafePointer, IPCServerTests, connectionFailed, Data, Int

### Community 118 - "AutoSetPrompt"
Cohesion: 0.22
Nodes (8): LocalizedError, CLIError, closeInFlight, connection, general, permissionDenied, processSafety, Int32

### Community 119 - "GitStatusServiceUnifiedDiffTests"
Cohesion: 0.67
Nodes (3): description, type, blocked

### Community 120 - "InspectPanelState"
Cohesion: 0.67
Nodes (3): description, type, date

### Community 121 - "SidebarExpandedContentView"
Cohesion: 0.19
Nodes (9): SessionContentView, Bool, CGFloat, CGSize, SessionHeaderView, CGFloat, SplitTreeView, Bool (+1 more)

### Community 122 - "SidebarSessionRowView"
Cohesion: 0.29
Nodes (10): items, additionalProperties, required, type, items, items, shipped, description (+2 more)

### Community 123 - "items"
Cohesion: 0.39
Nodes (3): AppMetrics, Int, UInt64

### Community 124 - "EnvironmentBuilderTests"
Cohesion: 0.15
Nodes (15): Badge, local, localAndOrigin, origin, BranchEntry.Kind, BranchListViewModel, BranchRow, Direction (+7 more)

### Community 125 - "WorktreeKindTests"
Cohesion: 0.17
Nodes (11): CacheEntry, CacheResult, hit, miss, DetectionCache, Date, Sendable, String (+3 more)

### Community 127 - "PollingRefresher"
Cohesion: 0.67
Nodes (3): description, type, done

### Community 129 - "WorkspaceWindowContent"
Cohesion: 0.67
Nodes (3): description, type, link

### Community 131 - "os"
Cohesion: 0.80
Nodes (4): assert_call_exact(), assert_no_call(), run_hook(), tian-hook-log-test.sh script

### Community 132 - "MarkdownCopyButton"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 133 - "Response"
Cohesion: 0.42
Nodes (7): emit_block(), err(), log_run(), need_val(), implement.sh script, log(), usage()

### Community 134 - "Response"
Cohesion: 0.16
Nodes (7): PaneKind, claude, terminal, PaneNode, RemoteSpawnSpec, PaneSpawner, RestoreCommandPaneViewModelTests

### Community 135 - "WorkspaceCreationFlowTests"
Cohesion: 0.33
Nodes (7): MarkdownCopyButton, MarkdownDiffToggleButton, ReaderCloseButton, CGFloat, Never, Task, Void

### Community 136 - "MockWorkspaceProvider"
Cohesion: 0.18
Nodes (9): Bool, Duration, Never, Task, UInt32, UInt64, Void, SystemMonitor (+1 more)

### Community 137 - "status.schema"
Cohesion: 0.25
Nodes (7): Response, cancel, skipTeardown, SkipTeardownConfirmationDialog, Int, NSWindow, Void

### Community 138 - "BusyDotView"
Cohesion: 0.25
Nodes (7): Response, cancel, closeOnly, removeWorktreeAndClose, NSWindow, Void, WorktreeCloseDialog

### Community 139 - ".stopPreventsFurtherCallbacks"
Cohesion: 0.50
Nodes (4): PollTimeoutError, pollUntil(), Duration, MainActor

### Community 140 - "blockingAwait"
Cohesion: 0.14
Nodes (6): Darwin, os, BranchDeleteOutcome, deleted, keptUnmerged, notFound

### Community 141 - ".makeHarness"
Cohesion: 0.15
Nodes (4): InspectTabState, Bool, InspectTab, InspectTabStateTests

### Community 142 - "AppMetrics"
Cohesion: 0.25
Nodes (7): How to read the output, Improvement catalog (map flags → fixes), Input, Litmus test to report, Run, session-audit — audit a tian orchestrator session, What to produce

### Community 143 - "InspectPanelFileRow"
Cohesion: 0.21
Nodes (8): NSAlert, ConfirmAlert, QuitConfirmationDialog, Bool, Int, NSAlert, NSWindow, Void

### Community 144 - "Response"
Cohesion: 0.47
Nodes (3): ImageFileType, Bool, Set

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
Cohesion: 0.12
Nodes (13): Binding, SessionOverviewCardView, Bool, Void, WorkspaceChip, CreateWorkspaceView, Field, directory (+5 more)

### Community 150 - "RefreshSchedulerTests"
Cohesion: 0.32
Nodes (6): InspectPanelFileRow, Spacing, Bool, CGFloat, Int, Void

### Community 151 - "resolve_from_runlog"
Cohesion: 0.29
Nodes (6): Response, cancel, forceRemove, NSWindow, Void, WorktreeForceRemoveDialog

### Community 152 - ".updateSurfaceSize"
Cohesion: 0.40
Nodes (3): blockingAwait(), escaping, T

### Community 153 - "PaneState"
Cohesion: 0.29
Nodes (6): ShellReadinessWaiter, ShellReadyReason, osc7, timeout, TimeInterval, UUID

### Community 154 - "PaneState"
Cohesion: 0.17
Nodes (9): RemoteInspectFileScanner, RemoteScanError, commandFailed, Data, Duration, Int32, URL, Data (+1 more)

### Community 157 - "DebugOverlayView"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 158 - "SessionSplitNavigation"
Cohesion: 0.39
Nodes (6): SessionSplitNavigation, CGRect, CGSize, PaneNode, UUID, Target

### Community 159 - "GitRepoWatcherBranchGraphTests"
Cohesion: 0.11
Nodes (17): KeyAction, closeWorkspace, cycleFocusArea, focusSidebar, goToSession, newSession, newWorkspace, nextSession (+9 more)

### Community 160 - "SidebarWorkspaceHeaderView"
Cohesion: 0.40
Nodes (5): Direction, down, left, right, up

### Community 161 - "PollingRefresher"
Cohesion: 0.27
Nodes (6): PollingRefresher, Duration, MainActor, Never, Task, Void

### Community 162 - "CheckForUpdatesView"
Cohesion: 0.17
Nodes (9): Commands, ObservableObject, Sparkle, CheckForUpdatesView, CheckForUpdatesViewModel, SPUUpdater, SPUUpdater, WorkspaceCommands (+1 more)

### Community 164 - "WorktreeConfig"
Cohesion: 0.36
Nodes (4): NSLayoutConstraint, CGFloat, NSWindow, TrafficLightAligner

### Community 166 - ".startClaude"
Cohesion: 0.15
Nodes (6): SessionGitContext, ForegroundProcessSummary, Bool, Int32, URL, UUID

### Community 167 - "AppMetrics"
Cohesion: 0.05
Nodes (23): SwiftUI, SettingsView, InspectPanelRail, CGFloat, Void, InspectPanelResizeHandle, CGFloat, PaneExitOverlay (+15 more)

### Community 168 - "NSView"
Cohesion: 0.60
Nodes (3): OverviewKeyboardResponder, Context, KeyView

### Community 169 - "NSRange"
Cohesion: 0.50
Nodes (4): IPCTestError, socketCreationFailed, writeFailed, Int32

### Community 170 - "handleListResponse"
Cohesion: 0.29
Nodes (4): SessionOverviewSort, SessionOverviewSortMode, defaultOrder, sessionState

### Community 171 - "resolve_from_runlog"
Cohesion: 0.67
Nodes (3): description, type, item

### Community 172 - "DebugOverlayView"
Cohesion: 0.67
Nodes (3): title, description, type

### Community 173 - "EventCoalescerTests"
Cohesion: 0.09
Nodes (16): WorktreeError, baseWithExisting, branchAlreadyExists, closeInFlight, configParseError, gitError, invalidBaseRef, notAGitRepo (+8 more)

### Community 174 - ".unifiedDiff"
Cohesion: 0.33
Nodes (4): InspectPanelTabRow, Bool, CGFloat, InspectTab

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

### Community 184 - ".reorderDestinationIndex"
Cohesion: 0.47
Nodes (3): HtmlFileType, Bool, Set

### Community 186 - "filter_zombies"
Cohesion: 0.83
Nodes (3): tian-bash-integration.bash script, _tian_fix_path(), _tian_install_claude_wrapper()

### Community 187 - ".makeEmpty"
Cohesion: 0.33
Nodes (5): SidebarWorkspaceHeaderView, Bool, URL, Void, WorkspaceDropIndicator

### Community 188 - "ConfirmAlert"
Cohesion: 0.13
Nodes (6): AppKit, Bool, CGRect, WindowFrame, DirectoryPicker, URL

### Community 192 - "BusyDotView"
Cohesion: 0.08
Nodes (19): MarkdownContent, Color, BranchCommitRow, Bool, CGFloat, BranchGraphCanvas, InspectBranchBody, Bool (+11 more)

### Community 193 - "OverviewGridNavigation"
Cohesion: 0.20
Nodes (4): RemoteCommandBuilder, ShellQuoting, SSHMultiplexing, RemoteCommandBuilderTests

### Community 195 - "PRState"
Cohesion: 0.12
Nodes (8): WorkspaceProviding, Bool, UUID, WorktreeCreateResult, Set, T, URL, UUID

### Community 196 - "ImageFileType"
Cohesion: 0.40
Nodes (3): MarkdownFileType, Bool, Set

### Community 200 - "CLIError+IPC.swift"
Cohesion: 0.80
Nodes (4): assert_call(), assert_no_call(), run_hook(), tian-hook-activity-test.sh script

### Community 203 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.83
Nodes (3): log_raw_payload(), run_tian(), tian-hook-activity.sh script

### Community 214 - "T"
Cohesion: 0.09
Nodes (25): S, DiffBinaryPlaceholderRow, DiffFileHeaderRow, DiffHunkHeaderRow, DiffLineRow, DiffTruncatedRow, Bool, CGFloat (+17 more)

### Community 229 - "ADR 0002: binary scope, orchestration in skill"
Cohesion: 0.20
Nodes (8): InspectFileScanner, ScannerError, decodeFailed, gitFailed, Data, Int32, URL, Void

### Community 231 - "ADR 0004: flatten hierarchy to Workspace-Session"
Cohesion: 0.30
Nodes (5): Bool, UserDefaults, TianSettings, UserDefaults, TianSettingsTests

### Community 242 - ".insertionSlot"
Cohesion: 0.16
Nodes (3): CGFloat, Int, WorkspaceReorderGeometry

### Community 244 - "CharacterChord"
Cohesion: 0.35
Nodes (7): CharacterChord, KeyBinding, KeyBindingRegistry, KeyCodeChord, NSEvent, UInt16, UInt

### Community 245 - "Row"
Cohesion: 0.20
Nodes (10): InspectDiffBody, Row, binary, divider, fileHeader, hunkHeader, line, truncated (+2 more)

### Community 246 - ".makeHarness"
Cohesion: 0.29
Nodes (5): Harness, Int, NSView, NSWindow, TerminalSurfaceViewFocusTests

### Community 247 - ".continueCreation"
Cohesion: 0.23
Nodes (6): CopyRule, ClosedRange, TimeInterval, WorktreeConfig, Bool, Int

### Community 248 - ".unifiedDiff"
Cohesion: 0.27
Nodes (5): Carbon.HIToolbox, KeyboardLayoutTranslator, Data, UInt16, UInt32

### Community 249 - ".write"
Cohesion: 0.20
Nodes (5): App, Scene, TianApp, GhosttyConfigOverrides, URL

### Community 250 - ".resolve"
Cohesion: 0.24
Nodes (3): URL, WorkingDirectoryResolver, WorkingDirectoryResolverTests

### Community 251 - "Git-watch redesign — implementation plan"
Cohesion: 0.20
Nodes (9): Current shape (what we're replacing), Git-watch redesign — implementation plan, Orchestration notes, Phase 0 — quick mitigations (ship immediately, survive the refactor), Phase 1 — `GitMonitor` skeleton + global concurrency + subscription (A, foundation), Phase 2 — split the signal: refs watcher vs working-tree watcher (B), Phase 3 — visible-or-busy gating of the working-tree watcher (C), Phase 4 — `SessionGitContext` → thin adapter + detection cache (+1 more)

### Community 253 - "NSRange"
Cohesion: 0.25
Nodes (4): NSAttributedString, NSRange, NSRangePointer, NSRect

### Community 254 - "PaneState"
Cohesion: 0.22
Nodes (8): Kind, agent, bash, other, teammate, Source, lifecycle, snapshot

### Community 256 - "ChangeBadgeView"
Cohesion: 0.33
Nodes (5): ChangeBadgeView, Int, Never, Task, Void

### Community 257 - "ClaudeEventOrigin"
Cohesion: 0.38
Nodes (4): ClaudeEventOrigin, agent, main, ClaudeEventOriginTests

### Community 260 - "ProcessClaudeInvoker"
Cohesion: 0.40
Nodes (3): ClaudeInvoker, ProcessClaudeInvoker, URL

### Community 261 - "GitFileStatus"
Cohesion: 0.33
Nodes (6): GitFileStatus, added, deleted, modified, renamed, unmerged

### Community 264 - "OptionAsAltSetting"
Cohesion: 0.33
Nodes (6): OptionAsAltSetting, alt, `default`, left, right, unicode

### Community 265 - "DebugOverlayView"
Cohesion: 0.33
Nodes (3): DebugOverlayView, LabeledMetric, Timer

### Community 267 - "InspectPanelStatusStrip"
Cohesion: 0.40
Nodes (4): InspectPanelStatusStrip, InspectTab, CGFloat, InspectTab

### Community 268 - "GitRepoWatcher.swift"
Cohesion: 0.50
Nodes (3): WatchScope, refs, workingTree

### Community 272 - "Kind"
Cohesion: 0.67
Nodes (3): Kind, local, remote

## Knowledge Gaps
- **458 isolated node(s):** `Current shape (what we're replacing)`, `Phase 0 — quick mitigations (ship immediately, survive the refactor)`, `Phase 1 — `GitMonitor` skeleton + global concurrency + subscription (A, foundation)`, `Phase 2 — split the signal: refs watcher vs working-tree watcher (B)`, `Phase 3 — visible-or-busy gating of the working-tree watcher (C)` (+453 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **81 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `Git Types` to `IPC Command Handling`, `Terminal Surface Input`, `Session Git & PR Status`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Sidebar Container`, `Worktree Orchestrator`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Workspace Collection`, `Refresh Scheduling & Coalescing`, `Off-Main Process Runner`, `Decision Record Schema`, `Session State Fixtures`, `Worktree Service Tests`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Error Types`, `Pane Status Manager`, `Session Git Context Tests`, `Sidebar Drag Reorder`, `Session Migration Encoding Tests`, `Graphify Pipeline Skill`, `Session Divider Drag`, `Framework Imports`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Working Tree Watcher`, `Branch Graph Rendering`, `Inspect File Scanner`, `CLI Output Formatting`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `Ghostty Terminal Surface`, `Branch List Tests`, `IPC Client CLI`, `Create Session View`, `IPC Message Protocol`, `Session Split Navigation`, `Fuzzy Match`, `Worktree Setup Progress`, `Background Activity Sync`, `Pane Node Tree`, `Create Session Flow Tests`, `IPC Env Encoding`, `Pane Status Aggregation Tests`, `Session Restorer`, `Session Restorer Tests`, `Quit Flow Coordinator`, `IPC Server Socket`, `Key Binding Registry`, `App Delegate Lifecycle`, `File Log Writer`, `Commit Graph Tests`, `IPC Message Tests`, `Skill Installer`, `Branch List ViewModel`, `Key Chord Model`, `Process Detector`, `Status Doc Schema`, `Image Reader`, `Session Serializer`, `Check For Updates`, `Working Directory Resolver`, `Shipped Items Schema`, `Status Bar View`, `TianSettings`, `KeyboardLayoutTranslator`, `socklen_t`, `AutoSetPrompt`, `SidebarExpandedContentView`, `items`, `EnvironmentBuilderTests`, `SessionSplitNavigation`, `Response`, `BusyDotView`, `.makeHarness`, `Response`, `InlineRenameView`, `os`, `RefreshSchedulerTests`, `resolve_from_runlog`, `PaneState`, `.fromIPCError`, `.startClaude`, `AppMetrics`, `handleListResponse`, `EventCoalescerTests`, `.unifiedDiff`, `.from`, `.reorderDestinationIndex`, `ConfirmAlert`, `BusyDotView`, `OverviewGridNavigation`, `PRState`, `ImageFileType`, `T`, `ADR 0002: binary scope, orchestration in skill`, `ADR 0004: flatten hierarchy to Workspace-Session`, `CharacterChord`, `Row`, `.continueCreation`, `.unifiedDiff`, `.write`, `.resolve`, `PaneState`, `ClaudeEventOrigin`, `ProcessClaudeInvoker`, `GitFileStatus`, `.makeEmpty`, `.claudePreviewText`, `OptionAsAltSetting`, `DebugOverlayView`, `InspectPanelStatusStrip`, `Kind`?**
  _High betweenness centrality (0.453) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Harness Utilities` to `IPC Command Handling`, `Split Layout & Navigation`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Command Logger`, `Off-Main Process Runner`, `Session State Fixtures`, `Ghostty App Core`, `Pane Status Manager`, `Session Divider Drag`, `Markdown Reader`, `Worktree Config Parser`, `Working Tree Watcher`, `Branch Graph Rendering`, `Inspect File Scanner`, `CLI Output Formatting`, `Markdown Diff Segments`, `Ghostty Terminal Surface`, `IPC Message Protocol`, `Worktree Setup Progress`, `Pane Node Tree`, `Create Session Flow Tests`, `Pane Status Aggregation Tests`, `Session State Registry`, `Session Restorer Tests`, `Quit Flow Coordinator`, `Key Binding Registry`, `App Delegate Lifecycle`, `Commit Graph Tests`, `IPC Message Tests`, `Remote Command Builder`, `Branch List ViewModel`, `Branch List Service`, `Process Detector`, `Status Doc Schema`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `TianSettings`, `Row`, `AutoSetPrompt`, `EnvironmentBuilderTests`, `WorktreeKindTests`, `SessionSplitNavigation`, `Response`, `.stopPreventsFurtherCallbacks`, `blockingAwait`, `Response`, `BranchListService`, `.updateSurfaceSize`, `PaneState`, `PaneState`, `PollingRefresher`, `.fromIPCError`, `.startClaude`, `handleListResponse`, `EventCoalescerTests`, `.reorderDestinationIndex`, `ConfirmAlert`, `OverviewGridNavigation`, `PRState`, `ImageFileType`, `MarkdownFileType`, `.continueCreation`, `.write`, `.resolve`, `PaneState`, `CoreGraphics`, `ProcessClaudeInvoker`, `GitRepoWatcher.swift`?**
  _High betweenness centrality (0.119) - this node is a cross-community bridge._
- **Why does `Session` connect `Session Git & PR Status` to `IPC Command Handling`, `implement`, `Response`, `.claudePreviewText`, `Git Repo Watcher`, `Sidebar Container`, `Split Tree Model`, `.applyRemoteChannel`, `Inspect File Tree Scanning`, `Persistence State Models`, `os`, `Worktree Service Tests`, `SessionSplitNavigation`, `Inspect File Tree ViewModel`, `Workspace Reorder Logic`, `.fromIPCError`, `.startClaude`, `Sidebar Drag Reorder`, `Session Audit Analyzer`, `Git Types`, `CLI Output Formatting`, `Ghostty Terminal Surface`, `Worktree Setup Progress`, `PRState`, `InspectPanelStatusStrip`, `Session Restorer`, `Session Restorer Tests`, `Quit Flow Coordinator`, `Close Confirmation Dialog`, `Image Reader`, `Session Serializer`, `Workspace Keyboard Navigation`, `SidebarExpandedContentView`, `.makeSession`?**
  _High betweenness centrality (0.055) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `String` (e.g. with `.run()` and `.resolveRepoRoot()`) actually correct?**
  _`String` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 124 inferred relationships involving `PaneStatusManager` (e.g. with `.fireDoneIfStillIdle()` and `.handlePaneList()`) actually correct?**
  _`PaneStatusManager` has 124 INFERRED edges - model-reasoned connections that need verification._
- **Are the 62 inferred relationships involving `Session` (e.g. with `.buildWorkspaceCollection()` and `SessionReaderState`) actually correct?**
  _`Session` has 62 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Current shape (what we're replacing)`, `Phase 0 — quick mitigations (ship immediately, survive the refactor)`, `Phase 1 — `GitMonitor` skeleton + global concurrency + subscription (A, foundation)` to the rest of the system?**
  _479 weakly-connected nodes found - possible documentation gaps or missing edges._