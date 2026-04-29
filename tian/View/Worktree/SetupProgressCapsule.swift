import SwiftUI

/// Bottom-right overlay shown while `[[setup]]`, `[[archive]]` commands run,
/// or while `git worktree remove` is in progress for a Space.
/// Rendering is phase-driven: `.setup`/`.cleanup` show a step counter,
/// current command, and a cancel button; `.removing` shows only the bare
/// "Removing..." label with no counter, no command, and no cancel affordance.
struct SetupProgressCapsule: View {
    let progress: SetupProgress
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)

            switch progress.phase {
            case .setup, .cleanup:
                Text("\(progress.labelPrefix) \(progress.stepText)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if progress.didFailRun {
                    failureGlyph
                }

                Text("·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(progress.commandLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 320, alignment: .leading)

                cancelButton

            case .removing:
                Text(progress.labelPrefix) // "Removing..."
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                // No step counter, no command label, no cancel button.
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    @ViewBuilder private var failureGlyph: some View {
        Image(systemName: "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.red)
            .accessibilityLabel("a step in this run failed")
    }

    @ViewBuilder private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel \(progress.labelPrefix.lowercased())")
    }
}
