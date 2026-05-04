import Foundation

enum InspectFileScanner {
    /// Returns POSIX-relative paths (no leading `./`) for every tracked or
    /// untracked-not-ignored file under `workingTree`. Throws if `git`
    /// returns a non-zero exit code.
    static func scanGitTracked(workingTree: String) async throws -> [String] {
        fatalError("not yet implemented")
    }

    /// Returns POSIX-relative paths for every non-hidden file under `root`
    /// using `FileManager`. Used when the directory is not in a git repo.
    /// Skips bundle internals (`*.app/Contents`) and standard junk like
    /// `.DS_Store`.
    static func scanFileSystem(root: URL) async throws -> [String] {
        fatalError("not yet implemented")
    }
}
