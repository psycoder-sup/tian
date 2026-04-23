import SwiftUI

/// Rendered inside a Claude `SectionView` when the section has zero tabs
/// (FR-07). Displays the Claude glyph, a label, a "New Claude pane"
/// button, a "Close Space" button wired to Cmd+W (FR-07 clause a), and a
/// shortcut caption.
struct EmptyClaudePlaceholderView: View {
    let onNewTab: () -> Void
    var onCloseSpace: (() -> Void)? = nil
    var shortcutHint: String = "⌘T for new tab, ⌘D for split"

    var body: some View {
        VStack(spacing: 16) {
            SectionKindGlyph(kind: .claude, size: 48)

            Text("No Claude pane running")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Button(action: onNewTab) {
                Label("New Claude pane", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityLabel("New Claude pane")

            Text(shortcutHint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            // FR-07 clause a — Cmd+W on the empty-Claude placeholder asks
            // the owning SpaceModel to close. The button is hidden-but-
            // addressable so it receives the key equivalent while the
            // placeholder is the focused surface.
            if let onCloseSpace {
                Button("Close Space") { onCloseSpace() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .opacity(0.01)
                    .frame(width: 1, height: 1)
                    .accessibilityLabel("Close Space")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Empty Claude section")
    }
}
