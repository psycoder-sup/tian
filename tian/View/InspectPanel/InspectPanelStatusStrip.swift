import SwiftUI

/// 20 px status strip pinned to the bottom of the inspect panel (FR-09).
///
/// Layout: `files · {spaceName}` left-aligned, `inspect` right-aligned.
/// Font: 9.5 px monospaced.
struct InspectPanelStatusStrip: View {
    static let height: CGFloat = 20

    let spaceName: String

    var body: some View {
        HStack(spacing: 0) {
            Text("files · \(spaceName)")
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

// MARK: - Previews

#Preview("Status strip") {
    InspectPanelStatusStrip(spaceName: "tian")
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Status strip – long name") {
    InspectPanelStatusStrip(spaceName: "my-very-long-project-name-that-truncates")
        .frame(width: 320)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
