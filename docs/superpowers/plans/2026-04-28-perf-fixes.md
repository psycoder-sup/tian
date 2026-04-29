# tian Performance Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the five highest-impact performance regressions identified in the 2026-04-28 performance audit: notification fan-out from Ghostty events, per-keystroke linear keybinding scan, git refresh storms during builds, stacked 30 FPS animations, and observable cascade from the `PaneStatusManager` singleton.

**Architecture:** Each task is independent and shippable as its own PR. Together they reduce per-keystroke work, coalesce event chatter into single SwiftUI invalidations, throttle background animation cost, and scope observation to a finer granularity so a single pane's state change no longer re-renders the entire chrome.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, `Observation` framework, AppKit (`NSWindow`, `NSEvent`), Swift Testing (`@Test` / `#expect`), XcodeGen for project generation, ghostty C API.

**Project conventions to honor:**
- All model types are `@MainActor @Observable`. New per-pane observable state must follow this pattern.
- After adding/renaming Swift files, run `xcodegen generate` (CLAUDE.md). Never edit `project.pbxproj`.
- Build via `scripts/build.sh Debug`. Test via `xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS'`.
- Tests live in `tianTests/`. Use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Each task = its own commit (and ideally its own PR). Conventional-commit style emoji prefix matches existing log (`✨ feat`, `🐛 fix`, `⚡ perf`).

**Verification posture:** Where logic is testable in isolation (coalescer, scheduler, hash registry) write unit tests. Where the win is structural (animations, observation scope) verify by code inspection plus a manual smoke test plan.

---

## File Structure

**New files:**
- `tian/Utilities/EventCoalescer.swift` — generic per-key trailing debouncer for Ghostty events.
- `tian/Utilities/RefreshScheduler.swift` — per-repo trailing debouncer + global concurrency cap for git refresh.
- `tianTests/EventCoalescerTests.swift`
- `tianTests/RefreshSchedulerTests.swift`
- `tianTests/KeyBindingRegistryTests.swift` (extends/adds tests if absent)

**Modified files:**
- `tian/Core/GhosttyApp.swift` — wire coalescer for title/pwd/bell.
- `tian/Input/KeyBindingRegistry.swift` — replace linear scan with hash lookup.
- `tian/Tab/SpaceGitContext.swift` — route refresh calls through `RefreshScheduler`.
- `tian/View/Shared/RainbowGlowBorder.swift` — add `paused` parameter; reduce frame interval.
- `tian/View/Sidebar/BusyDotView.swift` — same pause/throttle treatment.
- `tian/View/TabBar/AuroraCapsuleFill.swift` — same pause/throttle treatment.
- `tian/Pane/PaneViewModel.swift` — add per-pane `sessionState` and `status` observable properties.
- `tian/Pane/PaneStatusManager.swift` — convert to a writer that fans out to per-pane state; keep aggregate accessors.
- Call sites that read `PaneStatusManager.shared.sessionState(for:)` etc., listed in Task 5.

---

## Task 1: Coalesce Ghostty title / pwd / bell notifications

**Why:** `tian/Core/GhosttyApp.swift:256-323` posts a NotificationCenter event for every VT escape (OSC 0/2 title, OSC 7 pwd, BEL). Prompt redraws emit several per command — with N panes this is O(N²) observer fan-out. Each pwd post additionally triggers a git refresh task (Task 3 will further dampen that, but the post itself must be coalesced first).

**Files:**
- Create: `tian/Utilities/EventCoalescer.swift`
- Create: `tianTests/EventCoalescerTests.swift`
- Modify: `tian/Core/GhosttyApp.swift:240-340` (title, bell, pwd action handlers)

### Steps

- [ ] **1.1: Write failing test for `EventCoalescer`**

Create `tianTests/EventCoalescerTests.swift`:

