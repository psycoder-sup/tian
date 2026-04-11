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
    nonisolated(unsafe) private var boundInode: UInt64 = 0

    init(commandHandler: @Sendable @escaping (IPCRequest) async -> IPCResponse) {
        self.commandHandler = commandHandler
    }

    // MARK: - Lifecycle

    func start() {
        let path = Self.socketPath

        if FileManager.default.fileExists(atPath: path) {
            if isSocketAlive(path: path) {
                Log.ipc.warning("Another aterm instance is listening on \(path); taking over")
            }
            unlink(path)
        }

        guard let fd = createListeningSocket(path: path) else { return }

        self.listeningFD = fd
        self.isRunning = true
        Log.ipc.info("IPC server listening on \(path)")

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        boundInode = 0

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
        var consecutiveErrors = 0
        let maxConsecutiveErrors = 10
        let path = Self.socketPath

        while isRunning {
            let clientFD = Darwin.accept(listeningFD, nil, nil)
            if clientFD < 0 {
                let err = errno
                if err == EINTR { continue }
                if !isRunning { break }

                if err == EAGAIN || err == EWOULDBLOCK {
                    checkSocketFile(path: path)
                    continue
                }

                // Transient error — retry with backoff
                consecutiveErrors += 1
                Log.ipc.error("accept() failed (\(consecutiveErrors)/\(maxConsecutiveErrors)): \(String(cString: strerror(err)))")
                if consecutiveErrors >= maxConsecutiveErrors {
                    Log.ipc.error("Too many consecutive accept errors; attempting socket recovery")
                    if rebindSocket(path: path) {
                        consecutiveErrors = 0
                        continue
                    }
                    // Back off and retry from scratch instead of exiting
                    Log.ipc.error("Socket recovery failed; will retry in 5s")
                    consecutiveErrors = 0
                    Thread.sleep(forTimeInterval: 5)
                    if isRunning { _ = rebindSocket(path: path) }
                    continue
                }
                Thread.sleep(forTimeInterval: Double(min(consecutiveErrors, 5)) * 0.1)
                continue
            }

            consecutiveErrors = 0

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleConnection(fd: clientFD)
            }
        }

        // Accept loop exited — clean up the socket file so stale files
        // don't prevent future connections or confuse clients.
        if !isRunning {
            let fd = listeningFD
            if fd >= 0 {
                listeningFD = -1
                close(fd)
            }
            unlink(path)
            Log.ipc.info("Accept loop exited; socket cleaned up")
        }
    }

    // MARK: - Socket Recovery

    private func checkSocketFile(path: String) {
        var st = stat()
        let currentInode = boundInode

        guard stat(path, &st) == 0 else {
            Log.ipc.warning("Socket file disappeared from \(path); rebinding")
            _ = rebindSocket(path: path)
            return
        }

        if currentInode != 0 && UInt64(st.st_ino) != currentInode {
            // The socket file's inode changed — someone replaced it.
            // Always reclaim rather than shutting down, because isSocketAlive
            // can self-trigger (connecting to our own socket).
            Log.ipc.warning("Socket file inode changed (was \(currentInode), now \(st.st_ino)); reclaiming \(path)")
            _ = rebindSocket(path: path)
        }
    }

    private func rebindSocket(path: String) -> Bool {
        let oldFD = listeningFD
        listeningFD = -1

        unlink(path)

        guard let fd = createListeningSocket(path: path) else {
            listeningFD = oldFD
            return false
        }

        if oldFD >= 0 { close(oldFD) }

        // Always install the new FD. If isRunning became false, the accept
        // loop's while-check will exit and the cleanup block handles closing.
        // Previously this would close the fd but leave the socket file orphaned.
        listeningFD = fd
        Log.ipc.info("Socket successfully rebound to \(path)")
        return true
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

    // MARK: - Socket Setup

    /// Creates a Unix domain socket, binds it to `path`, starts listening,
    /// sets the accept timeout, and records the bound inode.
    /// Returns the listening fd on success, or nil on failure (errors are logged).
    private func createListeningSocket(path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.ipc.error("Failed to create socket: \(String(cString: strerror(errno)))")
            return nil
        }

        var addr = Self.makeSockaddr(path: path)
        guard addr != nil else {
            Log.ipc.error("Socket path too long: \(path)")
            close(fd)
            return nil
        }

        let bindResult = Self.withSockaddr(&addr!) { ptr, len in
            Darwin.bind(fd, ptr, len)
        }
        guard bindResult == 0 else {
            Log.ipc.error("Failed to bind socket: \(String(cString: strerror(errno)))")
            close(fd)
            return nil
        }

        chmod(path, 0o600)

        guard listen(fd, 128) == 0 else {
            Log.ipc.error("Failed to listen on socket: \(String(cString: strerror(errno)))")
            close(fd)
            unlink(path)
            return nil
        }

        // Periodic timeout so the accept loop can check socket file health
        var acceptTimeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &acceptTimeout, socklen_t(MemoryLayout<timeval>.size))

        var st = stat()
        if stat(path, &st) == 0 {
            boundInode = UInt64(st.st_ino)
        }

        return fd
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
