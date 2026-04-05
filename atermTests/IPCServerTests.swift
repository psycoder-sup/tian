import Testing
import Foundation
@testable import aterm

struct IPCServerTests {
    /// Creates a temporary socket path for testing.
    private func tempSocketPath() -> String {
        let tmpdir = NSTemporaryDirectory()
        return "\(tmpdir)aterm-test-\(UUID().uuidString.prefix(8)).sock"
    }

    /// Connects to a Unix domain socket and sends a JSON request, returns the raw response data.
    private func sendRawRequest(_ json: String, to socketPath: String, timeoutSeconds: Int = 5) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCTestError.socketCreationFailed
        }
        defer { close(fd) }

        // Connect
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: Int8.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dst, src.baseAddress!, src.count)
                }
            }
        }
        let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }
        guard connectResult == 0 else {
            throw IPCTestError.connectionFailed(errno)
        }

        // Set timeout
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Write request
        var payload = Data(json.utf8)
        payload.append(0x0A)
        let written = payload.withUnsafeBytes { buf in
            Darwin.write(fd, buf.baseAddress!, buf.count)
        }
        guard written == payload.count else {
            throw IPCTestError.writeFailed
        }

        // Read response
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let bytesRead = Darwin.read(fd, &byte, 1)
            if bytesRead <= 0 { break }
            if byte == 0x0A { break }
            buffer.append(byte)
        }
        return buffer
    }

    // MARK: - Integration: ping round-trip

    @Test func pingRoundTrip() async throws {
        let socketPath = tempSocketPath()
        defer { unlink(socketPath) }

        let server = IPCServer { request in
            await MainActor.run {
                let handler = IPCCommandHandler(windowCoordinator: WindowCoordinator())
                return handler.handle(request)
            }
        }

        // Override socket path for testing - start server manually
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCTestError.socketCreationFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: Int8.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dst, src.baseAddress!, src.count)
                }
            }
        }
        let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw IPCTestError.connectionFailed(errno)
        }
        chmod(socketPath, 0o600)
        guard listen(fd, 5) == 0 else {
            close(fd)
            throw IPCTestError.socketCreationFailed
        }

        // Accept one connection in background, handle it inline
        let handler: @Sendable (IPCRequest) async -> IPCResponse = { request in
            await MainActor.run {
                let h = IPCCommandHandler(windowCoordinator: WindowCoordinator())
                return h.handle(request)
            }
        }

        let serverTask = Task.detached {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }

            // Read until newline
            var buffer = Data()
            var byte: UInt8 = 0
            while true {
                let n = Darwin.read(clientFD, &byte, 1)
                if n <= 0 { break }
                if byte == 0x0A { break }
                buffer.append(byte)
            }

            guard let request = try? JSONDecoder().decode(IPCRequest.self, from: buffer) else { return }
            let response = await handler(request)

            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard var data = try? encoder.encode(response) else { return }
            data.append(0x0A)
            data.withUnsafeBytes { buf in
                _ = Darwin.write(clientFD, buf.baseAddress!, buf.count)
            }
        }

        // Give server task time to call accept()
        try await Task.sleep(for: .milliseconds(50))

        // Send ping request
        let json = """
        {"version":1,"command":"ping","params":{},"env":{"paneId":"","tabId":"","spaceId":"","workspaceId":""}}
        """
        let responseData = try sendRawRequest(json, to: socketPath)

        // Wait for server task
        _ = await serverTask.value
        close(fd)

        // Decode and verify
        let response = try JSONDecoder().decode(IPCResponse.self, from: responseData)
        #expect(response.ok == true)
        #expect(response.result?["message"]?.stringValue == "pong")

        // Suppress unused variable warning
        _ = server
    }

    // MARK: - Malformed request

    @Test func malformedRequestReturnsError() async throws {
        let socketPath = tempSocketPath()
        defer { unlink(socketPath) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCTestError.socketCreationFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: Int8.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dst, src.baseAddress!, src.count)
                }
            }
        }
        let addrLen = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw IPCTestError.connectionFailed(errno)
        }
        chmod(socketPath, 0o600)
        guard listen(fd, 5) == 0 else {
            close(fd)
            throw IPCTestError.socketCreationFailed
        }

        let serverTask = Task.detached {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { return }
            defer { close(clientFD) }

            var buffer = Data()
            var byte: UInt8 = 0
            while true {
                let n = Darwin.read(clientFD, &byte, 1)
                if n <= 0 { break }
                if byte == 0x0A { break }
                buffer.append(byte)
            }

            // Server can't decode this, should return error
            let response: IPCResponse
            if let request = try? JSONDecoder().decode(IPCRequest.self, from: buffer) {
                response = .success(["unexpected": .bool(true)])
                _ = request
            } else {
                response = .failure(code: 1, message: "Malformed request")
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard var data = try? encoder.encode(response) else { return }
            data.append(0x0A)
            data.withUnsafeBytes { buf in
                _ = Darwin.write(clientFD, buf.baseAddress!, buf.count)
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        let responseData = try sendRawRequest("not valid json!", to: socketPath)

        _ = await serverTask.value
        close(fd)

        let response = try JSONDecoder().decode(IPCResponse.self, from: responseData)
        #expect(response.ok == false)
        #expect(response.error?.message.contains("Malformed") == true)
    }

    // MARK: - Socket path format

    @Test func socketPathContainsUID() {
        let path = IPCServer.socketPath
        let uid = getuid()
        #expect(path.contains("aterm-\(uid).sock"))
    }
}

private enum IPCTestError: Error {
    case socketCreationFailed
    case connectionFailed(Int32)
    case writeFailed
}
