import SwiftUI
import MarkdownUI

/// Read-only markdown viewer rendered inside a tab (in place of a terminal
/// surface). Opened from the Inspect Panel's Files tab by double-clicking a
/// `.md` / `.markdown` file. Loads the file's contents and renders them with
/// MarkdownUI; shows an inline error if the file can't be read.
struct MarkdownReaderView: View {
    let filePath: String

    @State private var content: String = ""
    @State private var loadError: String?

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
        .task(id: filePath) { load() }
    }

    // MARK: - Loading

    private func load() {
        do {
            content = try String(contentsOfFile: filePath, encoding: .utf8)
            loadError = nil
        } catch {
            content = ""
            loadError = "Couldn't open \((filePath as NSString).lastPathComponent)\n\(error.localizedDescription)"
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
