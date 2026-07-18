# Graph Report - fix-dead-teammate-busy-floor  (2026-07-17)

## Corpus Check
- 345 files · ~370,216 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4742 nodes · 12573 edges · 282 communities (191 shown, 91 thin omitted)
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 1858 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `a87f6363`
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
- .makeEmpty
- DockToggleDuringDragTests.swift
- RemoteCommandBuilderTests
- CLIError+IPC.swift
- .init
- GitRepoWatcherBranchGraphTests
- Row
- KeyView
- .init
- Git-watch redesign — implementation plan
- RemoteInspectFileScanner
- NSRange
- Swift Argument Parser
- TOMLKit
- PaneKind
- Observation
- .withSockaddr
- .autostartEnvironment
- WorktreeKind
- DockPosition
- OverviewGridNavigation
- PRState
- .run
- FileBaseline
- BranchDeleteOutcome
- .characterIndex
- .init
- Never
- Set
- T
- Task
- UInt64
- UUID
- Void
- tian-hook-prompt.sh

## God Nodes (most connected - your core abstractions)
1. `String` - 630 edges
2. `PaneStatusManager` - 186 edges
3. `Foundation` - 183 edges
4. `Session` - 149 edges
5. `IPCCommandHandler` - 114 edges
6. `WorkspaceCollection` - 114 edges
7. `View` - 110 edges
8. `Workspace` - 95 edges
9. `GitRepoID` - 87 edges
10. `Testing` - 86 edges

## Surprising Connections (you probably didn't know these)
- `CommandContext` --references--> `String`  [EXTRACTED]
  tian-cli/main.swift → tianTests/InspectFileTreeViewModelTests.swift
- `BranchEntry.Kind` --references--> `String`  [EXTRACTED]
  tian/View/CreateSession/BranchListViewModel.swift → tianTests/InspectFileTreeViewModelTests.swift
- `InspectTab` --references--> `String`  [EXTRACTED]
  tian/View/InspectPanel/InspectPanelStatusStrip.swift → tianTests/InspectFileTreeViewModelTests.swift
- `RefreshScheduler` --references--> `Handler`  [EXTRACTED]
  tian/Utilities/RefreshScheduler.swift → docs/pm/dashboard/serve.py
- `AutoSetPayload` --references--> `String`  [EXTRACTED]
  tian-cli/AutoSetPayload.swift → tianTests/InspectFileTreeViewModelTests.swift

## Import Cycles
- None detected.

## Communities (282 total, 91 thin omitted)

### Community 0 - "IPC Command Handling"
Cohesion: 0.06
Nodes (25): ClaudeSessionNotifier, Bool, ClaudeSessionState, Duration, UUID, IPCCommandHandler, Bool, ClaudeSessionState (+17 more)

### Community 1 - "Terminal Surface Input"
Cohesion: 0.25
Nodes (12): GitFileDiff, InspectDiffViewModel, Bool, Duration, Never, Set, Task, Void (+4 more)

### Community 2 - "Session Git & PR Status"
Cohesion: 0.07
Nodes (12): SessionGitContext, Session, Bool, CGSize, ClaudeSessionState, Date, URL, UUID (+4 more)

### Community 3 - "Split Layout & Navigation"
Cohesion: 0.07
Nodes (19): DividerInfo, SplitLayout, SplitLayoutResult, CGFloat, CGRect, PaneNode, SplitDirection, UUID (+11 more)

### Community 4 - "Session State Migration"
Cohesion: 0.09
Nodes (21): Migration, root, MigrationError, futureVersion, migrationFailed, missingVersion, SessionStateMigrator, Any (+13 more)

### Community 5 - "CLI Command Router"
Cohesion: 0.06
Nodes (47): ParsableCommand, IPCError, ActivityBegin, ActivityClear, ActivityEnd, ActivityGroup, ActivityReconcile, ActivityResetLifecycle (+39 more)

### Community 6 - "Git Repo Watcher"
Cohesion: 0.10
Nodes (8): HierarchicalEntry, SessionCollection, Bool, Int, URL, UUID, SessionCollectionStressTests, SessionCollectionTests

### Community 7 - "Session Model"
Cohesion: 0.18
Nodes (5): ghostty_input_mods_e, ghostty_input_key_s, ghostty_surface_t, NSEvent, UInt32

### Community 8 - "Session Collection"
Cohesion: 0.09
Nodes (42): bash_commands(), buckets(), child_branch(), child_hygiene(), count_tools(), failed_delegate_tasks(), file_path_tools(), filter_zombies() (+34 more)

### Community 9 - "SwiftUI View Components"
Cohesion: 0.11
Nodes (18): CaseIterable, ExpressibleByArgument, WorktreeCreateOutput, id, ids, json, OutputFormat, json (+10 more)

### Community 10 - "Config Auto-Set Runner"
Cohesion: 0.11
Nodes (21): Decodable, AutoSetPayload, ClaudeResultEnvelope, CopyEntry, SetupEntry, Bool, ClaudeInvoker, ProcessClaudeInvoker (+13 more)

