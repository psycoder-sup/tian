import Foundation
import TOMLKit

/// Result of a successful `config auto-set` run.
struct ConfigAutoSetResult: Equatable {
    let setupCount: Int
    let copyCount: Int
    let archiveCount: Int
}

/// Orchestrates `tian-cli config auto-set`: resolves the repo, invokes
/// `claude -p --json-schema`, decodes the structured payload, renders
/// TOML, and writes `.tian/config.toml`.
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
        // Drop stderr (git prints "fatal: not a git repository" on failure; the
        // non-zero exit status is enough signal). `Pipe()` without a reader
        // risks deadlock if ever filled, so target /dev/null instead.
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

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

    /// Top-level orchestration for `tian-cli config auto-set`.
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

        let envelopeJSON = try invoker.run(
            prompt: AutoSetPrompt.template,
            jsonSchema: AutoSetPayload.jsonSchema,
            cwd: repoRoot,
            model: model
        )

        // Only "not JSON at all" goes to .tian/config.toml.rejected for
        // inspection — semantic failures (is_error, missing structured_output)
        // are already human-readable error messages.
        let envelope: ClaudeResultEnvelope
        do {
            envelope = try JSONDecoder().decode(
                ClaudeResultEnvelope.self,
                from: Data(envelopeJSON.utf8)
            )
        } catch {
            try? writeRejectedOutput(envelopeJSON, repoRoot: repoRoot)
            throw CLIError.general(
                "claude -p did not return a valid JSON envelope: \(error.localizedDescription). Raw output saved to .tian/config.toml.rejected."
            )
        }

        let payload = try Self.extractPayload(envelope)
        let tomlString = try Self.renderTOML(payload: payload)
        try writeConfig(tomlString, to: configURL)

        return ConfigAutoSetResult(
            setupCount: payload.setup.count,
            copyCount: payload.copy.count,
            archiveCount: payload.archive.count
        )
    }

    // MARK: - Envelope decoding

    /// Extracts the schema-validated `structured_output` payload from a
    /// parsed envelope. Rejects error envelopes and missing payloads with
    /// a clear message.
    static func extractPayload(_ envelope: ClaudeResultEnvelope) throws -> AutoSetPayload {
        if envelope.isError {
            let subtype = envelope.subtype ?? "unknown"
            let detail = envelope.result?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                throw CLIError.general(
                    "claude -p returned an error envelope (\(subtype)): \(detail)"
                )
            }
            throw CLIError.general(
                "claude -p returned an error envelope (\(subtype))."
            )
        }

        guard let payload = envelope.structuredOutput else {
            throw CLIError.general(
                "claude -p envelope had no structured_output field. The model may have refused or timed out."
            )
        }

        return payload
    }

    // MARK: - TOML rendering

    /// Renders the validated payload as TOML with a comment header
    /// and any notes prepended as `#` comments.
    static func renderTOML(payload: AutoSetPayload) throws -> String {
        var header = "# tian worktree config — auto-generated by `tian-cli config auto-set`\n"
        if let notes = payload.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            for line in notes.split(separator: "\n", omittingEmptySubsequences: false) {
                header += "# \(line)\n"
            }
        }
        header += "\n"

        // `notes` is rendered in the header only, so encode a narrower
        // shape that excludes it rather than touching `AutoSetPayload`'s
        // Codable conformance (which is also the decoder for the envelope).
        // `archive` is omitted from the encoded body when empty so the
        // generated TOML stays clean for repos that don't need cleanup.
        struct Body: Encodable {
            let setup: [AutoSetPayload.SetupEntry]
            let copy: [AutoSetPayload.CopyEntry]
            let archive: [AutoSetPayload.SetupEntry]?
        }
        let body = Body(
            setup: payload.setup,
            copy: payload.copy,
            archive: payload.archive.isEmpty ? nil : payload.archive
        )

        let encoder = TOMLEncoder()
        let bodyTOML: String
        do {
            bodyTOML = try encoder.encode(body)
        } catch {
            throw CLIError.general(
                "Failed to encode config as TOML: \(error.localizedDescription)"
            )
        }

        return header + bodyTOML
    }

    // MARK: - File writes

    /// Atomically writes the rendered TOML to `.tian/config.toml`.
    /// `String.write(atomically: true)` writes to a sibling tempfile and
    /// renames it into place, so we get atomicity without a hand-rolled
    /// tmp/replace dance.
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

        do {
            try tomlString.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw CLIError.general(
                "Failed to write \(configURL.path): \(error.localizedDescription)"
            )
        }
    }

    /// Writes Claude's raw envelope to `.tian/config.toml.rejected` for
    /// user inspection when envelope decoding fails.
    private func writeRejectedOutput(_ raw: String, repoRoot: URL) throws {
        let dir = repoRoot.appendingPathComponent(".tian")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rejected = dir.appendingPathComponent("config.toml.rejected")
        try raw.write(to: rejected, atomically: true, encoding: .utf8)
    }
}
