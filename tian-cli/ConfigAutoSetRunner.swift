import Foundation

/// Result of a successful `config auto-set` run.
struct ConfigAutoSetResult: Equatable {
    let setupCount: Int
    let copyCount: Int
}

/// Orchestrates `tian config auto-set`: resolves the repo, invokes
/// `claude -p`, validates the output, and writes `.tian/config.toml`.
///
/// Pure Swift — no dependency on `ArgumentParser`. All outside-world
/// behavior (spawning `claude`, etc.) is behind the `ClaudeInvoker`
/// protocol for testability.
struct ConfigAutoSetRunner {
    let invoker: ClaudeInvoker

    /// Runs `git rev-parse --show-toplevel` from the given cwd and
    /// returns the repo root URL.
    func resolveRepoRoot(from cwd: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "--show-toplevel"]
        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe() // swallow git's error output

        do {
            try process.run()
        } catch {
            throw CLIError.general(
                "Could not launch git: \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CLIError.general(
                "Not a git repository. Run this command from inside the repo you want to configure."
            )
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else {
            throw CLIError.general("git output was not valid UTF-8.")
        }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw CLIError.general("git rev-parse returned empty output.")
        }
        return URL(fileURLWithPath: path)
    }
}
