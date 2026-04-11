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
                Color.black.opacity(0.30)
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
