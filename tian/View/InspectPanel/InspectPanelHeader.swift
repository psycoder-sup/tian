import SwiftUI

/// 48 px header for the Inspect panel (FR-03 / FR-04 / FR-05).
///
/// Layout (left → right):
///   - "Files" pill (segmented control, single item, always active in v1) — FR-04
///   - Space-name label with optional WorktreeKind suffix — FR-05
///
/// The inspect-panel toggle is rendered as a window-level floating rail
/// (`InspectPanelRail` overlay in `SidebarContainerView`) so its absolute
/// position is identical whether the panel is open or collapsed.
struct InspectPanelHeader: View {
    static let height: CGFloat = 48

    let spaceName: String
    let worktreeKind: WorktreeKind

    // MARK: - Subviews

    /// "Files" segmented control pill — always active in v1 (FR-04).
    private var filesPill: some View {
        Text("Files")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }

    /// `{spaceName} · {contextSuffix}` label (FR-05).
    private var spaceLabel: some View {
        let suffix = worktreeKind.label
        let text = suffix.map { "\(spaceName) · \($0)" } ?? spaceName
        return Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            filesPill
            spaceLabel
                .frame(maxWidth: .infinity, alignment: .leading)
            // Trailing space reserved for the floating InspectPanelRail
            // overlay (rail size 22 + trailing inset 10).
            Color.clear.frame(width: 32, height: 1)
        }
        .padding(.leading, 10)
        .frame(height: Self.height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Previews

#Preview("Header – worktree") {
    InspectPanelHeader(
        spaceName: "tian",
        worktreeKind: .linkedWorktree
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Header – repo") {
    InspectPanelHeader(
        spaceName: "my-project",
        worktreeKind: .mainCheckout
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Header – no dir") {
    InspectPanelHeader(
        spaceName: "untitled",
        worktreeKind: .noWorkingDirectory
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
