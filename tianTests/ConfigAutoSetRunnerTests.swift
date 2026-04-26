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

    private func gitInit(at dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "init", "-q"]
        p.currentDirectoryURL = dir
        try p.run()
        p.waitUntilExit()
        precondition(p.terminationStatus == 0, "git init failed")
    }

    /// Builds a minimal claude -p JSON envelope with a given
    /// `structured_output` payload (or an error envelope).
    private func envelope(
        payload: AutoSetPayload? = nil,
        isError: Bool = false,
        subtype: String = "success",
        resultText: String = ""
    ) throws -> String {
        struct TestEnvelope: Encodable {
            let type: String = "result"
            let subtype: String
            let is_error: Bool
            let result: String
            let structured_output: AutoSetPayload?
        }
        let env = TestEnvelope(
            subtype: subtype,
            is_error: isError,
            result: resultText,
            structured_output: payload
        )
        let data = try JSONEncoder().encode(env)
        return String(data: data, encoding: .utf8)!
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

        #expect(resolved.resolvingSymlinksInPath() == tmp.resolvingSymlinksInPath())
    }

    @Test func resolveRepoRoot_throws_whenCwdIsNotInsideRepo() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        let runner = ConfigAutoSetRunner(invoker: StubClaudeInvoker(output: ""))
        #expect(throws: CLIError.self) {
            try runner.resolveRepoRoot(from: tmp)
        }
    }

    // MARK: - run() happy path

    @Test func run_writesConfigFile_fromStructuredPayload() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let payload = AutoSetPayload(
            setup: [.init(command: "bun install")],
            copy: [.init(source: ".env.local", dest: ".")],
            notes: nil
        )
        let stub = StubClaudeInvoker(output: try envelope(payload: payload))
        let runner = ConfigAutoSetRunner(invoker: stub)

        let result = try runner.run(cwd: tmp, force: false, model: "sonnet")

        #expect(result.setupCount == 1)
        #expect(result.copyCount == 1)

        let configURL = tmp.appendingPathComponent(".tian/config.toml")
        let written = try String(contentsOf: configURL, encoding: .utf8)
        #expect(written.contains("# tian worktree config"))
        #expect(written.contains("bun install"))
        #expect(written.contains(".env.local"))

        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].prompt == AutoSetPrompt.template)
        #expect(stub.calls[0].jsonSchema == AutoSetPayload.jsonSchema)
        #expect(stub.calls[0].cwd.resolvingSymlinksInPath() == tmp.resolvingSymlinksInPath())
        #expect(stub.calls[0].model == "sonnet")
    }

    @Test func run_rendersArchiveSection_whenPresent() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let payload = AutoSetPayload(
            setup: [.init(command: "docker compose up -d")],
            copy: [],
            archive: [.init(command: "docker compose down -v")]
        )
        let stub = StubClaudeInvoker(output: try envelope(payload: payload))
        let result = try ConfigAutoSetRunner(invoker: stub).run(
            cwd: tmp, force: false, model: "sonnet"
        )

        #expect(result.archiveCount == 1)

        let written = try String(
            contentsOf: tmp.appendingPathComponent(".tian/config.toml"),
            encoding: .utf8
        )
        #expect(written.contains("[[archive]]"))
        #expect(written.contains("docker compose down -v"))
    }

    @Test func run_omitsArchiveSection_whenEmpty() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let payload = AutoSetPayload(setup: [.init(command: "echo hi")], copy: [])
        let stub = StubClaudeInvoker(output: try envelope(payload: payload))
        let result = try ConfigAutoSetRunner(invoker: stub).run(
            cwd: tmp, force: false, model: "sonnet"
        )

        #expect(result.archiveCount == 0)

        let written = try String(
            contentsOf: tmp.appendingPathComponent(".tian/config.toml"),
            encoding: .utf8
        )
        #expect(!written.contains("[[archive]]"))
    }

    @Test func run_rendersNotesAsCommentBlock() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let payload = AutoSetPayload(
            setup: [],
            copy: [],
            notes: "No build system detected.\nLeft arrays empty."
        )
        let stub = StubClaudeInvoker(output: try envelope(payload: payload))
        _ = try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: false, model: "sonnet")

        let written = try String(
            contentsOf: tmp.appendingPathComponent(".tian/config.toml"),
            encoding: .utf8
        )
        #expect(written.contains("# No build system detected."))
        #expect(written.contains("# Left arrays empty."))
    }

    @Test func run_createsDotTianDirectory_ifMissing() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let payload = AutoSetPayload(setup: [], copy: [], notes: nil)
        let stub = StubClaudeInvoker(output: try envelope(payload: payload))
        _ = try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: false, model: "sonnet")

        var isDir: ObjCBool = false
        let dotTian = tmp.appendingPathComponent(".tian").path
        #expect(FileManager.default.fileExists(atPath: dotTian, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    // MARK: - Overwrite guard

    @Test func run_refuses_whenConfigExists_andForceIsFalse() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let dotTian = tmp.appendingPathComponent(".tian")
        try FileManager.default.createDirectory(at: dotTian, withIntermediateDirectories: true)
        let configURL = dotTian.appendingPathComponent("config.toml")
        let original = "# existing content\n"
        try original.write(to: configURL, atomically: true, encoding: .utf8)

        let payload = AutoSetPayload(setup: [.init(command: "echo hi")], copy: [], notes: nil)
        let stub = StubClaudeInvoker(output: try envelope(payload: payload))

        #expect(throws: CLIError.self) {
            try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: false, model: "sonnet")
        }

        let after = try String(contentsOf: configURL, encoding: .utf8)
        #expect(after == original)
        #expect(stub.calls.isEmpty)
    }

    @Test func run_overwrites_whenConfigExists_andForceIsTrue() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let dotTian = tmp.appendingPathComponent(".tian")
        try FileManager.default.createDirectory(at: dotTian, withIntermediateDirectories: true)
        let configURL = dotTian.appendingPathComponent("config.toml")
        try "# existing content\n".write(to: configURL, atomically: true, encoding: .utf8)

        let payload = AutoSetPayload(setup: [.init(command: "echo hi")], copy: [], notes: nil)
        let stub = StubClaudeInvoker(output: try envelope(payload: payload))
        _ = try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: true, model: "sonnet")

        let after = try String(contentsOf: configURL, encoding: .utf8)
        #expect(after.contains("echo hi"))
        #expect(!after.contains("existing content"))
        #expect(stub.calls.count == 1)
    }

    // MARK: - Envelope failure modes

    @Test func run_writesRejectedFile_onMalformedEnvelope() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let garbage = "not even JSON"
        let stub = StubClaudeInvoker(output: garbage)

        #expect(throws: CLIError.self) {
            try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: false, model: "sonnet")
        }

        let configURL = tmp.appendingPathComponent(".tian/config.toml")
        #expect(!FileManager.default.fileExists(atPath: configURL.path))

        let rejectedURL = tmp.appendingPathComponent(".tian/config.toml.rejected")
        #expect(FileManager.default.fileExists(atPath: rejectedURL.path))
        let rejected = try String(contentsOf: rejectedURL, encoding: .utf8)
        #expect(rejected == garbage)
    }

    @Test func run_rejectsErrorEnvelope() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let errEnvelope = try envelope(
            isError: true,
            subtype: "error_max_turns",
            resultText: "hit max turns"
        )
        let stub = StubClaudeInvoker(output: errEnvelope)

        #expect(throws: CLIError.self) {
            try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: false, model: "sonnet")
        }

        let configURL = tmp.appendingPathComponent(".tian/config.toml")
        #expect(!FileManager.default.fileExists(atPath: configURL.path))
    }

    @Test func run_rejectsMissingStructuredOutput() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let envelopeJSON = #"{"type":"result","subtype":"success","is_error":false,"result":""}"#
        let stub = StubClaudeInvoker(output: envelopeJSON)

        #expect(throws: CLIError.self) {
            try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: false, model: "sonnet")
        }

        let configURL = tmp.appendingPathComponent(".tian/config.toml")
        #expect(!FileManager.default.fileExists(atPath: configURL.path))
    }

    // MARK: - Invoker error propagation

    @Test func run_propagatesInvokerError_andDoesNotWriteConfig() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try gitInit(at: tmp)

        let stub = StubClaudeInvoker(error: CLIError.general("claude -p failed (exit 1)"))

        #expect(throws: CLIError.self) {
            try ConfigAutoSetRunner(invoker: stub).run(cwd: tmp, force: false, model: "sonnet")
        }

        #expect(stub.calls.count == 1)

        let configURL = tmp.appendingPathComponent(".tian/config.toml")
        #expect(!FileManager.default.fileExists(atPath: configURL.path))

        let rejectedURL = tmp.appendingPathComponent(".tian/config.toml.rejected")
        #expect(!FileManager.default.fileExists(atPath: rejectedURL.path))
    }
}

// MARK: - StubClaudeInvoker

/// Test double that returns pre-configured output and records calls.
final class StubClaudeInvoker: ClaudeInvoker {
    var output: String
    var error: Error?
    private(set) var calls: [(prompt: String, jsonSchema: String, cwd: URL, model: String)] = []

    init(output: String = "", error: Error? = nil) {
        self.output = output
        self.error = error
    }

    func run(prompt: String, jsonSchema: String, cwd: URL, model: String) throws -> String {
        calls.append((prompt: prompt, jsonSchema: jsonSchema, cwd: cwd, model: model))
        if let error { throw error }
        return output
    }
}
