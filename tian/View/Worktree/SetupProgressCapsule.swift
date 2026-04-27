import SwiftUI

/// Bottom-right overlay shown while `[[setup]]` commands run for a
/// freshly-created worktree Space. Step counter, current command,
/// failure glyph, and a cancel button.
struct SetupProgressCapsule: View {
    let progress: SetupProgress
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)

            Text("Setup \(progress.stepText)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if progress.didFailRun {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
                    .accessibilityLabel("a step in this run failed")
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
