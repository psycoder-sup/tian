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
    /// Exit code 5: Another worktree close is already in flight
    case closeInFlight(String)

    var exitCode: Int32 {
        switch self {
        case .general: 1
        case .connection: 2
        case .processSafety: 3
        case .permissionDenied: 4
        case .closeInFlight: 5
        }
    }

    var errorDescription: String? {
        switch self {
        case .general(let msg),
             .connection(let msg),
             .processSafety(let msg),
             .permissionDenied(let msg),
             .closeInFlight(let msg):
            return msg
        }
    }
}
