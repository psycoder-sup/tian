# Graph Report - feat+prompt-hook-filter-injected  (2026-07-08)

## Corpus Check
- 323 files · ~333,739 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4216 nodes · 9324 edges · 836 communities (134 shown, 702 thin omitted)
- Extraction: 84% EXTRACTED · 16% INFERRED · 0% AMBIGUOUS · INFERRED: 1461 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3aa943fd`
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
- DiffFileHeaderRow
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
- TrafficLightAligner
- blockingAwait
- FileTreeNode
- AppMetrics
- InspectPanelFileRow
- Response
- ShellReadyReason
- InlineRenameView
- NSViewRepresentable
- RainbowGlowBorder
- BranchListService
- RefreshSchedulerTests
- resolve_from_runlog
- ContinuousClock
- PaneState
- ForegroundProcessSummary
- HtmlFileType
- ImageFileType
- DebugOverlayView
- InspectPanelTabRow
- ChangeBadgeView
- SidebarWorkspaceHeaderView
- EventCoalescerTests
- ClaudeLaunchBadge
- MarkdownFileType
- InspectPanelStatusStrip
- child_branch
- TerminalSurfaceViewDelegate
- now
- publish
- SessionRestorer
- tian-bash-integration
- InspectPanelFileBrowser
- PaneNodeConversionTests
- implement-logrec
- blocked
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
- build
- build-ghostty
- install
- release
- claude
- tian-hook-pr-refresh
- tian-hook-prompt
- Token reduction benchmark
- FalkorDB export
- Wiki export (crawlable index + articles)
- dev scratch space
- graphify knowledge graph
- NetworkImage
- swift-cmark
- tian-Bridging-Header
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
- extraction-spec.md
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
- Int
- URL
- Bool
- Int
- Int32
- IPCRequest
- IPCResponse
- Bool
- Decoder
- Encoder
- Int
- IPCEnv
- IPCError
- IPCValue
- IPCEnv
- Int
- IPCValue
- Bool
- Int
- UUID
- Bool
- ghostty_surface_t
- NSObjectProtocol
- UInt8
- URL
- UUID
- Bool
- ghostty_input_key_s
- ghostty_surface_t
- T
- UInt32
- UnsafePointer
- Bool
- DispatchQueue
- escaping
- FSEventStreamRef
- Void
- Bool
- escaping
- Int
- Int32
- T
- Bool
- Date
- Int
- URL
- Bool
- Int
- Kind
- Bool
- Never
- Task
- Void
- Bool
- Duration
- Never
- Set
- Task
- Void
- Bool
- Data
- Int32
- Set
- URL
- async
- Bool
- Duration
- Never
- Set
- Task
- URL
- Void
- Bool
- CGFloat
- Bool
- InspectTab
- Data
- Duration
- Int32
- URL
- Bool
- DispatchQueue
- Duration
- FSEventStreamRef
- Int
- Void
- Bool
- Int
- IPCEnv
- IPCRequest
- IPCResponse
- IPCValue
- UUID
- Bool
- Decoder
- Encoder
- Int
- IPCEnv
- IPCError
- IPCValue
- async
- Bool
- Data
- escaping
- Int32
- IPCResponse
- T
- UInt64
- UnsafePointer
- Int
- Bool
- UUID
- Bool
- Date
- Int
- Sendable
- TimeInterval
- Int
- NSEvent
- UInt16
- Data
- UInt16
- UInt32
- Bool
- Date
- TimeInterval
- UUID
- Bool
- Int
- UUID
- UInt32
- Bool
- ClaudeSessionState
- Duration
- Never
- Set
- T
- Task
- UInt64
- UUID
- Void
- Bool
- CGSize
- ClaudeSessionState
- NSObjectProtocol
- PaneNode
- Set
- SplitDirection
- UUID
- Void
- CGRect
- CGSize
- PaneNode
- UUID
- CGFloat
- CGRect
- PaneNode
- SplitDirection
- UUID
- CGFloat
- CGRect
- UUID
- Bool
- Int
- PaneNode
- SplitDirection
- UUID
- Bool
- Int
- UUID
- Bool
- Int
- Bool
- CGRect
- Data
- URL
- UUID
- Bool
- ClaudeSessionState
- Data
- URL
- UUID
- WindowFrame
- Bool
- ClaudeSessionState
- Date
- Decoder
- Encoder
- Int
- UUID
- WindowFrame
- Any
- Bool
- Data
- Int
- Data
- Date
- Bool
- Bool
- Data
- Int32
- Bool
- CGSize
- ClaudeSessionState
- ClosedRange
- Date
- Int
- Int32
- URL
- UUID
- Void
- Bool
- Int
- URL
- UUID
- Void
- Bool
- Void
- Bool
- Duration
- Int
- Never
- Set
- Task
- URL
- UUID
- Void
- Bool
- UserDefaults
- Int
- UInt64
- UInt8
- URL
- Duration
- Key
- Never
- Task
- Value
- Void
- ISO8601DateFormatter
- UInt64
- URL
- Int
- Bool
- Set
- Bool
- Set
- Bool
- Set
- Duration
- MainActor
- Never
- Task
- Void
- CheckedContinuation
- Duration
- Int
- Key
- Never
- Task
- Void
- URL
- UserDefaults
- Duration
- Never
- Task
- UInt32
- UInt64
- Void
- URL
- Int
- NSAlert
- NSWindow
- Void
- Bool
- Date
- Bool
- Field
- Set
- URL
- Void
- URL
- Void
- Date
- T
- Bool
- Void
- Bool
- CGFloat
- Bool
- CGFloat
- Int
- Bool
- CGFloat
- Bool
- Int
- InspectFileTreeViewModel
- Void
- Bool
- CGFloat
- Int
- Void
- Bool
- CGFloat
- Bool
- CGFloat
- InspectTab
- Int
- CGFloat
- Void
- CGFloat
- CGFloat
- InspectTab
- Bool
- CGFloat
- InspectTab
- Bool
- InspectFileTreeViewModel
- InspectTab
- Void
- Int
- Date
- Never
- T
- Task
- Void
- Bool
- Void
- Void
- Bool
- ClaudeSessionState
- UUID
- Bool
- Int
- NSAlert
- NSWindow
- Void
- CGFloat
- Never
- Task
- Void
- Bool
- CGFloat
- Void
- Int
- UUID
- Bool
- CGFloat
- CGSize
- Bool
- CGFloat
- Bool
- CGFloat
- CGSize
- Gesture
- CGFloat
- CGFloat
- CGRect
- CGSize
- Bool
- Void
- Bool
- CGFloat
- Context
- Int
- KeyView
- NSEvent
- UUID
- Void
- Bool
- Void
- CGFloat
- TimeInterval
- CGFloat
- Int
- Never
- Task
- Void
- ClaudeSessionState
- Bool
- Bool
- CGFloat
- CGSize
- Context
- Never
- NSView
- NSWindow
- Task
- Void
- Bool
- CGFloat
- CGRect
- Context
- Gesture
- Int
- KeyView
- NSEvent
- Set
- UUID
- Void
- Bool
- CGFloat
- ClaudeSessionState
- Date
- URL
- UUID
- Void
- Bool
- CGFloat
- Bool
- URL
- Void
- CGFloat
- Int
- CGFloat
- CGRect
- CGSize
- Gesture
- SplitDirection
- UUID
- Bool
- PaneNode
- CGFloat
- CGFloat
- UInt64
- Value
- Bool
- Context
- NSView
- SplitDirection
- UUID
- Any
- Bool
- ghostty_input_key_s
- ghostty_surface_t
- Int
- NSCoder
- NSEvent
- NSTrackingArea
- UInt32
- Bool
- Field
- Void
- Bool
- CGFloat
- Duration
- Never
- Task
- URL
- Void
- Bool
- NSWindow
- URL
- Void
- Int
- NSWindow
- Void
- NSWindow
- Void
- NSWindow
- Void
- NSApplication
- Bool
- NSApplication
- CGFloat
- NSWindow
- Bool
- Int
- UUID
- WindowFrame
- Bool
- Context
- NSEvent
- NSTrackingArea
- NSView
- NSWindow
- URL
- Any
- Bool
- NSCoder
- NSObjectProtocol
- NSWindow
- Bool
- Bool
- Date
- InspectFileTreeViewModel
- URL
- UUID
- Void
- Bool
- Int
- UUID
- Void
- UUID
- Bool
- Date
- Int32
- Kind
- Set
- pid_t
- TimeInterval
- Bool
- Data
- Int
- Bool
- Int
- UUID
- TimeInterval
- UUID
- ClosedRange
- Int
- SplitDirection
- TimeInterval
- TimeInterval
- URL
- Bool
- UUID
- Any
- Bool
- Error
- Int32
- Sendable
- Set
- T
- TimeInterval
- URL
- UUID
- Void
- Bool
- Bool
- Int
- Int32
- URL
- Duration
- MainActor
- ClaudeSessionState
- Bool
- Date
- URL
- Bool
- Error
- URL
- Bool
- Bool
- Duration
- Sendable
- Bool
- CheckedContinuation
- Never
- Set
- CheckedContinuation
- Never
- Bool
- Int
- URL
- IPCEnv
- IPCRequest
- IPCValue
- JSONEncoder
- Data
- Int
- Int32
- NSEvent
- UInt16
- pid_t
- UUID
- UUID
- MainActor
- Any
- MainActor
- Bool
- Int
- UUID
- Any
- Bool
- Int
- JSONEncoder
- URL
- URL
- Int
- NSView
- NSWindow
- UserDefaults
- Duration
- Int
- Sendable
- MainActor
- T
- Int32
- GitRepoWatcherTests.swift
- IPCTestError
- tian-hook-prompt.sh

## God Nodes (most connected - your core abstractions)
1. `String` - 588 edges
2. `Foundation` - 167 edges
3. `IPCCommandHandler` - 107 edges
4. `View` - 102 edges
5. `PaneStatusManager` - 100 edges
6. `Session` - 98 edges
7. `Workspace` - 86 edges
8. `WindowCoordinator` - 76 edges
9. `Testing` - 76 edges
10. `WorkspaceCollection` - 73 edges

## Surprising Connections (you probably didn't know these)
- `CommandContext` --references--> `String`  [EXTRACTED]
  tian-cli/main.swift → tianTests/InspectFileTreeViewModelTests.swift
- `BranchEntry.Kind` --references--> `String`  [EXTRACTED]
  tian/View/CreateSession/BranchListViewModel.swift → tianTests/InspectFileTreeViewModelTests.swift
- `XcodeGen project.yml` --references--> `Swift Argument Parser`  [INFERRED]
  project.yml → THIRD-PARTY-NOTICES.md
- `XcodeGen project.yml` --references--> `TOMLKit`  [INFERRED]
  project.yml → THIRD-PARTY-NOTICES.md
- `XcodeGen project.yml` --references--> `MarkdownUI`  [INFERRED]
  project.yml → THIRD-PARTY-NOTICES.md

## Import Cycles
- None detected.

## Communities (836 total, 702 thin omitted)

### Community 0 - "IPC Command Handling"
Cohesion: 0.09
Nodes (11): GitRepoID, PRStatus, CacheEntry, CacheKey, CacheResult, hit, miss, PRStatusCache (+3 more)

### Community 1 - "Terminal Surface Input"
Cohesion: 0.11
Nodes (5): NSMenu, NSPoint, NSTextInputClient, Selector, TerminalSurfaceView

### Community 3 - "Split Layout & Navigation"
Cohesion: 0.22
Nodes (4): First, Second, SplitContainerView, SplitDividerView

### Community 4 - "Session State Migration"
Cohesion: 0.11
Nodes (12): Migration, MigrationError, futureVersion, migrationFailed, missingVersion, SessionStateMigrator, session, SessionMigrationV3ToV4Tests (+4 more)

### Community 5 - "CLI Command Router"
Cohesion: 0.05
Nodes (49): LocalizedError, ParsableCommand, CLIError, closeInFlight, connection, general, permissionDenied, processSafety (+41 more)

### Community 6 - "Git Repo Watcher"
Cohesion: 0.10
Nodes (5): HierarchicalEntry, SessionCollection, DockToggleDuringDragTests, SessionCollectionStressTests, SessionCollectionTests

### Community 8 - "Session Collection"
Cohesion: 0.07
Nodes (3): IPCCommandHandler, WindowCoordinator, IPCCommandHandlerTests

### Community 9 - "SwiftUI View Components"
Cohesion: 0.05
Nodes (19): SwiftUI, SettingsView, DefaultDirectoryMenu, InspectPanelRail, InspectPanelResizeHandle, PaneView, ClaudeSessionState, SessionOverviewActivityListView (+11 more)

### Community 10 - "Config Auto-Set Runner"
Cohesion: 0.26
Nodes (5): TOMLKit, ConfigAutoSetResult, ConfigAutoSetRunner, ConfigAutoSetRunnerTests, StubClaudeInvoker

### Community 11 - "Session Overview Grid"
Cohesion: 0.06
Nodes (21): Badge, local, localAndOrigin, origin, BranchEntry.Kind, BranchListViewModel, BranchRow, Direction (+13 more)

### Community 12 - "Sidebar Container"
Cohesion: 0.09
Nodes (15): Accessibility, Notification, Notification.Name, SessionOverviewOverlayModifier, SidebarContainerView, SidebarNotificationModifier, TerminalToggleStatusBarButton, SidebarPanelView (+7 more)

### Community 13 - "Worktree Orchestrator"
Cohesion: 0.09
Nodes (3): Session, RetryClaudeSpawnTests, SessionModelTests

### Community 14 - "Split Tree Model"
Cohesion: 0.11
Nodes (9): ANSIStripper, State, csi, escape, escapeIntermediate, normal, osc, oscEscape (+1 more)

### Community 15 - "SSH Remote Execution"
Cohesion: 0.10
Nodes (7): Int8, SurfaceCallbackContext, claude, spawnFailed, PaneViewModel, PaneSpawner, PaneExitOverlay

### Community 16 - "Inspect File Tree Scanning"
Cohesion: 0.08
Nodes (12): CGPoint, DividerInfo, SplitLayout, SplitLayoutResult, NavigationDirection, down, left, right (+4 more)

### Community 17 - "ANSI Stripper"
Cohesion: 0.07
Nodes (7): SplitTree, RemoveResult, lastPane, notFound, removed, SplitTreeRestoreTests, SplitTreeTests

### Community 19 - "Persistence State Models"
Cohesion: 0.21
Nodes (3): MockWorkspaceProvider, OrchestratorTestError, WorktreeOrchestratorTests

### Community 20 - "Command Logger"
Cohesion: 0.09
Nodes (21): CodingKey, Encodable, FileHandle, CodingKeys, isError, result, structuredOutput, subtype (+13 more)

### Community 22 - "Refresh Scheduling & Coalescing"
Cohesion: 0.14
Nodes (11): ghostty_action_color_change_s, ghostty_action_s, ghostty_app_t, ghostty_clipboard_e, ghostty_config_t, ghostty_surface_config_s, ghostty_target_s, NSColor (+3 more)

### Community 23 - "Worktree Service"
Cohesion: 0.09
Nodes (42): bash_commands(), buckets(), child_branch(), child_hygiene(), count_tools(), failed_delegate_tasks(), file_path_tools(), filter_zombies() (+34 more)

### Community 24 - "Off-Main Process Runner"
Cohesion: 0.13
Nodes (10): DispatchWorkItem, KillGuard, State, alive, dead, terminating, LimitedBuffer, ResumeOnce (+2 more)

### Community 25 - "Decision Record Schema"
Cohesion: 0.05
Nodes (42): additionalProperties, description, type, description, type, description, type, description (+34 more)

### Community 26 - "Git Status Service"
Cohesion: 0.13
Nodes (6): NSLayoutConstraint, NSWindowController, NSWindowDelegate, TrafficLightAligner, WorkspaceWindowController, WorkspaceManager

### Community 28 - "Worktree Service Tests"
Cohesion: 0.05
Nodes (35): Architecture, Build, Concepts, graphify, Keeping the record current (do this without being asked), Key Layers, Lifecycle, Logs (+27 more)

### Community 29 - "Test Harness Utilities"
Cohesion: 0.09
Nodes (3): Foundation, Testing, tian

### Community 31 - "Inspect File Tree ViewModel"
Cohesion: 0.07
Nodes (10): GitStatusService, Kind, added, removed, unchanged, MarkdownDiffSegment, MarkdownInlineDiff, GitStatusServiceTests (+2 more)

### Community 32 - "Pane ViewModel"
Cohesion: 0.19
Nodes (6): SplitDirection, makeClaudeSession(), makeWorkspaceState(), SessionRestorerBuildTests, SessionRestorerLoadTests, SessionRestorerValidationTests

### Community 33 - "Error Types"
Cohesion: 0.07
Nodes (27): CustomStringConvertible, Error, Logger, RemoteScanError, RestoreError, emptySessions, emptyWorkspaces, FileLogger (+19 more)

### Community 34 - "Ghostty App Core"
Cohesion: 0.18
Nodes (8): sockaddr, sockaddr_un, socklen_t, blockingAwait(), IPCServer, Log, IPCServerTests, connectionFailed

### Community 35 - "Pane Status Manager"
Cohesion: 0.10
Nodes (3): Workspace, DefaultWorkingDirectoryTests, WorkspaceTests

### Community 37 - "Sidebar Drag Reorder"
Cohesion: 0.13
Nodes (5): DragGesture, SidebarExpandedContentView, SidebarItem, sessionRow, workspaceHeader

### Community 38 - "Session Migration Encoding Tests"
Cohesion: 0.13
Nodes (4): JSONDecoder, SessionMigrationV4ToV5Tests, SessionMigrationV5ToV6Tests, SessionMigrationV7ToV8Tests

### Community 39 - "Background Activity Store"
Cohesion: 0.09
Nodes (8): FileTreeNode, Kind, directory, file, InspectFileScanning, InspectFileTreeViewModel, LiveInspectFileScanner, InspectPanelFileBrowser

### Community 40 - "Graphify Pipeline Skill"
Cohesion: 0.22
Nodes (3): GitRepoWatcher, CallbackTracker, GitRepoWatcherTests

### Community 41 - "Session Divider Drag"
Cohesion: 0.22
Nodes (7): PaneLeafState, SessionRecord, WorkspaceState, RestoreCommandPaneViewModelTests, SessionRecordRestoreCommandRoundTripTests, SessionRecordWorktreePathTests, SessionStateRoundTripTests

### Community 42 - "Framework Imports"
Cohesion: 0.12
Nodes (10): S, Content, image, markdown, SessionReaderState, GlassHoverHighlight, LiquidGlassBackground, InspectPanelTabsWiringModifier (+2 more)

### Community 43 - "Markdown Reader"
Cohesion: 0.09
Nodes (16): MarkdownContent, MarkdownUI, ReaderFileSource, DiffColors, MarkdownDiffView, Rendered, DiffOutcome, notInRepo (+8 more)

### Community 44 - "Worktree Config Parser"
Cohesion: 0.16
Nodes (5): TOMLTable, table, CopyRule, WorktreeConfigParser, WorktreeConfigParserTests

### Community 45 - "Session Audit Analyzer"
Cohesion: 0.22
Nodes (7): IPCValue, array, bool, int, null, object, string

### Community 46 - "Git Types"
Cohesion: 0.17
Nodes (6): InspectChildEntry, InspectFileScanner, ScannerError, decodeFailed, gitFailed, InspectFileScannerTests

### Community 48 - "Working Tree Watcher"
Cohesion: 0.24
Nodes (5): DispatchSourceTimer, Box, WorkingTreeWatcher, CallbackTracker, WorkingTreeWatcherTests

### Community 49 - "Branch Graph Rendering"
Cohesion: 0.33
Nodes (3): Float, SIMD2, BusyDotView

### Community 50 - "Inspect File Scanner"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 51 - "CLI Output Formatting"
Cohesion: 0.14
Nodes (15): Codable, Decodable, AutoSetPayload, ClaudeResultEnvelope, CopyEntry, SetupEntry, IPCEnv, IPCError (+7 more)

### Community 52 - "Claude Session State"
Cohesion: 0.12
Nodes (14): CaseIterable, Comparable, ClaudeSessionState, busy, failed, idle, inactive, needsAttention (+6 more)

### Community 53 - "Remote Connection & Workspace Create"
Cohesion: 0.15
Nodes (6): GitChangedFile, BlockingScanner, FixedScanner, InspectFileTreeViewModel, InspectFileTreeViewModelTests, State

### Community 54 - "Inspect Branch ViewModel"
Cohesion: 0.14
Nodes (6): WorkspaceProviding, LayoutNode, pane, split, WorktreeCreateResult, WorktreeOrchestrator

### Community 55 - "Markdown Diff Segments"
Cohesion: 0.20
Nodes (10): SimpleHTTPRequestHandler, build_manifest(), Handler, iter_json_files(), main(), Every *.json under ROOT (used both for the manifest and the mtime watch)., Map of json path -> mtime, for change detection., Describe what exists so the dashboard can discover docs and ADRs. (+2 more)

### Community 56 - "Ghostty Terminal Surface"
Cohesion: 0.13
Nodes (3): Unmanaged, GhosttyTerminalSurface, Optional

### Community 57 - "Branch List Tests"
Cohesion: 0.20
Nodes (5): Color, BranchCommitRow, BranchGraphCanvas, InspectBranchBody, SidebarSessionRowView

### Community 58 - "IPC Client CLI"
Cohesion: 0.17
Nodes (3): FuzzyMatch, Result, FuzzyMatchTests

### Community 60 - "Inspect Diff ViewModel"
Cohesion: 0.10
Nodes (5): IPCEnv, IPCError, IPCRequest, IPCResponse, IPCMessageTests

### Community 61 - "Inspect Panel View"
Cohesion: 0.20
Nodes (6): PaneNode, PaneNodeState, pane, split, PaneSplitState, PaneNodeStateEncodingTests

### Community 62 - "Create Session View"
Cohesion: 0.20
Nodes (9): Character, CreateSessionView, CreateWorktreeSubmission, SubmitAction, blocked, checkoutExisting, claudeWorktree, createBranch (+1 more)

### Community 64 - "IPC Message Protocol"
Cohesion: 0.14
Nodes (22): CFTimeInterval, Equatable, Identifiable, Sendable, CallbackBox, GitCommit, GitCommitGraph, GitDiffHunk (+14 more)

### Community 65 - "Session Split Navigation"
Cohesion: 0.13
Nodes (3): DirectoryPicker, WorkspaceCreationFlow, WorkspaceCreationFlowTests

### Community 66 - "Fuzzy Match"
Cohesion: 0.14
Nodes (9): CreateSessionRequest, WorkspaceWindowContent, SetupProgressCapsule, Phase, cleanup, removing, setup, SetupProgress (+1 more)

### Community 67 - "Worktree Setup Progress"
Cohesion: 0.09
Nodes (14): ArgumentParser, ExpressibleByArgument, ClaudeInvoker, ProcessClaudeInvoker, handleListResponse(), PaneList, SessionList, WorkspaceList (+6 more)

### Community 68 - "Background Activity Sync"
Cohesion: 0.11
Nodes (18): A Session = one Claude pane + a toggleable terminal panel, Command reference, Core rules, Delegation orchestrator (bundled script — backs `/tian implement`), Discovery, Driving tian with the `tian` CLI, Gotchas, Long-session hygiene (+10 more)

### Community 69 - "Pane Node Building"
Cohesion: 0.22
Nodes (6): os, FileBaseline, committed, notInRepo, untracked, RepoLocation

### Community 70 - "Pane Node Tree"
Cohesion: 0.10
Nodes (9): Binding, RemoteConnectionState, CreateWorkspaceView, Field, directory, host, name, RemoteConnection (+1 more)

### Community 71 - "Create Session Flow Tests"
Cohesion: 0.14
Nodes (6): Darwin, AppMetrics, BranchDeleteOutcome, deleted, keptUnmerged, notFound

### Community 73 - "Pane Status Aggregation Tests"
Cohesion: 0.18
Nodes (3): SessionSnapshotWindowGeometryTests, SessionSnapshotTests, SessionSnapshotWorktreePathTests

### Community 74 - "Session State Registry"
Cohesion: 0.22
Nodes (4): ReaderOverlayView, SessionContentView, SessionHeaderView, SplitTreeView

### Community 76 - "Session Restorer Tests"
Cohesion: 0.12
Nodes (16): KeyAction, closeWorkspace, cycleFocusArea, focusSidebar, goToSession, newSession, newWorkspace, nextSession (+8 more)

### Community 78 - "Quit Flow Coordinator"
Cohesion: 0.31
Nodes (4): CloseConfirmationDialog, CloseTarget, pane, CloseConfirmationDialogTests

### Community 79 - "Pane Hierarchy Wiring"
Cohesion: 0.14
Nodes (6): PaneNode, leaf, split, SplitDirection, horizontal, vertical

### Community 80 - "Inspect Tab State"
Cohesion: 0.20
Nodes (4): RemoteCommandBuilder, ShellQuoting, SSHMultiplexing, RemoteCommandBuilderTests

### Community 81 - "IPC Server Socket"
Cohesion: 0.12
Nodes (16): description, type, description, type, description, type, description, type (+8 more)

### Community 84 - "Branch List Fakes"
Cohesion: 0.17
Nodes (3): ProcessDetector, RunningProcessInfo, ProcessDetectorTests

### Community 85 - "App Delegate Lifecycle"
Cohesion: 0.17
Nodes (8): NSApplicationDelegate, NSObject, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse, UNUserNotificationCenter, UNUserNotificationCenterDelegate, TianAppDelegate

### Community 86 - "File Log Writer"
Cohesion: 0.17
Nodes (5): SessionDividerClamper, SessionDividerView, SessionLayout, DividerClampingTests, SessionLayoutTests

### Community 87 - "Window Drag Blocker"
Cohesion: 0.14
Nodes (13): Architecture, Build, Concepts, Key Layers, Lifecycle, Logs, Scratch / Temporary Files, Source Layout (+5 more)

### Community 88 - "Commit Graph Tests"
Cohesion: 0.21
Nodes (3): active, PaneStatus, WeakBox

### Community 90 - "Remote Command Builder"
Cohesion: 0.15
Nodes (12): WorktreeError, baseWithExisting, branchAlreadyExists, closeInFlight, configParseError, gitError, invalidBaseRef, notAGitRepo (+4 more)

### Community 91 - "Skill Installer"
Cohesion: 0.15
Nodes (13): description, type, properties, commit, since, summary, target, description (+5 more)

### Community 93 - "Branch List Service"
Cohesion: 0.19
Nodes (3): InspectPanelState, WorkspaceSnapshot, InspectPanelStateTests

### Community 94 - "Key Chord Model"
Cohesion: 0.18
Nodes (12): Hashable, UInt, CharacterChord, KeyBinding, KeyBindingRegistry, KeyCodeChord, Field, dialog (+4 more)

### Community 95 - "Key Actions"
Cohesion: 0.15
Nodes (7): Direction, down, left, right, up, OverviewGridNavigation, OverviewGridNavigationTests

### Community 97 - "Status Doc Schema"
Cohesion: 0.21
Nodes (3): EnvironmentBuilder, PaneHierarchyContext, EnvironmentBuilderTests

### Community 100 - "Close Confirmation Dialog"
Cohesion: 0.22
Nodes (7): IPCValue, array, bool, int, null, object, string

### Community 101 - "Image Reader"
Cohesion: 0.21
Nodes (5): ImageIO, NSImage, ImageDocument, Sendbox, ImageReaderView

### Community 102 - "Session Serializer"
Cohesion: 0.08
Nodes (13): RemoteInspectFileScanner, commandFailed, RemoteReaderFileSource, RemoteExecutionRegistry, SSHConnection, State, connected, connecting (+5 more)

### Community 103 - "Workspace Keyboard Navigation"
Cohesion: 0.08
Nodes (25): CGFloat, Color, Context, GridItem, Int, NSEvent, OverviewGridNavigation, String (+17 more)

### Community 104 - "System Monitor (CPU/RAM)"
Cohesion: 0.25
Nodes (5): UserNotifications, NotificationError, permissionDenied, NotificationManager, NotificationManagerTests

### Community 105 - "Check For Updates"
Cohesion: 0.24
Nodes (6): Commands, ObservableObject, Sparkle, CheckForUpdatesView, CheckForUpdatesViewModel, WorkspaceCommands

### Community 106 - "Working Directory Resolver"
Cohesion: 0.29
Nodes (6): RestoreMetrics, RestoreResult, Source, backup, primary, SessionRestorerMetricsTests

### Community 107 - "App Hero Screenshot (UI)"
Cohesion: 0.24
Nodes (13): Claude Pane (Claude Code v2.1.140), Claude Code Statusline (ctx/model/branch), File Explorer Panel (Files/Diff/Branch), Workspace -> Session -> Pane Hierarchy, New Workspace Action, Session Row (name + branch + git diff), Workspace/Session Sidebar, Bottom Status Bar (CPU/RAM) (+5 more)

### Community 109 - "Status Bar View"
Cohesion: 0.29
Nodes (10): items, additionalProperties, required, type, items, items, shipped, description (+2 more)

### Community 110 - "SessionCloseFlow"
Cohesion: 0.35
Nodes (10): commit_count(), committed(), dedup(), delegation_key(), load(), main(), pct(), rank() (+2 more)

### Community 113 - "Row"
Cohesion: 0.15
Nodes (3): PaneNodeConversionTests, SplitDirectionConversionTests, WindowFrameTests

### Community 114 - "AppKit"
Cohesion: 0.20
Nodes (4): AppKit, Carbon.HIToolbox, WindowFrame, SessionCloseFlow

### Community 116 - "implement-log"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 117 - "socklen_t"
Cohesion: 0.33
Nodes (5): Response, cancel, closeOnly, removeWorktreeAndClose, WorktreeCloseDialog

### Community 118 - "AutoSetPrompt"
Cohesion: 0.42
Nodes (7): emit_block(), err(), log(), log_run(), need_val(), implement.sh script, usage()

### Community 120 - "InspectPanelState"
Cohesion: 0.31
Nodes (3): Keys, TianSettings, TianSettingsTests

### Community 121 - "SidebarExpandedContentView"
Cohesion: 0.13
Nodes (9): NSView, NSViewRepresentable, PreferenceKey, WindowAccessor, KeyView, SidebarKeyboardResponder, WorkspaceFramePreferenceKey, Coordinator (+1 more)

### Community 126 - "SessionSplitNavigation"
Cohesion: 0.22
Nodes (4): NSAttributedString, NSRange, NSRangePointer, NSRect

### Community 127 - "PollingRefresher"
Cohesion: 0.25
Nodes (7): How to read the output, Improvement catalog (map flags → fixes), Input, Litmus test to report, Run, session-audit — audit a tian orchestrator session, What to produce

### Community 128 - "DiffFileHeaderRow"
Cohesion: 0.11
Nodes (19): DiffBinaryPlaceholderRow, DiffFileHeaderRow, DiffHunkHeaderRow, DiffLineRow, DiffTruncatedRow, InspectPanelEmptyContentView, InspectPanelLoadingView, InspectPanelMutedMessage (+11 more)

### Community 129 - "WorkspaceWindowContent"
Cohesion: 0.25
Nodes (7): additionalProperties, description, $id, required, $schema, title, type

### Community 130 - "implement"
Cohesion: 0.25
Nodes (7): Cutting a release, Day-to-day, Environment, Examples, scripts, Versioning, What's here

### Community 132 - "MarkdownCopyButton"
Cohesion: 0.40
Nodes (4): Response, cancel, skipTeardown, SkipTeardownConfirmationDialog

### Community 136 - "MockWorkspaceProvider"
Cohesion: 0.06
Nodes (26): AnyObject, BranchGraphDirtyHost, InspectBranchViewModel, SessionGitContext, InspectDiffViewModel, InspectTabState, mainCheckout, InspectDiffBody (+18 more)

### Community 137 - "status.schema"
Cohesion: 0.40
Nodes (4): Response, cancel, forceRemove, WorktreeForceRemoveDialog

### Community 139 - "TrafficLightAligner"
Cohesion: 0.33
Nodes (3): Timer, DebugOverlayView, LabeledMetric

### Community 140 - "blockingAwait"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 141 - "FileTreeNode"
Cohesion: 0.17
Nodes (3): CoreServices, Observation, OSLog

### Community 142 - "AppMetrics"
Cohesion: 0.33
Nodes (6): GitFileStatus, added, deleted, modified, renamed, unmerged

### Community 143 - "InspectPanelFileRow"
Cohesion: 0.36
Nodes (3): NSAlert, ConfirmAlert, QuitConfirmationDialog

### Community 150 - "RefreshSchedulerTests"
Cohesion: 0.40
Nodes (4): ShellReadinessWaiter, ShellReadyReason, osc7, timeout

### Community 152 - "ContinuousClock"
Cohesion: 0.67
Nodes (3): ContinuousClock, PollTimeoutError, pollUntil()

### Community 153 - "PaneState"
Cohesion: 0.40
Nodes (5): PRState, closed, draft, merged, open

### Community 154 - "ForegroundProcessSummary"
Cohesion: 0.40
Nodes (4): WorktreeKind, linkedWorktree, notARepo, noWorkingDirectory

### Community 156 - "ImageFileType"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 157 - "DebugOverlayView"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 158 - "InspectPanelTabRow"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

### Community 160 - "SidebarWorkspaceHeaderView"
Cohesion: 0.50
Nodes (4): description, items, type, now

### Community 162 - "ClaudeLaunchBadge"
Cohesion: 0.50
Nodes (3): PaneState, exited, running

### Community 163 - "MarkdownFileType"
Cohesion: 0.83
Nodes (3): tian-bash-integration.bash script, _tian_fix_path(), _tian_install_claude_wrapper()

### Community 171 - "tian-bash-integration"
Cohesion: 0.67
Nodes (3): description, type, date

### Community 172 - "InspectPanelFileBrowser"
Cohesion: 0.67
Nodes (3): description, type, done

### Community 173 - "PaneNodeConversionTests"
Cohesion: 0.67
Nodes (3): description, type, item

### Community 174 - "implement-logrec"
Cohesion: 0.67
Nodes (3): description, type, link

### Community 175 - "blocked"
Cohesion: 0.67
Nodes (3): description, type, next

### Community 176 - "date"
Cohesion: 0.67
Nodes (3): title, description, type

### Community 179 - "TianApp"
Cohesion: 0.40
Nodes (3): App, Scene, TianApp

### Community 180 - "tian-hook-prompt-test.sh"
Cohesion: 0.80
Nodes (4): assert_forwarded(), assert_rejected(), run_hook(), tian-hook-prompt-test.sh script

### Community 181 - "Glowing Vertical Cursor Bar Motif"
Cohesion: 1.00
Nodes (3): Glowing Vertical Cursor Bar Motif, tian App Icon (macOS AppIcon), Terminal Emulator Symbolism

### Community 193 - "tian-hook-prompt"
Cohesion: 0.50
Nodes (4): BackgroundActivity, Kind, bash, other

### Community 198 - "graphify knowledge graph"
Cohesion: 0.25
Nodes (9): Bundle tian CLI build phase, Bundled Claude hook scripts, tian-cli tool target, tian app target, tianTests target, XcodeGen project.yml, MarkdownUI, Swift Argument Parser (+1 more)

### Community 834 - "IPCTestError"
Cohesion: 0.50
Nodes (3): IPCTestError, socketCreationFailed, writeFailed

## Knowledge Gaps
- **419 isolated node(s):** `tian-hook-prompt.sh script`, `$schema`, `$id`, `title`, `description` (+414 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **702 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `Error Types` to `IPC Command Handling`, `Terminal Surface Input`, `Session Git & PR Status`, `Session State Migration`, `CLI Command Router`, `Git Repo Watcher`, `Session Model`, `Session Collection`, `SwiftUI View Components`, `Config Auto-Set Runner`, `Session Overview Grid`, `Sidebar Container`, `Worktree Orchestrator`, `Split Tree Model`, `SSH Remote Execution`, `ANSI Stripper`, `Workspace Model`, `Persistence State Models`, `Command Logger`, `Workspace Collection`, `Refresh Scheduling & Coalescing`, `Off-Main Process Runner`, `Session State Fixtures`, `Workspace Reorder Logic`, `Inspect File Tree ViewModel`, `Pane ViewModel`, `Ghostty App Core`, `Pane Status Manager`, `Session Git Context Tests`, `Sidebar Drag Reorder`, `Background Activity Store`, `Graphify Pipeline Skill`, `Session Divider Drag`, `Markdown Reader`, `Worktree Config Parser`, `Session Audit Analyzer`, `Git Types`, `Working Tree Watcher`, `CLI Output Formatting`, `Claude Session State`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `Ghostty Terminal Surface`, `Branch List Tests`, `IPC Client CLI`, `Workspace Window Controller`, `Inspect Diff ViewModel`, `Inspect Panel View`, `Create Session View`, `Git Status Service Tests`, `IPC Message Protocol`, `Session Split Navigation`, `Fuzzy Match`, `Worktree Setup Progress`, `Pane Node Building`, `Pane Node Tree`, `Create Session Flow Tests`, `Session State Registry`, `Session Restorer`, `Worktree Config Execution`, `Pane Hierarchy Wiring`, `Inspect Tab State`, `Session Content View`, `Branch List Fakes`, `Commit Graph Tests`, `Remote Command Builder`, `Branch List ViewModel`, `Branch List Service`, `Key Chord Model`, `Status Doc Schema`, `Terminal Content View`, `Close Confirmation Dialog`, `Image Reader`, `Session Serializer`, `System Monitor (CPU/RAM)`, `Working Directory Resolver`, `Shipped Items Schema`, `NotificationManager`, `Row`, `KeyboardLayoutTranslator`, `socklen_t`, `InspectPanelState`, `items`, `DiffFileHeaderRow`, `os`, `Response`, `MockWorkspaceProvider`, `status.schema`, `TrafficLightAligner`, `AppMetrics`, `ShellReadyReason`, `InlineRenameView`, `NSViewRepresentable`, `PaneState`, `ForegroundProcessSummary`, `HtmlFileType`, `InspectPanelStatusStrip`, `tian-hook-prompt`, `GitRepoWatcherTests.swift`?**
  _High betweenness centrality (0.366) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Harness Utilities` to `IPC Command Handling`, `os`, `Session State Migration`, `CLI Command Router`, `Response`, `Git Repo Watcher`, `MockWorkspaceProvider`, `Config Auto-Set Runner`, `Session Overview Grid`, `BusyDotView`, `FileTreeNode`, `Split Tree Model`, `SSH Remote Execution`, `Inspect File Tree Scanning`, `Response`, `ANSI Stripper`, `Command Logger`, `RainbowGlowBorder`, `RefreshSchedulerTests`, `resolve_from_runlog`, `Off-Main Process Runner`, `ContinuousClock`, `ForegroundProcessSummary`, `HtmlFileType`, `Git Status Service`, `Inspect File Tree ViewModel`, `Pane ViewModel`, `Error Types`, `Ghostty App Core`, `Background Activity Store`, `Framework Imports`, `Markdown Reader`, `Worktree Config Parser`, `Git Types`, `CLI Output Formatting`, `Claude Session State`, `Remote Connection & Workspace Create`, `Inspect Branch ViewModel`, `IPC Client CLI`, `Inspect Diff ViewModel`, `Inspect Panel View`, `Git Status Service Tests`, `IPC Message Protocol`, `tian-hook-prompt`, `Session Split Navigation`, `Worktree Setup Progress`, `Fuzzy Match`, `Pane Node Building`, `Pane Node Tree`, `Create Session Flow Tests`, `GitRepoWatcherTests.swift`, `IPCTestError`, `Pane Hierarchy Wiring`, `Inspect Tab State`, `Session Content View`, `Branch List Fakes`, `Commit Graph Tests`, `Remote Command Builder`, `Branch List Service`, `Key Actions`, `Status Doc Schema`, `Terminal Content View`, `Session Serializer`, `Shipped Items Schema`, `TianSettings`, `Row`, `AppKit`, `GitStatusServiceUnifiedDiffTests`, `InspectPanelState`, `SidebarSessionRowView`?**
  _High betweenness centrality (0.077) - this node is a cross-community bridge._
