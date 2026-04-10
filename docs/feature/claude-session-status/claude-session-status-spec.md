# SPEC: Claude Session Status

**Based on:** docs/feature/claude-session-status/claude-session-status-prd.md v1.3
**Author:** CTO Agent
**Date:** 2026-04-09
**Version:** 1.1
**Status:** Approved

---

## 1. Overview

This spec covers the remaining implementation work to bring the Claude Session Status feature to parity with the PRD v1.3. The feature tracks Claude Code session lifecycle state per-pane (active, busy, idle, needs_attention, inactive) and surfaces each active session as an individual color-coded dot on the sidebar Space row.

Significant portions of this feature are already implemented. The `ClaudeSessionState` enum exists at `aterm/Core/ClaudeSessionState.swift` with the correct five cases and priority-based `Comparable` conformance. The `PaneStatusManager` at `aterm/Pane/PaneStatusManager.swift` already has `sessionStates` storage, `setSessionState`, `clearSessionState`, `sessionState(for:)`, `sessionStates(in:)`, and the `clearStatus`/`clearAll` methods already clear both label and session state. The `IPCCommandHandler.handleStatusSet` at `aterm/Core/IPCCommandHandler.swift` already accepts the optional `state` parameter, validates it against `ClaudeSessionState`, and calls the appropriate manager methods. The sidebar views `ClaudeSessionDotsView`, `BusyDotView`, `SpaceStatusAreaView`, and `SidebarSpaceRowView` already render per-session dots with priority sorting. Pane cleanup in `PaneViewModel.closePane` already calls `PaneStatusManager.shared.clearStatus(paneID:)`.

This spec addresses the **six remaining gaps** between the PRD and the current implementation:

1. **CLI `StatusSet` command** -- needs a `--state` flag and `--label` must become optional (FR-009, FR-010)
2. **Busy dot animation** -- PRD specifies a smooth opacity pulse (1.0 to 0.4 to 1.0 over ~2s), not the current spinning rainbow gradient (FR-023)
3. **Reduce Motion accessibility** -- `BusyDotView` explicitly ignores Reduce Motion; PRD requires it to be respected (FR-023)
4. **Status label coexistence** -- `SpaceStatusAreaView` hides the free-form label when sessions exist; PRD says they must coexist (FR-019, FR-024)
5. **Second-line render condition** -- the label-only condition is too narrow; the second line must render when either a label or sessions exist (FR-019)
6. **Debug logging for state transitions** -- the existing `Log.ipc.debug` call in `setSessionState` is present but should be verified against NFR-005

---

## 2. Database Schema

Not applicable. Claude session state is ephemeral, in-memory only, stored in `PaneStatusManager.sessionStates: [UUID: ClaudeSessionState]`. No persistence, no schema changes. Per PRD NG1, state is not persisted across app restarts.

### Data Flow

1. Claude Code hook fires (e.g., `SessionStart`)
2. Hook command executes: `aterm-cli status set --state active`
3. CLI parses `--state active`, constructs IPC request with `params: ["state": "active"]`
4. IPC request sent over Unix domain socket to aterm app
5. `IPCCommandHandler.handleStatusSet` validates the state string, calls `statusManager.setSessionState(paneID:state:)`
6. `PaneStatusManager.sessionStates` dictionary updates (observed property)
7. `SidebarSpaceRowView` re-evaluates `PaneStatusManager.shared.sessionStates(in: space)`
8. `SpaceStatusAreaView` re-renders with updated dots
9. View update completes within one SwiftUI render cycle (~16ms)

---

## 3. API Layer

### Existing IPC Commands (Already Implemented)

The `status.set` and `status.clear` IPC commands at `aterm/Core/IPCCommandHandler.swift` lines 437-485 already handle the `state` parameter correctly. No changes needed to the IPC layer.

| Command | Parameters | Behavior | Status |
|---------|-----------|----------|--------|
| `status.set` | `label` (optional string), `state` (optional string) | Sets label and/or session state independently. At least one required. State validated against `ClaudeSessionState.allCases`. | Already implemented |
| `status.clear` | (none, uses env paneId) | Clears both label and session state for the pane. | Already implemented |