### Community 11 - "Session Overview Grid"
Cohesion: 0.07
Nodes (21): InspectFileScanning, InspectFileTreeViewModel, InspectScanOutcome, normal, rootTooBroad, truncated, LiveInspectFileScanner, async (+13 more)

### Community 12 - "Sidebar Container"
Cohesion: 0.07
Nodes (26): Accessibility, InspectPanelTabsWiringModifier, InspectPanelWiringModifier, Notification, Notification.Name, SessionOverviewOverlayModifier, SidebarContainerView, SidebarNotificationModifier (+18 more)

### Community 13 - "Worktree Orchestrator"
Cohesion: 0.24
Nodes (5): Any, Void, WorktreeOrchestrator, MockWorkspaceProvider, WorktreeOrchestratorTests

### Community 14 - "Split Tree Model"
Cohesion: 0.15
Nodes (15): RestoreMetrics, Bool, Int, SessionState, Date, Int, makeClaudeSession(), makeWorkspaceState() (+7 more)

### Community 15 - "SSH Remote Execution"
Cohesion: 0.09
Nodes (12): SurfaceCallbackContext, ghostty_surface_t, UUID, GhosttyTerminalSurface, Bool, ghostty_input_key_s, ghostty_surface_t, UInt32 (+4 more)

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
Cohesion: 0.06
Nodes (23): PaneKind, claude, terminal, PaneViewModel, Bool, CGSize, ClaudeSessionState, NSObjectProtocol (+15 more)

### Community 20 - "Command Logger"
Cohesion: 0.09
Nodes (29): CodingKey, Encodable, CodingKeys, isError, result, structuredOutput, subtype, CodingKeys (+21 more)

### Community 21 - "Workspace Collection"
Cohesion: 0.13
Nodes (4): Int, Int32, WorktreeServiceTests, WorktreeServiceTestsRunner

### Community 22 - "Refresh Scheduling & Coalescing"
Cohesion: 0.11
Nodes (15): ghostty_action_color_change_s, ghostty_action_s, ghostty_app_t, ghostty_clipboard_e, ghostty_config_t, ghostty_target_s, NSPasteboard, GhosttyApp (+7 more)

### Community 23 - "Worktree Service"
Cohesion: 0.05
Nodes (42): additionalProperties, description, type, description, type, description, type, description (+34 more)

### Community 24 - "Off-Main Process Runner"
Cohesion: 0.10
Nodes (19): DispatchWorkItem, KillGuard, State, alive, dead, terminating, pid_t, TimeInterval (+11 more)

### Community 25 - "Decision Record Schema"
Cohesion: 0.23
Nodes (8): IPCServer, async, Bool, Data, Int32, IPCResponse, UInt64, Log

### Community 26 - "Git Status Service"
Cohesion: 0.10
Nodes (12): NSWindowController, NSWindowDelegate, Bool, WindowFrame, Any, Bool, NSCoder, NSObjectProtocol (+4 more)

### Community 27 - "Session State Fixtures"
Cohesion: 0.06
Nodes (37): Codable, IPCEnv, IPCError, IPCRequest, IPCResponse, IPCValue, array, bool (+29 more)

### Community 28 - "Worktree Service Tests"
Cohesion: 0.09
Nodes (9): ClaudeEventOrigin, Duration, Never, PaneStatusManager, ClaudeSessionState, Session, PaneStatusManagerTests, UUID (+1 more)

### Community 29 - "Test Harness Utilities"
Cohesion: 0.08
Nodes (3): Foundation, Testing, tian

### Community 30 - "Workspace Reorder Logic"
Cohesion: 0.08
Nodes (5): Bool, UUID, Void, WorkspaceCollection, WorkspaceCollectionTests

### Community 31 - "Inspect File Tree ViewModel"
Cohesion: 0.08
Nodes (8): ForegroundProcessSummary, Int32, InspectFileTreeViewModel, URL, Workspace, DefaultWorkingDirectoryTests, MainActor, WorkspaceTests

### Community 32 - "Pane ViewModel"
Cohesion: 0.05
Nodes (35): Architecture, Build, Concepts, graphify, Keeping the record current (do this without being asked), Key Layers, Lifecycle, Logs (+27 more)

### Community 33 - "Error Types"
Cohesion: 0.13
Nodes (7): PaneViewModel, Set, T, PaneStatus, String, WeakBox, UInt64

### Community 34 - "Ghostty App Core"
Cohesion: 0.26
Nodes (4): InspectChildEntry, InspectIgnoredEntries, Set, CountingScanner

### Community 35 - "Pane Status Manager"
Cohesion: 0.16
Nodes (16): Hashable, GitRepoID, PRStatus, URL, CacheEntry, CacheKey, CacheResult, hit (+8 more)

