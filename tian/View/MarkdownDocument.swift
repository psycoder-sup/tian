import Foundation
import MarkdownUI

/// Transfers a non-`Sendable` value across an actor boundary. Justified for
/// immutable value types (here `MarkdownContent`, a tree of value-type blocks)
/// that are safe to hand off once constructed.
private struct Sendbox<T>: @unchecked Sendable { let value: T }

/// Tab-lived model backing a markdown reader tab. Holds the *pre-parsed*
/// `MarkdownContent` so that switching to the tab doesn't re-read or re-parse
/// the file — the view just lays out content the model already has. Mirrors how
/// a terminal pane's ghostty surface lives in the model and is reused across
/// tab switches, rather than being rebuilt by the transient SwiftUI view.
///
/// Reads and CommonMark parsing run off the main thread; the parsed result is
/// published on the main actor for the view to observe.
@MainActor @Observable
final class MarkdownDocument {
    let filePath: String
    private(set) var content = MarkdownContent("")
    private(set) var loadError: String?
    private(set) var hasLoaded = false

    private var lastModified: Date?
    /// Guards against overlapping reloads when a parse outlasts the poll tick.
    private var isReloading = false

    init(filePath: String) { self.filePath = filePath }

    /// Reload from disk only when the file changed (or was never loaded),
    /// parsing off the main thread. A no-op when the modification date is
    /// unchanged, so re-activating the tab or a routine poll stays instant.
    func refreshIfNeeded() async {
        let mtime = Self.modificationDate(filePath)
        if hasLoaded && mtime == lastModified { return }
        if isReloading { return }
        isReloading = true
        defer { isReloading = false }

        let path = filePath
        let boxed = await Task.detached(priority: .userInitiated) {
            () -> Sendbox<Result<MarkdownContent, Error>> in
            do {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                return Sendbox(value: .success(MarkdownContent(text)))
            } catch {
                return Sendbox(value: .failure(error))
            }
        }.value

        switch boxed.value {
        case .success(let parsed):
            content = parsed
            loadError = nil
        case .failure(let error):
            content = MarkdownContent("")
            loadError = "Couldn't open \((path as NSString).lastPathComponent)\n\(error.localizedDescription)"
        }
        lastModified = mtime
        hasLoaded = true
    }

    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
