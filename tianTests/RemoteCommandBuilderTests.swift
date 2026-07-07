import Testing
import Foundation
@testable import tian

/// Covers the two shell-quoting layers a remote command passes through: the
/// local shell that ghostty runs `config.command` under, and the remote shell
/// that ssh spawns.
struct RemoteCommandBuilderTests {

    // MARK: - ShellQuoting

    @Test func singleQuoteWrapsPlainString() {
        #expect(ShellQuoting.singleQuote("hello") == "'hello'")
    }

    @Test func singleQuoteEscapesEmbeddedSingleQuote() {
        // it's  ->  'it'\''s'
        #expect(ShellQuoting.singleQuote("it's") == "'it'\\''s'")
    }

    @Test func singleQuotePreservesSpacesAndMetacharacters() {
        #expect(ShellQuoting.singleQuote("a b; rm -rf $HOME && echo `x`")
            == "'a b; rm -rf $HOME && echo `x`'")
    }

    @Test func singleQuoteHandlesEmptyString() {
        #expect(ShellQuoting.singleQuote("") == "''")
    }

    // MARK: - remoteShellCommand

    @Test func remoteShellCommandQuotesDirAndEveryArg() {
        let cmd = RemoteCommandBuilder.remoteShellCommand(
            argv: ["git", "--no-optional-locks", "status"],
            workingDirectory: "/srv/app"
        )
        #expect(cmd == "cd '/srv/app' && exec 'git' '--no-optional-locks' 'status'")
    }

    @Test func remoteShellCommandQuotesPathWithSpaces() {
        let cmd = RemoteCommandBuilder.remoteShellCommand(
            argv: ["ls", "-a"],
            workingDirectory: "/home/me/my project"
        )
        #expect(cmd == "cd '/home/me/my project' && exec 'ls' '-a'")
    }

    @Test func remoteShellCommandNeutralizesMetacharactersInArgs() {
        // An argument containing shell metacharacters and a single quote must
        // reach the remote shell as a single literal argument.
        let cmd = RemoteCommandBuilder.remoteShellCommand(
            argv: ["cat", "weird'; rm -rf /.txt"],
            workingDirectory: "/tmp"
        )
        #expect(cmd == "cd '/tmp' && exec 'cat' 'weird'\\''; rm -rf /.txt'")
    }

    // MARK: - interactiveSSHCommandLine

    @Test func interactiveCommandLineHasBothQuotingLayers() {
        let line = RemoteCommandBuilder.interactiveSSHCommandLine(
            host: "myserver",
            workingDirectory: "/srv/app",
            remoteCommand: "claude"
        )
        // The remote fragment `cd '/srv/app' && exec claude` is single-quoted
        // for the local shell, so its embedded single quotes become '\''.
        #expect(line.hasPrefix("/usr/bin/ssh -tt "))
        #expect(line.contains("ControlMaster=auto"))
        #expect(line.hasSuffix("'myserver' 'cd '\\''/srv/app'\\'' && exec claude'"))
    }

    @Test func interactiveCommandLineQuotesDirWithSpaces() {
        let line = RemoteCommandBuilder.interactiveSSHCommandLine(
            host: "user@host",
            workingDirectory: "/home/me/my app",
            remoteCommand: "\"$SHELL\" -l"
        )
        // Local shell sees one ssh argv for the host and one for the remote
        // fragment; the remote shell then expands $SHELL (kept unquoted inside).
        #expect(line.contains("'user@host'"))
        #expect(line.contains("exec \"$SHELL\" -l"))
        // The directory's space survives inside the inner single-quoting.
        #expect(line.contains("cd '\\''/home/me/my app'\\''"))
    }
}