```swift
import Testing
import Foundation
@testable import tian

@MainActor
struct EventCoalescerTests {

    @Test func deliversLastValuePerKeyAfterInterval() async throws {
        var delivered: [(UUID, String)] = []
        let coalescer = EventCoalescer<UUID, String>(interval: .milliseconds(20)) { key, value in
            delivered.append((key, value))
        }
        let key = UUID()

        coalescer.submit(key: key, value: "first")
        coalescer.submit(key: key, value: "second")
        coalescer.submit(key: key, value: "third")

        // Wait past the interval.
        try await Task.sleep(for: .milliseconds(60))

        #expect(delivered.count == 1)
        #expect(delivered.first?.1 == "third")
    }

    @Test func separateKeysFireIndependently() async throws {
        var delivered: [(UUID, String)] = []
        let coalescer = EventCoalescer<UUID, String>(interval: .milliseconds(20)) { key, value in
            delivered.append((key, value))
        }
        let a = UUID()
        let b = UUID()

        coalescer.submit(key: a, value: "alpha")
        coalescer.submit(key: b, value: "beta")

        try await Task.sleep(for: .milliseconds(60))

        #expect(delivered.count == 2)
        #expect(delivered.contains(where: { $0.0 == a && $0.1 == "alpha" }))
        #expect(delivered.contains(where: { $0.0 == b && $0.1 == "beta" }))
    }

    @Test func laterSubmitResetsTimer() async throws {
        var delivered: [String] = []
        let coalescer = EventCoalescer<String, String>(interval: .milliseconds(40)) { _, value in
            delivered.append(value)
        }

        coalescer.submit(key: "k", value: "v1")
        try await Task.sleep(for: .milliseconds(20))
        coalescer.submit(key: "k", value: "v2")
        try await Task.sleep(for: .milliseconds(20))
        // 40ms total since first, but only 20ms since last — should not have fired yet.
        #expect(delivered.isEmpty)

        try await Task.sleep(for: .milliseconds(40))
        #expect(delivered == ["v2"])
    }
}
```

- [ ] **1.2: Run the test and verify it fails**

```
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS' -only-testing:tianTests/EventCoalescerTests
```

Expected: build failure ("cannot find type 'EventCoalescer' in scope").

- [ ] **1.3: Implement `EventCoalescer`**

Create `tian/Utilities/EventCoalescer.swift`:

```swift
import Foundation

/// Trailing-edge debouncer that coalesces rapid submissions per key.
/// Only the most recent `value` for a key within `interval` is delivered.
///
/// Used to smooth NotificationCenter posts driven by VT escape sequences
/// (title, pwd, bell) which arrive faster than the UI cares about.
@MainActor
final class EventCoalescer<Key: Hashable, Value> {
    typealias Handler = (Key, Value) -> Void

    private struct Entry {
        var value: Value
        var task: Task<Void, Never>
    }

    private let interval: Duration
    private let handler: Handler
    private var pending: [Key: Entry] = [:]

    init(interval: Duration, handler: @escaping Handler) {
        self.interval = interval
        self.handler = handler
    }

    /// Schedule `value` for delivery. Replaces any pending value for the same key.
    func submit(key: Key, value: Value) {
        pending[key]?.task.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.interval)
            guard !Task.isCancelled else { return }
            guard let entry = self.pending.removeValue(forKey: key) else { return }
            self.handler(key, entry.value)
        }
        pending[key] = Entry(value: value, task: task)
    }

    /// Cancel any pending delivery for `key` (e.g., on pane close).
    func cancel(key: Key) {
        pending.removeValue(forKey: key)?.task.cancel()
    }
}
```

- [ ] **1.4: Regenerate Xcode project and run tests**

```
xcodegen generate
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS' -only-testing:tianTests/EventCoalescerTests
```

Expected: 3 tests pass.

- [ ] **1.5: Commit the coalescer**

```
git add tian/Utilities/EventCoalescer.swift tianTests/EventCoalescerTests.swift project.yml
git commit -m "✨ feat(util): add EventCoalescer for trailing-edge debounce per key"
```

- [ ] **1.6: Wire coalescers into `GhosttyApp`**

In `tian/Core/GhosttyApp.swift`, near the top of the class (alongside `notificationManager`), add:

```swift
    private lazy var titleCoalescer = EventCoalescer<UUID, String>(interval: .milliseconds(75)) { surfaceId, title in
        NotificationCenter.default.post(
            name: GhosttyApp.surfaceTitleNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceId, "title": title]
        )
    }

    private lazy var pwdCoalescer = EventCoalescer<UUID, String>(interval: .milliseconds(75)) { surfaceId, pwd in
        NotificationCenter.default.post(
            name: GhosttyApp.surfacePwdNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceId, "pwd": pwd]
        )
    }

    private lazy var bellCoalescer = EventCoalescer<UUID, Void>(interval: .milliseconds(200)) { surfaceId, _ in
        NotificationCenter.default.post(
            name: GhosttyApp.surfaceBellNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceId]
        )
    }
```

