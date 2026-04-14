import SwiftUI

/// Small capsule button shown during worktree setup commands.
/// Appears as a bottom-right overlay on the terminal area.
struct SetupCancelButton: View {
    let onCancel: () -> Void

    var body: some View {
        Button(action: onCancel) {
            Label("Cancel Setup", systemImage: "xmark")
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
