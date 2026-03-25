import Foundation
import os
@testable import aterm

struct PTYTestFixture {
    let process: PTYProcess
    let fileHandle: PTYFileHandle
    let output: OSAllocatedUnfairLock<String>

    static func create(label: String = "test-pty") async throws -> PTYTestFixture {
        let process = try PTYProcess(columns: 80, rows: 24)
        let output = OSAllocatedUnfairLock(initialState: "")
        let queue = DispatchQueue(label: label)
        let fileHandle = PTYFileHandle(fd: process.masterFD, queue: queue) { data in
            let text = String(decoding: data, as: UTF8.self)
            output.withLock { $0.append(text) }
        }
        try await Task.sleep(for: .seconds(1))
        return PTYTestFixture(process: process, fileHandle: fileHandle, output: output)
    }

    /// Create a fixture that discards output (for exit-code tests)
    static func createDraining(label: String = "test-pty") async throws -> PTYTestFixture {
        let process = try PTYProcess(columns: 80, rows: 24)
        let output = OSAllocatedUnfairLock(initialState: "")
        let queue = DispatchQueue(label: label)
        let fileHandle = PTYFileHandle(fd: process.masterFD, queue: queue) { _ in }
        try await Task.sleep(for: .seconds(1))
        return PTYTestFixture(process: process, fileHandle: fileHandle, output: output)
    }

    func cleanup() {
        fileHandle.close()
        process.terminate()
    }

    var currentOutput: String {
        output.withLock { $0 }
    }
}