Replace the title handler at lines 253-264 with:

```swift
        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                let surfaceId = ctx.surfaceId
                DispatchQueue.main.async { [weak self] in
                    self?.titleCoalescer.submit(key: surfaceId, value: title)
                }
            }
            return true
```

Replace the bell handler at lines 266-276 with:

```swift
        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            let surfaceId = ctx.surfaceId
            DispatchQueue.main.async { [weak self] in
                self?.bellCoalescer.submit(key: surfaceId, value: ())
            }
            return true
```

Replace the pwd handler at lines 313-325 with:

```swift
        case GHOSTTY_ACTION_PWD:
            if let pwdPtr = action.action.pwd.pwd {
                let pwd = String(cString: pwdPtr)
                let surfaceId = ctx.surfaceId
                DispatchQueue.main.async { [weak self] in
                    self?.pwdCoalescer.submit(key: surfaceId, value: pwd)
                }
            }
            return true
```

- [ ] **1.7: Cancel pending events on surface close**

Find the surface-close path in `GhosttyApp.swift` (search for `surfaceExitedNotification` post or wherever a surface is torn down — likely in `closeSurface` or the `SHOW_CHILD_EXITED` handler around line 278-289). After the existing teardown, add:

```swift
        self.titleCoalescer.cancel(key: surfaceId)
        self.pwdCoalescer.cancel(key: surfaceId)
        self.bellCoalescer.cancel(key: surfaceId)
```

If no such helper exists, add the three cancel calls inside the `SHOW_CHILD_EXITED` action just after the notification is posted.

- [ ] **1.8: Build and smoke test**

```
scripts/build.sh Debug
```

Expected: clean build. Manually launch the app, open 4 panes, run `for i in {1..50}; do echo done; done` in each, verify no UI hitches and titles still update.

- [ ] **1.9: Commit the wiring**

```
git add tian/Core/GhosttyApp.swift
git commit -m "⚡ perf(ghostty): coalesce title/pwd/bell notifications per surface

Cuts O(N²) observer fan-out on prompt redraws by debouncing duplicate
title/pwd posts (75ms trailing) and bell bursts (200ms trailing) per
surface."
```

---

## Task 2: Hash-based `KeyBindingRegistry` lookup

**Why:** `tian/Input/KeyBindingRegistry.swift:48-54` linear-scans every action→binding entry on every `keyDown`. With dozens of bindings this adds measurable per-keystroke latency and runs inside the global key event monitor.

**Files:**
- Modify: `tian/Input/KeyBindingRegistry.swift`
- Create or extend: `tianTests/KeyBindingRegistryTests.swift`

### Steps

- [ ] **2.1: Read current registry shape**

```
cat tian/Input/KeyBindingRegistry.swift
```

Note the existing `KeyBinding` struct fields (key code, modifier flags, character) and the `Action` enum cases. The exact hash key shape depends on what `KeyBinding` carries — usually `(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)`. Confirm before step 2.3.

- [ ] **2.2: Write failing test for hash lookup correctness**

In `tianTests/KeyBindingRegistryTests.swift`, add (or create):

```swift
import Testing
import AppKit
@testable import tian

@MainActor
struct KeyBindingRegistryTests {

    @Test func resolvesRegisteredBindingByEvent() {
        let registry = KeyBindingRegistry()  // assume init() exists or expose for tests
        // Register a binding for ⌘T → newTab (use whatever the real API is).
        registry.bind(.newTab, keyCode: 0x11 /* T */, modifiers: [.command])

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "t",
            charactersIgnoringModifiers: "t",
            isARepeat: false,
            keyCode: 0x11
        )!

        #expect(registry.action(for: event) == .newTab)
    }

    @Test func returnsNilForUnboundChord() {
        let registry = KeyBindingRegistry()
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: 0x06
        )!

        #expect(registry.action(for: event) == nil)
    }
}
```