### Community 36 - "Session Git Context Tests"
Cohesion: 0.12
Nodes (15): InspectPanelHeader, Bool, CGFloat, DiffSummary, FilesContext, InspectPanelInfoStrip, Bool, CGFloat (+7 more)

### Community 37 - "Sidebar Drag Reorder"
Cohesion: 0.09
Nodes (14): DragGesture, PreferenceKey, SidebarExpandedContentView, SidebarItem, sessionRow, workspaceHeader, CGFloat, CGRect (+6 more)

### Community 38 - "Session Migration Encoding Tests"
Cohesion: 0.14
Nodes (6): PaneKind, Bool, BackgroundActivityLifecycleTests, String, TimeInterval, UUID

### Community 39 - "Background Activity Store"
Cohesion: 0.12
Nodes (10): GitRepoWatcher, Bool, FSEventStreamRef, RepoLocation, CallbackTracker, GitRepoWatcherTests, PathRecorder, Bool (+2 more)

### Community 41 - "Session Divider Drag"
Cohesion: 0.33
Nodes (6): SessionSplitNavigation, CGRect, CGSize, PaneNode, UUID, Target

### Community 42 - "Framework Imports"
Cohesion: 0.33
Nodes (4): Int8, Optional, T, UnsafePointer

### Community 43 - "Markdown Reader"
Cohesion: 0.07
Nodes (24): MarkdownContent, MarkdownUI, ReaderFileSource, RemoteReaderFileSource, Data, Date, DiffColors, MarkdownDiffView (+16 more)

### Community 44 - "Worktree Config Parser"
Cohesion: 0.09
Nodes (16): table, CopyRule, LayoutNode, pane, split, ClosedRange, Int, SplitDirection (+8 more)

### Community 45 - "Session Audit Analyzer"
Cohesion: 0.06
Nodes (18): Date, String, Task, BackgroundActivity, Kind, agent, bash, other (+10 more)

### Community 46 - "Git Types"
Cohesion: 0.09
Nodes (26): CustomStringConvertible, Error, Logger, RemoteScanError, Int32, NotificationError, permissionDenied, RestoreError (+18 more)

### Community 48 - "Working Tree Watcher"
Cohesion: 0.14
Nodes (14): DispatchSourceTimer, Box, Bool, DispatchQueue, Duration, FSEventStreamRef, Int, Void (+6 more)

### Community 49 - "Branch Graph Rendering"
Cohesion: 0.09
Nodes (38): Equatable, Identifiable, Sendable, GitCommit, GitCommitGraph, GitDiffHunk, GitDiffLine, GitDiffSummary (+30 more)

### Community 50 - "Inspect File Scanner"
Cohesion: 0.18
Nodes (4): GitChangedFile, FixedScanner, InspectFileTreeViewModel, InspectFileTreeViewModelTests

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
Cohesion: 0.18
Nodes (7): SessionRestorer, Bool, Data, URL, UUID, SessionRestorerDecodeTests, Int

### Community 55 - "Markdown Diff Segments"
Cohesion: 0.12
Nodes (18): build_manifest(), Handler, iter_json_files(), main(), Every *.json under ROOT (used both for the manifest and the mtime watch)., Map of json path -> mtime, for change detection., Describe what exists so the dashboard can discover docs and ADRs., serve() (+10 more)

### Community 56 - "Ghostty Terminal Surface"
Cohesion: 0.12
Nodes (13): SessionContentView, Bool, CGFloat, CGSize, SessionDividerView, Bool, CGFloat, CGSize (+5 more)

### Community 57 - "Branch List Tests"
Cohesion: 0.25
Nodes (3): Counter, InspectFileScannerTests, Int

### Community 58 - "IPC Client CLI"
Cohesion: 0.11
Nodes (12): BranchEntry, BranchListProviding, BranchListServiceAdapter, Kind, local, remote, Bool, Date (+4 more)

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
Cohesion: 0.11
Nodes (17): KeyAction, closeWorkspace, cycleFocusArea, focusSidebar, goToSession, newSession, newWorkspace, nextSession (+9 more)

### Community 65 - "Session Split Navigation"
Cohesion: 0.11
Nodes (16): InspectFileScanner, InspectScanResult, InspectScanTruncation, depthCap, entryCap, examinedCap, ScanCancellationFlag, ScannerError (+8 more)

### Community 67 - "Worktree Setup Progress"
Cohesion: 0.09
Nodes (16): GitMonitor, PRBackoffKey, StatusTarget, repo, SubscriberActivity, Subscription, async, Bool (+8 more)

### Community 68 - "Background Activity Sync"
Cohesion: 0.29
Nodes (6): InspectPanelFileBrowser, InspectPanelTruncationBanner, CGFloat, InspectFileTreeViewModel, Int, Void

### Community 69 - "Pane Node Building"
Cohesion: 0.17
Nodes (11): CGPoint, First, Second, SplitContainerView, SplitDividerView, CGFloat, CGRect, CGSize (+3 more)

