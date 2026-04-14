import Foundation

struct IPCClient {
    let socketPath: String

    func send(_ request: IPCRequest, timeout: Int? = nil) throws -> IPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIError.connection("Failed to create socket: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw CLIError.connection("Socket path too long: \(socketPath)")
        }
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
            let errNo = errno
            if errNo == ECONNREFUSED {
                throw CLIError.connection("Connection refused. Is the tian app running?")
            }
            throw CLIError.connection("Failed to connect to socket: \(String(cString: strerror(errNo)))")
        }

        let timeoutSeconds = timeout
            ?? ProcessInfo.processInfo.environment["TIAN_CLI_TIMEOUT"].flatMap(Int.init)
            ?? 5
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)

        let written = payload.withUnsafeBytes { buf in
            Darwin.write(fd, buf.baseAddress!, buf.count)
        }
        guard written == payload.count else {
            throw CLIError.connection("Failed to write request: \(String(cString: strerror(errno)))")
        }

        return try readResponse(fd: fd)
    }

    private func readResponse(fd: Int32) throws -> IPCResponse {
        var buffer = Data(count: 4096)
        var total = 0

        while total < 1_048_576 {
            if total == buffer.count { buffer.count *= 2 }

            let bytesRead = buffer.withUnsafeMutableBytes { buf in
                Darwin.read(fd, buf.baseAddress! + total, buf.count - total)
            }
            if bytesRead == 0 {
                throw CLIError.connection("Connection closed by server before response completed")
            }
            if bytesRead < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw CLIError.connection("Timeout waiting for response from tian")
                }
                throw CLIError.connection("Read error: \(String(cString: strerror(errno)))")
            }
            total += bytesRead

            if let nlIndex = buffer[..<total].firstIndex(of: 0x0A) {
                return try JSONDecoder().decode(IPCResponse.self, from: buffer.prefix(nlIndex))
            }
        }
        throw CLIError.connection("Response too large")
    }
}