If a `KeyBindingRegistryTests.swift` already exists, append these tests rather than overwriting. Adjust the `bind` API name to match the real registry; if there is no public `bind` method, mark these tests `@available(*, deprecated)` or use `@testable` access to whatever internal seeding function the registry already exposes.

- [ ] **2.3: Run the test and verify it fails**

```
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS' -only-testing:tianTests/KeyBindingRegistryTests
```

Expected: tests fail (either compile error if the API differs, or runtime mismatch).

- [ ] **2.4: Replace linear scan with `Dictionary` lookup**

Open `tian/Input/KeyBindingRegistry.swift`. Add a hashable chord key:

```swift
struct KeyChord: Hashable {
    let keyCode: UInt16
    /// Filtered to relevant modifiers only — strip non-binding bits like
    /// .numericPad, .help, .function before hashing.
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .control, .option, .shift])
    }

    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }
}
```

Add a stored dictionary (alongside whatever `bindings` already exists):

```swift
private var bindingsByChord: [KeyChord: Action] = [:]
```

After every mutation that updates bindings, rebuild this dict (cheap, happens at config load only). For example, where bindings are seeded:

```swift
private func rebuildIndex() {
    bindingsByChord = Dictionary(
        uniqueKeysWithValues: bindings.map { (KeyChord(keyCode: $0.keyCode, modifiers: $0.modifiers), $0.action) }
    )
}
```

Replace the existing `action(for:)` body (currently at lines 48-54) with:

```swift
func action(for event: NSEvent) -> Action? {
    bindingsByChord[KeyChord(event: event)]
}
```

- [ ] **2.5: Run tests and verify they pass**

```
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS' -only-testing:tianTests/KeyBindingRegistryTests
```

Expected: 2 new tests pass; existing tests continue to pass.

- [ ] **2.6: Run full suite to catch regressions**

```
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS'
```

Expected: full pass.

- [ ] **2.7: Commit**

```
git add tian/Input/KeyBindingRegistry.swift tianTests/KeyBindingRegistryTests.swift
git commit -m "⚡ perf(input): O(1) keybinding lookup via KeyChord hash table

Replaces the per-keystroke linear scan in action(for:) with a
Dictionary<KeyChord, Action> indexed at bind/seed time."
```

---

## Task 3: Debounce + cap concurrent git refreshes during FSEvents storms

**Why:** `tian/Tab/SpaceGitContext.swift:307-376` already has per-repo cancellation but no global cap. During an active build, FSEvents fire across N pinned repos every ~2 s, each spawning `git status` + `git diff` + `gh pr view` subprocesses. Code comments at lines 306-308 explicitly acknowledge sidebar lag from this. We add a `RefreshScheduler` that (a) trailing-debounces per `repoID` 250 ms beyond the FSEvents coalesce, and (b) caps total concurrent refreshes globally at 2.

**Files:**
- Create: `tian/Utilities/RefreshScheduler.swift`
- Create: `tianTests/RefreshSchedulerTests.swift`
- Modify: `tian/Tab/SpaceGitContext.swift` (route FSEvents-driven and pwd-driven refreshes through the scheduler)

### Steps

- [ ] **3.1: Write failing test for `RefreshScheduler`**

Create `tianTests/RefreshSchedulerTests.swift`:

```swift
import Testing
import Foundation
@testable import tian

@MainActor
struct RefreshSchedulerTests {

    @Test func coalescesRapidSubmitsForSameKey() async throws {
        var fired: [String] = []
        let scheduler = RefreshScheduler<String>(
            debounce: .milliseconds(30),
            maxConcurrent: 4
        ) { key in
            fired.append(key)
        }

        scheduler.schedule(key: "repo-a")
        scheduler.schedule(key: "repo-a")
        scheduler.schedule(key: "repo-a")

        try await Task.sleep(for: .milliseconds(80))

        #expect(fired == ["repo-a"])
    }

    @Test func capsConcurrentExecutions() async throws {
        actor Counter {
            var inFlight = 0
            var peak = 0
            func enter() { inFlight += 1; peak = max(peak, inFlight) }
            func exit() { inFlight -= 1 }
            func snapshot() -> Int { peak }
        }
        let counter = Counter()

        let scheduler = RefreshScheduler<String>(
            debounce: .milliseconds(5),
            maxConcurrent: 2
        ) { _ in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(40))
            await counter.exit()
        }

        for i in 0..<6 {
            scheduler.schedule(key: "k\(i)")
        }

        try await Task.sleep(for: .milliseconds(400))

        let peak = await counter.snapshot()
        #expect(peak <= 2)
    }
}
```