### Server Functions

None required. The IPC handler dispatches directly to `PaneStatusManager` methods on the main actor.

---

## 4. State Management

### Existing State (Already Implemented)

| Storage | Location | Type | Description |
|---------|----------|------|-------------|
| Session states | `PaneStatusManager.sessionStates` | `[UUID: ClaudeSessionState]` | Per-pane Claude session state. Observable. |
| Status labels | `PaneStatusManager.statuses` | `[UUID: PaneStatus]` | Per-pane free-form label. Observable. Independent from session states. |

### Query Methods (Already Implemented)

| Method | Returns | Called From |
|--------|---------|------------|
| `sessionStates(in: SpaceModel)` | `[(paneID: UUID, state: ClaudeSessionState)]` sorted by priority, excluding nil and inactive | `SidebarSpaceRowView.body` |
| `latestStatus(in: SpaceModel)` | `PaneStatus?` (most recently updated label across all panes in space) | `SpaceStatusAreaView.body` |
| `sessionState(for: UUID)` | `ClaudeSessionState?` | Not currently used by views, available for future use |

### Invalidation

State changes in `PaneStatusManager` are observed by SwiftUI via `@Observable`. When `sessionStates` or `statuses` dictionaries are mutated, any view that reads from those properties re-renders automatically. No manual invalidation, no cache keys, no stale time.

### Local State

`BusyDotView` uses `@State private var rotation: Double = 0` for its current spinning animation. This will change to `@State private var isAnimating: Bool = false` for the opacity pulse (see Section 5.3).

---

## 5. Component Architecture

### 5.1 Feature Directory Structure

No new directories or files are created. All changes are modifications to existing files:

```
aterm/
  View/Sidebar/
    BusyDotView.swift          -- MODIFY: replace spinning rainbow with opacity pulse + Reduce Motion
    SpaceStatusAreaView.swift   -- MODIFY: show status label alongside sessions
  aterm-cli/
    CommandRouter.swift         -- MODIFY: add --state flag to StatusSet, make --label optional
```

### 5.2 CLI `StatusSet` Command Changes

**File:** `aterm-cli/CommandRouter.swift`, lines 541-554 (the `StatusSet` struct)

**Current behavior:** `StatusSet` has a single required `@Option` named `--label`. It sends `params: ["label": .string(label)]`.

**Required changes:**

- Add an optional `@Option` named `--state` with help text "Claude session state (active, busy, idle, needs_attention, inactive)."
- Change `--label` from required to optional (change from `@Option` non-optional to `@Option` optional `String?`).
- Add validation in `run()`: if both `label` and `state` are nil, throw `CLIError.general("At least one of --label or --state must be provided.")`. This exits with code 1 (non-zero), consistent with standard CLI error conventions. Do not use `CleanExit.message` here -- that exits with code 0, which would incorrectly signal success.
- Build the params dictionary conditionally: only include `"label"` if `label` is non-nil, only include `"state"` if `state` is non-nil.
- Per PRD FR-011, the CLI must NOT validate the `--state` value itself -- it passes the raw string through. Server-side validation happens in `IPCCommandHandler`.

**StatusGroup abstract text:** Update from "Manage pane status labels." to "Manage pane status." (remove "labels" since the command now handles both labels and session state).

### 5.3 `BusyDotView` Animation Changes

**File:** `aterm/View/Sidebar/BusyDotView.swift`

**Current behavior:** An 8pt circle filled with a spinning `AngularGradient` of rainbow colors, rotating 360 degrees over 1.5s forever. Explicitly ignores Reduce Motion.

**Required changes per PRD FR-023:**

The busy dot must use a smooth opacity pulse: opacity cycles from 1.0 to 0.4 and back over approximately 2 seconds. The fill color must be blue (the color already defined in `ClaudeSessionDotsView.dotView(for:)` is not used since `BusyDotView` handles its own rendering -- the blue color must be `Color(red: 0.2, green: 0.55, blue: 1.0)`, matching the existing palette used by other dots in `ClaudeSessionDotsView`).

