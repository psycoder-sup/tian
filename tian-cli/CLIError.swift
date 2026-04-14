import Foundation

enum CLIError: Error, LocalizedError {
    /// Exit code 1: Invalid arguments, entity not found, etc.
    case general(String)
    /// Exit code 2: Socket not found, connection refused, timeout
    case connection(String)
    /// Exit code 3: Running processes detected, --force not specified
    case processSafety(String)
    /// Exit code 4: Notification permission denied
    case permissionDenied(String)

    var exitCode: Int32 {
        switch self {
        case .general: 1
        case .connection: 2
        case .processSafety: 3
        case .permissionDenied: 4
        }
    }

    var errorDescription: String? {
        switch self {
        case .general(let msg),
             .connection(let msg),
             .processSafety(let msg),
             .permissionDenied(let msg):
            return msg
        }
    }

    /// Map an IPC error response to the appropriate CLIError case.
    static func fromIPCError(_ error: IPCError) -> CLIError {
        switch error.code {
        case 2: .connection(error.message)
        case 3: .processSafety(error.message)
        case 4: .permissionDenied(error.message)
        default: .general(error.message)
        }
    }
}
