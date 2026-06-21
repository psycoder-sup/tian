import SwiftUI

/// Read-only image viewer rendered inside a tab (in place of a terminal
/// surface). Opened from the Inspect Panel's Files tab by double-clicking an
/// image file (see `ImageFileType`). Draws the decoded bitmap aspect-fit and
/// centered; shows an inline error if the file can't be decoded.
///
/// Live-reloads: while open it polls the file's modification date and reloads
/// when it changes on disk. Mirrors `MarkdownReaderView` — including the
/// focus-gated hidden button that supplies Cmd+W (a reader tab has no terminal
/// surface to intercept it, so without this Cmd+W would close the window).
struct ImageReaderView: View {
    /// Tab-lived store holding the decoded image. Persists across tab switches,
    /// so re-activating this view draws the already-decoded bitmap instead of
    /// re-reading the file.
    let document: ImageDocument
    /// True only when this tab's section owns focus in the active space — gates
    /// the Cmd+W shortcut so background readers don't steal it.
    var isFocused: Bool = false
    /// Closes this reader tab (wired to `SectionModel.removeTab`).
    var onClose: () -> Void = {}

    var body: some View {
        Group {
            if let loadError = document.loadError {
                errorView(loadError)
            } else if let image = document.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    // Never upscale past native size; fit-to-window otherwise.
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                // Brief window between tab-open and the off-main decode landing.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { closeShortcut }
        .task(id: document.filePath) { await watch() }
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

    /// Initial load (a no-op when already cached and unchanged), then poll once
    /// a second and reload on change. Cancelled automatically when the view
    /// disappears or the `filePath` changes. Reads/decode run off-main in
    /// `ImageDocument`.
    private func watch() async {
        await document.refreshIfNeeded()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
            await document.refreshIfNeeded()
        }
    }

    // MARK: - Error state

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
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
