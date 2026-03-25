import Testing
import Foundation
import os
@testable import aterm

@Suite(.serialized)
struct PTYIntegrationTests {
    // MARK: - Round-trip I/O

    @Test func echoRoundTrip() async throws {
        let fixture = try await PTYTestFixture.create(label: "test-pty-io")
        defer { fixture.cleanup() }

        fixture.fileHandle.write("echo TESTOUTPUT42\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(500))

        #expect(fixture.currentOutput.contains("TESTOUTPUT42"))
    }

    @Test func asyncReadCallbackFires() async throws {
        let fixture = try await PTYTestFixture.create(label: "test-pty-read")
        defer { fixture.cleanup() }

        fixture.fileHandle.write("echo CALLBACKTEST77\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(500))

        #expect(fixture.currentOutput.contains("CALLBACKTEST77"))
    }

    // MARK: - Shell exit

    @Test func shellExitsCleanly() async throws {
        let fixture = try await PTYTestFixture.createDraining(label: "test-pty-exit0")
        defer { fixture.cleanup() }

        let pid = fixture.process.childPID
        fixture.fileHandle.write("exit 0\r".data(using: .utf8)!)

        var exited = false
        for _ in 0..<30 {
            if kill(pid, 0) != 0 {
                exited = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(exited, "Shell process should have exited after 'exit 0'")
    }

    // MARK: - Terminate

    @Test func terminateKillsChild() throws {
        let process = try PTYProcess(columns: 80, rows: 24)
        let pid = process.childPID

        #expect(kill(pid, 0) == 0)

        process.terminate()

        #expect(kill(pid, 0) != 0)
    }

    // MARK: - Multiple commands

    @Test func multipleCommandsRoundTrip() async throws {
        let fixture = try await PTYTestFixture.create(label: "test-pty-multi")
        defer { fixture.cleanup() }

        fixture.fileHandle.write("echo AAA111\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(300))
        fixture.fileHandle.write("echo BBB222\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(300))
        fixture.fileHandle.write("echo CCC333\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(500))

        let output = fixture.currentOutput
        #expect(output.contains("AAA111"))
        #expect(output.contains("BBB222"))
        #expect(output.contains("CCC333"))
    }

    // MARK: - Ctrl+C interrupt

    @Test func ctrlCInterrupt() async throws {
        let fixture = try await PTYTestFixture.create(label: "test-pty-ctrlc")
        defer { fixture.cleanup() }

        fixture.fileHandle.write("sleep 60\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(300))

        fixture.fileHandle.write(Data([0x03]))
        try await Task.sleep(for: .milliseconds(500))

        fixture.fileHandle.write("echo AFTERCTRLC99\r".data(using: .utf8)!)
        try await Task.sleep(for: .milliseconds(500))

        #expect(fixture.currentOutput.contains("AFTERCTRLC99"))
    }
}
