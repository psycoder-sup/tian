import Testing
import Foundation
import os
@testable import aterm

@Suite(.serialized)
struct PTYProcessTests {
    // MARK: - Environment

    @Test func buildEnvironmentSetsTerminalVars() async throws {
        let fixture = try await PTYTestFixture.create(label: "test-pty-env-term")
        defer { fixture.cleanup() }

        fixture.fileHandle.write("echo $TERM\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(500))

        #expect(fixture.currentOutput.contains("xterm-256color"))
    }

    @Test func buildEnvironmentInheritsPath() async throws {
        let fixture = try await PTYTestFixture.create(label: "test-pty-env-path")
        defer { fixture.cleanup() }

        fixture.fileHandle.write("echo $PATH\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(500))

        #expect(fixture.currentOutput.contains("/usr/bin"))
    }

    // MARK: - Shell detection

    @Test func spawnsWithValidShell() throws {
        let process = try PTYProcess(columns: 80, rows: 24)
        defer { process.terminate() }

        #expect(process.childPID > 0)
        #expect(process.masterFD >= 0)
    }

    // MARK: - Resize

    @Test func resizeDoesNotCrash() throws {
        let process = try PTYProcess(columns: 80, rows: 24)
        defer { process.terminate() }

        process.resize(columns: 120, rows: 40)
        process.resize(columns: 40, rows: 10)
    }

    @Test func resizeUpdatesTerminalSize() async throws {
        let fixture = try await PTYTestFixture.create(label: "test-pty-resize")
        defer { fixture.cleanup() }

        fixture.process.resize(columns: 132, rows: 50)
        try await Task.sleep(for: .milliseconds(200))

        fixture.fileHandle.write("stty size\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(500))

        #expect(fixture.currentOutput.contains("50 132"))
    }

    // MARK: - Exit codes

    @Test func shellExitsAfterExitCommand() async throws {
        let fixture = try await PTYTestFixture.createDraining(label: "test-pty-exit42")
        defer { fixture.cleanup() }

        let pid = fixture.process.childPID
        fixture.fileHandle.write("exit 42\r".data(using: .utf8)!)

        // Poll kill(pid, 0) — doesn't race with dispatch source's waitpid
        var exited = false
        for _ in 0..<30 {
            if kill(pid, 0) != 0 {
                exited = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(exited, "Shell process should have exited after 'exit 42'")
    }

    // MARK: - Error descriptions

    @Test func ptyErrorDescriptions() {
        let openptyError = PTYError.openptyFailed(EACCES)
        #expect(openptyError.errorDescription != nil)
        #expect(openptyError.errorDescription!.contains("openpty()"))
        #expect(openptyError.errorDescription!.contains("\(EACCES)"))

        let forkError = PTYError.forkFailed(ENOMEM)
        #expect(forkError.errorDescription != nil)
        #expect(forkError.errorDescription!.contains("fork()"))
        #expect(forkError.errorDescription!.contains("\(ENOMEM)"))
    }
}
