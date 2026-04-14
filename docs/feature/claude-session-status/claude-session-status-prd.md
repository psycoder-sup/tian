# PRD: Claude Session Status

**Author:** psycoder
**Date:** 2026-04-07
**Version:** 1.3
**Status:** Approved

---

## 1. Overview

Claude Session Status is an tian feature that tracks the lifecycle state of Claude Code sessions running inside terminal panes and surfaces that state visually in the sidebar. Each pane can independently report its Claude Code session state (active, busy, idle, needs_attention, inactive) via the existing `status.set` IPC command, extended with an optional `--state` parameter. The sidebar displays each active session as an individual color-coded dot on the Space row, sorted by priority (highest-priority state leftmost). This gives the developer per-session visibility without collapsing multiple sessions into a single aggregated indicator.

The feature bridges the gap between Claude Code's hook system and tian's UI: Claude Code hooks invoke `tian-cli status set --state <state>` at each lifecycle transition, and tian renders the result in the sidebar so the developer can monitor multiple concurrent Claude sessions at a glance without switching between panes or watching terminal output.

---

## 2. Problem Statement

**User Pain Point:** When running multiple Claude Code sessions across different panes (e.g., one per worktree Space), the developer has no way to see which sessions are actively working, which are waiting for input, and which need attention (permission prompts) without manually switching to each pane and reading the terminal. This is especially costly when Claude Code is blocked on a permission prompt in a backgrounded pane -- the developer doesn't notice until they happen to check, wasting time that Claude could be working.

**Current Workaround:** The developer uses `tian-cli status set --label "Thinking..."` via Claude Code hooks to display free-form text in the sidebar's Space row. This provides some visibility, but (a) the status is a plain text string with no semantic meaning -- tian cannot distinguish "busy" from "needs attention," (b) all panes within a Space share a single "latest status" display so there is no per-pane tracking, (c) there is no visual priority system -- a permission prompt in a backgrounded pane looks the same as a "Thinking..." status, and (d) the free-form label has no color coding or icon, so scanning the sidebar for important states requires reading text.

**Business Opportunity:** tian's 4-level hierarchy is designed for managing multiple parallel workstreams. Claude Code is the primary tool running inside those workstreams. Making Claude session state a first-class concept in the sidebar transforms tian from a passive terminal into an active AI session dashboard. The developer can run Claude Code in 3-5 Spaces simultaneously and instantly see which ones need attention, which are still working, and which are done -- enabling a multiplexed AI-assisted development workflow that is tian's primary differentiator.

---

## 3. Goals & Non-Goals

### Goals

- **G1:** Track Claude Code session state per-pane, with typed state values (not free-form strings), persisted in memory for the lifetime of the app session.
- **G2:** Display per-pane Claude session states on the Space row as individual color-coded dots, sorted by priority, so the developer can see how many sessions are running and what state each is in.
- **G3:** Make the per-session dots scannable at a glance in the sidebar's Space row, with distinct colors per state and priority-based sort order (highest-priority leftmost).
- **G4:** Extend the existing `status.set` IPC command with an optional `--state` parameter, layered alongside the existing free-form `--label`. The two are independent -- a pane can have a label, a session state, both, or neither.
- **G5:** Define the complete hook-to-state mapping so that all six Claude Code hooks produce the correct state transitions with no additional user configuration beyond installing the hooks.

### Non-Goals

- **NG1:** Persisting Claude session state across app restarts. Session state is ephemeral -- it resets when tian restarts. (Tracked in Open Questions for future consideration.)
- **NG2:** Aggregating session state at the Workspace level. v1 shows per-session dots at the Space level only.
- **NG3:** Auto-focus or auto-switch to a pane/Space when its state changes to `needs_attention`. This is a future enhancement.
- **NG4:** Timeout or staleness detection (e.g., marking a "busy" session as "stale" after N minutes of no state change). State is only changed by explicit IPC calls.
- **NG5:** A dedicated Claude sessions panel or dashboard view. v1 uses only the existing sidebar Space row.
- **NG6:** Tracking non-Claude-Code tools. The state machine and hook mapping are designed for Claude Code, though the `--state` parameter is generic enough for future extension.

---

