import Foundation

/// Abstracts where the reader loads a file's bytes and modification time from.
/// The reader documents default to reading the local disk directly (source ==
/// nil); a remote workspace injects a `RemoteReaderFileSource` so the same
/// documents fetch over SSH instead.
protocol ReaderFileSource: Sendable {
    /// The file's raw bytes, or nil if it can't be read.
    func readBytes(path: String) async -> Data?
    /// The file's modification time, or nil. Used to skip no-op reloads.
    func modificationDate(path: String) async -> Date?
}

/// Reads a file over an `SSHControlChannel`: `base64` for bytes (so binary image
/// data survives the UTF-8 stdout decode) and `stat` for the modification time.
struct RemoteReaderFileSource: ReaderFileSource {
    let channel: SSHControlChannel

    func readBytes(path: String) async -> Data? {
        let result = await channel.run(
            argv: ["base64", path],
            workingDirectory: (path as NSString).deletingLastPathComponent
        )
        guard result.exitCode == 0 else { return nil }
        // `base64` wraps at 76 columns; `.ignoreUnknownCharacters` skips the
        // embedded newlines.
        return Data(base64Encoded: result.stdoutTrimmed, options: .ignoreUnknownCharacters)
    }

    func modificationDate(path: String) async -> Date? {
        let dir = (path as NSString).deletingLastPathComponent
        // `stat`'s flags differ between GNU (Linux) and BSD (macOS); the argv
        // path can't use a shell `||`, so try GNU epoch-seconds first, then BSD.
        var result = await channel.run(argv: ["stat", "-c", "%Y", path], workingDirectory: dir)
        if result.exitCode != 0 {
            result = await channel.run(argv: ["stat", "-f", "%m", path], workingDirectory: dir)
        }
        guard result.exitCode == 0,
              let seconds = TimeInterval(result.stdoutTrimmed) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
