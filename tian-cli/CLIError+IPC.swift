import Foundation

extension CLIError {
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
