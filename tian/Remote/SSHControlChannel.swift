import Foundation

/// Nonisolated, `Sendable` channel that shells out over a multiplexed ssh
/// ControlMaster connection. Every git / directory-listing / file-read command
/// for a remote workspace funnels through `run`.
///
/// Must stay off-main because `GitStatusService.runGit` — its principal caller
/// via the registry redirect — runs on `DispatchQueue.global`.
///
/// `run` never throws: an ssh spawn failure or an offline host surfaces as a
/// non-zero `CommandResult`, which the git / file-tree / reader layers already
/// treat as "no data" and retry on the next poll. This is the graceful-
/// degradation contract for offline / auth-failing hosts.
struct SSHControlChannel: Sendable, Equatable {
    /// ssh alias (e.g. `myserver`) or `user@host`.
    let host: String
    /// The remote directory root this channel serves. Used by
    /// `RemoteExecutionRegistry` for longest-prefix matching.
    let root: String

    /// Raw result of a remote command: the union of the two existing local
    /// contracts (`GitStatusService.runGit`'s trimmed String and
    /// `InspectFileScanner.runGit`'s raw `Data`). Callers pick whichever they
    /// need — `stdout` bytes for `-z` / binary output, `stdoutTrimmed` for the
    /// text contract git callers expect.
    struct CommandResult: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: String

        /// stdout decoded as UTF-8 and trimmed of surrounding newlines — matches
        /// `GitStatusService.runGit`'s String contract exactly.
        var stdoutTrimmed: String {
            String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
        }

        /// Synthetic result for when the local ssh process couldn't even be
        /// spawned. 255 is ssh's own "connection error" exit code, so callers
        /// that branch on it can't tell a spawn failure from a connect failure —
        /// which is exactly the point: both mean "no data this round".
        static func spawnFailure(_ message: String) -> CommandResult {
            CommandResult(exitCode: 255, stdout: Data(), stderr: message)
        }
    }

    /// Whether `host` is safe to pass to `ssh` as a destination. A host starting
    /// with `-` would be parsed as an ssh *option* (argument injection); a real
    /// alias / `user@host` never does. This is the last-line backstop — creation
    /// boundaries reject such hosts up front, but this also covers a hand-edited
    /// persisted `state.json`.
    private var hostIsSafe: Bool {
        !host.isEmpty && !host.hasPrefix("-")
    }

    /// Runs `argv` in `workingDirectory` on the remote host, returning raw
    /// stdout. The argv is the full command (executable first), e.g.
    /// `["git", "--no-optional-locks", "status", …]` or `["cat", path]`.
    func run(argv: [String], workingDirectory: String) async -> CommandResult {
        guard hostIsSafe else {
            return .spawnFailure("refusing to run ssh with unsafe host \(host)")
        }
        let remote = RemoteCommandBuilder.remoteShellCommand(
            argv: argv,
            workingDirectory: workingDirectory
        )
        let sshArgs = SSHMultiplexing.dataChannelOptions + [host, remote]
        return await Self.runProcess(executable: Self.sshPath, arguments: sshArgs)
    }

    /// Opens (or confirms) the shared ControlMaster. Idempotent thanks to
    /// `ControlMaster=auto`. Best-effort: a failure just means the first `run`
    /// pays the connect cost instead. Returns whether the master is now alive.
    @discardableResult
    func openMaster() async -> Bool {
        guard hostIsSafe else {
            Log.remote.error("refusing to open ssh master with unsafe host \(self.host, privacy: .public)")
            return false
        }
        // ssh won't create the socket directory; make sure it exists (private to
        // this user — mode 700) first.
        _ = await Self.runProcess(
            executable: "/bin/mkdir",
            arguments: ["-p", "-m", "700", SSHMultiplexing.controlDirectory]
        )
        // `-N -f`: no remote command, fork to background once connected. With
        // ControlPersist the master lingers after this returns.
        let args = SSHMultiplexing.dataChannelOptions + ["-N", "-f", host]
        let result = await Self.runProcess(executable: Self.sshPath, arguments: args)
        if result.exitCode != 0 {
            Log.remote.error("ssh master open failed for \(host, privacy: .public): \(result.stderr, privacy: .public)")
            return false
        }
        return await checkMaster()
    }

    /// Whether a live ControlMaster socket exists for this host (`ssh -O check`).
    func checkMaster() async -> Bool {
        guard hostIsSafe else { return false }
        let args = SSHMultiplexing.controlPathOption + ["-O", "check", host]
        let result = await Self.runProcess(executable: Self.sshPath, arguments: args)
        return result.exitCode == 0
    }

    /// Tears the ControlMaster down (`ssh -O exit`). Called from
    /// `SSHConnection.close()` when the workspace is closed.
    func closeMaster() async {
        guard hostIsSafe else { return }
        let args = SSHMultiplexing.controlPathOption + ["-O", "exit", host]
        _ = await Self.runProcess(executable: Self.sshPath, arguments: args)
    }

    // MARK: - Process plumbing

    private static let sshPath = "/usr/bin/ssh"

    /// Spawns a local process on a background queue and collects its output.
    /// Mirrors `GitStatusService.runGit`'s pattern (cancellation-aware,
    /// `DispatchQueue.global`) but returns raw stdout `Data`. Never throws —
    /// a spawn error becomes a `spawnFailure` result.
    private static func runProcess(
        executable: String,
        arguments: [String]
    ) async -> CommandResult {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(
                            returning: .spawnFailure("failed to spawn \(executable): \(error)")
                        )
                        return
                    }

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let stderr = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .newlines) ?? ""
                    continuation.resume(returning: CommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdoutData,
                        stderr: stderr
                    ))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