The view must read the `@Environment(\.accessibilityReduceMotion)` property. When Reduce Motion is enabled, the dot must render as a static blue circle at full opacity (no animation). When Reduce Motion is disabled, the opacity pulse animation runs.

**Animation approach:** Use a `@State private var isAnimating: Bool` toggled in `onAppear`. Apply a SwiftUI `.opacity()` modifier driven by the state, with `.animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true))`. The `easeInOut` with `autoreverses: true` produces the smooth 1.0 to 0.4 to 1.0 cycle. Duration of 1.0 second per half-cycle means ~2 seconds for the full round trip. This uses SwiftUI framework-level animation per NFR-002 (no manual timers).

The removal of the rainbow spinning gradient also removes the dependency on `rainbowColors` from `RainbowGlowBorder.swift` in this specific view.

### 5.4 `SpaceStatusAreaView` Label Coexistence Changes

**File:** `aterm/View/Sidebar/SpaceStatusAreaView.swift`

**Current behavior (lines 73-84):** The free-form status label is only rendered when there are no repo lines AND no sessions. Specifically:

```
} else if hasSessions {
    ClaudeSessionDotsView(states: ...)
}

if let status = latestStatus, !hasRepoLines && !hasSessions {
    Text(...)
}
```

This means when sessions are present, the label is hidden. The PRD (FR-024) explicitly states: "The existing free-form status label must continue to display in the Space row as it does today, independently of the Claude session dots. A Space can show both a status label and session dots simultaneously."

**Required changes:**

The label rendering condition must change so that the label is shown whenever it exists, regardless of whether sessions or repo lines are present. The label should appear on its own line within the VStack, below any repo status lines and/or session dots.

> **PRD deviation note:** PRD FR-019 states that dots and label should appear "inline on the same row." This spec places the label on a separate line instead, matching the current `SpaceStatusAreaView` VStack layout pattern. Rationale: the sidebar is narrow (~180pt), and inline layout of 8pt dots plus a label of up to 50 characters would be cramped. A separate line provides better readability and is consistent with how the existing implementation structures repo status lines and labels in the VStack.

The revised logic for the body VStack in `SpaceStatusAreaView`:

1. If there are repo lines: render repo status lines as today (they already include Claude dots inline via `RepoStatusLineView`). Non-repo dots rendered separately below when applicable (multi-repo case).
2. Else if there are sessions (but no repo lines): render standalone `ClaudeSessionDotsView` with all session states.
3. After the repo/session section, independently: if `latestStatus` is non-nil, render the label text. This condition no longer checks for the absence of repo lines or sessions -- it simply renders whenever a label exists.

This preserves the existing layout for repo lines (which inline their own claude dots), adds the standalone dots for non-repo spaces with sessions, and always shows the label text below when present.

**FR-019 second-line render condition:** The VStack must render (the "second line" exists) whenever:
- There are repo lines, OR
- There are non-nil/non-inactive sessions, OR
- There is a status label

If none of these conditions are true, the VStack is empty (no second line). This is already the case structurally -- each branch only adds children when its condition is met -- but the label must now be included as an independent condition.

### 5.5 Accessibility

**SidebarSpaceRowView** at `aterm/View/Sidebar/SidebarSpaceRowView.swift` already has an `accessibilityDescription(sessions:)` method (lines 15-66) that includes session counts and `needs_attention` counts in the accessibility value. This satisfies FR-025. No changes needed.

---

## 6. Navigation

No new routes or navigation changes. The feature is entirely within the existing sidebar Space row UI.

---

## 7. Type Definitions

### Existing Types (No Changes)