### Community 70 - "Pane Node Tree"
Cohesion: 0.14
Nodes (12): DefaultDirectoryMenu, URL, Void, SidebarSessionRowMutationGate, SidebarSessionRowView, Bool, CGFloat, ClaudeSessionState (+4 more)

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
Cohesion: 0.13
Nodes (11): ClosedRange, SessionDividerClamper, Bool, CGFloat, Gesture, SessionLayout, CGFloat, CGRect (+3 more)

### Community 76 - "Session Restorer Tests"
Cohesion: 0.11
Nodes (22): PaneLeafState, PaneNode, PaneNodeState, pane, split, PaneSplitState, SessionRecord, Bool (+14 more)

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
Cohesion: 0.13
Nodes (10): SessionGitContext, Subscription, Bool, Int, Never, Set, Task, URL (+2 more)

### Community 82 - "Key Binding Registry"
Cohesion: 0.18
Nodes (9): Phase, cleanup, removing, setup, SetupProgress, Bool, Int, UUID (+1 more)

### Community 84 - "Branch List Fakes"
Cohesion: 0.20
Nodes (9): NSView, NSPoint, KeyView, SidebarKeyboardResponder, Bool, Context, KeyView, NSEvent (+1 more)

### Community 85 - "App Delegate Lifecycle"
Cohesion: 0.14
Nodes (4): ScanRootGuard, Bool, URL, ScanRootGuardTests

### Community 86 - "File Log Writer"
Cohesion: 0.35
Nodes (7): CharacterChord, KeyBinding, KeyBindingRegistry, KeyCodeChord, NSEvent, UInt16, UInt

### Community 87 - "Window Drag Blocker"
Cohesion: 0.27
Nodes (5): EnvironmentValues, Bool, NSWindow, WindowVisibilityState, WindowVisibilityStateTests

### Community 88 - "Commit Graph Tests"
Cohesion: 0.32
Nodes (5): SkillInstaller, URL, UserDefaults, SkillInstallerTests, URL

### Community 89 - "IPC Message Tests"
Cohesion: 0.24
Nodes (3): Bool, ClaudeSessionState, ClaudeNotificationPolicyTests

### Community 90 - "Remote Command Builder"
Cohesion: 0.40
Nodes (5): Direction, down, left, right, up

### Community 91 - "Skill Installer"
Cohesion: 0.31
Nodes (4): BranchListService, Int32, Set, BranchListServiceTests

### Community 92 - "Branch List ViewModel"
Cohesion: 0.14
Nodes (6): ProcessDetector, RunningProcessInfo, Bool, Int, UUID, ProcessDetectorTests

### Community 93 - "Branch List Service"
Cohesion: 0.19
Nodes (8): Kind, added, removed, unchanged, MarkdownDiffSegment, MarkdownInlineDiff, Int, MarkdownInlineDiffTests

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
Cohesion: 0.07
Nodes (18): ArgumentParser, ConfigAutoSet, ConfigGroup, Bool, IPCClient, Int, Int32, IPCRequest (+10 more)

### Community 99 - "Terminal Content View"
Cohesion: 0.24
Nodes (8): CloseConfirmationDialog, CloseTarget, pane, Int, NSAlert, NSWindow, Void, CloseConfirmationDialogTests

### Community 100 - "Close Confirmation Dialog"
Cohesion: 0.30
Nodes (5): Bool, UserDefaults, TianSettings, UserDefaults, TianSettingsTests

### Community 101 - "Image Reader"
Cohesion: 0.31
Nodes (5): SubscriptionToken, UUID, GitMonitorTests, StringError, MainActor

### Community 102 - "Session Serializer"
Cohesion: 0.15
Nodes (10): GridItem, CardEntry, KeyView, SessionOverviewGridView, Bool, CGFloat, Int, NSEvent (+2 more)

### Community 103 - "Workspace Keyboard Navigation"
Cohesion: 0.15
Nodes (7): DockPosition, bottom, right, SessionDividerDragController, Bool, Void, SessionSplitNavigationTests

### Community 104 - "System Monitor (CPU/RAM)"
Cohesion: 0.14
Nodes (13): Architecture, Build, Concepts, Key Layers, Lifecycle, Logs, Scratch / Temporary Files, Source Layout (+5 more)

### Community 105 - "Check For Updates"
Cohesion: 0.16
Nodes (8): InspectPanelState, Bool, CGFloat, Bool, Date, UUID, WorkspaceSnapshot, InspectPanelStateTests

### Community 106 - "Working Directory Resolver"
Cohesion: 0.18
Nodes (5): EnvironmentBuilder, UUID, PaneHierarchyContext, UUID, EnvironmentBuilderTests

