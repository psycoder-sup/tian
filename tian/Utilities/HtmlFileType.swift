import Foundation

/// Single source of truth for "is this an HTML file tian opens in the browser".
/// Used by the Inspect Panel's open-file routing (double-click launches the
/// system default browser) and the file-tree row icon, so the supported-
/// extension list lives in exactly one place.
enum HtmlFileType {
    private static let extensions: Set<String> = ["html", "htm", "xhtml"]

    /// True when `ext` (a bare extension, case-insensitive) is an HTML type.
    static func contains(_ ext: String) -> Bool {
        extensions.contains(ext.lowercased())
    }

    /// True when the file at `path` has an HTML extension.
    static func isHtml(path: String) -> Bool {
        contains((path as NSString).pathExtension)
    }
}