## 4. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | see per-session colored dots on each Space in the sidebar, one dot per active Claude session | I can instantly tell which Spaces have active Claude Code sessions, how many, and what state each is in |
| 2 | developer | have my Claude Code hooks automatically report session state to tian without manual configuration beyond installing the hooks | the status tracking works out of the box with no ongoing maintenance |
| 3 | developer | see an orange dot when any Claude Code session in a Space is blocked on a permission prompt | I notice immediately when a backgrounded Claude session needs my input, instead of discovering it minutes later |
| 4 | developer | see individual dots for each Claude session in a Space, sorted by priority | I can tell at a glance how many sessions are running and which ones need attention without expanding individual panes |
| 5 | developer | continue using `tian-cli status set --label "..."` for free-form text alongside the new `--state` parameter | the existing label-based status and the new typed session state coexist without conflict |
| 6 | developer | see dots disappear when no Claude session is active in a Space | the sidebar is not cluttered with indicators for Spaces that are not running Claude Code |

---

## 5. Functional Requirements

### State Machine

**FR-001:** The Claude session state for a pane must be one of the following typed values: `active`, `busy`, `idle`, `needs_attention`, `inactive`. No other values are accepted for the `--state` parameter.

**FR-002:** The state machine for a single pane's Claude session follows these transitions, driven by Claude Code hooks:

| Hook | Trigger | State Transition |
|------|---------|-----------------|
| `SessionStart` | Claude Code session begins | -> `active` |
| `UserPromptSubmit` | User sends a prompt to Claude | -> `busy` |
| `Stop` | Claude finishes responding | -> `idle` |
| `Notification` (`idle_prompt`) | Claude is waiting for user input | -> `idle` |
| `Notification` (`permission_prompt`) | Claude is blocked on a permission approval | -> `needs_attention` |
| `SessionEnd` | Claude Code session ends | -> `inactive` |

> **Note:** After a developer approves a permission prompt, the `needs_attention` state may linger for a few seconds until Claude Code fires the next hook. This is a known, accepted gap. In practice it self-resolves quickly: if Claude resumes working, the `Stop` hook fires within seconds and transitions to `idle`; if the developer submits a new prompt, `UserPromptSubmit` fires and transitions to `busy`. No additional mechanism is needed to clear `needs_attention` after approval.

**FR-003:** Any state can transition to any other state. The state machine has no illegal transitions -- each hook sets the state unconditionally. This is intentional: Claude Code hooks may fire in unexpected orders (e.g., `SessionEnd` without a preceding `Stop`), and the system must not reject valid IPC calls due to state ordering.

**FR-004:** When a pane is closed (removed from the split tree), its session state must be automatically cleaned up. No explicit `inactive` transition is required from the hook for pane closure.

### IPC Extension

**FR-005:** The `status.set` IPC command must accept an optional `state` parameter (string) in addition to the existing `label` parameter. At least one of `label` or `state` must be provided; if neither is provided, the command must return an error.

**FR-006:** When `state` is provided, it must be one of the values defined in FR-001. If the value is not recognized, the command must return an error with a message listing the valid values.

**FR-007:** When `state` is provided, it must be stored independently from `label` on the pane. Setting `state` must not affect the existing `label`, and setting `label` must not affect the existing `state`. They are separate, coexisting fields.

**FR-008:** The `status.clear` IPC command must clear both the label and the session state for the pane. There is no selective clear in v1.

> **Note:** `status.clear` resets session state to `nil` (distinct from `inactive`). `nil` means "no Claude session in this pane" and causes the icon to disappear, whereas `inactive` means "a session existed but has ended." For session lifecycle management, use `--state inactive` via the `SessionEnd` hook rather than `status.clear`.

### CLI Extension

**FR-009:** The `tian-cli status set` CLI command must accept an optional `--state <value>` flag alongside the existing `--label <text>` flag.

**FR-010:** The CLI must validate that at least one of `--label` or `--state` is provided. If neither is given, the CLI must print an error and exit with a non-zero exit code without sending an IPC request.

**FR-011:** The CLI must not validate the `--state` value itself -- validation happens server-side (FR-006). The CLI passes the value through to the IPC command.

### Pane-Level State Tracking

**FR-012:** The session state must be tracked per-pane by the existing `PaneStatusManager` (or an equivalent central manager). Each pane ID maps to an optional session state value.

**FR-013:** The session state must be queryable for any pane by its UUID. A pane with no session state set returns `nil` (no Claude session in this pane).

**FR-014:** When a pane is closed, both its label and session state must be removed from the manager. This must happen automatically as part of the existing pane cleanup lifecycle.

