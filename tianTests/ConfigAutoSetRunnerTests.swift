import Testing
import Foundation

struct ConfigAutoSetRunnerTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-auto-set-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Initializes a bare git repo at the given directory.
    private func gitInit(at dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "init", "-q"]
        p.currentDirectoryURL = dir
        try p.run()
        p.waitUntilExit()
        precondition(p.terminationStatus == 0, "git init failed")
    }

    // MARK: - resolveRepoRoot

    @Test func resolveRepoRoot_returnsRepoRoot_whenCwdIsInsideRepo() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let sub = tmp.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let runner = ConfigAutoSetRunner(invoker: StubClaudeInvoker(output: ""))
        let resolved = try runner.resolveRepoRoot(from: sub)

        // resolvingSymlinksInPath() normalizes /var/ vs /private/var/ on macOS.
        #expect(resolved.resolvingSymlinksInPath() == tmp.resolvingSymlinksInPath())
    }

    @Test func resolveRepoRoot_throws_whenCwdIsNotInsideRepo() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        // No `git init` — tmp is not a repo.

        let runner = ConfigAutoSetRunner(invoker: StubClaudeInvoker(output: ""))
        #expect(throws: CLIError.self) {
            try runner.resolveRepoRoot(from: tmp)
        }
    }
}

// MARK: - StubClaudeInvoker

/// Test double that returns pre-configured output and records calls.
final class StubClaudeInvoker: ClaudeInvoker {
    var output: String
    var error: Error?
    private(set) var calls: [(prompt: String, cwd: URL, model: String)] = []

    init(output: String = "", error: Error? = nil) {
        self.output = output
        self.error = error
    }

    func run(prompt: String, cwd: URL, model: String) throws -> String {
        calls.append((prompt: prompt, cwd: cwd, model: model))
        if let error { throw error }
        return output
    }
}