- **Why does `View` connect `DiffFileHeaderRow` to `Split Layout & Navigation`, `MockWorkspaceProvider`, `SwiftUI View Components`, `TrafficLightAligner`, `Sidebar Container`, `SSH Remote Execution`, `InlineRenameView`, `Session State Fixtures`, `Error Types`, `Sidebar Drag Reorder`, `Background Activity Store`, `Framework Imports`, `Markdown Reader`, `Branch Graph Rendering`, `Branch List Tests`, `Create Session View`, `Fuzzy Match`, `Pane Node Tree`, `Session State Registry`, `File Log Writer`, `Image Reader`, `Check For Updates`, `items`?**
  _High betweenness centrality (0.042) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `String` (e.g. with `.run()` and `.resolveRepoRoot()`) actually correct?**
  _`String` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 62 inferred relationships involving `IPCCommandHandler` (e.g. with `.applicationDidFinishLaunching()` and `.activitySyncInvalidPaneUUIDReturnsError()`) actually correct?**
  _`IPCCommandHandler` has 62 INFERRED edges - model-reasoned connections that need verification._
- **What connects `tian-hook-prompt.sh script`, `Cheap cwd sniff — read only the head of the file.`, `All tool inputs joined — used to detect which worktrees the parent touched.` to the rest of the system?**
  _440 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `IPC Command Handling` be split into smaller, more focused modules?**
  _Cohesion score 0.0931899641577061 - nodes in this community are weakly interconnected._