| Type | File | Fields | Description |
|------|------|--------|-------------|
| `ClaudeSessionState` | `aterm/Core/ClaudeSessionState.swift` | `needsAttention`, `busy`, `active`, `idle`, `inactive` (raw strings: `needs_attention`, `busy`, `active`, `idle`, `inactive`) | Enum with `Comparable` by priority. Already `CaseIterable`, `Sendable`, `Equatable`. |
| `PaneStatus` | `aterm/Pane/PaneStatusManager.swift` | `label: String`, `updatedAt: Date` | Free-form status label. Unchanged. |

No new types are introduced by this spec.

---

## 8. Analytics Implementation

Not applicable. The PRD does not define any analytics events. State transitions are logged at debug level via `Log.ipc` (NFR-005), which is already implemented in `PaneStatusManager.setSessionState`.

---

## 9. Permissions & Security

### Access Policies

| Operation | Who | Condition |
|-----------|-----|-----------|
| Set session state | Any process with `ATERM_SOCKET` and `ATERM_PANE_ID` env vars | Pane must exist in the split tree |
| Clear session state | Same as above | Pane must exist |

The IPC system has no authentication -- any process that knows the socket path and pane UUID can send commands. This is acceptable because the socket is at `$TMPDIR/aterm-<uid>.sock` (user-scoped) and pane UUIDs are injected only into child shell processes. This is consistent with the existing security model for all IPC commands.

### Client-Side Guards

- `aterm-cli` checks for `ATERM_SOCKET` in `AtermEnvironment.fromEnvironment()`. If absent, the CLI exits with an error. This prevents the CLI from being used outside aterm.
- The `--state` value is NOT validated client-side (FR-011). Server-side validation in `IPCCommandHandler` returns a descriptive error with valid values.
- No feature flags needed. The `--state` parameter is optional and backward-compatible.

---

## 10. Performance Considerations

**IPC latency:** State transition via Unix domain socket IPC is a local operation. The IPC server processes requests on the main actor. Expected latency is well under 10ms, satisfying NFR-001's 100ms requirement.

**Animation CPU:** The opacity pulse uses SwiftUI's built-in `.animation(.easeInOut)` modifier, which is GPU-composited. It does not trigger view body re-evaluation on each frame. This is significantly lighter than the current `TimelineView`-based spinning gradient (which re-evaluates every frame). The change actually reduces CPU usage.

**Aggregation:** `PaneStatusManager.sessionStates(in:)` iterates all tabs and all leaves in a space. With typical counts (1-10 panes per space), this is O(n) and negligible (NFR-003).

**No pagination needed.** The maximum number of dots displayed is bounded by the number of panes in a space, which is practically limited to single digits.

**Lazy rendering:** `SpaceStatusAreaView` only queries `PaneStatusManager` when the Space row is visible in the sidebar scroll view. Off-screen rows are not computed.

---

## 11. Migration & Deployment

No migrations. No feature flags. No deployment ordering concerns.

The changes are purely additive:
- CLI gets an additional optional flag
- `BusyDotView` changes its animation style
- `SpaceStatusAreaView` shows the label in more cases

**Backward compatibility:** Existing `aterm-cli status set --label "..."` calls continue to work because `--label` remains valid (it just becomes optional). The IPC protocol version does not change -- the `state` parameter was already accepted server-side.

**Rollback:** If the CLI change needs to be reverted, the server-side `handleStatusSet` already handles `state: nil` gracefully (it only processes state if provided). The view changes are visual only and can be reverted independently.

---

## 12. Implementation Phases

### Phase 1: CLI Extension (FR-009, FR-010, FR-011)

**Scope:** Modify `StatusSet` in `aterm-cli/CommandRouter.swift` to add `--state` optional flag and make `--label` optional with at-least-one validation. Update `StatusGroup` abstract text.

**Files modified:** `aterm-cli/CommandRouter.swift`

**Independently testable:** Yes. After this phase, `aterm-cli status set --state active` works end-to-end (the server already handles it). Manual test: run `aterm-cli status set --state busy` in an aterm pane and verify the dot appears in the sidebar. Also test `aterm-cli status set` with no flags returns an error. Test `aterm-cli status set --label "test"` still works (backward compat). Test `aterm-cli status set --state active --label "test"` sets both.