- [ ] **3.2: Run the test and verify it fails**

```
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS' -only-testing:tianTests/RefreshSchedulerTests
```

Expected: build failure ("cannot find type 'RefreshScheduler'").

- [ ] **3.3: Implement `RefreshScheduler`**

Create `tian/Utilities/RefreshScheduler.swift`:

```swift
import Foundation

/// Trailing-edge per-key debouncer with a global concurrency cap.
///
/// Designed for git refresh under FSEvents churn: each repo gets its own
/// debounce window, and only `maxConcurrent` refreshes run in parallel
/// regardless of repo count.
@MainActor
final class RefreshScheduler<Key: Hashable & Sendable> {
    typealias Handler = @Sendable (Key) async -> Void

    private let debounce: Duration
    private let handler: Handler
    private let semaphore: AsyncSemaphore

    private var pending: [Key: Task<Void, Never>] = [:]

    init(debounce: Duration, maxConcurrent: Int, handler: @escaping Handler) {
        self.debounce = debounce
        self.handler = handler
        self.semaphore = AsyncSemaphore(limit: maxConcurrent)
    }

    /// Schedule a refresh for `key`. Replaces any pending refresh for the same key.
    func schedule(key: Key) {
        pending[key]?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            self.pending.removeValue(forKey: key)
            await self.semaphore.acquire()
            defer { Task { await self.semaphore.release() } }
            await self.handler(key)
        }
        pending[key] = task
    }

    func cancel(key: Key) {
        pending.removeValue(forKey: key)?.cancel()
    }

    func cancelAll() {
        for task in pending.values { task.cancel() }
        pending.removeAll()
    }
}

/// Tiny async semaphore (no blocking).
actor AsyncSemaphore {
    private let limit: Int
    private var inFlight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            inFlight = max(0, inFlight - 1)
        }
    }
}
```

- [ ] **3.4: Regenerate project + run tests**

```
xcodegen generate
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS' -only-testing:tianTests/RefreshSchedulerTests
```

Expected: 2 tests pass.

- [ ] **3.5: Commit the scheduler**

```
git add tian/Utilities/RefreshScheduler.swift tianTests/RefreshSchedulerTests.swift project.yml
git commit -m "✨ feat(util): RefreshScheduler — per-key debounce + global concurrency cap"
```

- [ ] **3.6: Route SpaceGitContext through the scheduler**

In `tian/Tab/SpaceGitContext.swift`, add a stored property near the existing `inFlightTasks`:

```swift
    private lazy var refreshScheduler = RefreshScheduler<GitRepoID>(
        debounce: .milliseconds(250),
        maxConcurrent: 2
    ) { [weak self] repoID in
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard let dir = self.repoDirectories[repoID] else { return }
            self.refreshRepo(repoID: repoID, directory: dir)
        }
    }
```

Find the FSEvents handler around lines 358-376 and replace the body of the watcher closure:

```swift
        let watcher = GitRepoWatcher(watchPaths: watchPaths) { [weak self] paths in
            let affectsPR = GitRepoWatcher.pathsAffectPRState(
                paths,
                canonicalCommonDir: canonicalCommonDir
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                if affectsPR { self.prCache.evict(repoID: repoID) }
                self.refreshScheduler.schedule(key: repoID)
            }
        }
```

Find `paneWorkingDirectoryChanged` (line 77) — for the same-repo refresh branch (around line 86) and the new-repo branch (around line 119), replace direct `refreshRepo(repoID:directory:)` calls with:

```swift
        self.repoDirectories[repoID] = newDirectory  // ensure scheduler can resolve
        self.refreshScheduler.schedule(key: repoID)
```

Leave the *initial* repo detection (`detectRepo`) flow alone — it's once per pwd-into-new-dir and not the storm path.

In the teardown / `clearAll` path (around line 162), add:

```swift
        refreshScheduler.cancelAll()
```

- [ ] **3.7: Build + run existing SpaceGitContext tests**

