import Foundation

/// Single source of truth for "is this a file tian can open in the image
/// reader". Used by the Inspect Panel's open-file routing (which viewer to
/// launch) and the file-tree row icon, so the supported-extension list lives
/// in exactly one place.
///
/// The set covers the raster formats ImageIO / `NSImage` decode natively on
/// the target OS. Animated GIFs open as their first frame (static).
enum ImageFileType {
    private static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif",
        "tiff", "tif", "bmp", "webp", "ico"
    ]

    /// True when `ext` (a bare extension, case-insensitive) is a supported image type.
    static func contains(_ ext: String) -> Bool {
        extensions.contains(ext.lowercased())
    }

    /// True when the file at `path` has a supported image extension.
    static func isImage(path: String) -> Bool {
        contains((path as NSString).pathExtension)
    }
}