### Phase 2: Busy Dot Animation + Reduce Motion (FR-023)

**Scope:** Replace `BusyDotView`'s spinning rainbow gradient with a blue opacity pulse. Add `@Environment(\.accessibilityReduceMotion)` support.

**Files modified:** `aterm/View/Sidebar/BusyDotView.swift`

**Independently testable:** Yes. Set a pane's state to `busy` and verify the dot pulses blue. Enable Reduce Motion in System Settings > Accessibility > Display and verify the dot is static blue. Verify no rainbow gradient appears.

### Phase 3: Status Label Coexistence (FR-019, FR-024)

**Scope:** Modify `SpaceStatusAreaView` to render the free-form status label independently of session presence. The label appears below repo lines and/or session dots whenever it exists.

**Files modified:** `aterm/View/Sidebar/SpaceStatusAreaView.swift`

**Independently testable:** Yes. Set both `--state busy --label "Testing coexistence"` on a pane. Verify the sidebar shows both the blue dot AND the label text. Verify that clearing just the label (by setting a new label or clearing) does not affect the dot, and vice versa.

### Phase 4: Verification and Polish

**Scope:** End-to-end verification of all PRD user flows. Verify accessibility values. Run unit tests.

**No files modified.** This phase is testing only.

---

## 13. Test Strategy

### Mapping to PRD Success Criteria

The PRD does not define explicit success metrics (no Section 8 with numeric targets). The non-functional requirements serve as the success criteria:

| NFR | Target | Verification Method | Phase |
|-----|--------|---------------------|-------|
| NFR-001: IPC-to-sidebar latency | Under 100ms | Manual QA with `aterm-cli` timing. Instruments profiling if needed. | Phase 4 |
| NFR-002: Animation CPU usage | No excessive CPU | Activity Monitor during busy state. Compare CPU with old rainbow vs new opacity pulse. | Phase 2 |
| NFR-003: Aggregation complexity | O(n) | Code review of `sessionStates(in:)` -- already O(n). | Already satisfied |
| NFR-004: No new IPC commands | Zero new commands | Code review -- `status.set` extended, not new. | Already satisfied |
| NFR-005: Debug logging | State transitions logged with pane ID, old state, new state | Verify `Log.ipc.debug` output in Console.app during state transitions. | Phase 4 |

### Mapping to Functional Requirements

