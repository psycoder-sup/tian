# Pane Visual Indicators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the rainbow focus border with unfocused-pane dimming, and add Claude session state borders (rainbow for busy, orange for needsAttention) directly on panes.

**Architecture:** Two overlay changes in `PaneView`: (1) a dim overlay on unfocused panes when there are multiple splits, (2) a session-state border overlay driven by `PaneStatusManager`. The existing `RainbowBorder` view is reused for busy state. A new `SessionStateBorder` view handles the orange needsAttention border.

**Tech Stack:** SwiftUI, `@Observable`, `PaneStatusManager` singleton

**Spec:** `docs/superpowers/specs/2026-04-11-pane-visual-indicators-design.md`

---

### Task 1: Add `SessionStateBorder` view for needsAttention state

**Files:**
- Modify: `tian/View/Shared/RainbowGlowBorder.swift`

- [ ] **Step 1: Add `SessionStateBorder` view**

Add the following view at the end of `RainbowGlowBorder.swift`, after the `RainbowGlow` struct:

```swift
// MARK: - Session state indicator (static colored border)

struct SessionStateBorder: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: glowCornerRadius)
            .strokeBorder(color, lineWidth: 2)
            .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project tian.xcodeproj -scheme tian -configuration Debug -derivedDataPath .build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add tian/View/Shared/RainbowGlowBorder.swift
git commit -m "feat(pane): add SessionStateBorder view for colored pane borders"
```

---

### Task 2: Replace focus rainbow border with unfocused dimming in PaneView

**Files:**
- Modify: `tian/View/PaneView.swift`

- [ ] **Step 1: Replace `showFocusBorder` with `showDimOverlay`**

Replace the entire contents of `PaneView.swift` with:

```swift
import SwiftUI

/// Renders a single terminal pane by looking up its surface view from the view model.
struct PaneView: View {
    let paneID: UUID
    let viewModel: PaneViewModel

    private var isFocused: Bool {
        viewModel.splitTree.focusedPaneID == paneID
    }

    private var showDimOverlay: Bool {
        !isFocused && viewModel.splitTree.leafCount > 1
    }

    private var showBellGlow: Bool {
        viewModel.bellNotifications.contains(paneID)
    }

    private var sessionState: ClaudeSessionState? {
        PaneStatusManager.shared.sessionState(for: paneID)
    }

    var body: some View {
        TerminalContentView(
            paneID: paneID,
            viewModel: viewModel,
            isFocused: isFocused
        )
        // Layer 2: Dim overlay for unfocused panes
        .overlay {
            if showDimOverlay {
                Color.black.opacity(0.22)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showDimOverlay)
        // Layer 3: Session state border (busy = rainbow, needsAttention = orange)
        .overlay {
            switch sessionState {
            case .busy:
                RainbowBorder()
                    .transition(.opacity)
            case .needsAttention:
                SessionStateBorder(color: Color(red: 1.0, green: 0.624, blue: 0.039))
                    .transition(.opacity)
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: sessionState)
        // Layer 4: Bell glow
        .overlay {
            if showBellGlow {
                RainbowGlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showBellGlow)
        // Layer 5: Exit overlay
        .overlay {
            let state = viewModel.paneState(for: paneID)
            if state != .running {
                PaneExitOverlay(
                    state: state,
                    onRestart: { viewModel.restartShell(paneID: paneID) },
                    onClose: { viewModel.closePane(paneID: paneID) }
                )
            }
        }
    }
}
```

Key changes from the original:
- Removed `showFocusBorder` computed property and its rainbow border overlay.
- Added `showDimOverlay`: `!isFocused && leafCount > 1`.
- Added `sessionState` computed property reading from `PaneStatusManager.shared`.
- Added dim overlay (layer 2) with `Color.black.opacity(0.22)`.
- Added session state border (layer 3) switching on `sessionState`.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project tian.xcodeproj -scheme tian -configuration Debug -derivedDataPath .build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add tian/View/PaneView.swift
git commit -m "feat(pane): replace focus rainbow border with unfocused dimming and session state borders"
```

---

### Task 3: Add reduce-motion support for busy rainbow border

**Files:**
- Modify: `tian/View/Shared/RainbowGlowBorder.swift`

- [ ] **Step 1: Add reduce-motion support to `RainbowBorder`**

Replace the `RainbowBorder` struct with:

```swift
struct RainbowBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            // Static gradient — no animation
            AngularGradient(
                colors: rainbowColors,
                center: .center
            )
            .mask {
                RoundedRectangle(cornerRadius: glowCornerRadius)
                    .strokeBorder(lineWidth: 2)
            }
            .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project tian.xcodeproj -scheme tian -configuration Debug -derivedDataPath .build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add tian/View/Shared/RainbowGlowBorder.swift
git commit -m "feat(a11y): respect reduce-motion for busy rainbow border"
```

---

### Task 4: Manual verification

- [ ] **Step 1: Build and run the app**

Run: `xcodebuild -project tian.xcodeproj -scheme tian -configuration Debug -derivedDataPath .build build 2>&1 | tail -5`

- [ ] **Step 2: Verify unfocused pane dimming**

1. Open a terminal pane and split it (Cmd+D or equivalent).
2. Click between panes — the unfocused pane should dim with a ~22% black overlay.
3. Close one pane to go back to a single pane — no dimming should appear.

- [ ] **Step 3: Verify Claude session busy border**

1. In a split view, run `claude` in one pane to start a Claude session.
2. Give Claude a task so it enters `busy` state.
3. The busy pane should show a rotating rainbow border.
4. The rainbow border should appear regardless of whether the pane is focused or unfocused.
5. When unfocused, the busy pane shows both the dim overlay and the rainbow border.

- [ ] **Step 4: Verify no rainbow border on focus**

1. In a split view with no Claude sessions, confirm that the focused pane does NOT show a rainbow border.
2. Focus is indicated purely by the absence of dimming.

- [ ] **Step 5: Verify bell glow still works**

1. Trigger a bell notification in an unfocused pane.
2. The bell glow should still appear on top of the dim overlay.
