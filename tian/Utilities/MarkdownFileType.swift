import Foundation

/// Single source of truth for "is this a file tian opens in the markdown
/// reader". Mirrors `ImageFileType`, so the Inspect Panel's open-file routing
/// classifies both reader kinds through typed helpers instead of hardcoded
/// extension strings.
enum MarkdownFileType {
    static let extensions: Set<String> = ["md", "markdown"]

    /// True when the file at `path` has a supported markdown extension.
    static func isMarkdown(path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }
}