### Community 107 - "App Hero Screenshot (UI)"
Cohesion: 0.24
Nodes (13): Claude Pane (Claude Code v2.1.140), Claude Code Statusline (ctx/model/branch), File Explorer Panel (Files/Diff/Branch), Workspace -> Session -> Pane Hierarchy, New Workspace Action, Session Row (name + branch + git diff), Workspace/Session Sidebar, Bottom Status Bar (CPU/RAM) (+5 more)

### Community 108 - "Shipped Items Schema"
Cohesion: 0.19
Nodes (5): BlockingScanner, GatedScanner, Bool, Int, URL

### Community 109 - "Status Bar View"
Cohesion: 0.22
Nodes (9): CreateSessionRequest, Bool, CGFloat, Duration, Never, Task, URL, Void (+1 more)

### Community 110 - "SessionCloseFlow"
Cohesion: 0.15
Nodes (13): description, type, properties, commit, since, summary, target, description (+5 more)

### Community 111 - "NotificationManager"
Cohesion: 0.08
Nodes (13): ghostty_surface_config_s, NSAttributedString, NSMenu, NSRange, NSRangePointer, NSRect, NSSize, NSTextInputClient (+5 more)

### Community 112 - "TianSettings"
Cohesion: 0.20
Nodes (4): URL, URL, WorkspaceCreationFlow, WorkspaceCreationFlowTests

### Community 113 - "Row"
Cohesion: 0.12
Nodes (3): CoreGraphics, Observation, Keys

### Community 114 - "AppKit"
Cohesion: 0.21
Nodes (9): NSNumber, RainbowBorderLayer, RainbowBorderNSView, Bool, CFTimeInterval, CGFloat, Context, Int (+1 more)

### Community 115 - "KeyboardLayoutTranslator"
Cohesion: 0.12
Nodes (8): App, Scene, TianApp, GhosttyConfigOverrides, URL, GhosttyConfigLoadOrderTests, URL, GhosttyConfigOverridesTests

### Community 117 - "socklen_t"
Cohesion: 0.29
Nodes (8): sockaddr, sockaddr_un, socklen_t, UnsafePointer, IPCServerTests, connectionFailed, Data, Int

### Community 118 - "AutoSetPrompt"
Cohesion: 0.14
Nodes (12): LocalizedError, CLIError, closeInFlight, connection, general, permissionDenied, processSafety, Int32 (+4 more)

### Community 119 - "GitStatusServiceUnifiedDiffTests"
Cohesion: 0.67
Nodes (3): description, type, blocked

### Community 120 - "InspectPanelState"
Cohesion: 0.67
Nodes (3): description, type, date

### Community 121 - "SidebarExpandedContentView"
Cohesion: 0.21
Nodes (9): InspectBranchViewModel, Bool, Never, Task, Void, BlockingGraphService, InspectBranchViewModelTests, CheckedContinuation (+1 more)

### Community 122 - "SidebarSessionRowView"
Cohesion: 0.29
Nodes (10): items, additionalProperties, required, type, items, items, shipped, description (+2 more)

### Community 123 - "items"
Cohesion: 0.39
Nodes (3): AppMetrics, Int, UInt64

### Community 124 - "EnvironmentBuilderTests"
Cohesion: 0.06
Nodes (23): RemoteInspectFileScanner, commandFailed, Data, Duration, URL, RemoteCommandBuilder, ShellQuoting, SSHMultiplexing (+15 more)

### Community 125 - "WorktreeKindTests"
Cohesion: 0.16
Nodes (14): Badge, local, localAndOrigin, origin, BranchEntry.Kind, BranchListViewModel, BranchRow, Direction (+6 more)

### Community 127 - "PollingRefresher"
Cohesion: 0.67
Nodes (3): description, type, done

### Community 129 - "WorkspaceWindowContent"
Cohesion: 0.67
Nodes (3): description, type, link

### Community 130 - "implement"
Cohesion: 0.09
Nodes (13): CoreServices, Darwin, os, OSLog, WatchScope, refs, workingTree, BranchDeleteOutcome (+5 more)

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
Cohesion: 0.18
Nodes (9): CacheEntry, CacheResult, hit, miss, DetectionCache, Date, Sendable, TimeInterval (+1 more)

### Community 135 - "WorkspaceCreationFlowTests"
Cohesion: 0.33
Nodes (7): MarkdownCopyButton, MarkdownDiffToggleButton, ReaderCloseButton, CGFloat, Never, Task, Void

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
Cohesion: 0.13
Nodes (10): FileBaseline, committed, notInRepo, untracked, GitStatusService, Bool, escaping, Int (+2 more)

### Community 141 - ".makeHarness"
Cohesion: 0.17
Nodes (7): SparklineView, CGFloat, StatusBarPalette, StatusBarView, CGFloat, UInt64, Value

### Community 142 - "AppMetrics"
Cohesion: 0.25
Nodes (7): How to read the output, Improvement catalog (map flags → fixes), Input, Litmus test to report, Run, session-audit — audit a tian orchestrator session, What to produce

