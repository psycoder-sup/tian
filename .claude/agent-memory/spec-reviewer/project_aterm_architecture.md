---
name: aterm architecture context
description: Key architecture patterns for aterm - SwiftUI terminal emulator with @MainActor @Observable models, NotificationCenter events, Process+DispatchQueue subprocess pattern
type: project
---

aterm is a macOS terminal emulator using SwiftUI + Ghostty. Key architecture patterns discovered during spec review:

- **Models**: `@MainActor @Observable` classes (SpaceModel, PaneViewModel, PaneStatusManager, SpaceCollection)
- **Services**: Stateless enums with static async methods (WorktreeService pattern) - shell out to git via `Process` + `DispatchQueue.global(qos: .userInitiated)` + `withCheckedThrowingContinuation`
- **WorktreeService.runGit** is `private` - cannot be reused from other files without extraction
- **Event flow**: NotificationCenter for Ghostty surface events (pwd, title, close, bell). Callback closures for parent-child wiring (onEmpty, directoryFallback)
- **PaneStatusManager**: singleton with `[UUID: PaneStatus]` where PaneStatus has non-optional `label: String`
- **SidebarSpaceRowView**: HStack with active dot, optional worktree icon, VStack(name + optional status label), Spacer, tab count badge
- **Test framework**: Swift Testing (`import Testing`, `@Test`, `#expect`), temp git repos in WorktreeServiceTests
- **Hierarchy**: Workspace > SpaceCollection > SpaceModel > TabModel > PaneViewModel > SplitTree
- **Logger**: `Log` enum in `aterm/Utilities/Logger.swift` with categories: core, view, ghostty, persistence, lifecycle, perf, ipc, worktree
- **RainbowGlowBorder.swift**: `rainbowColors` is `private let` at file scope - not accessible from other files
- **Sandbox**: disabled (`ENABLE_APP_SANDBOX: false`)

**Why:** Needed to ground spec reviews in actual codebase patterns rather than assumptions.
**How to apply:** Reference these patterns when reviewing specs that propose new services, models, or view modifications.
