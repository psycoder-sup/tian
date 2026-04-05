import Foundation

/// Dispatches IPC requests to the appropriate model layer operations.
/// Stub implementation for Phase 1 — only handles `ping`.
@MainActor
final class IPCCommandHandler {
    private let windowCoordinator: WindowCoordinator

    init(windowCoordinator: WindowCoordinator) {
        self.windowCoordinator = windowCoordinator
    }

    func handle(_ request: IPCRequest) -> IPCResponse {
        // Version check
        guard request.version == ipcProtocolVersion else {
            return .failure(
                code: 1,
                message: "Protocol version mismatch: client sent v\(request.version), server supports v\(ipcProtocolVersion). Update your CLI."
            )
        }

        switch request.command {
        case "ping":
            return .success(["message": .string("pong")])
        default:
            return .failure(code: 1, message: "Unknown command: \(request.command)")
        }
    }
}