### Community 143 - "InspectPanelFileRow"
Cohesion: 0.21
Nodes (8): NSAlert, ConfirmAlert, QuitConfirmationDialog, Bool, Int, NSAlert, NSWindow, Void

### Community 144 - "Response"
Cohesion: 0.27
Nodes (5): Carbon.HIToolbox, KeyboardLayoutTranslator, Data, UInt16, UInt32

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
Cohesion: 0.26
Nodes (5): BlockerView, Bool, NSEvent, NSTrackingArea, NSWindow

### Community 150 - "RefreshSchedulerTests"
Cohesion: 0.32
Nodes (6): InspectPanelFileRow, Spacing, Bool, CGFloat, Int, Void

### Community 151 - "resolve_from_runlog"
Cohesion: 0.29
Nodes (6): Response, cancel, forceRemove, NSWindow, Void, WorktreeForceRemoveDialog

### Community 152 - ".updateSurfaceSize"
Cohesion: 0.29
Nodes (7): FileTreeNode, Kind, directory, file, Bool, Int, Kind

### Community 153 - "PaneState"
Cohesion: 0.29
Nodes (6): ShellReadinessWaiter, ShellReadyReason, osc7, timeout, TimeInterval, UUID

### Community 157 - "DebugOverlayView"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 158 - "SessionSplitNavigation"
Cohesion: 0.29
Nodes (5): Harness, Int, NSView, NSWindow, TerminalSurfaceViewFocusTests

### Community 160 - "SidebarWorkspaceHeaderView"
Cohesion: 0.15
Nodes (4): InspectTabState, Bool, InspectTab, InspectTabStateTests

### Community 161 - "PollingRefresher"
Cohesion: 0.27
Nodes (6): PollingRefresher, Duration, MainActor, Never, Task, Void

### Community 162 - "CheckForUpdatesView"
Cohesion: 0.17
Nodes (9): Commands, ObservableObject, Sparkle, CheckForUpdatesView, CheckForUpdatesViewModel, SPUUpdater, SPUUpdater, WorkspaceCommands (+1 more)

### Community 164 - "WorktreeConfig"
Cohesion: 0.43
Nodes (4): NSLayoutConstraint, CGFloat, NSWindow, TrafficLightAligner

### Community 167 - "AppMetrics"
Cohesion: 0.05
Nodes (27): SwiftUI, InspectPanelRail, CGFloat, Void, InspectPanelResizeHandle, CGFloat, InspectPanelStatusStrip, InspectTab (+19 more)

### Community 168 - "NSView"
Cohesion: 0.28
Nodes (4): ClaudeEventOrigin, agent, main, ClaudeEventOriginTests

### Community 169 - "NSRange"
Cohesion: 0.33
Nodes (3): DebugOverlayView, LabeledMetric, Timer

### Community 171 - "resolve_from_runlog"
Cohesion: 0.67
Nodes (3): description, type, item

### Community 172 - "DebugOverlayView"
Cohesion: 0.67
Nodes (3): title, description, type

### Community 173 - "EventCoalescerTests"
Cohesion: 0.06
Nodes (24): WorkspaceProviding, Bool, UUID, WorktreeCreateResult, WorktreeError, baseWithExisting, branchAlreadyExists, closeInFlight (+16 more)

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
Cohesion: 0.19
Nodes (10): AsyncSemaphore, RefreshScheduler, CheckedContinuation, Duration, Int, Key, Never, Task (+2 more)

### Community 186 - "filter_zombies"
Cohesion: 0.83
Nodes (3): tian-bash-integration.bash script, _tian_fix_path(), _tian_install_claude_wrapper()

### Community 187 - ".makeEmpty"
Cohesion: 0.22
Nodes (9): Comparable, ClaudeSessionState, active, busy, failed, idle, inactive, needsAttention (+1 more)

### Community 188 - "ConfirmAlert"
Cohesion: 0.17
Nodes (4): AppKit, CGRect, WindowFrame, DirectoryPicker

### Community 192 - "BusyDotView"
Cohesion: 0.13
Nodes (12): Color, BranchCommitRow, Bool, CGFloat, BranchGraphCanvas, InspectBranchBody, Bool, CGFloat (+4 more)

### Community 193 - "OverviewGridNavigation"
Cohesion: 0.47
Nodes (3): ImageFileType, Bool, Set

### Community 195 - "PRState"
Cohesion: 0.33
Nodes (5): AnyObject, BranchGraphDirtyHost, SessionGitContext, FakeBranchGraphHost, Set

### Community 196 - "ImageFileType"
Cohesion: 0.40
Nodes (3): MarkdownFileType, Bool, Set

### Community 200 - "CLIError+IPC.swift"
Cohesion: 0.80
Nodes (4): assert_call(), assert_no_call(), run_hook(), tian-hook-activity-test.sh script

### Community 201 - "MarkdownFileType"
Cohesion: 0.07
Nodes (8): JSONDecoder, RemoteConnectionState, RemoteConnection, Bool, RemoteConnectionTests, SessionMigrationV4ToV5Tests, SessionMigrationV5ToV6Tests, SessionMigrationV7ToV8Tests

