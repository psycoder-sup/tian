import Testing
import Foundation
@testable import tian

struct RemoteConnectionTests {

    // MARK: - deriveWorkspaceName

    @Test func deriveNameUsesBasenameAndShortHost() {
        #expect(RemoteConnection.deriveWorkspaceName(
            host: "myserver", remoteDirectory: "/srv/app") == "app @ myserver")
    }

    @Test func deriveNameStripsUserFromHost() {
        #expect(RemoteConnection.deriveWorkspaceName(
            host: "deploy@prod.example.com", remoteDirectory: "/var/www/site")
            == "site @ prod.example.com")
    }

    @Test func deriveNameFallsBackToPathWhenNoBasename() {
        #expect(RemoteConnection.deriveWorkspaceName(
            host: "box", remoteDirectory: "/") == "/ @ box")
    }

    @Test func initTrimsWhitespace() {
        let remote = RemoteConnection(host: "  host  ", remoteDirectory: "  /srv/app  ")
        #expect(remote.host == "host")
        #expect(remote.remoteDirectory == "/srv/app")
    }

    // MARK: - Host safety (argument-injection guard)

    @Test func plainHostsAreSafe() {
        #expect(RemoteConnection(host: "myserver", remoteDirectory: "/a").isHostSafe)
        #expect(RemoteConnection(host: "deploy@host.example.com", remoteDirectory: "/a").isHostSafe)
    }

    @Test func dashLeadingHostIsRejected() {
        // A `-`-leading host would be parsed by ssh as an option.
        #expect(!RemoteConnection(host: "-oProxyCommand=touch /tmp/pwned", remoteDirectory: "/a").isHostSafe)
        #expect(!RemoteConnection(host: "", remoteDirectory: "/a").isHostSafe)
    }

    @Test func channelRefusesUnsafeHost() async {
        // Defense-in-depth: even if an unsafe host reaches a channel (e.g. a
        // hand-edited state.json), it never spawns ssh.
        let channel = SSHControlChannel(host: "-oProxyCommand=x", root: "/a")
        let result = await channel.run(argv: ["git", "status"], workingDirectory: "/a")
        #expect(result.exitCode == 255)
        #expect(result.stdout.isEmpty)
    }

    // MARK: - Codable round-trip

    @Test func stateRoundTripsThroughJSON() throws {
        let original = RemoteConnectionState(host: "myserver", remoteDirectory: "/srv/app")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteConnectionState.self, from: data)
        #expect(decoded == original)
    }

    @Test func stateBridgesToAndFromValueType() {
        let remote = RemoteConnection(host: "h", remoteDirectory: "/d")
        let state = RemoteConnectionState(remote)
        #expect(state.host == "h")
        #expect(state.remoteDirectory == "/d")
        #expect(state.remoteConnection == remote)
    }

    @Test func decodesToNilWhenFieldAbsent() throws {
        // A pre-v8 WorkspaceState has no `remote` key; an optional field decodes
        // as nil. Model that with a wrapper carrying an optional.
        struct Wrapper: Codable { let remote: RemoteConnectionState? }
        let json = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        #expect(decoded.remote == nil)
    }
}