| FR ID | Test Description | Type | Preconditions | Phase |
|-------|-----------------|------|---------------|-------|
| FR-001 | Verify `ClaudeSessionState` enum has exactly 5 cases with correct raw values | Unit | None | Already satisfied (enum exists) |
| FR-002 | Verify each hook produces the correct state transition (table in PRD) | E2E | Claude Code hooks configured | Phase 4 |
| FR-003 | Verify any state can transition to any other state without error | Unit | `PaneStatusManager` instance | Already satisfied |
| FR-004 | Verify pane close removes session state from manager | Unit | Pane with session state set | Already satisfied |
| FR-005 | Verify `status.set` accepts `state` without `label`, `label` without `state`, and both together | Integration | IPC server running | Already satisfied (server-side) |
| FR-006 | Verify invalid `--state` value returns error with valid values list | Integration | IPC server running | Already satisfied (server-side) |
| FR-007 | Verify setting `state` does not affect `label` and vice versa | Integration | Pane with both set | Already satisfied (server-side) |
| FR-008 | Verify `status.clear` clears both label and session state | Integration | Pane with both set | Already satisfied |
| FR-009 | CLI `status set --state active` sends correct IPC request | Integration | aterm running | Phase 1 |
| FR-010 | CLI `status set` with no flags prints error and exits non-zero | Unit (CLI) | None | Phase 1 |
| FR-011 | CLI passes `--state` value through without validation | Integration | aterm running, invalid state value | Phase 1 |
| FR-012 | Session state tracked per-pane in `PaneStatusManager.sessionStates` | Unit | Manager instance | Already satisfied |
| FR-013 | Pane with no session state returns nil | Unit | Manager instance | Already satisfied |
| FR-014 | Pane close removes both label and session state | Unit | Manager instance | Already satisfied |
| FR-015 | Space row shows dots for non-nil non-inactive sessions, one per pane | Visual QA | Space with multiple Claude sessions | Phase 4 |
| FR-016 | Dots sorted by priority (needs_attention > busy > active > idle) | Visual QA + unit test of sort | Multiple sessions in different states | Already satisfied (sort in `sessionStates(in:)`) |
| FR-017 | No dots when all panes are nil or inactive | Visual QA | Space with no sessions or all inactive | Phase 4 |
| FR-018 | Dots update reactively on state change | Visual QA | Change state via CLI, observe sidebar | Phase 4 |
| FR-019 | Second line renders when label exists but no sessions, when sessions exist but no label, and when both exist | Visual QA | Various combinations | Phase 3 |
| FR-020 | Color mapping: green (active), blue (busy), gray (idle), orange (needs_attention) | Visual QA | One session per state | Phase 4 |
| FR-021 | No dots when no sessions in space | Visual QA | Empty space | Already satisfied |
| FR-022 | Dots do not displace existing row elements | Visual QA | Space with sessions | Already satisfied |
| FR-023 | Busy dot is smooth opacity pulse, respects Reduce Motion | Visual QA | Busy session + toggle Reduce Motion | Phase 2 |
| FR-024 | Status label and session dots coexist | Visual QA | `--state busy --label "text"` | Phase 3 |
| FR-025 | Accessibility value includes session counts and needs_attention count | VoiceOver QA or accessibility audit | Space with sessions | Already satisfied |
| FR-026 | Hook configuration documented in PRD Appendix A | Code review | N/A | Already satisfied (PRD has it) |
| FR-027 | Hooks use `$ATERM_CLI_PATH` | Code review of hook config | N/A | Already satisfied |
| FR-028 | Hooks are no-ops outside aterm | Manual test | Run hook command outside aterm | Already satisfied |

### Unit Tests

**ClaudeSessionState (already tested implicitly, verify coverage):**
- Priority ordering: `needsAttention > busy > active > idle > inactive`
- Raw value round-tripping: `ClaudeSessionState(rawValue: "needs_attention")` returns `.needsAttention`
- Invalid raw value: `ClaudeSessionState(rawValue: "thinking")` returns `nil`

**PaneStatusManager (already tested implicitly, verify coverage):**
- `setSessionState` followed by `sessionState(for:)` returns the set state
- `clearStatus` clears both label and session state
- `sessionStates(in:)` excludes nil and inactive, sorts by priority
- `setStatus` does not affect `sessionStates` and vice versa

**CLI StatusSet validation (new, Phase 1):**
- If the test harness supports it: verify `StatusSet` parsing accepts `--state` alone, `--label` alone, and both together
- Verify `StatusSet` with neither flag produces a validation error
- Note: CLI tests may not exist in the current test suite (no CLI test files found in `atermTests/`). If CLI-level unit tests are impractical, rely on integration testing.

### Integration Tests

**IPC round-trip (extend existing `IPCServerTests` or `IPCMessageTests`):**
- Send `status.set` with `state: "busy"` -- verify `PaneStatusManager.sessionStates` updated
- Send `status.set` with `state: "invalid"` -- verify error response with valid values
- Send `status.set` with only `state`, only `label`, both -- verify independent storage
- Send `status.clear` -- verify both cleared

### End-to-End Tests

**Happy path (manual, Phase 4):**
1. Start Claude Code in a pane with hooks configured
2. Observe green dot on `SessionStart`
3. Submit a prompt, observe blue pulsing dot on `UserPromptSubmit`
4. Wait for response, observe gray dot on `Stop`
5. Trigger a permission prompt, observe orange dot on `Notification(permission_prompt)`
6. Exit Claude Code, observe dot disappears on `SessionEnd`

