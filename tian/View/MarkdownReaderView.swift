import SwiftUI
import MarkdownUI

/// Read-only markdown viewer rendered inside a tab (in place of a terminal
/// surface). Opened from the Inspect Panel's Files tab by double-clicking a
/// `.md` / `.markdown` file. Loads the file's contents and renders them with
/// MarkdownUI; shows an inline error if the file can't be read.
///
/// Live-reloads: while open it polls the file's modification date and reloads
/// when it changes on disk (handles editor saves, including atomic replaces).
///
/// A markdown tab has no terminal surface, so it can't intercept Cmd+W the way
/// `TerminalSurfaceView` does. A focus-gated hidden button supplies that
/// shortcut so Cmd+W closes the tab instead of falling through to "close
/// window" (which would quit the app).
struct MarkdownReaderView: View {
    /// Tab-lived store holding the pre-parsed content. Persists across tab
    /// switches, so re-activating this view renders already-parsed content
    /// instead of re-reading and re-parsing the file.
    let document: MarkdownDocument
    /// True only when this tab's section owns focus in the active space — gates
    /// the Cmd+W shortcut so background readers don't steal it.
    var isFocused: Bool = false
    /// Closes this reader tab (wired to `SectionModel.removeTab`).
    var onClose: () -> Void = {}

    var body: some View {
        Group {
            if let loadError = document.loadError {
                errorView(loadError)
            } else if document.showDiff {
                MarkdownDiffView(document: document)
            } else {
                ScrollView(.vertical) {
                    Markdown(document.content)
                        .markdownTheme(.tianReader)
                        .textSelection(.enabled)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { closeShortcut }
        .task(id: document.filePath) { await watch() }
        .onChange(of: document.showDiff) { _, showDiff in
            // Load the diff the moment the user toggles into diff mode; the
            // poll keeps it fresh thereafter.
            if showDiff { Task { await document.refreshDiffIfNeeded() } }
        }
    }

    // MARK: - Cmd+W

    private var closeShortcut: some View {
        Button(action: onClose) { EmptyView() }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!isFocused)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    // MARK: - Loading / live reload

    /// Initial load (a no-op re-parse when already cached and unchanged), then
    /// poll once a second and reload on change. Cancelled automatically when the
    /// view disappears or the `filePath` changes. Reads/parses run off-main in
    /// `MarkdownDocument`.
    private func watch() async {
        await document.refreshIfNeeded()
        await document.refreshDiffIfNeeded()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
            await document.refreshIfNeeded()
            // No-op unless the reader is in diff mode and the diff went stale
            // (file changed on disk), so this never spawns git on its own.
            await document.refreshDiffIfNeeded()
        }
    }

    // MARK: - Error state

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Theme

// Internal (not private) so the inline-diff view can reuse the reader's look.
extension Theme {
    /// GitHub theme typography, but with the base-text background stripped so
    /// the reader is transparent and shows the app background behind it.
    /// (Code blocks keep their own subtle background.)
    static var tianReader: Theme {
        Theme.gitHub.text {
            ForegroundColor(.primary)
            FontSize(16)
        }
    }

    /// `tianReader` variant for removed (deleted) diff segments: base text is
    /// tinted muted-red and struck through. (Strikethrough color follows text
    /// color in MarkdownUI, so the two are set together.) Pairs with the red
    /// change-bar / tint that `MarkdownDiffView` draws around the segment.
    static var tianReaderRemoved: Theme {
        Theme.gitHub.text {
            ForegroundColor(DiffColors.deleted)
            FontSize(16)
            StrikethroughStyle(.single)
        }
    }
}