```
scripts/build.sh Debug
xcodebuild test -scheme tian -derivedDataPath .build -destination 'platform=macOS' -only-testing:tianTests/SpaceGitContextTests
```

Expected: clean build, existing tests still pass. If a test asserts synchronous refresh-on-FSEvents, update it to await the scheduler's debounce window (`Task.sleep(for: .milliseconds(300))`).

- [ ] **3.8: Manual smoke test**

Open the app on a repo with an active dev server / build that touches files. Confirm sidebar git status updates lag at most ~500 ms behind file changes (was previously thrashing). With multiple pinned repos all churning, confirm at most 2 git subprocesses run concurrently.

- [ ] **3.9: Commit**

```
git add tian/Tab/SpaceGitContext.swift
git commit -m "⚡ perf(git): debounce + cap concurrent repo refreshes

Routes FSEvents- and pwd-driven refreshes through RefreshScheduler so
N pinned repos churning during a build cause at most 2 concurrent git
subprocesses, and same-repo bursts coalesce to a single refresh."
```

---

## Task 4: Throttle / pause `TimelineView` animations when not in use

**Why:** `tian/View/Shared/RainbowGlowBorder.swift:44,67`, `tian/View/Sidebar/BusyDotView.swift:11`, `tian/View/TabBar/AuroraCapsuleFill.swift:20` each tick a `TimelineView` at 30 FPS. Multiple instances coexist (every busy tab + every sidebar busy dot + every focus border). Each frame re-evaluates `body` and pulls from `PaneStatusManager` (Task 5 will scope that — but cutting tick count is an independent win). Drop to 12 FPS (`1.0/12.0`) and add a `paused` parameter so off-screen / non-busy callers can stop the timeline entirely.

**Files:**
- Modify: `tian/View/Shared/RainbowGlowBorder.swift`
- Modify: `tian/View/Sidebar/BusyDotView.swift`
- Modify: `tian/View/TabBar/AuroraCapsuleFill.swift`
- Inspect call sites of `RainbowGlow`, `RainbowBorder`, `BusyDotView`, `AuroraCapsuleFill` to thread the `paused` parameter through.

This is a structural change with no easy unit test. We rely on code review + Instruments verification.

### Steps

- [ ] **4.1: Add `paused` to `RainbowGlow` and `RainbowBorder`**

In `tian/View/Shared/RainbowGlowBorder.swift`, change:

```swift
struct RainbowBorder: View {
    var paused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion || paused {
            AngularGradient(colors: rainbowColors, center: .center)
                .mask {
                    RoundedRectangle(cornerRadius: glowCornerRadius)
                        .strokeBorder(lineWidth: 2)
                }
                .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 60)
                AngularGradient(
                    colors: rainbowColors,
                    center: .center,
                    startAngle: angle,
                    endAngle: angle + .degrees(360)
                )
                .mask {
                    RoundedRectangle(cornerRadius: glowCornerRadius)
                        .strokeBorder(lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct RainbowGlow: View {
    var paused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            (reduceMotion || paused)
                ? .animation(minimumInterval: nil, paused: true)
                : .animation(minimumInterval: 1.0 / 12.0)
        ) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t * 60)
            let breathe = rainbowBreathe(t)

            let gradient = AngularGradient(
                colors: rainbowColors,
                center: .center,
                startAngle: angle,
                endAngle: angle + .degrees(360)
            )

            ZStack {
                gradient
                    .mask {
                        RoundedRectangle(cornerRadius: glowCornerRadius)
                            .strokeBorder(lineWidth: 18)
                    }
                    .blur(radius: 18)
                    .opacity(0.35 * breathe)

                gradient
                    .mask {
                        RoundedRectangle(cornerRadius: glowCornerRadius)
                            .strokeBorder(lineWidth: 8)
                    }
                    .blur(radius: 8)
                    .opacity(0.6 * breathe)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
```

- [ ] **4.2: Lower frame rate of `BusyDotView` and `AuroraCapsuleFill`**

In `tian/View/Sidebar/BusyDotView.swift:11`, change:

```swift
TimelineView(reduceMotion ? .animation(minimumInterval: nil, paused: true) : .animation(minimumInterval: 1.0 / 12.0)) { timeline in
```

In `tian/View/TabBar/AuroraCapsuleFill.swift:20`, same change to `1.0 / 12.0`.

