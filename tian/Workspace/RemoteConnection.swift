import Foundation

/// A workspace's SSH target. `host` is an ssh alias (e.g. `myserver`) or
/// `user@host`; `remoteDirectory` is the absolute POSIX path on that host that
/// every session under the workspace operates against.
///
/// The remote path is deliberately also stored in the workspace's existing
/// `defaultWorkingDirectory` (a POSIX path round-trips through `URL.path`
/// unchanged), so every working-directory resolver keeps working verbatim; this
/// value type just records that the path is *remote* and on which host.
struct RemoteConnection: Sendable, Equatable, Hashable {
    var host: String
    var remoteDirectory: String

    init(host: String, remoteDirectory: String) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteDirectory = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the host is safe to hand to `ssh` as a destination argument. A
    /// value starting with `-` would be parsed by ssh as an *option* (e.g.
    /// `-oProxyCommand=…`), so rejecting it closes an argument-injection →
    /// local-command-execution vector. A real ssh alias or `user@host` never
    /// starts with `-`. Enforced at every creation boundary and, as a backstop,
    /// in `SSHControlChannel` (which also covers a hand-edited persisted state).
    var isHostSafe: Bool {
        !host.isEmpty && !host.hasPrefix("-")
    }

    /// A default workspace name derived from the target, mirroring how a local
    /// workspace names itself from its directory basename — e.g.
    /// `myserver:/srv/app` → `app @ myserver`. Falls back to the full path when
    /// the directory has no basename (e.g. the remote home `~` or `/`).
    static func deriveWorkspaceName(host: String, remoteDirectory: String) -> String {
        let trimmedDir = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmedDir as NSString).lastPathComponent
        let label = (base.isEmpty || base == "/") ? trimmedDir : base
        // Drop any `user@` prefix so the host reads cleanly in the label.
        let shortHost = host.split(separator: "@").last.map(String.init) ?? host
        let cleanHost = shortHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanHost.isEmpty ? label : "\(label) @ \(cleanHost)"
    }
}
