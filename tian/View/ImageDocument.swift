import AppKit
import ImageIO

/// Transfers a non-`Sendable` value across an actor boundary. Justified for the
/// freshly-constructed `NSImage` handed off once from the decode task and never
/// mutated afterward. Mirrors the same helper in `MarkdownDocument`.
private struct Sendbox<T>: @unchecked Sendable { let value: T }

/// Tab-lived model backing an image reader tab. Holds the *decoded* `NSImage`
/// so switching to the tab doesn't re-read or re-decode the file — the view
/// just draws the bitmap the model already has. Mirrors `MarkdownDocument`
/// (and, like a terminal pane's ghostty surface, the heavy state lives in the
/// model and is reused across tab switches rather than rebuilt by the view).
///
/// The read + decode run off the main thread; the result is published on the
/// main actor for the view to observe, so opening never blocks the UI.
@MainActor @Observable
final class ImageDocument {
    let filePath: String
    /// The decoded bitmap. Its `.size` carries the native dimensions the view
    /// uses to avoid upscaling small images past 100%.
    private(set) var image: NSImage?
    private(set) var loadError: String?
    private(set) var hasLoaded = false

    private var lastModified: Date?
    /// Guards against overlapping reloads when a decode outlasts the poll tick.
    private var isReloading = false

    init(filePath: String) { self.filePath = filePath }

    /// Reload from disk only when the file changed (or was never loaded),
    /// decoding off the main thread. A no-op when the modification date is
    /// unchanged, so re-activating the tab or a routine poll stays instant.
    func refreshIfNeeded() async {
        let mtime = Self.modificationDate(filePath)
        if hasLoaded && mtime == lastModified { return }
        if isReloading { return }
        isReloading = true
        defer { isReloading = false }

        let path = filePath
        let boxed = await Task.detached(priority: .userInitiated) {
            () -> Sendbox<Result<NSImage, Error>> in
            let url = URL(fileURLWithPath: path)
            // Decode fully now (off-main) so the first draw is a cheap GPU
            // upload with no main-thread hitch.
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                let size = CGSize(width: cg.width, height: cg.height)
                return Sendbox(value: .success(NSImage(cgImage: cg, size: size)))
            }
            // Fallback for anything ImageIO won't open but NSImage will.
            if let img = NSImage(contentsOf: url) {
                return Sendbox(value: .success(img))
            }
            return Sendbox(value: .failure(NSError(
                domain: "ImageDocument", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported or unreadable image"])))
        }.value

        switch boxed.value {
        case .success(let img):
            image = img
            loadError = nil
        case .failure(let error):
            image = nil
            loadError = "Couldn't open \((path as NSString).lastPathComponent)\n\(error.localizedDescription)"
        }
        lastModified = mtime
        hasLoaded = true
    }

    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