**Multi-pane (manual, Phase 4):**
1. Three panes in one Space: one busy, one idle, one no session
2. Verify 2 dots: blue (busy) then gray (idle), sorted correctly
3. Change busy to needs_attention, verify dots re-sort: orange then gray

### Edge Case & Error Path Tests

| Edge Case (from PRD Section 8) | Test | Phase |
|-------------------------------|------|-------|
| EC-1: Claude crashes without SessionEnd | Verify pane retains last state; cleared on pane close | Phase 4 |
| EC-3: Sequential sessions in same pane | Set active -> inactive -> active; verify state resets correctly | Phase 4 |
| EC-4: State set without label, then label set without state | Verify both fields independent | Already covered |
| EC-5: status.clear with both set | Verify both cleared | Already covered |
| EC-7: One needs_attention + one inactive | Verify one orange dot, no dot for inactive | Phase 4 |
| EC-8: All inactive | Verify no dots | Phase 4 |
| EC-10: State set for non-existent pane | Verify IPC error "Pane not found" | Already covered |
| EC-11: Reduce Motion enabled | Verify static busy dot | Phase 2 |

### Performance & Load Tests

Not required for this feature. The operation is lightweight (dictionary lookup and SwiftUI view update). NFR-001 (100ms) is verified manually. The animation change (Phase 2) actually reduces CPU load compared to the current implementation.

---

## 14. Technical Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| CLI ArgumentParser breaking change when making `--label` optional | CLI commands that currently rely on `--label` being required may behave differently if called with no args (error message changes) | Low | The validation in `run()` produces a clear error. Existing scripts that always pass `--label` are unaffected. The error message format may change from ArgumentParser's built-in required-option error to a custom message. |
| BusyDotView animation flicker during state transitions | If a dot transitions from busy to idle and back rapidly, the animation may restart visually | Low | SwiftUI handles animation interruption gracefully. The opacity modifier transitions smoothly between states. If needed, add `.animation(.easeInOut, value: isAnimating)` to scope the animation. |
| SpaceStatusAreaView layout shift when label appears/disappears | Adding the label below dots may cause a visible layout shift in the sidebar | Low | The VStack already uses fixed spacing (2pt). The label line is ~10pt font, adding minimal height. The sidebar scroll view handles content size changes smoothly. |
| Reduce Motion environment not propagating in all contexts | `@Environment(\.accessibilityReduceMotion)` may not update if the view is deeply nested | Very Low | `BusyDotView` is a leaf view in the hierarchy. The environment value propagates through all parent views. SwiftUI guarantees this. |

---

## 15. Open Technical Questions

| Question | Context | Impact if Unresolved |
|----------|---------|---------------------|
| Should the busy dot blue color be extracted to a shared constant? | The color is pinned to `Color(red: 0.2, green: 0.55, blue: 1.0)` in both `ClaudeSessionDotsView` and `BusyDotView`. Should it be a shared constant in `Colors.swift`? | Minor inconsistency risk if colors drift. Low impact -- can be addressed as a follow-up. |
| PRD OQ#4: Should `status.clear` have selective clear (label-only or state-only)? | The PRD leaves this as TBD. Current implementation clears both. | No impact on this spec -- v1 clears both. Can be added later as a `--label-only` / `--state-only` flag on `status.clear`. |
| PRD OQ#5: Should busy pulse speed be configurable? | PRD leaves this as TBD. Spec hardcodes ~2s cycle. | No impact -- single hardcoded animation is sufficient for v1. |
| PRD OQ#7: Should `pane.list` include session state? | Low cost to add `sessionState` field to `handlePaneList` output. | No impact on this spec's scope. Can be added independently. |
| Should the `SpaceStatusAreaView` label be truncated to 50 characters even when displayed alongside dots? | Current code truncates to 50 characters via `String(status.label.prefix(50))`. With dots taking horizontal space, the available width for the label is reduced. | Minor -- SwiftUI's `lineLimit(1)` and `truncationMode(.tail)` handle overflow gracefully regardless of the 50-char prefix. |
