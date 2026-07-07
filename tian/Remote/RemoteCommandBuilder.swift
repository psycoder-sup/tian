import Foundation

/// POSIX shell single-quote escaping. Wrapping a string in single quotes makes
/// the shell treat every character literally; the one character that can't
/// appear inside single quotes — the single quote itself — is emitted by
/// closing the quote, escaping a literal `'` as `\'`, then reopening. This is
/// the standard `'\''` idiom.
enum ShellQuoting {
    static func singleQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Shared ssh ControlMaster options. Every ssh invocation tian makes — the
/// non-interactive data channel (git / ls / cat) and the interactive pane
/// spawn — uses the same `ControlPath`, so they multiplex over a single master
/// connection and each command is near-instant after the first.
enum SSHMultiplexing {
    /// Directory holding ControlMaster sockets. ssh will NOT create it, so the
    /// channel `mkdir -p -m 700`s it before opening a master.
    ///
    /// Namespaced by uid and created mode-700 so it isn't a shared, world-
    /// writable path another local user could pre-create to hijack the
    /// multiplexed connection. Kept under `/tmp` (not `$TMPDIR`) so the path plus
    /// ssh's `%C` digest stays well under the ~104-char `sun_path` limit.
    static let controlDirectory = "/tmp/tian-ssh-\(getuid())"

    /// ssh's `%C` token hashes (localhost, host, port, user) into a short digest,
    /// keeping the socket path well under the ~104-char `sun_path` limit that a
    /// literal `%r@%h:%p` path would blow past for long hostnames.
    static let controlPath = "\(controlDirectory)/%C"

    /// The `ControlPath` option on its own — needed by `-O check` / `-O exit`,
    /// which must locate the existing socket.
    static let controlPathOption = ["-o", "ControlPath=\(controlPath)"]

    /// Options establishing / reusing the shared master.
    private static let multiplexOptions = [
        "-o", "ControlMaster=auto",
        "-o", "ControlPath=\(controlPath)",
        "-o", "ControlPersist=45",
    ]

    /// Data-channel options: multiplex, plus fail fast and never block on an
    /// interactive prompt (`BatchMode=yes`, `ConnectTimeout=8`). Used for every
    /// git / directory-listing / file-read command.
    static let dataChannelOptions = multiplexOptions + [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=8",
    ]

    /// Interactive (pane) options: multiplex over the same master, but WITHOUT
    /// `BatchMode` so the terminal can prompt for a passphrase if the master
    /// isn't up yet. Once the data channel has opened the master, the pane
    /// reuses it and never prompts.
    static let interactiveOptions = multiplexOptions
}

/// Builds the two kinds of remote command strings tian sends over ssh:
///
/// 1. A non-interactive `cd <dir> && exec <argv>` string handed to the data
///    channel for git / `ls` / `cat` queries.
/// 2. The full interactive `ssh -tt … 'cd <dir> && exec <cmd>'` command line
///    handed to ghostty's `config.command` for pane spawn.
///
/// Two quoting layers are in play for the interactive line and both are covered
/// by `RemoteCommandBuilderTests`: ghostty runs `config.command` through a local
/// shell (`/bin/sh -c` / `bash -c "exec -l …"`, per ghostty's embedded apprt),
/// which is the first layer; the remote shell that ssh spawns is the second.
enum RemoteCommandBuilder {

    /// Remote-shell command for a non-interactive query: change into
    /// `workingDirectory`, then `exec` the argv. Every element is single-quoted
    /// so shell metacharacters in paths or arguments stay literal on the remote.
    static func remoteShellCommand(argv: [String], workingDirectory: String) -> String {
        let cd = "cd " + ShellQuoting.singleQuote(workingDirectory)
        let exec = "exec " + argv.map(ShellQuoting.singleQuote).joined(separator: " ")
        return cd + " && " + exec
    }

    /// The full local command line for spawning an interactive remote session,
    /// suitable for ghostty's `config.command`. Runs `ssh -tt` over the shared
    /// ControlMaster, changes into `workingDirectory` on the host, then execs
    /// `remoteCommand` (e.g. `claude` or `"$SHELL" -l`).
    ///
    /// `remoteCommand` is inserted into the remote-shell fragment *unquoted*, so
    /// the remote shell expands things like `$SHELL`; the whole fragment is then
    /// single-quoted for the local shell so it reaches ssh as one argument and
    /// no local expansion happens.
    static func interactiveSSHCommandLine(
        host: String,
        workingDirectory: String,
        remoteCommand: String
    ) -> String {
        let remoteFragment = "cd " + ShellQuoting.singleQuote(workingDirectory)
            + " && exec " + remoteCommand
        let options = SSHMultiplexing.interactiveOptions.joined(separator: " ")
        return "/usr/bin/ssh -tt " + options
            + " " + ShellQuoting.singleQuote(host)
            + " " + ShellQuoting.singleQuote(remoteFragment)
    }
}