### Community 202 - "InspectPanelStatusStrip"
Cohesion: 0.38
Nodes (5): NSViewRepresentable, Context, NSView, NSWindow, WindowAccessor

### Community 203 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.83
Nodes (3): log_raw_payload(), run_tian(), tian-hook-activity.sh script

### Community 214 - "T"
Cohesion: 0.08
Nodes (30): S, DiffBinaryPlaceholderRow, DiffFileHeaderRow, DiffHunkHeaderRow, DiffLineRow, DiffTruncatedRow, Bool, CGFloat (+22 more)

### Community 244 - "CharacterChord"
Cohesion: 0.29
Nodes (4): SessionOverviewSort, SessionOverviewSortMode, defaultOrder, sessionState

### Community 249 - "CLIError+IPC.swift"
Cohesion: 0.12
Nodes (13): Binding, SessionOverviewCardView, Bool, Void, WorkspaceChip, CreateWorkspaceView, Field, directory (+5 more)

### Community 250 - ".init"
Cohesion: 0.36
Nodes (5): CallbackBox, CFTimeInterval, DispatchQueue, escaping, Void

### Community 252 - "Row"
Cohesion: 0.20
Nodes (10): InspectDiffBody, Row, binary, divider, fileHeader, hunkHeader, line, truncated (+2 more)

### Community 253 - "KeyView"
Cohesion: 0.60
Nodes (3): OverviewKeyboardResponder, Context, KeyView

### Community 254 - ".init"
Cohesion: 0.47
Nodes (3): HtmlFileType, Bool, Set