### Space-Level Display

**FR-015:** Each Space must display the Claude session states of all panes that have a non-nil, non-inactive session state as individual color-coded dots on the Space row's second line. Each dot represents one pane's Claude session. Panes with no Claude session (`nil`) or ended sessions (`inactive`) do not produce a dot.

**FR-016:** The dots must be sorted by priority order (highest-priority state leftmost). The priority ordering is:

| Priority | State | Rationale |
|----------|-------|-----------|
| 1 (highest) | `needs_attention` | Blocked -- developer action required |
| 2 | `busy` | Claude is actively working |
| 3 | `active` | Session exists but no prompt submitted yet |
| 4 | `idle` | Waiting for user input (not blocked) |
| 5 (lowest) | `inactive` | Session ended (dot not shown) |

> **Rationale for `active` > `idle` ordering:** `active` means a session just started but no prompt has been submitted yet -- it signals a new session the developer may want to interact with. `idle` means Claude has already responded and is passively waiting. A newly started session is more noteworthy than a waiting one, so `active` takes priority.

> **Rationale for per-session dots over single aggregated icon:** A Space can contain multiple tabs and panes, each running its own Claude Code session. A single aggregated icon collapses this information -- the developer cannot tell how many sessions are running or what mix of states exists. Per-session dots give at-a-glance visibility: two dots means two sessions, and each dot's color shows its individual state. This is more useful for the multiplexed AI workflow that is tian's differentiator.

**FR-017:** If no pane in the Space has any session state set (all `nil`), no dots are shown. The Space row looks identical to current behavior. If all panes have `inactive` state, no dots are shown either -- ended sessions do not produce dots.

**FR-018:** The dots must update reactively when any pane's session state changes. There is no polling or manual refresh.

### Sidebar UI

