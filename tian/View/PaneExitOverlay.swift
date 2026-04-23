import SwiftUI

/// Overlay shown on a pane when the shell exits with a non-zero code
/// or fails to spawn. Offers Restart and Close actions.
struct PaneExitOverlay: View {
    let state: PaneState
    /// Phase 5 / FR-08 — governs the overlay's restart-button label.
    /// Claude-kind panes show "Retry" so the wording matches the user's
    /// mental model (the Claude binary failed to spawn), while Terminal
    /// panes keep the existing "Restart Shell" copy.
    var sectionKind: SectionKind = .terminal
    let onRestart: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)

            VStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text(titleText)
                    .font(.system(size: 15, weight: .semibold))

                Text(detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button(restartLabel) { onRestart() }
                        .keyboardShortcut(.return, modifiers: [])

                    Button("Close Pane") { onClose() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .controlSize(.regular)
            }
            .padding(24)
            .frame(width: 280)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(titleText)
        }
    }

    private var restartLabel: String {
        switch state {
        case .spawnFailed:
            return sectionKind == .claude ? "Retry" : "Restart Shell"
        case .exited:
            return "Restart Shell"
        case .running:
            preconditionFailure("PaneExitOverlay should not be shown for .running state")
        }
    }

    private var iconName: String {
        switch state {
        case .exited: "exclamationmark.triangle"
        case .spawnFailed: "xmark.circle"
        case .running: preconditionFailure("PaneExitOverlay should not be shown for .running state")
        }
    }

    private var titleText: String {
        switch state {
        case .exited(let code): "Shell exited with code \(code)"
        case .spawnFailed: "Shell failed to start"
        case .running: preconditionFailure("PaneExitOverlay should not be shown for .running state")
        }
    }

    private var detailText: String {
        switch state {
        case .exited: "The process terminated abnormally."
        case .spawnFailed: "Could not create a new terminal session."
        case .running: preconditionFailure("PaneExitOverlay should not be shown for .running state")
        }
    }
}
