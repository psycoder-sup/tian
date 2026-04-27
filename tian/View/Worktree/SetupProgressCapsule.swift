import SwiftUI

/// Bottom-right overlay shown while `[[setup]]` commands run for a
/// freshly-created worktree Space. Displays the step counter, current
/// command, a failure glyph if the most recent step failed, and a
/// cancel button. Replaces the older cancel-only `SetupCancelButton`.
struct SetupProgressCapsule: View {
    let progress: SetupProgress
    let onCancel: () -> Void

    private var stepText: String {
        let displayed = max(progress.currentIndex + 1, 1)
        return "\(displayed)/\(progress.totalCommands)"
    }

    private var commandLabel: String {
        progress.currentCommand ?? "starting…"
    }

    private var didFailLastStep: Bool {
        progress.lastFailedIndex != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)

            Text("Setup \(stepText)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if didFailLastStep {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
                    .accessibilityLabel("a step in this run failed")
            }

            Text("·")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(commandLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel setup")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
