# Pane Visual Indicators Design

**Date:** 2026-04-11
**Status:** Approved

## Summary

Replace the rainbow focus border with unfocused-pane dimming, and add Claude session state borders directly on panes. This creates two distinct visual channels: dimming communicates focus, rainbow/colored borders communicate Claude activity.

## Changes

### 1. Unfocused Pane Dimming

**Replaces:** The current `RainbowBorder` overlay used as a focus indicator in `PaneView`.

**Behavior:**
- Unfocused panes receive a semi-transparent black overlay (`rgba(0, 0, 0, 0.22)`, ~22% opacity).
- The focused pane has no overlay — it stands out by contrast.
- Dimming only applies when `leafCount > 1`. A single pane (no splits) is never dimmed.
- The overlay sits above the terminal content but below session-state borders, bell glow, and exit overlay.

**Rationale:** Matches how native Ghostty handles split focus. Subtractive indication (dimming others) is less visually noisy than additive indication (border on focused).

### 2. Claude Session State Borders on Panes

**New behavior:** Panes with active Claude sessions display a border overlay based on their session state, driven by `PaneStatusManager.sessionStates[paneID]`.

| State | Pane Border | Notes |
|---|---|---|
| `busy` | Rotating rainbow border (2pt stroke) | Reuses existing `RainbowBorder` view |
| `needsAttention` | Static orange border (2pt stroke, `rgb(255, 159, 10)`) | Matches sidebar dot color |
| `active` | None | Sidebar dots only |
| `idle` | None | Sidebar dots only |
| `inactive` | None | Sidebar dots only |

**Interaction with dimming:** Dimming applies uniformly to all unfocused panes, including those with Claude session borders. An unfocused busy pane shows rainbow border + dim overlay. This keeps focus indication consistent.

**New view needed:** A simple `SessionStateBorder` view (or equivalent) that renders a 2pt orange rounded-rect stroke for the `needsAttention` state. The `busy` state reuses the existing `RainbowBorder`.

### 3. Bell Glow (Unchanged)

`RainbowGlow` continues to work as-is for bell notifications. No changes.

## Implementation Scope

### Files to modify

**`PaneView.swift`** — Main change site:
- Remove the `showFocusBorder` computed property and its `RainbowBorder` overlay.
- Add a dimming overlay: `Color.black.opacity(0.22)` shown when `!isFocused && leafCount > 1`.
- Add a session-state border overlay: read `PaneStatusManager.shared.sessionStates[paneID]` and show `RainbowBorder()` for `.busy`, a static orange border for `.needsAttention`, nothing otherwise.
- Overlay stacking order (bottom to top): terminal content → dim overlay → session border → bell glow → exit overlay.

**`RainbowGlowBorder.swift`** — No changes to existing views. Optionally add a new `SessionStateBorder` view here (a 2pt rounded-rect stroke in a given color) to keep border views co-located.

### Files unchanged

- `PaneStatusManager.swift` — already provides `sessionStates[paneID]`.
- `ClaudeSessionState.swift` — enum stays as-is.
- `SplitTreeView.swift`, `SplitContainerView.swift` — no changes needed.
- `BusyDotView.swift`, sidebar views — unaffected.

## Overlay Stacking Order in PaneView

```
5. PaneExitOverlay          (topmost, blocks interaction)
4. RainbowGlow              (bell notification)
3. Session border           (RainbowBorder or orange stroke)
2. Dim overlay              (Color.black.opacity(0.22))
1. TerminalContentView      (base)
```

## Animations

- **Dim overlay:** `.easeInOut(duration: 0.3)` fade, animated on `isFocused` and `leafCount` changes.
- **Session border (busy):** 30fps `TimelineView` rotation (existing `RainbowBorder` behavior).
- **Session border (needsAttention):** Static, no animation. Fades in/out with `.easeInOut(duration: 0.3)`.
- **Bell glow:** Unchanged.

## Accessibility

- Respect `accessibilityReduceMotion`: when enabled, the busy rainbow border should stop rotating (static gradient instead). The dim overlay is not affected (it's not animated content).
