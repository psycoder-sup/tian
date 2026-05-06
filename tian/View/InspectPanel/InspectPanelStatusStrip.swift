import SwiftUI

/// 20 px status strip pinned to the bottom of the inspect panel (FR-09 / FR-T35).
///
/// Layout: `{tab} · {spaceName}` left-aligned, `inspect` right-aligned.
/// Font: 9.5 px monospaced.
///
/// The left label switches per `activeTab` (FR-T35):
///   - `.files`  → `files · {spaceName}`
///   - `.diff`   → `diff · {spaceName}`
///   - `.branch` → `branch · {spaceName}`
struct InspectPanelStatusStrip: View {
    static let height: CGFloat = 20

    let spaceName: String
    let activeTab: InspectTab

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            Text("\(activeTab.statusLabel) · \(spaceName)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.3))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 10)

            Spacer(minLength: 4)

            Text("inspect")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.2))
                .padding(.trailing, 10)
        }
        .frame(height: Self.height)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
        }
    }
}

// MARK: - InspectTab status label

private extension InspectTab {
    /// Short lowercase label rendered in the status strip (FR-T35).
    var statusLabel: String {
        switch self {
        case .files:  "files"
        case .diff:   "diff"
        case .branch: "branch"
        }
    }
}

// MARK: - Previews

#Preview("Status strip – files") {
    InspectPanelStatusStrip(spaceName: "tian", activeTab: .files)
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Status strip – diff") {
    InspectPanelStatusStrip(spaceName: "tian", activeTab: .diff)
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Status strip – branch") {
    InspectPanelStatusStrip(spaceName: "my-project", activeTab: .branch)
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Status strip – long name") {
    InspectPanelStatusStrip(
        spaceName: "my-very-long-project-name-that-truncates",
        activeTab: .files
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
