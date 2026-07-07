import Testing
import Foundation
@testable import tian

struct RemoteExecutionRegistryTests {

    private func channel(host: String = "h", root: String) -> SSHControlChannel {
        SSHControlChannel(host: host, root: root)
    }

    @Test func emptyRegistryReturnsNil() {
        let registry = RemoteExecutionRegistry()
        #expect(registry.channel(forDirectory: "/srv/app") == nil)
    }

    @Test func exactRootMatches() {
        let registry = RemoteExecutionRegistry()
        registry.register(channel(root: "/srv/app"))
        #expect(registry.channel(forDirectory: "/srv/app")?.root == "/srv/app")
    }

    @Test func nestedDirectoryResolvesToRoot() {
        let registry = RemoteExecutionRegistry()
        registry.register(channel(root: "/srv/app"))
        #expect(registry.channel(forDirectory: "/srv/app/sub/dir")?.root == "/srv/app")
    }

    @Test func trailingSlashesNormalizeEqual() {
        // A root registered WITH a trailing slash is still found by a lookup
        // WITHOUT one (and vice versa) — normalization strips it on both sides.
        let registry = RemoteExecutionRegistry()
        registry.register(channel(host: "trailing", root: "/srv/app/"))
        #expect(registry.channel(forDirectory: "/srv/app")?.host == "trailing")
        #expect(registry.channel(forDirectory: "/srv/app/")?.host == "trailing")
    }

    @Test func siblingPrefixDoesNotFalseMatch() {
        // /srv/app must NOT match /srv/app-2 — the boundary is a path separator.
        let registry = RemoteExecutionRegistry()
        registry.register(channel(root: "/srv/app"))
        #expect(registry.channel(forDirectory: "/srv/app-2") == nil)
    }

    @Test func longestPrefixWins() {
        let registry = RemoteExecutionRegistry()
        registry.register(channel(host: "outer", root: "/srv"))
        registry.register(channel(host: "inner", root: "/srv/app"))
        #expect(registry.channel(forDirectory: "/srv/app/x")?.host == "inner")
        #expect(registry.channel(forDirectory: "/srv/other")?.host == "outer")
    }

    @Test func unregisterRemovesChannel() {
        let registry = RemoteExecutionRegistry()
        let ch = channel(root: "/srv/app")
        registry.register(ch)
        registry.unregister(ch)
        #expect(registry.channel(forDirectory: "/srv/app") == nil)
    }

    @Test func unregisterNormalizesRoot() {
        let registry = RemoteExecutionRegistry()
        // Registered without trailing slash; the channel's own root carries a
        // trailing slash — unregister still matches via normalization.
        registry.register(channel(root: "/srv/app"))
        registry.unregister(channel(root: "/srv/app/"))
        #expect(registry.channel(forDirectory: "/srv/app") == nil)
    }

    // MARK: - Host collision (same path, different hosts)

    @Test func samePathOnTwoHostsIsAmbiguousAndResolvesToNil() {
        let registry = RemoteExecutionRegistry()
        registry.register(channel(host: "staging", root: "/srv/app"))
        registry.register(channel(host: "prod", root: "/srv/app"))
        // Ambiguous root — never guesses a host.
        #expect(registry.channel(forDirectory: "/srv/app") == nil)
        #expect(registry.channel(forDirectory: "/srv/app/sub") == nil)
    }

    @Test func ambiguousRootSelfHealsWhenOneCloses() {
        let registry = RemoteExecutionRegistry()
        let staging = channel(host: "staging", root: "/srv/app")
        let prod = channel(host: "prod", root: "/srv/app")
        registry.register(staging)
        registry.register(prod)
        #expect(registry.channel(forDirectory: "/srv/app") == nil)
        // Closing prod leaves staging unambiguous.
        registry.unregister(prod)
        #expect(registry.channel(forDirectory: "/srv/app")?.host == "staging")
    }

    @Test func reRegisteringSameChannelIsIdempotent() {
        let registry = RemoteExecutionRegistry()
        let ch = channel(host: "h", root: "/srv/app")
        registry.register(ch)
        registry.register(ch)   // same (host, root) — not a collision
        #expect(registry.channel(forDirectory: "/srv/app")?.host == "h")
    }

    @Test func filesystemRootMatchesEverything() {
        let registry = RemoteExecutionRegistry()
        registry.register(channel(root: "/"))
        #expect(registry.channel(forDirectory: "/anything/here")?.root == "/")
    }
}