- [ ] **4.3: Pause borders on non-busy / non-focused panes**

Find the call sites of `RainbowBorder` / `RainbowGlow` (likely in a pane overlay view). Use `grep -rn "RainbowBorder\|RainbowGlow" tian/View`. At each call site that already has access to a "is this pane busy / focused / window-active" condition, pass `paused: !isActiveAndVisible`.

For windows that are not key (`NSApp.keyWindow !== window`), prefer pausing the animations entirely. If a single source-of-truth `WindowActivityState` doesn't exist, defer this and only pass `paused: !isBusy` for the busy-driven aurora.

- [ ] **4.4: Build and visually confirm**

```
scripts/build.sh Debug
```

Open the app, drive a Claude pane to busy, confirm aurora still animates (just smoother / lower CPU). Switch to another window, confirm the rainbow borders in the previous window stop animating. Open Activity Monitor → tian → CPU; confirm idle CPU dropped meaningfully (target: < 2% with one busy pane in foreground; was previously higher).

- [ ] **4.5: Commit**

```
git add tian/View/Shared/RainbowGlowBorder.swift tian/View/Sidebar/BusyDotView.swift tian/View/TabBar/AuroraCapsuleFill.swift tian/View/  # plus any call sites you changed
git commit -m "⚡ perf(view): drop animation tick to 12 FPS, pause when off-scope

Halves per-frame body() re-evaluations for RainbowBorder/RainbowGlow,
BusyDotView, and AuroraCapsuleFill. Adds paused: parameter so callers
can stop timelines for non-key windows or non-busy panes."
```

---

## Task 5: Scope `PaneStatusManager` — per-pane observable session state

> **Implementation note:** The original design here was a "router model" — `PaneStatusManager` would lose its observable state entirely and become a thin write-through to per-pane storage. After surveying ~40 affected tests (and the `SessionSerializer` + `IPCCommandHandler` contracts that read manager state directly), this task narrowed to a **dual-write** design: the manager keeps its authoritative state and API, and `PaneViewModel` gains observable mirrors that the per-pane reader (`PaneView`) consults instead. The per-pane reader is where the observation cascade actually originated, so this captures the meaningful perf win without breaking the broader contract surface. Rationale captured in commit 1362631's message.

**Why:** `tian/Pane/PaneStatusManager.swift:15-95` is a `@MainActor @Observable` singleton holding `[UUID: ClaudeSessionState]` and `[UUID: PaneStatus]`. Because Swift `Observation` tracks at the property level, *any* dictionary mutation invalidates *every* view that read the property — even if the change is for a pane the view doesn't render. With the rainbow aurora driving session-state writes ~1 Hz, the entire chrome re-renders constantly.

**Files:**
- Modify: `tian/Pane/PaneViewModel.swift` — add observable per-pane mirrors and accessors.
- Modify: `tian/Pane/PaneStatusManager.swift` — add a weak pane registry and dual-write to the registered PVM on every setter.
- Modify: `tian/View/.../PaneView.swift` — switch the per-pane reader to consult the owning PVM's mirror.
- Aggregate readers (`TabBarItemView`, `SidebarSpaceRowView`, `SpaceStatusAreaView`) — untouched; they iterate all panes anyway and are not the cascade source.
- `tianTests/PaneStatusManagerTests.swift` — existing behavioural tests preserved; the manager's authoritative API is unchanged.

### What was implemented (commits 1362631 and 1d2fe09)

