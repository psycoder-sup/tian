import Foundation
import Observation

/// Backing state for the session's single replace-on-open reader overlay.
///
/// A session shows at most one reader at a time, layered over the Claude
/// region (`ReaderOverlayView`). Opening a new file replaces whatever is
/// showing; re-opening the file already on screen is a no-op so the overlay
/// doesn't rebuild its document. Not persisted.
@MainActor @Observable
final class SessionReaderState {
    /// The document kind currently shown in the overlay.
    enum Content {
        case markdown(MarkdownDocument)
        case image(ImageDocument)
    }

    private(set) var current: Content?

    /// Non-nil for a remote workspace — the reader documents fetch bytes + mtime
    /// over SSH instead of the local disk. Set by `Session.wirePane`.
    var fileSource: ReaderFileSource?

    /// Opens `filePath` as a markdown reader, replacing the current overlay.
    /// A no-op when the same markdown file is already showing.
    func openMarkdown(filePath: String) {
        if case .markdown(let doc) = current, doc.filePath == filePath { return }
        current = .markdown(MarkdownDocument(filePath: filePath, remoteSource: fileSource))
    }

    /// Opens `filePath` as an image reader, replacing the current overlay.
    /// A no-op when the same image file is already showing.
    func openImage(filePath: String) {
        if case .image(let doc) = current, doc.filePath == filePath { return }
        current = .image(ImageDocument(filePath: filePath, remoteSource: fileSource))
    }

    /// Dismisses the overlay.
    func close() {
        current = nil
    }
}