**FR-019:** When any pane in a Space has a non-nil, non-inactive Claude session state, the sidebar Space row must display per-session dots on the **second line** of the Space row (the status text line in `SidebarSpaceRowView`'s VStack), positioned to the **left of the status label text**. Each dot should be small (~8pt) and represent one pane's Claude session. When there is no status label but there ARE Claude session dots, the dots still appear on the second line alone. When there is a status label, the dots and label appear inline on the same row. **The second line must render when either a status label OR at least one non-nil/non-inactive Claude session state exists** -- not only when a label is present as in the current implementation.

**FR-020:** Each per-session dot must be color-coded to reflect its individual pane's session state:

| State | Color | Behavior |
|-------|-------|----------|
| `active` | Green | Static |
| `busy` | Blue | Pulsing animation |
| `idle` | Gray | Static |
| `needs_attention` | Orange | Static (high contrast against sidebar background) |
| `inactive` | Not shown | Dot not rendered |

**FR-021:** When no pane in the Space has a non-nil, non-inactive session state, no dots are shown. The Space row should look identical to how it looks today.

**FR-022:** The per-session dots must not displace or resize the existing Space row elements (name, tab count badge, active dot, status label). They should be additive -- placed in a position that does not shift the existing layout. Dots are spaced ~3pt apart.

**FR-023:** The `busy` state's pulsing animation must be subtle and non-distracting. It should be a smooth opacity pulse (1.0 → 0.4 → 1.0 over ~2s) on the individual busy dot, not a rapid blink or color flash. The animation must respect the system's "Reduce Motion" accessibility setting -- when Reduce Motion is enabled, the pulse must be replaced with a static indicator (e.g., a solid color without animation).

**FR-024:** The existing free-form status label (from `--label`) must continue to display in the Space row as it does today, independently of the Claude session dots. A Space can show both a status label and session dots simultaneously.

**FR-025:** When Claude session states are present (non-nil) for a Space, the Space row's accessibility value must include the session states. For example, if the Space is selected and has two sessions (one busy, one needs_attention), the accessibility value should read "selected, 2 Claude sessions, 1 needs attention". When no session state is present, the accessibility value remains unchanged from current behavior.

### Hook Configuration

**FR-026:** The complete set of Claude Code hook configurations required for this feature must be documented in the PRD. The developer installs these hooks in their Claude Code configuration. Each hook invocation is a single `tian-cli status set --state <value>` call.

**FR-027:** The hook commands must use the `tian-cli` binary path from the `TIAN_CLI_PATH` environment variable that tian injects into every shell session. This ensures the hooks work regardless of where the CLI binary is located.

**FR-028:** The hooks must be no-ops (silent failure, non-blocking) when not running inside tian. Since `tian-cli` refuses to run outside of tian (it checks for `TIAN_SOCKET`), and Claude Code hooks tolerate non-zero exit codes, no special guard logic is needed in the hook commands.

---

## 6. Non-Functional Requirements

**NFR-001:** State transitions via IPC must be reflected in the sidebar within 100ms of the IPC request arriving. The feature must not introduce perceptible lag in sidebar updates.

**NFR-002:** The pulsing animation for the `busy` state must not cause excessive CPU usage. It should use framework-level animation (SwiftUI `.animation`) rather than a manual timer.

**NFR-003:** The aggregation computation must be O(n) in the number of panes across the Space, not O(n^2) or worse. With typical pane counts (1-10 per Space), this is not a practical concern, but the design should not degrade with scale.

**NFR-004:** The feature must not add any new IPC commands -- it extends the existing `status.set` command. This minimizes protocol surface area.

**NFR-005:** State transitions received via IPC must be logged at debug level, including pane ID, old state, and new state, for integration debugging.

---

## 7. User Flow

### Happy Path: Developer Runs Claude Code in a Pane

```
Precondition: Developer has tian open with at least one Space. Claude Code hooks 
are installed in ~/.claude/settings.json (or project-level .claude/settings.json).

1. Developer opens a terminal pane and starts Claude Code (`claude`).
   -> Claude Code fires SessionStart hook.
   -> Hook runs: tian-cli status set --state active
   -> Pane state: active.
   -> Sidebar: A green dot appears on the Space row's second line.

2. Developer types a prompt and presses Enter.
   -> Claude Code fires UserPromptSubmit hook.
   -> Hook runs: tian-cli status set --state busy
   -> Pane state: busy.
   -> Sidebar: The dot changes to blue with a pulse animation.

3. Claude finishes responding.
   -> Claude Code fires Stop hook.
   -> Hook runs: tian-cli status set --state idle
   -> Pane state: idle.
   -> Sidebar: The dot changes to gray (static).

4. Developer submits another prompt (repeat steps 2-3).

5. Claude encounters a tool use requiring approval.
   -> Claude Code fires Notification hook with permission_prompt.
   -> Hook runs: tian-cli status set --state needs_attention
   -> Pane state: needs_attention.
   -> Sidebar: The dot changes to orange.

6. Developer approves the permission. Claude resumes. Developer submits more prompts 
   (cycles through busy -> idle). Eventually exits Claude Code.
   -> Claude Code fires SessionEnd hook.
   -> Hook runs: tian-cli status set --state inactive
   -> Pane state: inactive.
   -> Sidebar: The dot disappears (inactive sessions are not shown).
```

### Multi-Pane Sessions

```
Precondition: Space has 3 panes. Pane A is idle. Pane B is busy. Pane C has no 
Claude session (state is nil).

-> Sidebar shows 2 dots on Space row: [blue (busy)] [gray (idle)].
   Dots sorted by priority: busy first, idle second. Pane C (nil) has no dot.

Pane B's Claude Code hits a permission prompt:
-> Pane B state: needs_attention.
-> Sidebar shows 2 dots: [orange (needs_attention)] [gray (idle)].
   Dots re-sorted: needs_attention first, idle second.

Pane B's developer approves, Claude resumes and finishes:
-> Pane B state: idle.
-> Sidebar shows 2 dots: [gray (idle)] [gray (idle)].
   Both sessions idle.
```

### Coexistence with Label Status

```
Precondition: A Claude Code hook sets both --state and --label.

Hook runs: tian-cli status set --state busy --label "Implementing auth module"
-> Pane has both: state=busy, label="Implementing auth module".
-> Sidebar Space row shows: session dot (blue, pulsing) followed by status label 
   text "Implementing auth module" on the second line.
```

### Error States

```
- Invalid --state value sent via CLI:
  -> IPC handler returns error: "Invalid state: 'thinking'. Valid values: active, 
     busy, idle, needs_attention, inactive."
  -> tian-cli prints error to stderr, exits with non-zero code.
  -> Claude Code hook failure is non-blocking (Claude continues).

- Pane closed while Claude session is active:
  -> Pane's state is automatically cleaned up from the manager.
  -> Its dot is removed from the Space row.
  -> If no other pane has a session state, all dots disappear from Space row.

- tian-cli invoked outside tian (no TIAN_SOCKET):
  -> CLI exits with error: "Not running inside tian."
  -> Claude Code hook failure is non-blocking.

- Multiple --state updates arrive in rapid succession (e.g., busy -> idle within ms):
  -> Each update overwrites the previous. Last write wins. No queuing or debouncing.
```

### Empty States

```
- Space with no Claude sessions in any pane:
  -> No dots shown. Space row looks identical to current behavior.

- Space where all Claude sessions have ended (all inactive):
  -> No dots shown (inactive sessions do not produce dots). Space row appears clean.
```

### Loading States

```
- No loading states apply. State transitions are synchronous from the sidebar's 
  perspective -- the IPC handler updates the manager, the Observable model propagates 
  to the view immediately.
```

---

## 8. Edge Cases & Error Handling

| # | Scenario | Expected Behavior |
|---|----------|-------------------|
| 1 | Claude Code crashes without firing `SessionEnd` | Pane retains its last state (e.g., `busy`). No automatic timeout or cleanup. The state is cleared when the pane itself is closed. |
| 2 | Developer quits Claude Code with Ctrl+C during a response | Claude Code fires `SessionEnd`. State transitions to `inactive`. |
| 3 | Multiple Claude Code sessions in the same pane (sequential) | Each `SessionStart` resets to `active`. Previous session's state is overwritten. Only the current session's state is tracked. |
| 4 | `--state` set without `--label`, then `--label` set without `--state` | Both fields are independent. Setting one does not affect the other. Pane has state from first call and label from second call. |
| 5 | `status.clear` called while pane has both state and label | Both are cleared. |
| 6 | Two panes in different Spaces have `needs_attention` | Each Space independently shows its own dots. Both Space rows show an orange dot. |
| 7 | Space has one pane with `needs_attention` and another with `inactive` | Space shows one orange dot (needs_attention). The inactive pane does not produce a dot. |
| 8 | All panes in a Space have `inactive` state | No dots shown. Space row appears clean. |
| 9 | Pane with active Claude session is moved to another tab within the same Space (if tab drag is supported) | Session state follows the pane ID. Its dot remains on the same Space row. |
| 10 | `tian-cli status set --state active` called for a pane that no longer exists (stale env vars) | IPC handler returns error: "Pane not found: <UUID>". Non-blocking for the hook. |
| 11 | Reduce Motion accessibility setting is enabled | The `busy` pulsing animation is replaced with a static indicator. |

---

## 9. Dependencies & Constraints

### Dependencies

- **Existing IPC system:** The `status.set` and `status.clear` commands already exist in `IPCCommandHandler`. This feature extends `status.set` with an optional `state` parameter.
- **Existing PaneStatusManager:** Tracks per-pane status labels. This feature extends it (or adds a parallel manager) to also track session state.
- **Existing SidebarSpaceRowView:** The sidebar Space row already renders the status label from `PaneStatusManager.latestStatus(in:)`. The per-session dots are additive elements in this view.
- **Existing tian-cli `StatusSet` command:** The CLI command currently accepts `--label`. This feature adds `--state`.
- **Claude Code hooks system:** Claude Code must support the six hooks listed in FR-002. The hook configuration is external to tian (managed in Claude Code's settings).

### Constraints

- **No new IPC commands.** The feature must be implemented as an extension to the existing `status.set` command, not as new commands.
- **Backward compatibility.** Existing `tian-cli status set --label "..."` calls must continue to work unchanged. The `--state` parameter is optional.
- **No special icon asset required.** Per-session dots are simple colored circles (~8pt), drawn programmatically. No external icon asset is needed.

---

## 10. Open Questions

| # | Question | Owner | Due Date |
|---|----------|-------|----------|
| 1 | ~~What exact colors should map to each state?~~ **Resolved:** Hues locked: green (active), blue (busy), gray (idle), orange (needs_attention). Exact hex values to be tuned during implementation against the sidebar's dark background for contrast and accessibility. | psycoder | Resolved |
| 2 | ~~Should `inactive` state be cleaned up after a timeout?~~ **Resolved:** No timeout-based cleanup in v1 per NG4. `inactive` persists until the pane is closed or a new session starts. | psycoder | Resolved |
| 3 | ~~Should the Claude icon be the official Anthropic mark, a stylized "C", or a generic AI indicator?~~ **Resolved:** v1.3 switched to per-session colored dots (~8pt circles). No special icon asset needed. | psycoder | Resolved |
| 4 | Should the `--state` parameter clear itself when `status.clear` is called, or should there be a way to clear only label or only state independently? v1 design clears both (FR-008), but selective clear might be useful. | psycoder | TBD |
| 5 | Should the `busy` pulsing animation have a configurable speed or intensity, or is a single hardcoded animation sufficient for v1? | psycoder | TBD |
| 6 | ~~What is the exact placement of the Claude icon within the Space row?~~ **Resolved:** Per-session dots appear on the second line of the Space row (the status text line), positioned to the left of the status label text. Each dot is ~8pt. See FR-019. | psycoder | Resolved |
| 7 | Should `pane.list` IPC command include the session state in its output? This would make it queryable for scripts/automation. Low cost to add, but out of scope for v1 unless needed. | psycoder | TBD |

---

## 11. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.3 | 2026-04-07 | Changed from single aggregated icon to per-session dots (Option B). Each pane's Claude session gets its own color-coded dot, sorted by priority. Updated FR-015–FR-025, G2–G3, user stories, user flows, edge cases, and Appendix B. Rationale: a single aggregated icon hides how many sessions are running; per-session dots give better visibility for multiplexed workflows. |
| 1.2 | 2026-04-07 | Final polish: made second-line rendering condition explicit in FR-019, locked color hues (green/blue/gray/orange), resolved OQ#1, added hook merging note to Appendix A. Approved. |
| 1.1 | 2026-04-07 | Review fixes: documented `needs_attention` linger gap after permission approval (FR-002 note), verified Notification matcher strings (Appendix A note), resolved icon placement to second line of Space row (FR-019, OQ#6), closed OQ#2 referencing NG4, added diagnostic logging NFR (NFR-005), added accessibility requirement (FR-025), added `active` vs `idle` priority rationale (FR-016 note), clarified `status.clear` vs `inactive` distinction (FR-008 note). |
| 1.0 | 2026-04-07 | Initial draft. Core state machine, IPC extension, aggregation rules, sidebar UI, and hook mapping. |

---

## Appendix A: Claude Code Hook Configuration

The following hook configuration must be added to Claude Code's settings (either `~/.claude/settings.json` for global or `.claude/settings.json` for per-project). The `$TIAN_CLI_PATH` variable is injected by tian into every shell session.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "command": "$TIAN_CLI_PATH status set --state active"
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "command": "$TIAN_CLI_PATH status set --state busy"
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "command": "$TIAN_CLI_PATH status set --state idle"
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "command": "$TIAN_CLI_PATH status set --state idle"
      },
      {
        "matcher": "permission_prompt",
        "command": "$TIAN_CLI_PATH status set --state needs_attention"
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "command": "$TIAN_CLI_PATH status set --state inactive"
      }
    ]
  }
}
```

**Note:** The `$TIAN_CLI_PATH` environment variable is set by tian's `EnvironmentBuilder` in every shell session. When running outside tian, this variable is unset and the command fails gracefully. Claude Code hooks tolerate non-zero exit codes without interrupting the session.

**Note:** Verified against Claude Code documentation: Notification hook matchers `idle_prompt` and `permission_prompt` are the correct strings.

**Note:** These hooks should be **added to existing hook arrays**, not replace them. Claude Code supports multiple hooks per event. If you already have hooks for `SessionStart`, `Notification`, etc., append these entries to those arrays.

## Appendix B: Per-Session Dots Visualization

```
Dot sort order (leftmost = highest priority):
needs_attention (1) > busy (2) > active (3) > idle (4)
inactive and nil panes do not produce dots.

Space with 3 panes [idle, busy, nil]:
  -> 2 dots: [blue (busy)] [gray (idle)]
     Pane with nil has no dot.

Space with 3 panes [idle, needs_attention, busy]:
  -> 3 dots: [orange (needs_attention)] [blue (busy)] [gray (idle)]

Space with 2 panes [inactive, inactive]:
  -> no dots (inactive sessions are not shown)

Space with 2 panes [nil, nil]:
  -> no dots (no Claude sessions)

Space with 5 panes [nil, busy, nil, needs_attention, nil]:
  -> 2 dots: [orange (needs_attention)] [blue (busy)]
     Only panes with active Claude sessions produce dots.
```
