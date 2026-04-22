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

    /// Top-level orchestration for `tian config auto-set`.
    ///
    /// - Parameters:
    ///   - cwd: User's current working directory.
    ///   - force: Overwrite an existing `.tian/config.toml` if true.
    ///   - model: Claude model name passed through to `claude -p --model`.
    /// - Returns: Counts of setup/copy entries written.
    /// - Throws: `CLIError` on any failure.
    @discardableResult
    func run(cwd: URL, force: Bool, model: String) throws -> ConfigAutoSetResult {
        let repoRoot = try resolveRepoRoot(from: cwd)
        let configURL = repoRoot
            .appendingPathComponent(".tian")
            .appendingPathComponent("config.toml")

        if FileManager.default.fileExists(atPath: configURL.path) && !force {
            throw CLIError.general(
                ".tian/config.toml already exists. Re-run with --force to overwrite."
            )
        }

        FileHandle.standardError.write(Data(
            "Analyzing repository with claude -p (this usually takes 20–60s)…\n".utf8
        ))

        let tomlString = try invoker.run(
            prompt: AutoSetPrompt.template,
            cwd: repoRoot,
            model: model
        )

        let validation: ConfigValidationResult
        do {
            validation = try ConfigValidator.validate(tomlString: tomlString)
        } catch {
            try? writeRejectedOutput(tomlString, repoRoot: repoRoot)
            throw CLIError.general(
                "\(error.localizedDescription) Raw output saved to .tian/config.toml.rejected."
            )
        }

        try writeConfig(tomlString, to: configURL)

        return ConfigAutoSetResult(
            setupCount: validation.setupCount,
            copyCount: validation.copyCount
        )
    }

    // MARK: - File writes

    /// Atomically writes the validated TOML to `.tian/config.toml`.
    private func writeConfig(_ tomlString: String, to configURL: URL) throws {
        let dir = configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
        } catch {
            throw CLIError.general(
                "Failed to create \(dir.path): \(error.localizedDescription)"
            )
        }

        let tmpURL = configURL.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tmpURL) // clear stale tmp
        do {
            try tomlString.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            throw CLIError.general(
                "Failed to write \(tmpURL.path): \(error.localizedDescription)"
            )
        }

        // Atomic replace. If the destination doesn't exist,
        // replaceItemAt throws, so fall back to a plain move.
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                _ = try FileManager.default.replaceItemAt(configURL, withItemAt: tmpURL)
            } catch {
                throw CLIError.general(
                    "Failed to replace \(configURL.path): \(error.localizedDescription)"
                )
            }
        } else {
            do {
                try FileManager.default.moveItem(at: tmpURL, to: configURL)
            } catch {
                throw CLIError.general(
                    "Failed to move \(tmpURL.path) → \(configURL.path): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Writes Claude's raw output to `.tian/config.toml.rejected` for
    /// user inspection when validation fails.
    private func writeRejectedOutput(_ tomlString: String, repoRoot: URL) throws {
        let dir = repoRoot.appendingPathComponent(".tian")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rejected = dir.appendingPathComponent("config.toml.rejected")
        try tomlString.write(to: rejected, atomically: true, encoding: .utf8)
    }
}
