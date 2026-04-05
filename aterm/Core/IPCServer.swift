import Foundation

/// Unix domain socket server for CLI-to-app IPC.
/// One-shot-per-connection: accepts, reads one JSON request, dispatches to
/// the command handler, writes a JSON response, closes the connection.
final class IPCServer: Sendable {
    static var socketPath: String {
        let tmpdir = NSTemporaryDirectory()
        return "\(tmpdir)aterm-\(getuid()).sock"
    }

    private let commandHandler: @Sendable (IPCRequest) async -> IPCResponse
    private let queue = DispatchQueue(label: "com.aterm.ipc-server", qos: .userInitiated)
    nonisolated(unsafe) private var listeningFD: Int32 = -1
    nonisolated(unsafe) private var isRunning = false

    init(commandHandler: @Sendable @escaping (IPCRequest) async -> IPCResponse) {
        self.commandHandler = commandHandler
    }

    // MARK: - Lifecycle

    func start() {
        let path = Self.socketPath

        if FileManager.default.fileExists(atPath: path) {
            if isSocketAlive(path: path) {
                Log.ipc.warning("Another aterm instance is already listening on \(path)")
                return
            }
            unlink(path)
            Log.ipc.info("Removed stale socket file at \(path)")
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.ipc.error("Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        var addr = Self.makeSockaddr(path: path)
        guard addr != nil else {
            Log.ipc.error("Socket path too long: \(path)")
            close(fd)
            return
        }

        let bindResult = Self.withSockaddr(&addr!) { ptr, len in
            Darwin.bind(fd, ptr, len)
        }
        guard bindResult == 0 else {
            Log.ipc.error("Failed to bind socket: \(String(cString: strerror(errno)))")
            close(fd)
            return
        }

        chmod(path, 0o600)

        guard listen(fd, 128) == 0 else {
            Log.ipc.error("Failed to listen on socket: \(String(cString: strerror(errno)))")
            close(fd)
            unlink(path)
            return
        }

        self.listeningFD = fd
        self.isRunning = true
        Log.ipc.info("IPC server listening on \(path)")

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false

        let fd = listeningFD
        if fd >= 0 {
            listeningFD = -1
            close(fd)
        }

        unlink(Self.socketPath)
        Log.ipc.info("IPC server stopped, socket removed")
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while isRunning {
            let clientFD = Darwin.accept(listeningFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                if !isRunning { break }
                Log.ipc.error("accept() failed: \(String(cString: strerror(errno)))")
                break
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleConnection(fd: clientFD)
            }
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(fd: Int32) {
        defer { close(fd) }

        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let requestData = readLine(fd: fd) else {
            writeResponse(.failure(code: 1, message: "Failed to read request"), to: fd)
            return
        }

        let request: IPCRequest
        do {
            request = try JSONDecoder().decode(IPCRequest.self, from: requestData)
        } catch {
            writeResponse(.failure(code: 1, message: "Malformed request: \(error.localizedDescription)"), to: fd)
            return
        }

        let handler = self.commandHandler
        let response: IPCResponse = blockingAwait { await handler(request) }
        writeResponse(response, to: fd)
    }

    /// Reads from fd into a buffer until a newline is found.
    private func readLine(fd: Int32) -> Data? {
        var buffer = Data(count: 4096)
        var total = 0

        while total < 1_048_576 {
            if total == buffer.count { buffer.count *= 2 }

            let bytesRead = buffer.withUnsafeMutableBytes { buf in
                Darwin.read(fd, buf.baseAddress! + total, buf.count - total)
            }
            if bytesRead <= 0 { return total > 0 ? buffer.prefix(total) : nil }
            total += bytesRead

            // Scan the newly read bytes for newline
            if let nlIndex = buffer[..<total].firstIndex(of: 0x0A) {
                return buffer.prefix(nlIndex)
            }
        }
        return nil
    }

    private func writeResponse(_ response: IPCResponse, to fd: Int32) {
        do {
            var data = try JSONEncoder().encode(response)
            data.append(0x0A)
            data.withUnsafeBytes { buf in
                _ = Darwin.write(fd, buf.baseAddress!, buf.count)
            }
        } catch {
            Log.ipc.error("Failed to encode IPC response: \(error)")
        }
    }

    // MARK: - Socket Address Helpers

    private static func makeSockaddr(path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: Int8.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dst, src.baseAddress!, src.count)
                }
            }
        }
        return addr
    }

    private static func withSockaddr<T>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        let len = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + strlen(&addr.sun_path) + 1)
        return withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                body(sockaddrPtr, len)
            }
        }
    }

    private func isSocketAlive(path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        guard var addr = Self.makeSockaddr(path: path) else { return false }
        return Self.withSockaddr(&addr) { ptr, len in
            Darwin.connect(fd, ptr, len) == 0
        }
    }
}

/// Bridges an async operation to blocking synchronous code on a dispatch queue.
private func blockingAwait<T: Sendable>(
    _ operation: @Sendable @escaping () async -> T
) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: T?
    Task.detached {
        result = await operation()
        semaphore.signal()
    }
    semaphore.wait()
    return result!
}
