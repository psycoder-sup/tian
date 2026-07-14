import Foundation

/// `InspectFileScanning` conformer that runs the same enumeration commands as
/// `InspectFileScanner`, but over an `SSHControlChannel` instead of a local
/// subprocess. Injected into a remote workspace's `InspectFileTreeViewModel`;
/// its non-nil `pollInterval` makes the view model poll (FSEvents can't watch
/// another host).
struct RemoteInspectFileScanner: InspectFileScanning {
    let channel: SSHControlChannel

    /// Remote trees are refreshed by polling on this cadence.
    var pollInterval: Duration? { .seconds(5) }

    func scanGitTracked(workingTree: String) async throws -> [String] {
        let result = await channel.run(
            argv: ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            workingDirectory: workingTree
        )
        guard result.exitCode == 0 else {
            throw RemoteScanError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return Self.splitNulPaths(result.stdout)
    }

    func scanGitIgnored(workingTree: String) async throws -> InspectIgnoredEntries {
        let result = await channel.run(
            argv: ["git", "ls-files", "--others", "--ignored", "--exclude-standard",
                   "--directory", "-z"],
            workingDirectory: workingTree
        )
        guard result.exitCode == 0 else {
            throw RemoteScanError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        var directories: Set<String> = []
        var files: Set<String> = []
        for entry in Self.splitNulPaths(result.stdout) {
            // git's `--directory` appends `/` to rolled-up directories — the same
            // signal the local scanner keys on.
            if entry.hasSuffix("/") {
                directories.insert(String(entry.dropLast()))
            } else {
                files.insert(entry)
            }
        }
        return InspectIgnoredEntries(directories: directories, files: files)
    }

    func scanFileSystem(root: URL) async throws -> InspectScanResult {
        // Non-repo remote directory: enumerate files with `find`, null-delimited.
        // `-maxdepth` mirrors the local scanner's depth cap; the entry cap is
        // applied here, on the results, since `find` has no equivalent flag.
        let result = await channel.run(
            argv: ["find", ".", "-maxdepth", "\(InspectFileScanner.maxFileSystemDepth)",
                   "-type", "f", "-print0"],
            workingDirectory: root.path
        )
        guard result.exitCode == 0 else {
            throw RemoteScanError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        let paths = Self.splitNulPaths(result.stdout).compactMap { raw -> String? in
            var path = raw
            if path.hasPrefix("./") { path.removeFirst(2) }
            guard !path.isEmpty else { return nil }
            // Match the local FileManager scan's `skipsHiddenFiles`: drop any
            // path with a hidden component at any level (e.g. `.git/…`).
            if path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                return nil
            }
            return path
        }
        let limit = InspectFileScanner.maxFileSystemEntries
        guard paths.count > limit else { return .complete(paths) }
        return InspectScanResult(paths: Array(paths.prefix(limit)), isTruncated: true)
    }

    func scanImmediateChildren(absolutePath: String) async throws -> [InspectChildEntry] {
        // -A: all but `.`/`..`; -p: trailing `/` on directories; -1: one per line.
        // A trailing `/` marks a directory; anything else (including a symlink) is
        // treated as a file, matching the local scanner.
        let result = await channel.run(
            argv: ["ls", "-1Ap"],
            workingDirectory: absolutePath
        )
        guard result.exitCode == 0 else { return [] }
        return result.stdoutTrimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                var name = String(line)
                let isDirectory = name.hasSuffix("/")
                if isDirectory { name.removeLast() }
                guard !name.isEmpty, name != ".DS_Store" else { return nil }
                return InspectChildEntry(name: name, isDirectory: isDirectory)
            }
    }

    private static func splitNulPaths(_ data: Data) -> [String] {
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        return raw.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
    }

    enum RemoteScanError: Error, CustomStringConvertible {
        case commandFailed(exitCode: Int32, stderr: String)

        var description: String {
            switch self {
            case .commandFailed(let code, let stderr):
                return "remote scan command exited \(code): \(stderr)"
            }
        }
    }
}
