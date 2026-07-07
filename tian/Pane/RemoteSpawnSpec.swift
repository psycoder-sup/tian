import Foundation

/// Everything `PaneSpawner` needs to spawn a pane over SSH instead of locally.
/// Propagated from `Workspace` → `Session` → `PaneViewModel.remoteSpawn`; nil
/// for local panes, which keeps the local spawn path byte-for-byte unchanged.
///
/// `remoteDirectory` is the workspace's remote root (informational — a pane's
/// actual `cd` target is its own resolved working directory, which is what
/// `PaneSpawner` puts into the ssh command line); `channel` carries the host and
/// multiplex options.
struct RemoteSpawnSpec: Sendable, Equatable {
    let channel: SSHControlChannel
    let remoteDirectory: String
}
