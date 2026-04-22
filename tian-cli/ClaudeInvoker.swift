import Foundation

/// Invokes `claude -p` with a given prompt and returns stdout.
///
/// Extracted behind a protocol so `ConfigAutoSetRunner` tests can inject
/// a stub without spawning a real subprocess.
protocol ClaudeInvoker {
    /// - Parameters:
    ///   - prompt: The prompt to send to `claude -p`.
    ///   - cwd: Working directory for the subprocess (the repo root).
    ///   - model: Model name passed via `--model`.
    /// - Returns: Full captured stdout, UTF-8 decoded.
    /// - Throws: `CLIError.general` on spawn failure, non-zero exit, or
    ///   output decoding failure.
    func run(prompt: String, cwd: URL, model: String) throws -> String
}

/// Spawns `claude -p` with read-only tools and captures stdout.
struct ProcessClaudeInvoker: ClaudeInvoker {
    /// Path to the `claude` executable. `nil` means resolve via `PATH`.
    let claudePath: String?

    init(claudePath: String? = nil) {
        self.claudePath = claudePath
    }

    func run(prompt: String, cwd: URL, model: String) throws -> String {
        let process = Process()

        // Resolve the claude executable.
        if let override = claudePath {
            process.executableURL = URL(fileURLWithPath: override)
        } else {
            // Use /usr/bin/env so PATH resolution matches the user's shell.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        }

        var arguments: [String] = []
        if claudePath == nil { arguments.append("claude") }
        arguments.append(contentsOf: [
            "-p",
            "--allowedTools", "Read,Glob,Grep",
            "--permission-mode", "acceptEdits",
            "--model", model,
            prompt,
        ])
        process.arguments = arguments

        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // Let stderr pass through to the user's terminal so any claude
        // diagnostics are visible. (claude -p is mostly silent in text
        // mode, so this is rarely chatty.)
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw CLIError.general(
                "Could not launch claude. Install the Claude CLI (https://claude.com/claude-code) or pass --claude-path. Underlying error: \(error.localizedDescription)"
            )
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CLIError.general(
                "claude -p failed (exit \(process.terminationStatus)). See stderr above for details."
            )
        }

        guard let output = String(data: stdoutData, encoding: .utf8) else {
            throw CLIError.general("claude -p output was not valid UTF-8.")
        }

        return output
    }
}
