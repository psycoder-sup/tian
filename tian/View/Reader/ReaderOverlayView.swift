import SwiftUI

/// The session's single reader, layered over the Claude region by
/// `SessionContentView` whenever `session.readerState.current != nil`.
///
/// A slim chrome bar (file name, markdown-only diff/copy controls, and a close
/// X) sits above the reader body — `MarkdownReaderView` or `ImageReaderView`,
/// switched on `content`. The overlay paints an opaque background so it fully
/// covers the live Claude pane beneath: the Claude surface stays mounted (no
/// Metal teardown) and is simply hidden while the reader is up, the same
/// keep-mounted approach the old section reader branch used.
struct ReaderOverlayView: View {
    let content: SessionReaderState.Content
    /// True only while the Claude region owns focus — gates the readers' hidden
    /// Cmd+W button so a background overlay doesn't steal the shortcut.
    let isFocused: Bool
    /// Dismisses the overlay (chrome X and the readers' Cmd+W both route here).
    let onClose: () -> Void

    /// Mirrors `GhosttyApp.shared.defaultBackgroundColor` so the overlay fills
    /// with the same color the Claude pane Metal layer paints, refreshed on
    /// `defaultBackgroundColorChangedNotification`.
    @State private var backgroundColor: Color = Color(nsColor: GhosttyApp.shared.defaultBackgroundColor)

    private static let chromeHeight: CGFloat = 32

    private var fileName: String {
        let path: String
        switch content {
        case .markdown(let doc): path = doc.filePath
        case .image(let doc): path = doc.filePath
        }
        return (path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            reader
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .onReceive(NotificationCenter.default.publisher(for: GhosttyApp.defaultBackgroundColorChangedNotification)) { _ in
            let new = Color(nsColor: GhosttyApp.shared.defaultBackgroundColor)
            guard new != backgroundColor else { return }
            backgroundColor = new
        }
    }

    // MARK: - Chrome

    private var chromeBar: some View {
        HStack(spacing: 4) {
            Text(fileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.chromeForeground.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 8)

            Spacer(minLength: 8)

            if case .markdown(let document) = content {
                MarkdownDiffToggleButton(document: document)
                MarkdownCopyButton(document: document)
            }
            ReaderCloseButton(action: onClose)
        }
        .frame(height: Self.chromeHeight)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Reader body

    @ViewBuilder
    private var reader: some View {
        switch content {
        case .markdown(let document):
            MarkdownReaderView(document: document, isFocused: isFocused, onClose: onClose)
        case .image(let document):
            ImageReaderView(document: document, isFocused: isFocused, onClose: onClose)
        }
    }
}
