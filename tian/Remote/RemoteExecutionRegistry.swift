import Foundation

/// Process-wide `root -> channel` map. `GitStatusService` is a stateless enum
/// with dozens of `directory: String` call sites; rather than thread a channel
/// through every one, it consults this registry inside its single `runGit` /
/// `runProcess` choke points to learn whether a directory is remote.
///
/// Lookup is longest-prefix so a nested path (a worktree, a subdirectory, a
/// file's parent) under a registered remote root resolves to that root's
/// channel. The local (non-remote) case is the empty registry: a lock plus an
/// empty loop, which is why the seam can sit in git's hot path without changing
/// local behavior.
///
/// The lookup key is a *directory path* — which isn't globally unique, since two
/// hosts can expose the same absolute path (e.g. `/srv/app` on staging and
/// prod). When two channels register the same root, the root is **ambiguous**
/// and `channel(forDirectory:)` returns nil rather than guessing a host — the
/// colliding workspaces degrade to "no remote git" (local git runs, finds no
/// repo at that remote-only path, shows nothing) instead of silently reading the
/// wrong host. They self-heal the moment one of them closes.
final class RemoteExecutionRegistry: @unchecked Sendable {
    static let shared = RemoteExecutionRegistry()

    private let lock = NSLock()
    /// Root → channels. Normally one channel per root; more than one means the
    /// root is ambiguous (same path on different hosts) and won't resolve.
    private var channelsByRoot: [String: [SSHControlChannel]] = [:]

    /// Tests construct their own instance; production uses `.shared`.
    init() {}

    /// Registers a channel under its `root`. Called synchronously from
    /// `SSHConnection.init` so a channel is discoverable the instant the
    /// workspace exists — before any session is seeded or restored.
    func register(_ channel: SSHControlChannel) {
        let key = Self.normalize(channel.root)
        lock.lock()
        defer { lock.unlock() }
        var channels = channelsByRoot[key] ?? []
        // Avoid duplicate entries for the same (host, root) on a re-register.
        guard !channels.contains(channel) else { return }
        if !channels.isEmpty {
            Log.remote.error("Remote root \(key, privacy: .public) is now ambiguous across hosts (\(channels.map(\.host).joined(separator: ", "), privacy: .public) + \(channel.host, privacy: .public)); remote git/file/reader are disabled for these workspaces until one closes.")
        }
        channels.append(channel)
        channelsByRoot[key] = channels
    }

    /// Unregisters a channel, leaving any other channel that shared the same
    /// normalized root (a different host) in place. Matched by host within the
    /// normalized-root bucket, so a trailing-slash difference in `root` doesn't
    /// prevent removal.
    func unregister(_ channel: SSHControlChannel) {
        let key = Self.normalize(channel.root)
        lock.lock()
        defer { lock.unlock() }
        guard var channels = channelsByRoot[key] else { return }
        channels.removeAll { $0.host == channel.host }
        if channels.isEmpty {
            channelsByRoot.removeValue(forKey: key)
        } else {
            channelsByRoot[key] = channels
        }
    }

    /// The channel serving `directory`, or nil if the directory isn't under any
    /// registered remote root — or the matching root is ambiguous (registered by
    /// more than one host). Longest matching root wins.
    func channel(forDirectory directory: String) -> SSHControlChannel? {
        let dir = Self.normalize(directory)
        lock.lock()
        defer { lock.unlock() }
        guard !channelsByRoot.isEmpty else { return nil }

        var bestChannels: [SSHControlChannel]?
        var bestLength = -1
        for (root, channels) in channelsByRoot where Self.isPrefix(root, of: dir) {
            if root.count > bestLength {
                bestChannels = channels
                bestLength = root.count
            }
        }
        // Exactly one channel at the longest-matching root, else ambiguous → nil.
        guard let bestChannels, bestChannels.count == 1 else { return nil }
        return bestChannels[0]
    }

    // MARK: - Path helpers

    /// Strips a trailing slash so `/srv/app` and `/srv/app/` compare equal.
    /// The filesystem root `/` is left intact.
    static func normalize(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    /// True when `root` is `dir` itself or a path-boundary prefix of it —
    /// `/srv/app` is a prefix of `/srv/app/sub` but NOT of `/srv/app-2`.
    /// Assumes both inputs are already normalized.
    static func isPrefix(_ root: String, of dir: String) -> Bool {
        if root == dir { return true }
        if root == "/" { return dir.hasPrefix("/") }
        return dir.hasPrefix(root + "/")
    }
}
