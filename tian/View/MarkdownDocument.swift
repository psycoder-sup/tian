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
    /// Verbatim file source, kept so the reader's "copy all" button can copy
    /// the original markdown rather than the rendered text.
    private(set) var rawText = ""
    private(set) var loadError: String?
    private(set) var hasLoaded = false

    // MARK: - Git diff (reader's "Diff" toggle)

    /// Result of diffing the file against its HEAD baseline.
    enum DiffOutcome: Equatable {
        /// The path isn't inside a git work tree — nothing to diff.
        case notInRepo
        /// Line-level segments (unchanged / added / removed) in document order.
        /// All-`.unchanged` means "no changes against HEAD".
        case segments([MarkdownDiffSegment])
    }

    /// `true` when the reader overlays the file's git diff on the rendered
    /// markdown instead of showing it plain. Flipped by the toggle in the
    /// new-tab capsule.
    var showDiff = false
    /// The current diff result; `nil` until the first load completes.
    private(set) var diffOutcome: DiffOutcome?
    private(set) var isLoadingDiff = false
    private(set) var diffHasLoaded = false

    /// Non-nil for a remote workspace: bytes + mtime are fetched over SSH
    /// instead of the local disk. nil keeps the local read path unchanged.
    private let remoteSource: ReaderFileSource?

    private var lastModified: Date?
    /// Guards against overlapping reloads when a parse outlasts the poll tick.
    private var isReloading = false
    /// Set whenever the file content reloads, so the cached diff is recomputed
    /// the next time the reader is in diff mode. `true` initially so the first
    /// toggle-on always loads.
    private var diffStale = true
    /// In-flight diff fetch, cancelled before a newer one starts.
    private var diffTask: Task<Void, Never>?

    init(filePath: String, remoteSource: ReaderFileSource? = nil) {
        self.filePath = filePath
        self.remoteSource = remoteSource
    }

    /// Reload from disk only when the file changed (or was never loaded),
    /// parsing off the main thread. A no-op when the modification date is
    /// unchanged, so re-activating the tab or a routine poll stays instant.
    func refreshIfNeeded() async {
        let mtime = remoteSource != nil
            ? await remoteSource!.modificationDate(path: filePath)
            : Self.modificationDate(filePath)
        if hasLoaded && mtime == lastModified { return }
        if isReloading { return }
        isReloading = true
        defer { isReloading = false }

        let path = filePath
        let boxed: Sendbox<Result<(String, MarkdownContent), Error>>
        if let remoteSource {
            // Remote: fetch bytes over SSH, then parse off the main thread.
            let bytes = await remoteSource.readBytes(path: path)
            boxed = await Task.detached(priority: .userInitiated) {
                () -> Sendbox<Result<(String, MarkdownContent), Error>> in
                guard let bytes, let text = String(data: bytes, encoding: .utf8) else {
                    return Sendbox(value: .failure(NSError(
                        domain: "MarkdownDocument", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Couldn't read remote file"])))
                }
                return Sendbox(value: .success((text, MarkdownContent(text))))
            }.value
        } else {
            boxed = await Task.detached(priority: .userInitiated) {
                () -> Sendbox<Result<(String, MarkdownContent), Error>> in
                do {
                    let text = try String(contentsOfFile: path, encoding: .utf8)
                    return Sendbox(value: .success((text, MarkdownContent(text))))
                } catch {
                    return Sendbox(value: .failure(error))
                }
            }.value
        }

        switch boxed.value {
        case .success(let (text, parsed)):
            rawText = text
            content = parsed
            loadError = nil
        case .failure(let error):
            rawText = ""
            content = MarkdownContent("")
            loadError = "Couldn't open \((path as NSString).lastPathComponent)\n\(error.localizedDescription)"
        }
        lastModified = mtime
        hasLoaded = true
        // The file changed on disk (we returned early when unchanged), so any
        // cached diff is stale — recompute it next time the reader is in diff mode.
        diffStale = true
    }

    /// Recompute the file's diff when needed: only while the reader is in diff
    /// mode and the cached diff is missing or stale. A no-op otherwise, so the
    /// 1 s reader poll can call this every tick without spawning git. The git
    /// baseline fetch runs off the main thread inside `GitStatusService`; the
    /// line diff is pure. The result is published here on the main actor.
    /// Cancels any prior in-flight fetch.
    func refreshDiffIfNeeded() async {
        guard showDiff else { return }
        guard !diffHasLoaded || diffStale else { return }
        // Can't diff a file we couldn't read.
        guard loadError == nil else { return }

        diffTask?.cancel()
        isLoadingDiff = !diffHasLoaded
        let path = filePath
        let new = rawText
        let task = Task { [weak self] in
            let baseline = await GitStatusService.fileBaseline(filePath: path)
            if Task.isCancelled { return }
            let outcome: DiffOutcome
            switch baseline {
            case .notInRepo:
                outcome = .notInRepo
            case .committed(let old):
                outcome = .segments(MarkdownInlineDiff.segments(old: old, new: new))
            case .untracked:
                outcome = .segments(MarkdownInlineDiff.segments(old: "", new: new))
            }
            guard let self else { return }
            self.diffOutcome = outcome
            self.diffHasLoaded = true
            self.diffStale = false
            self.isLoadingDiff = false
        }
        diffTask = task
        await task.value
        if diffTask == task { diffTask = nil }
    }

    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
