import Foundation
import Observation

/// Lifecycle model for a workspace's SSH connection. The `Workspace` owns exactly
/// one of these when `workspace.remote != nil`.
///
/// It holds the (`Sendable`) `SSHControlChannel` and an observable `state` for UI,
/// **registers the channel into `RemoteExecutionRegistry` synchronously at
/// construction** (a dict insert — this removes every restore/seed ordering race,
/// since git & the file tree can find the channel the moment the workspace
/// exists), and opens the ControlMaster lazily on the first `open()`.
@MainActor
@Observable
final class SSHConnection {
    enum State: Equatable {
        /// Constructed but the master hasn't been opened yet.
        case idle
        /// `open()` is establishing the master.
        case connecting
        /// A live ControlMaster exists.
        case connected
        /// The last connect attempt failed (host down / auth failed). Data
        /// commands still degrade gracefully and self-heal on the next poll.
        case offline
    }

    let host: String
    let remoteDirectory: String
    let channel: SSHControlChannel

    private(set) var state: State = .idle

    init(host: String, remoteDirectory: String) {
        self.host = host
        self.remoteDirectory = remoteDirectory
        self.channel = SSHControlChannel(host: host, root: remoteDirectory)
        // Register synchronously so the channel is discoverable before the first
        // session is seeded/restored (see the type doc's ordering-race note).
        RemoteExecutionRegistry.shared.register(channel)
    }

    /// Opens the shared ControlMaster in the background. Idempotent — a no-op
    /// while already connecting or connected.
    func open() {
        guard state == .idle || state == .offline else { return }
        state = .connecting
        let channel = self.channel
        Task {
            let alive = await channel.openMaster()
            self.state = alive ? .connected : .offline
        }
    }

    /// Tears the master down and unregisters the channel. Called from
    /// `Workspace.cleanup()`. Unregistration is synchronous (so no stale lookups
    /// survive the workspace); the `ssh -O exit` runs detached.
    func close() {
        RemoteExecutionRegistry.shared.unregister(channel)
        state = .idle
        let channel = self.channel
        Task.detached {
            await channel.closeMaster()
        }
    }
}
