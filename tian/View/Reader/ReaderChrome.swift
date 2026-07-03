import SwiftUI

/// Git-diff toggle for a markdown reader. Flips the reader between rendered
/// markdown and the file's line-by-line diff against HEAD, tinting when the
/// diff face is showing. Rendered as a cell in the reader overlay's chrome bar
/// (`ReaderOverlayView`); carries no background of its own so it sits flush on
/// the bar. Lives here rather than with the reader because it's chrome, not
/// document content.
struct MarkdownDiffToggleButton: View {
    let document: MarkdownDocument
    var size: CGFloat = 32
    var iconSize: CGFloat = 14

    var body: some View {
        Button {
            document.showDiff.toggle()
        } label: {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(document.showDiff
                    ? Color.accentColor
                    : Color.chromeForeground.opacity(0.92))
                // Frame + contentShape inside the label so the whole cell is
                // clickable, not just the glyph.
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(document.showDiff ? "Show rendered markdown" : "Show git diff")
        .accessibilityLabel("Toggle git diff")
        .accessibilityAddTraits(document.showDiff ? .isSelected : [])
    }
}

/// "Copy all" control for a markdown reader. A plain icon button that copies
/// the document's verbatim source, flashing a checkmark to confirm. Rendered
/// as a cell in the reader overlay's chrome bar (`ReaderOverlayView`); carries
/// no background of its own so it sits flush on the bar. Lives here rather than
/// with the reader because it's chrome, not document content.
struct MarkdownCopyButton: View {
    let document: MarkdownDocument
    var size: CGFloat = 32
    var iconSize: CGFloat = 14

    @State private var didCopy = false
    /// Outstanding task that resets `didCopy`; cancelled if copied again first.
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        Button(action: copyAll) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(didCopy ? Color.green : Color.chromeForeground.opacity(0.92))
                .contentTransition(.symbolEffect(.replace))
                // Frame + contentShape inside the label so the whole cell is
                // clickable, not just the glyph.
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? "Copied" : "Copy all")
        .accessibilityLabel("Copy all contents")
    }

    /// Copies the verbatim markdown source to the general pasteboard and shows
    /// a brief checkmark confirmation.
    private func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(document.rawText, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
        }
    }
}

/// Dismisses the reader overlay. A plain icon button matching the diff/copy
/// cells; rendered as the trailing chrome-bar control in `ReaderOverlayView`.
struct ReaderCloseButton: View {
    let action: () -> Void
    var size: CGFloat = 32
    var iconSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Color.chromeForeground.opacity(0.92))
                // Frame + contentShape inside the label so the whole cell is
                // clickable, not just the glyph.
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close reader")
        .accessibilityLabel("Close reader")
    }
}
