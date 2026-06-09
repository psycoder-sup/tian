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
    let filePath: String
    /// True only when this tab's section owns focus in the active space — gates
    /// the Cmd+W shortcut so background readers don't steal it.
    var isFocused: Bool = false
    /// Closes this reader tab (wired to `SectionModel.removeTab`).
    var onClose: () -> Void = {}

    @State private var content: String = ""
    @State private var loadError: String?
    @State private var lastModified: Date?

    var body: some View {
        Group {
            if let loadError {
                errorView(loadError)
            } else {
                ScrollView(.vertical) {
                    Markdown(content)
                        .markdownTheme(.tianReader)
                        .textSelection(.enabled)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { closeShortcut }
        .task(id: filePath) { await watch() }
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

    /// Initial load, then poll the modification date once a second and reload
    /// on change. Cancelled automatically when the view disappears or the
    /// `filePath` changes.
    private func watch() async {
        load()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
            if modificationDate() != lastModified { load() }
        }
    }

    private func load() {
        do {
            content = try String(contentsOfFile: filePath, encoding: .utf8)
            lastModified = modificationDate()
            loadError = nil
        } catch {
            content = ""
            lastModified = modificationDate()
            loadError = "Couldn't open \((filePath as NSString).lastPathComponent)\n\(error.localizedDescription)"
        }
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: filePath))?[.modificationDate] as? Date
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

private extension Theme {
    /// GitHub theme typography, but with the base-text background stripped so
    /// the reader is transparent and shows the app background behind it.
    /// (Code blocks keep their own subtle background.)
    static var tianReader: Theme {
        Theme.gitHub.text {
            ForegroundColor(.primary)
            FontSize(16)
        }
    }
}
