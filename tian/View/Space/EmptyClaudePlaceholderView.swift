import SwiftUI

/// Rendered inside a Claude `SectionView` when the section has zero tabs
/// (FR-07). Displays the Claude glyph, a label, a "New Claude pane"
/// button, and a shortcut caption.
///
/// The full Cmd+W close-Space handler lands in Phase 5; Phase 2 wires only
/// the "New Claude pane" button.
struct EmptyClaudePlaceholderView: View {
    let onNewTab: () -> Void
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Empty Claude section")
    }
}