- **Manager retains its existing API and authoritative state.** `sessionStates` and `paneStatuses` continue to live on `PaneStatusManager.shared`; `SessionSerializer` and `IPCCommandHandler` still read them directly. No call-site re-pointing was needed for those contracts.
- **`PaneViewModel` gained observable mirrors:** `var sessionStates: [UUID: ClaudeSessionState]` and `var paneStatuses: [UUID: PaneStatus]`, plus accessors `sessionState(forPane:)` and `paneStatus(forPane:)`. Because `PaneViewModel` is already `@MainActor @Observable`, mirror mutations participate in Observation at PVM granularity — a write on pane A's PVM does not invalidate `PaneView`s reading from pane B's PVM.
- **Manager gained a weak pane registry:** `private var ownersByPane: [UUID: WeakBox<PaneViewModel>]`, plus `registerPane(_:owner:)` / `unregisterPane(_:)`. `PaneViewModel` registers every leaf on init / split / replace and unregisters on close / deinit.
- **Existing setters dual-write:** every authoritative mutation in the manager (`setSessionState`, `clearSessionState`, `setStatus`, `clearStatus`, `clearAll(for:)`) writes the manager's own dictionary *and* mirrors the change into `owner(of: paneID)?.sessionStates[paneID]` / `paneStatuses[paneID]`. The two stores stay in lock-step.
- **`PaneView` switched to the per-pane reader:** the rainbow aurora and per-pane status indicators now read `viewModel.sessionState(forPane: paneID)` / `viewModel.paneStatus(forPane: paneID)` instead of `PaneStatusManager.shared.sessionState(for:)`. This is the perf win — the high-frequency reader no longer participates in the singleton's global Observation invalidation.
- **Aggregate readers untouched.** `TabBarItemView`, `SidebarSpaceRowView`, `SpaceStatusAreaView` still call `PaneStatusManager.shared.hasSessionState(_:in:)` etc. — they iterate all panes by definition, so scoping wouldn't help them.
- **Prune-on-read in `owner(of:)`** drops registry entries whose `WeakBox.value` has gone nil, bounding registry size across long-running sessions where panes come and go.

### Trade-offs

- **Two sources of state.** The manager's dict and the PVM's mirror are both authoritative-looking; correctness depends on every setter dual-writing. Mitigated by routing all mutations through the small `setSessionState` / `setStatus` / clear surface — there is no other write path.
- **No router-level test for cross-pane isolation.** The original plan included a unit test that wrote to pane A and asserted no Observation fired on pane B. With the dual-write design, both writes go through the same singleton, and Observation isolation manifests at the SwiftUI body-eval level — not directly observable from a unit test. Verified by code inspection plus the manual Instruments smoke test.

---

## Self-Review

- **Spec coverage:** Each of the five top-priority audit findings has a dedicated task. Secondary findings (synchronous I/O on quit, observer leak in `WorkspaceWindowController`, `prFetchTasks` unbounded growth, tree-copy cost) are deferred — gather Instruments evidence first to avoid speculative work.
- **Placeholder scan:** No "TBD"s, no "implement later"s, no "add appropriate error handling". The keybinding registry steps note that exact API names should be verified against the existing file in 2.1 — that's a guarded assumption, not a placeholder. The pane-registration call sites in 5.6 say "wherever leaves are removed" — engineer must locate them, but the inserted code is concrete.
- **Type consistency:** `EventCoalescer<UUID, String>` for title/pwd, `<UUID, Void>` for bell. `RefreshScheduler<GitRepoID>`. `KeyChord` consistent across registry + tests. `WeakBox<PaneViewModel>` scoped private to `PaneStatusManager.swift`.
- **Order:** Tasks 1–4 are independent; Task 5 builds on no prior task but should ship last because it's the biggest refactor and most regression-prone. Tasks 3 and 5 both touch `SpaceGitContext` / `PaneStatusManager` neighbourhoods but in non-conflicting ways.
- **Each task is its own PR:** Commit messages and surface area are scoped accordingly.

---

## Out of scope (deferred)

These secondary findings from the audit were intentionally not turned into tasks here. Profile first, then add as follow-up plans:

- `WorkspaceWindowController.observeActiveWorkspaceName()` — the `withObservationTracking` rearm pattern is canonical (one-shot observer; no leak). Per-name-change `Task { @MainActor in ... }` allocation is real but the path runs only on workspace rename — not a perf hot path.
- `tian/View/Sidebar/SidebarExpandedContentView.swift:12,103-105` — memoize `flatItems` and add an index map. Add when sidebars exceed ~50 rows in practice.
- `tian/View/Sidebar/SpaceStatusAreaView.swift:35` — extract `groupSessionsByRepo()` from `body` into cached `@State`.
- `tian/Persistence/SessionSerializer.swift:94-132` — move JSON encode + atomic write off main. Quit-time only.
- `tian/Pane/PaneNode.swift:123` — structural sharing for split-tree mutations. Consider only if profiling shows splits at depth >5 cause hitches.
- `tian/View/DebugOverlayView.swift:35` — only fire timer when overlay is visible.