### Community 255 - "Git-watch redesign — implementation plan"
Cohesion: 0.20
Nodes (9): Current shape (what we're replacing), Git-watch redesign — implementation plan, Orchestration notes, Phase 0 — quick mitigations (ship immediately, survive the refactor), Phase 1 — `GitMonitor` skeleton + global concurrency + subscription (A, foundation), Phase 2 — split the signal: refs watcher vs working-tree watcher (B), Phase 3 — visible-or-busy gating of the working-tree watcher (C), Phase 4 — `SessionGitContext` → thin adapter + detection cache (+1 more)

### Community 256 - "RemoteInspectFileScanner"
Cohesion: 0.33
Nodes (5): ChangeBadgeView, Int, Never, Task, Void

### Community 257 - "NSRange"
Cohesion: 0.47
Nodes (3): Context, NSView, WindowDragBlocker

### Community 260 - "PaneKind"
Cohesion: 0.40
Nodes (4): ClaudeNotificationPolicy, ClaudeNotificationTrigger, done, needsAttention

### Community 262 - ".withSockaddr"
Cohesion: 0.40
Nodes (3): blockingAwait(), escaping, T

### Community 267 - "OverviewGridNavigation"
Cohesion: 0.38
Nodes (3): OverviewGridNavigation, Int, UUID

### Community 269 - ".run"
Cohesion: 0.18
Nodes (5): SessionCloseFlow, Bool, NSWindow, URL, Error

## Knowledge Gaps
- **462 isolated node(s):** `agent`, `teammate`, `bash`, `other`, `lifecycle` (+457 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **91 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `Git Types` to `IPC Command Handling`, `Terminal Surface Input`, `Session Git & PR Status`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `Session Model`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Sidebar Container`, `Worktree Orchestrator`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Workspace Collection`, `Refresh Scheduling & Coalescing`, `Off-Main Process Runner`, `Decision Record Schema`, `Session State Fixtures`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Ghostty App Core`, `Pane Status Manager`, `Session Git Context Tests`, `Sidebar Drag Reorder`, `Background Activity Store`, `Graphify Pipeline Skill`, `Markdown Reader`, `Worktree Config Parser`, `Working Tree Watcher`, `Branch Graph Rendering`, `Inspect File Scanner`, `CLI Output Formatting`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `Ghostty Terminal Surface`, `Branch List Tests`, `IPC Client CLI`, `Create Session View`, `Session Split Navigation`, `Fuzzy Match`, `Worktree Setup Progress`, `Background Activity Sync`, `Pane Node Tree`, `Create Session Flow Tests`, `IPC Env Encoding`, `Pane Status Aggregation Tests`, `Session Restorer Tests`, `Worktree Config Execution`, `Quit Flow Coordinator`, `IPC Server Socket`, `Key Binding Registry`, `Session Content View`, `App Delegate Lifecycle`, `File Log Writer`, `Commit Graph Tests`, `Skill Installer`, `Branch List ViewModel`, `Branch List Service`, `Key Chord Model`, `Process Detector`, `Status Doc Schema`, `Close Confirmation Dialog`, `Image Reader`, `Session Serializer`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `Shipped Items Schema`, `Status Bar View`, `NotificationManager`, `TianSettings`, `KeyboardLayoutTranslator`, `socklen_t`, `AutoSetPrompt`, `SidebarExpandedContentView`, `items`, `EnvironmentBuilderTests`, `WorktreeKindTests`, `SessionSplitNavigation`, `implement`, `Response`, `BusyDotView`, `blockingAwait`, `.makeHarness`, `Response`, `InlineRenameView`, `RefreshSchedulerTests`, `resolve_from_runlog`, `.updateSurfaceSize`, `PaneState`, `SidebarWorkspaceHeaderView`, `.fromIPCError`, `AppMetrics`, `NSView`, `NSRange`, `handleListResponse`, `EventCoalescerTests`, `.unifiedDiff`, `.from`, `.makeEmpty`, `BusyDotView`, `OverviewGridNavigation`, `ImageFileType`, `MarkdownFileType`, `T`, `.insertionSlot`, `CharacterChord`, `RemoteCommandBuilderTests`, `CLIError+IPC.swift`, `.init`, `GitRepoWatcherBranchGraphTests`, `Row`, `.init`, `.autostartEnvironment`, `WorktreeKind`, `PRState`, `FileBaseline`?**
  _High betweenness centrality (0.537) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Harness Utilities` to `IPC Command Handling`, `implement`, `Split Layout & Navigation`, `PaneKind`, `CLI Command Router`, `Response`, `.withSockaddr`, `Session State Migration`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Git Repo Watcher`, `MockWorkspaceProvider`, `OverviewGridNavigation`, `WorktreeKind`, `.stopPreventsFurtherCallbacks`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `BranchListService`, `Split Tree Model`, `.updateSurfaceSize`, `Off-Main Process Runner`, `Git Status Service`, `Session State Fixtures`, `PaneState`, `GitRepoWatcherBranchGraphTests`, `Error Types`, `PollingRefresher`, `Pane Status Manager`, `.fromIPCError`, `NSView`, `Session Divider Drag`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `EventCoalescerTests`, `Branch Graph Rendering`, `CLI Output Formatting`, `Markdown Diff Segments`, `.reorderDestinationIndex`, `IPC Client CLI`, `ConfirmAlert`, `Session Split Navigation`, `OverviewGridNavigation`, `Worktree Setup Progress`, `PRState`, `ImageFileType`, `Create Session Flow Tests`, `MarkdownFileType`, `Pane Status Aggregation Tests`, `Session Restorer Tests`, `Quit Flow Coordinator`, `IPC Server Socket`, `Key Binding Registry`, `App Delegate Lifecycle`, `Commit Graph Tests`, `Branch List ViewModel`, `Branch List Service`, `Process Detector`, `Status Doc Schema`, `Workspace Keyboard Navigation`, `Check For Updates`, `Working Directory Resolver`, `TianSettings`, `Row`, `KeyboardLayoutTranslator`, `CharacterChord`, `Row`, `AutoSetPrompt`, `.init`, `EnvironmentBuilderTests`, `WorktreeKindTests`, `SessionSplitNavigation`?**
  _High betweenness centrality (0.062) - this node is a cross-community bridge._
- **Why does `Session` connect `Session Git & PR Status` to `IPC Command Handling`, `Git Repo Watcher`, `SessionDividerDragController`, `DockPosition`, `Sidebar Container`, `.run`, `Split Tree Model`, `FileBaseline`, `Inspect File Tree Scanning`, `Persistence State Models`, `Worktree Service Tests`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Error Types`, `.fromIPCError`, `Sidebar Drag Reorder`, `Session Divider Drag`, `Session Audit Analyzer`, `Git Types`, `EventCoalescerTests`, `Branch Graph Rendering`, `CLI Output Formatting`, `Ghostty Terminal Surface`, `Pane Node Tree`, `Session Restorer`, `Session Restorer Tests`, `Quit Flow Coordinator`, `Session Serializer`, `Workspace Keyboard Navigation`, `Row`, `CLIError+IPC.swift`, `EnvironmentBuilderTests`?**
  _High betweenness centrality (0.046) - this node is a cross-community bridge._
- **Are the 20 inferred relationships involving `String` (e.g. with `.run()` and `.resolveRepoRoot()`) actually correct?**
  _`String` has 20 INFERRED edges - model-reasoned connections that need verification._
- **Are the 135 inferred relationships involving `PaneStatusManager` (e.g. with `.fireDoneIfStillIdle()` and `.handlePaneList()`) actually correct?**
  _`PaneStatusManager` has 135 INFERRED edges - model-reasoned connections that need verification._
- **Are the 63 inferred relationships involving `Session` (e.g. with `.buildWorkspaceCollection()` and `SessionReaderState`) actually correct?**
  _`Session` has 63 INFERRED edges - model-reasoned connections that need verification._
- **What connects `agent`, `teammate`, `bash` to the rest of the system?**
  _483 weakly-connected nodes found - possible documentation gaps or missing edges._