# Graph Report - git-watch-redesign-adr  (2026-07-16)

## Corpus Check
- 346 files · ~368,741 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4725 nodes · 12511 edges · 261 communities (184 shown, 77 thin omitted)
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 1848 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9282ce63`
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
- CLIError+IPC.swift
- .resolve
- Git-watch redesign — implementation plan
- DockToggleDuringDragTests.swift
- async
- Date
- Duration
- ChangeBadgeView
- ClaudeEventOrigin
- Swift Argument Parser
- TOMLKit
- tian-hook-prompt.sh

## God Nodes (most connected - your core abstractions)
1. `String` - 605 edges
2. `Foundation` - 183 edges
3. `PaneStatusManager` - 173 edges
4. `Session` - 156 edges
5. `IPCCommandHandler` - 114 edges
6. `WorkspaceCollection` - 114 edges
7. `View` - 110 edges
8. `PaneViewModel` - 95 edges
9. `Workspace` - 95 edges
10. `Testing` - 86 edges

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

## Communities (261 total, 77 thin omitted)

### Community 0 - "IPC Command Handling"
Cohesion: 0.06
Nodes (24): ClaudeSessionNotifier, Bool, ClaudeSessionState, Duration, UUID, IPCCommandHandler, Bool, ClaudeSessionState (+16 more)

### Community 1 - "Terminal Surface Input"
Cohesion: 0.25
Nodes (12): GitFileDiff, InspectDiffViewModel, Bool, Duration, Never, Set, Task, Void (+4 more)

### Community 2 - "Session Git & PR Status"
Cohesion: 0.07
Nodes (10): Session, CGSize, ClaudeSessionState, Date, Int, Void, CustomLaunchCommandTests, RetryClaudeSpawnTests (+2 more)

### Community 3 - "Split Layout & Navigation"
Cohesion: 0.07
Nodes (19): DividerInfo, SplitLayout, SplitLayoutResult, CGFloat, CGRect, PaneNode, SplitDirection, UUID (+11 more)

### Community 4 - "Session State Migration"
Cohesion: 0.15
Nodes (13): Migration, root, SessionStateMigrator, Any, Bool, session, SessionMigrationV3ToV4Tests, SessionMigrationV6ToV7Tests (+5 more)

### Community 5 - "CLI Command Router"
Cohesion: 0.07
Nodes (40): ParsableCommand, ActivityBegin, ActivityClear, ActivityEnd, ActivityGroup, ActivityReconcile, ActivityResetLifecycle, ActivitySync (+32 more)

### Community 6 - "Git Repo Watcher"
Cohesion: 0.10
Nodes (8): HierarchicalEntry, SessionCollection, Bool, Int, URL, UUID, SessionCollectionStressTests, SessionCollectionTests

### Community 7 - "Session Model"
Cohesion: 0.11
Nodes (12): BranchEntry, BranchListProviding, BranchListServiceAdapter, Kind, local, remote, Bool, Date (+4 more)

### Community 8 - "Session Collection"
Cohesion: 0.09
Nodes (42): bash_commands(), buckets(), child_branch(), child_hygiene(), count_tools(), failed_delegate_tasks(), file_path_tools(), filter_zombies() (+34 more)

### Community 9 - "SwiftUI View Components"
Cohesion: 0.08
Nodes (22): CaseIterable, ExpressibleByArgument, IPCError, handleListResponse(), PaneList, SessionList, IPCValue, WorkspaceList (+14 more)

### Community 10 - "Config Auto-Set Runner"
Cohesion: 0.14
Nodes (18): Decodable, AutoSetPayload, ClaudeResultEnvelope, CopyEntry, SetupEntry, Bool, ConfigAutoSetResult, ConfigAutoSetRunner (+10 more)

### Community 11 - "Session Overview Grid"
Cohesion: 0.08
Nodes (18): FileTreeNode, Kind, directory, file, Bool, Int, Kind, InspectFileScanning (+10 more)

### Community 12 - "Sidebar Container"
Cohesion: 0.07
Nodes (26): Accessibility, InspectPanelTabsWiringModifier, InspectPanelWiringModifier, Notification, Notification.Name, SessionOverviewOverlayModifier, SidebarContainerView, SidebarNotificationModifier (+18 more)

### Community 13 - "Worktree Orchestrator"
Cohesion: 0.22
Nodes (5): Any, Void, WorktreeOrchestrator, OrchestratorTestError, WorktreeOrchestratorTests

### Community 14 - "Split Tree Model"
Cohesion: 0.18
Nodes (11): SessionState, Date, Int, makeClaudeSession(), makeWorkspaceState(), SessionRestorerBuildTests, SessionRestorerLoadTests, SessionRestorerValidationTests (+3 more)

### Community 15 - "SSH Remote Execution"
Cohesion: 0.08
Nodes (38): Equatable, Identifiable, Sendable, GitCommit, GitCommitGraph, GitDiffHunk, GitDiffLine, GitDiffSummary (+30 more)

### Community 16 - "Inspect File Tree Scanning"
Cohesion: 0.15
Nodes (5): Bool, WindowFrame, SessionSnapshotWindowGeometryTests, SessionSnapshotTests, SessionSnapshotWorktreePathTests

### Community 17 - "ANSI Stripper"
Cohesion: 0.11
Nodes (11): RemoveResult, lastPane, notFound, removed, SplitTree, Bool, Int, PaneNode (+3 more)

### Community 18 - "Workspace Model"
Cohesion: 0.11
Nodes (9): ANSIStripper, State, csi, escape, escapeIntermediate, normal, osc, oscEscape (+1 more)

### Community 19 - "Persistence State Models"
Cohesion: 0.06
Nodes (23): PaneStatus, T, UInt64, WeakBox, PaneViewModel, Bool, CGSize, ClaudeSessionState (+15 more)

### Community 20 - "Command Logger"
Cohesion: 0.06
Nodes (37): CodingKey, Encodable, CodingKeys, isError, result, structuredOutput, subtype, CodingKeys (+29 more)

### Community 21 - "Workspace Collection"
Cohesion: 0.09
Nodes (7): Bool, Int, Int32, WorktreeService, Int32, WorktreeServiceTests, WorktreeServiceTestsRunner

### Community 22 - "Refresh Scheduling & Coalescing"
Cohesion: 0.08
Nodes (20): ghostty_action_color_change_s, ghostty_action_s, ghostty_app_t, ghostty_clipboard_e, ghostty_config_t, ghostty_target_s, NSPasteboard, Selector (+12 more)

### Community 23 - "Worktree Service"
Cohesion: 0.05
Nodes (42): additionalProperties, description, type, description, type, description, type, description (+34 more)

### Community 24 - "Off-Main Process Runner"
Cohesion: 0.10
Nodes (19): DispatchWorkItem, KillGuard, State, alive, dead, terminating, pid_t, TimeInterval (+11 more)

### Community 25 - "Decision Record Schema"
Cohesion: 0.16
Nodes (13): sockaddr, blockingAwait(), IPCServer, async, Bool, Data, escaping, Int32 (+5 more)

### Community 26 - "Git Status Service"
Cohesion: 0.13
Nodes (8): NSWindowController, NSWindowDelegate, Any, Bool, NSCoder, NSObjectProtocol, NSWindow, WorkspaceWindowController

### Community 27 - "Session State Fixtures"
Cohesion: 0.06
Nodes (20): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+12 more)

### Community 28 - "Worktree Service Tests"
Cohesion: 0.10
Nodes (7): PaneStatusManager, ClaudeSessionState, Duration, Never, Void, PaneStatusManagerTests, UUID

### Community 29 - "Test Harness Utilities"
Cohesion: 0.08
Nodes (3): Foundation, Testing, tian

### Community 30 - "Workspace Reorder Logic"
Cohesion: 0.07
Nodes (6): Bool, Int, UUID, Void, WorkspaceCollection, WorkspaceCollectionTests

### Community 31 - "Inspect File Tree ViewModel"
Cohesion: 0.07
Nodes (12): SessionEmptyStateView, Bool, Date, InspectFileTreeViewModel, URL, UUID, Workspace, WorkspaceSnapshot (+4 more)

### Community 32 - "Pane ViewModel"
Cohesion: 0.05
Nodes (35): Architecture, Build, Concepts, graphify, Keeping the record current (do this without being asked), Key Layers, Lifecycle, Logs (+27 more)

### Community 33 - "Error Types"
Cohesion: 0.15
Nodes (7): ClaudeEventOrigin, agent, main, Bool, Set, UUID, ClaudeEventOriginTests

### Community 34 - "Ghostty App Core"
Cohesion: 0.07
Nodes (33): async, Date, Duration, GitRepoWatcher, Hashable, PollingRefresher, GitMonitor, PRBackoffKey (+25 more)

### Community 35 - "Pane Status Manager"
Cohesion: 0.17
Nodes (15): GitRepoID, PRStatus, URL, CacheEntry, CacheKey, CacheResult, hit, miss (+7 more)

### Community 36 - "Session Git Context Tests"
Cohesion: 0.17
Nodes (9): SessionContentView, Bool, CGFloat, CGSize, SessionHeaderView, CGFloat, SplitTreeView, Bool (+1 more)

### Community 37 - "Sidebar Drag Reorder"
Cohesion: 0.10
Nodes (13): DragGesture, PreferenceKey, SidebarExpandedContentView, SidebarItem, sessionRow, workspaceHeader, CGFloat, CGRect (+5 more)

### Community 39 - "Background Activity Store"
Cohesion: 0.12
Nodes (18): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool, int (+10 more)

### Community 40 - "Graphify Pipeline Skill"
Cohesion: 0.11
Nodes (19): SessionGitContext, Subscription, Bool, GitRepoID, GitRepoStatus, Int, Never, RepoLocation (+11 more)

### Community 41 - "Session Divider Drag"
Cohesion: 0.12
Nodes (13): Binding, SessionOverviewCardView, Bool, Void, WorkspaceChip, CreateWorkspaceView, Field, directory (+5 more)

### Community 42 - "Framework Imports"
Cohesion: 0.09
Nodes (12): ghostty_surface_config_s, Int8, GhosttyTerminalSurface, Optional, Bool, ghostty_input_key_s, ghostty_surface_t, T (+4 more)

### Community 43 - "Markdown Reader"
Cohesion: 0.09
Nodes (20): MarkdownContent, MarkdownUI, DiffColors, MarkdownDiffView, Rendered, Int, DiffOutcome, notInRepo (+12 more)

### Community 44 - "Worktree Config Parser"
Cohesion: 0.15
Nodes (7): table, CopyRule, TimeInterval, URL, WorktreeConfigParser, WorktreeConfigParserTests, TOMLTable

### Community 45 - "Session Audit Analyzer"
Cohesion: 0.06
Nodes (15): BackgroundActivity, Kind, agent, bash, other, teammate, Source, lifecycle (+7 more)

### Community 46 - "Git Types"
Cohesion: 0.07
Nodes (35): CustomStringConvertible, Error, Logger, ScannerError, decodeFailed, Int32, RemoteScanError, Int32 (+27 more)

### Community 48 - "Working Tree Watcher"
Cohesion: 0.14
Nodes (14): DispatchSourceTimer, Box, Bool, DispatchQueue, Duration, FSEventStreamRef, Int, Void (+6 more)

### Community 49 - "Branch Graph Rendering"
Cohesion: 0.29
Nodes (5): FileHandle, FileLogWriter, ISO8601DateFormatter, UInt64, URL

### Community 50 - "Inspect File Scanner"
Cohesion: 0.12
Nodes (8): GitChangedFile, InspectChildEntry, InspectIgnoredEntries, Set, CountingScanner, FixedScanner, InspectFileTreeViewModel, InspectFileTreeViewModelTests

### Community 51 - "CLI Output Formatting"
Cohesion: 0.18
Nodes (7): SessionSerializer, ClaudeSessionState, Data, URL, UUID, SessionSerializerWriteTests, URL

### Community 52 - "Claude Session State"
Cohesion: 0.17
Nodes (10): ProcessCPUMonitor, Bool, ContinuousClock, Duration, Int, Never, Task, UInt64 (+2 more)

### Community 53 - "Remote Connection & Workspace Create"
Cohesion: 0.15
Nodes (3): Date, BranchListViewModelTests, Date

### Community 54 - "Inspect Branch ViewModel"
Cohesion: 0.17
Nodes (7): SessionRestorer, Bool, Data, URL, UUID, SessionRestorerDecodeTests, Int

### Community 55 - "Markdown Diff Segments"
Cohesion: 0.08
Nodes (27): build_manifest(), Handler, iter_json_files(), main(), Every *.json under ROOT (used both for the manifest and the mtime watch)., Map of json path -> mtime, for change detection., Describe what exists so the dashboard can discover docs and ADRs., serve() (+19 more)

### Community 56 - "Ghostty Terminal Surface"
Cohesion: 0.25
Nodes (3): RemoteExecutionRegistry, Bool, RemoteExecutionRegistryTests

### Community 57 - "Branch List Tests"
Cohesion: 0.19
Nodes (5): gitFailed, Data, Counter, InspectFileScannerTests, Int

### Community 58 - "IPC Client CLI"
Cohesion: 0.07
Nodes (10): JSONDecoder, Data, SessionMigrationV4ToV5Tests, SessionMigrationV5ToV6Tests, SessionMigrationV7ToV8Tests, PaneNodeStateEncodingTests, SessionMigrationV1ChainTests, SessionStateMigratorTests (+2 more)

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
Cohesion: 0.15
Nodes (13): BranchGraphDirtyHost, InspectBranchViewModel, SessionGitContext, Bool, Never, Task, Void, BlockingGraphService (+5 more)

### Community 65 - "Session Split Navigation"
Cohesion: 0.15
Nodes (13): Badge, local, localAndOrigin, origin, BranchListViewModel, BranchRow, Direction, down (+5 more)

### Community 69 - "Pane Node Building"
Cohesion: 0.17
Nodes (11): InspectFileScanner, InspectScanResult, InspectScanTruncation, depthCap, entryCap, examinedCap, ScanCancellationFlag, Bool (+3 more)

### Community 70 - "Pane Node Tree"
Cohesion: 0.16
Nodes (4): RemoteConnectionState, RemoteConnection, Bool, RemoteConnectionTests

### Community 71 - "Create Session Flow Tests"
Cohesion: 0.16
Nodes (9): PaneNode, leaf, split, SplitDirection, horizontal, vertical, Bool, Int (+1 more)

### Community 72 - "IPC Env Encoding"
Cohesion: 0.22
Nodes (3): BackgroundActivityBadgeView, Int, BackgroundActivityBadgeTests

### Community 73 - "Pane Status Aggregation Tests"
Cohesion: 0.16
Nodes (4): FuzzyMatch, Result, Int, FuzzyMatchTests

### Community 75 - "Session Restorer"
Cohesion: 0.10
Nodes (15): ClosedRange, SessionDividerClamper, Bool, CGFloat, SessionDividerView, Bool, CGFloat, CGSize (+7 more)

### Community 76 - "Session Restorer Tests"
Cohesion: 0.13
Nodes (21): Codable, PaneLeafState, PaneNode, PaneNodeState, pane, split, PaneSplitState, SessionRecord (+13 more)

### Community 77 - "Worktree Config Execution"
Cohesion: 0.17
Nodes (9): ImageIO, NSImage, ImageDocument, Sendbox, Date, T, ImageReaderView, Bool (+1 more)

### Community 78 - "Quit Flow Coordinator"
Cohesion: 0.11
Nodes (11): Content, image, markdown, SessionReaderState, DefaultDirectoryMenu, URL, Void, ReaderOverlayView (+3 more)

### Community 79 - "Pane Hierarchy Wiring"
Cohesion: 0.11
Nodes (18): A Session = one Claude pane + a toggleable terminal panel, Command reference, Core rules, Delegation orchestrator (bundled script — backs `/tian implement`), Discovery, Driving tian with the `tian` CLI, Gotchas, Long-session hygiene (+10 more)

### Community 80 - "Inspect Tab State"
Cohesion: 0.17
Nodes (11): 1. Settle the tree (graphify churn), 2. (Confirmed) — proceed once the version and a clean tree are both settled., 3. Publish, 4. Update the release record — `docs/pm/status.json`, 5. Verify, Cutting a tian release with `/release`, Escape hatches (env vars, forwarded to publish.sh), Execution: delegate to a subagent (+3 more)

### Community 81 - "IPC Server Socket"
Cohesion: 0.10
Nodes (15): ghostty_input_mods_e, NSMenu, NSSize, NSTextInputClient, NSScreen, ghostty_input_key_s, ghostty_surface_t, Int (+7 more)

### Community 82 - "Key Binding Registry"
Cohesion: 0.09
Nodes (19): SidebarSessionRowMutationGate, SidebarSessionRowView, Bool, CGFloat, Date, URL, UUID, Void (+11 more)

### Community 83 - "Session Content View"
Cohesion: 0.05
Nodes (25): CacheEntry, CacheResult, hit, miss, DetectionCache, Date, Sendable, TimeInterval (+17 more)

### Community 84 - "Branch List Fakes"
Cohesion: 0.29
Nodes (7): KeyView, SidebarKeyboardResponder, Bool, Context, KeyView, NSEvent, Void

### Community 85 - "App Delegate Lifecycle"
Cohesion: 0.14
Nodes (4): ScanRootGuard, Bool, URL, ScanRootGuardTests

### Community 86 - "File Log Writer"
Cohesion: 0.13
Nodes (10): FileBaseline, committed, notInRepo, untracked, GitStatusService, Bool, escaping, Int (+2 more)

### Community 87 - "Window Drag Blocker"
Cohesion: 0.27
Nodes (5): EnvironmentValues, Bool, NSWindow, WindowVisibilityState, WindowVisibilityStateTests

### Community 88 - "Commit Graph Tests"
Cohesion: 0.32
Nodes (5): SkillInstaller, URL, UserDefaults, SkillInstallerTests, URL

### Community 89 - "IPC Message Tests"
Cohesion: 0.05
Nodes (18): Comparable, ClaudeNotificationPolicy, ClaudeNotificationTrigger, done, needsAttention, Bool, ClaudeSessionState, ClaudeSessionState (+10 more)

### Community 90 - "Remote Command Builder"
Cohesion: 0.12
Nodes (15): InspectPanelHeader, Bool, CGFloat, DiffSummary, FilesContext, InspectPanelInfoStrip, Bool, CGFloat (+7 more)

### Community 91 - "Skill Installer"
Cohesion: 0.31
Nodes (4): BranchListService, Int32, Set, BranchListServiceTests

### Community 92 - "Branch List ViewModel"
Cohesion: 0.14
Nodes (6): ProcessDetector, RunningProcessInfo, Bool, Int, UUID, ProcessDetectorTests

### Community 93 - "Branch List Service"
Cohesion: 0.21
Nodes (8): SSHConnection, State, connected, connecting, idle, offline, SSHControlChannel, Bool

### Community 94 - "Key Chord Model"
Cohesion: 0.25
Nodes (4): KeyBindingRegistryPhase3Tests, KeyBindingRegistryTests, NSEvent, UInt16

### Community 95 - "Key Actions"
Cohesion: 0.12
Nodes (16): description, type, description, type, description, type, description, type (+8 more)

### Community 96 - "Process Detector"
Cohesion: 0.17
Nodes (9): Commands, ObservableObject, Sparkle, CheckForUpdatesView, CheckForUpdatesViewModel, SPUUpdater, SPUUpdater, WorkspaceCommands (+1 more)

### Community 97 - "Status Doc Schema"
Cohesion: 0.08
Nodes (18): ArgumentParser, ClaudeInvoker, ProcessClaudeInvoker, URL, ConfigAutoSet, ConfigGroup, Bool, IPCClient (+10 more)

### Community 99 - "Terminal Content View"
Cohesion: 0.22
Nodes (8): CloseConfirmationDialog, CloseTarget, pane, Int, NSAlert, NSWindow, Void, CloseConfirmationDialogTests

### Community 100 - "Close Confirmation Dialog"
Cohesion: 0.20
Nodes (4): RemoteCommandBuilder, ShellQuoting, SSHMultiplexing, RemoteCommandBuilderTests

### Community 101 - "Image Reader"
Cohesion: 0.16
Nodes (5): NSAttributedString, NSRange, NSRangePointer, NSRect, Any

### Community 102 - "Session Serializer"
Cohesion: 0.15
Nodes (10): GridItem, CardEntry, KeyView, SessionOverviewGridView, Bool, CGFloat, Int, NSEvent (+2 more)

### Community 103 - "Workspace Keyboard Navigation"
Cohesion: 0.19
Nodes (6): DockPosition, bottom, right, SessionDividerDragController, Bool, Void

### Community 104 - "System Monitor (CPU/RAM)"
Cohesion: 0.14
Nodes (13): Architecture, Build, Concepts, Key Layers, Lifecycle, Logs, Scratch / Temporary Files, Source Layout (+5 more)

### Community 105 - "Check For Updates"
Cohesion: 0.33
Nodes (4): InspectPanelState, Bool, CGFloat, InspectPanelStateTests

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

### Community 111 - "NotificationManager"
Cohesion: 0.25
Nodes (10): sockaddr_un, socklen_t, IPCServerTests, IPCTestError, connectionFailed, socketCreationFailed, writeFailed, Data (+2 more)

### Community 112 - "TianSettings"
Cohesion: 0.24
Nodes (3): URL, WorkspaceCreationFlow, WorkspaceCreationFlowTests

### Community 113 - "Row"
Cohesion: 0.21
Nodes (8): RestoreMetrics, RestoreResult, Source, backup, primary, Bool, Int, SessionRestorerMetricsTests

### Community 114 - "AppKit"
Cohesion: 0.05
Nodes (34): CGPoint, First, NSNumber, NSView, NSViewRepresentable, Second, RainbowBorderLayer, RainbowBorderNSView (+26 more)

### Community 115 - "KeyboardLayoutTranslator"
Cohesion: 0.23
Nodes (3): GhosttyConfigLoadOrderTests, URL, GhosttyConfigOverridesTests

### Community 116 - "implement-log"
Cohesion: 0.30
Nodes (5): Bool, UserDefaults, TianSettings, UserDefaults, TianSettingsTests

### Community 117 - "socklen_t"
Cohesion: 0.16
Nodes (3): CGFloat, Int, WorkspaceReorderGeometry

### Community 118 - "AutoSetPrompt"
Cohesion: 0.22
Nodes (8): LocalizedError, CLIError, closeInFlight, connection, general, permissionDenied, processSafety, Int32

### Community 119 - "GitStatusServiceUnifiedDiffTests"
Cohesion: 0.67
Nodes (3): description, type, blocked

### Community 120 - "InspectPanelState"
Cohesion: 0.23
Nodes (5): RemoteInspectFileScanner, commandFailed, Data, Duration, URL

### Community 121 - "SidebarExpandedContentView"
Cohesion: 0.04
Nodes (28): Observation, SwiftUI, Keys, BranchEntry.Kind, InspectPanelRail, CGFloat, Void, InspectPanelResizeHandle (+20 more)

### Community 122 - "SidebarSessionRowView"
Cohesion: 0.29
Nodes (10): items, additionalProperties, required, type, items, items, shipped, description (+2 more)

### Community 124 - "EnvironmentBuilderTests"
Cohesion: 0.29
Nodes (5): Harness, Int, NSView, NSWindow, TerminalSurfaceViewFocusTests

### Community 125 - "WorktreeKindTests"
Cohesion: 0.20
Nodes (4): ReaderFileSource, RemoteReaderFileSource, Data, Date

### Community 127 - "PollingRefresher"
Cohesion: 0.67
Nodes (3): description, type, done

### Community 128 - ".move"
Cohesion: 0.20
Nodes (5): App, Scene, TianApp, GhosttyConfigOverrides, URL

### Community 129 - "WorkspaceWindowContent"
Cohesion: 0.67
Nodes (3): description, type, link

### Community 130 - "implement"
Cohesion: 0.08
Nodes (17): SessionCloseFlow, Bool, NSWindow, URL, LayoutNode, pane, split, ClosedRange (+9 more)

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
Cohesion: 0.14
Nodes (6): PaneKind, claude, terminal, RemoteSpawnSpec, PaneSpawner, PaneViewModelRealizeSurfaceTests

### Community 136 - "MockWorkspaceProvider"
Cohesion: 0.17
Nodes (10): Snapshot, Bool, Duration, Never, Task, UInt32, UInt64, Void (+2 more)

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
Cohesion: 0.39
Nodes (3): AppMetrics, Int, UInt64

### Community 141 - ".makeHarness"
Cohesion: 0.08
Nodes (14): InspectTabState, Bool, InspectTab, InspectDiffBody, Row, binary, divider, fileHeader (+6 more)

### Community 142 - "AppMetrics"
Cohesion: 0.25
Nodes (7): How to read the output, Improvement catalog (map flags → fixes), Input, Litmus test to report, Run, session-audit — audit a tian orchestrator session, What to produce

### Community 143 - "InspectPanelFileRow"
Cohesion: 0.14
Nodes (10): NSAlert, ConfirmAlert, QuitConfirmationDialog, Bool, Int, NSAlert, NSWindow, Void (+2 more)

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
Cohesion: 0.29
Nodes (6): InspectPanelFileBrowser, InspectPanelTruncationBanner, CGFloat, InspectFileTreeViewModel, Int, Void

### Community 149 - "BranchListService"
Cohesion: 0.15
Nodes (7): BlockingScanner, Counts, GatedScanner, State, Bool, Int, URL

### Community 150 - "RefreshSchedulerTests"
Cohesion: 0.32
Nodes (6): InspectPanelFileRow, Spacing, Bool, CGFloat, Int, Void

### Community 151 - "resolve_from_runlog"
Cohesion: 0.29
Nodes (6): Response, cancel, forceRemove, NSWindow, Void, WorktreeForceRemoveDialog

### Community 153 - "PaneState"
Cohesion: 0.29
Nodes (6): ShellReadinessWaiter, ShellReadyReason, osc7, timeout, TimeInterval, UUID

### Community 155 - "HtmlFileType"
Cohesion: 0.33
Nodes (4): InspectPanelTabRow, Bool, CGFloat, InspectTab

### Community 157 - "DebugOverlayView"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 158 - "SessionSplitNavigation"
Cohesion: 0.14
Nodes (10): SessionGitContext, SessionSplitNavigation, CGRect, CGSize, PaneNode, UUID, Target, Bool (+2 more)

### Community 159 - "GitRepoWatcherBranchGraphTests"
Cohesion: 0.11
Nodes (17): KeyAction, closeWorkspace, cycleFocusArea, focusSidebar, goToSession, newSession, newWorkspace, nextSession (+9 more)

### Community 160 - "SidebarWorkspaceHeaderView"
Cohesion: 0.22
Nodes (5): StatusBarPalette, StatusBarView, CGFloat, UInt64, Value

### Community 161 - "PollingRefresher"
Cohesion: 0.27
Nodes (6): PollingRefresher, Duration, MainActor, Never, Task, Void

### Community 163 - "DebugOverlayView"
Cohesion: 0.43
Nodes (4): NSLayoutConstraint, CGFloat, NSWindow, TrafficLightAligner

### Community 166 - ".startClaude"
Cohesion: 0.29
Nodes (4): SessionOverviewSort, SessionOverviewSortMode, defaultOrder, sessionState

### Community 167 - "AppMetrics"
Cohesion: 0.38
Nodes (3): OverviewGridNavigation, Int, UUID

### Community 168 - "NSView"
Cohesion: 0.40
Nodes (4): InspectPanelStatusStrip, InspectTab, CGFloat, InspectTab

### Community 169 - "NSRange"
Cohesion: 0.12
Nodes (7): CoreServices, Darwin, os, OSLog, WatchScope, refs, workingTree

### Community 170 - "handleListResponse"
Cohesion: 0.33
Nodes (7): MarkdownCopyButton, MarkdownDiffToggleButton, ReaderCloseButton, CGFloat, Never, Task, Void

### Community 171 - "resolve_from_runlog"
Cohesion: 0.67
Nodes (3): description, type, item

### Community 172 - "DebugOverlayView"
Cohesion: 0.67
Nodes (3): title, description, type

### Community 173 - "EventCoalescerTests"
Cohesion: 0.33
Nodes (5): WorktreeKind, linkedWorktree, mainCheckout, notARepo, noWorkingDirectory

### Community 174 - ".unifiedDiff"
Cohesion: 0.33
Nodes (5): PaneState, exited, running, spawnFailed, UInt32

### Community 175 - ".from"
Cohesion: 0.33
Nodes (6): OptionAsAltSetting, alt, `default`, left, right, unicode

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

### Community 188 - "ConfirmAlert"
Cohesion: 0.15
Nodes (5): AppKit, CGRect, WindowFrame, DirectoryPicker, URL

### Community 192 - "BusyDotView"
Cohesion: 0.11
Nodes (14): Color, BranchCommitRow, Bool, CGFloat, BranchGraphCanvas, InspectBranchBody, Bool, CGFloat (+6 more)

### Community 195 - "PRState"
Cohesion: 0.07
Nodes (19): AnyObject, WorkspaceProviding, Bool, UUID, WorktreeCreateResult, WorktreeError, baseWithExisting, branchAlreadyExists (+11 more)

### Community 196 - "ImageFileType"
Cohesion: 0.33
Nodes (3): DebugOverlayView, LabeledMetric, Timer

### Community 200 - "CLIError+IPC.swift"
Cohesion: 0.80
Nodes (4): assert_call(), assert_no_call(), run_hook(), tian-hook-activity-test.sh script

### Community 201 - "MarkdownFileType"
Cohesion: 0.40
Nodes (5): Direction, down, left, right, up

### Community 202 - "InspectPanelStatusStrip"
Cohesion: 0.60
Nodes (3): OverviewKeyboardResponder, Context, KeyView

### Community 203 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.83
Nodes (3): log_raw_payload(), run_tian(), tian-hook-activity.sh script

### Community 214 - "T"
Cohesion: 0.09
Nodes (25): S, DiffBinaryPlaceholderRow, DiffFileHeaderRow, DiffHunkHeaderRow, DiffLineRow, DiffTruncatedRow, Bool, CGFloat (+17 more)

### Community 229 - "ADR 0002: binary scope, orchestration in skill"
Cohesion: 0.33
Nodes (5): SidebarWorkspaceHeaderView, Bool, URL, Void, WorkspaceDropIndicator

### Community 230 - "ADR 0003: accept context duplication, defer token opt"
Cohesion: 0.50
Nodes (3): CommandResult, Data, Int32

### Community 231 - "ADR 0004: flatten hierarchy to Workspace-Session"
Cohesion: 0.50
Nodes (4): BranchDeleteOutcome, deleted, keptUnmerged, notFound

### Community 244 - "CharacterChord"
Cohesion: 0.35
Nodes (7): CharacterChord, KeyBinding, KeyBindingRegistry, KeyCodeChord, NSEvent, UInt16, UInt

### Community 246 - ".makeHarness"
Cohesion: 0.67
Nodes (3): description, type, date

### Community 248 - ".unifiedDiff"
Cohesion: 0.27
Nodes (5): Carbon.HIToolbox, KeyboardLayoutTranslator, Data, UInt16, UInt32

### Community 251 - "Git-watch redesign — implementation plan"
Cohesion: 0.20
Nodes (9): Current shape (what we're replacing), Git-watch redesign — implementation plan, Orchestration notes, Phase 0 — quick mitigations (ship immediately, survive the refactor), Phase 1 — `GitMonitor` skeleton + global concurrency + subscription (A, foundation), Phase 2 — split the signal: refs watcher vs working-tree watcher (B), Phase 3 — visible-or-busy gating of the working-tree watcher (C), Phase 4 — `SessionGitContext` → thin adapter + detection cache (+1 more)

## Knowledge Gaps
- **457 isolated node(s):** `repo`, `$schema`, `$id`, `title`, `description` (+452 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **77 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `Git Types` to `IPC Command Handling`, `Terminal Surface Input`, `Session Git & PR Status`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `Session Model`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Sidebar Container`, `Worktree Orchestrator`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Workspace Collection`, `Refresh Scheduling & Coalescing`, `Off-Main Process Runner`, `Decision Record Schema`, `Session State Fixtures`, `Worktree Service Tests`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Error Types`, `Pane Status Manager`, `Session Git Context Tests`, `Sidebar Drag Reorder`, `Session Migration Encoding Tests`, `Background Activity Store`, `Session Divider Drag`, `Framework Imports`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Working Tree Watcher`, `Branch Graph Rendering`, `Inspect File Scanner`, `CLI Output Formatting`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `Ghostty Terminal Surface`, `Branch List Tests`, `IPC Client CLI`, `Create Session View`, `IPC Message Protocol`, `Session Split Navigation`, `Fuzzy Match`, `Worktree Setup Progress`, `Background Activity Sync`, `Pane Node Building`, `Pane Node Tree`, `Create Session Flow Tests`, `IPC Env Encoding`, `Pane Status Aggregation Tests`, `Session Restorer Tests`, `Worktree Config Execution`, `Quit Flow Coordinator`, `IPC Server Socket`, `Key Binding Registry`, `Session Content View`, `App Delegate Lifecycle`, `File Log Writer`, `Commit Graph Tests`, `IPC Message Tests`, `Remote Command Builder`, `Skill Installer`, `Branch List ViewModel`, `Branch List Service`, `Key Chord Model`, `Status Doc Schema`, `Close Confirmation Dialog`, `Image Reader`, `Session Serializer`, `Workspace Keyboard Navigation`, `Working Directory Resolver`, `Shipped Items Schema`, `Status Bar View`, `NotificationManager`, `TianSettings`, `Row`, `KeyboardLayoutTranslator`, `implement-log`, `AutoSetPrompt`, `InspectPanelState`, `SidebarExpandedContentView`, `items`, `WorktreeKindTests`, `SessionSplitNavigation`, `.move`, `implement`, `Response`, `BusyDotView`, `blockingAwait`, `.makeHarness`, `Response`, `InlineRenameView`, `os`, `BranchListService`, `RefreshSchedulerTests`, `resolve_from_runlog`, `.updateSurfaceSize`, `HtmlFileType`, `SessionSplitNavigation`, `SidebarWorkspaceHeaderView`, `WorktreeConfig`, `.fromIPCError`, `.startClaude`, `NSView`, `EventCoalescerTests`, `.from`, `.reorderDestinationIndex`, `ConfirmAlert`, `BusyDotView`, `PRState`, `ImageFileType`, `T`, `ADR 0003: accept context duplication, defer token opt`, `CharacterChord`, `.unifiedDiff`, `.resolve`?**
  _High betweenness centrality (0.473) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Harness Utilities` to `IPC Command Handling`, `Split Layout & Navigation`, `CLI Command Router`, `Git Repo Watcher`, `Session Model`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Off-Main Process Runner`, `Decision Record Schema`, `Session State Fixtures`, `Inspect File Tree ViewModel`, `Ghostty App Core`, `Pane Status Manager`, `Background Activity Store`, `Graphify Pipeline Skill`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Git Types`, `Branch Graph Rendering`, `CLI Output Formatting`, `Markdown Diff Segments`, `Ghostty Terminal Surface`, `IPC Message Protocol`, `Pane Node Building`, `Pane Node Tree`, `Create Session Flow Tests`, `Pane Status Aggregation Tests`, `Session Restorer Tests`, `Quit Flow Coordinator`, `Key Binding Registry`, `Session Content View`, `App Delegate Lifecycle`, `Commit Graph Tests`, `IPC Message Tests`, `Branch List ViewModel`, `Branch List Service`, `Status Doc Schema`, `Close Confirmation Dialog`, `Workspace Keyboard Navigation`, `Working Directory Resolver`, `TianSettings`, `AutoSetPrompt`, `InspectPanelState`, `SidebarExpandedContentView`, `WorktreeKindTests`, `SessionSplitNavigation`, `.move`, `implement`, `Response`, `WorkspaceCreationFlowTests`, `MockWorkspaceProvider`, `.stopPreventsFurtherCallbacks`, `.makeHarness`, `Response`, `BranchListService`, `PaneState`, `PollingRefresher`, `CheckForUpdatesView`, `.fromIPCError`, `.startClaude`, `AppMetrics`, `NSRange`, `EventCoalescerTests`, `.reorderDestinationIndex`, `.makeEmpty`, `ConfirmAlert`, `PRState`, `ADR 0003: accept context duplication, defer token opt`, `CLIError+IPC.swift`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `PaneViewModel` connect `Persistence State Models` to `IPC Command Handling`, `Session Git & PR Status`, `Split Layout & Navigation`, `implement`, `Response`, `ANSI Stripper`, `PaneState`, `Worktree Service Tests`, `SessionSplitNavigation`, `Inspect File Tree ViewModel`, `Error Types`, `Session Git Context Tests`, `Session Migration Encoding Tests`, `Framework Imports`, `Session Audit Analyzer`, `.unifiedDiff`, `Git Types`, `IPC Server Socket`, `Branch List ViewModel`, `Working Directory Resolver`, `AppKit`, `SidebarExpandedContentView`?**
  _High betweenness centrality (0.058) - this node is a cross-community bridge._
- **Are the 18 inferred relationships involving `String` (e.g. with `.run()` and `.resolveRepoRoot()`) actually correct?**
  _`String` has 18 INFERRED edges - model-reasoned connections that need verification._
- **Are the 124 inferred relationships involving `PaneStatusManager` (e.g. with `.fireDoneIfStillIdle()` and `.handlePaneList()`) actually correct?**
  _`PaneStatusManager` has 124 INFERRED edges - model-reasoned connections that need verification._
- **Are the 63 inferred relationships involving `Session` (e.g. with `.buildWorkspaceCollection()` and `SessionReaderState`) actually correct?**
  _`Session` has 63 INFERRED edges - model-reasoned connections that need verification._
- **What connects `repo`, `Cheap cwd sniff — read only the head of the file.`, `All tool inputs joined — used to detect which worktrees the parent touched.` to the rest of the system?**
  _478 weakly-connected nodes found - possible documentation gaps or missing edges._