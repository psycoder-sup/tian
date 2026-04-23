import Foundation

/// Invokes `claude -p` with a given prompt + JSON Schema and returns the
/// full JSON-envelope stdout.
///
/// Extracted behind a protocol so `ConfigAutoSetRunner` tests can inject
/// a stub without spawning a real subprocess.
protocol ClaudeInvoker {
    /// - Parameters:
    ///   - prompt: The prompt to send to `claude -p`.
    ///   - jsonSchema: Compact JSON Schema passed to `--json-schema`.
    ///     Claude validates its response against this server-side, so
    ///     the caller can trust the shape on a successful envelope.
    ///   - cwd: Working directory for the subprocess (the repo root).
    ///   - model: Model name passed via `--model`.
    /// - Returns: Full captured stdout, UTF-8 decoded. With
    ///   `--output-format json`, this is a single-object JSON envelope.
    /// - Throws: `CLIError.general` on spawn failure, non-zero exit, or
    ///   output decoding failure.
    func run(prompt: String, jsonSchema: String, cwd: URL, model: String) throws -> String
}

/// Spawns `claude -p --json-schema …` with read-only tools and captures stdout.
struct ProcessClaudeInvoker: ClaudeInvoker {
    /// Path to the `claude` executable. `nil` means resolve via `PATH`.
    let claudePath: String?

    init(claudePath: String? = nil) {
        self.claudePath = claudePath
    }

    func run(prompt: String, jsonSchema: String, cwd: URL, model: String) throws -> String {
        let process = Process()

        // `--tools` is authoritative (restricts to exactly these). `--json-schema`
        // + `--output-format json` force a schema-validated `structured_output`.
        var arguments: [String] = [
            "-p",
            "--tools", "Read,Glob,Grep",
            "--model", model,
            "--output-format", "json",
            "--json-schema", jsonSchema,
            prompt,
        ]
        if let override = claudePath {
            process.executableURL = URL(fileURLWithPath: override)
        } else {
            // /usr/bin/env so PATH resolution matches the user's shell.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments.insert("claude", at: 0)
        }
        process.arguments = arguments

        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
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
