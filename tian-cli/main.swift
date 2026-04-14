import ArgumentParser
import Foundation

struct TianCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tian",
        abstract: "Control the tian terminal emulator from within its shell sessions.",
        discussion: "Run commands from within a tian terminal session to manage workspaces, spaces, tabs, and panes. Requires the TIAN_SOCKET environment variable set by the tian app.",
        version: "0.1.0",
        subcommands: [
            Ping.self,
            WorkspaceGroup.self,
            SpaceGroup.self,
            TabGroup.self,
            PaneGroup.self,
            StatusGroup.self,
            NotifyCommand.self,
            WorktreeGroup.self,
        ]
    )
}

// MARK: - Environment

struct TianEnvironment {
    let socketPath: String
    let paneId: String
    let tabId: String
    let spaceId: String
    let workspaceId: String

    var ipcEnv: IPCEnv {
        IPCEnv(paneId: paneId, tabId: tabId, spaceId: spaceId, workspaceId: workspaceId)
    }

    static func fromEnvironment() throws -> TianEnvironment {
        guard let socketPath = ProcessInfo.processInfo.environment["TIAN_SOCKET"] else {
            throw CLIError.connection(
                "Not running inside tian.\n"
                + "The tian CLI can only be used from within a tian terminal session."
            )
        }

        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw CLIError.connection(
                "Socket not found at \(socketPath). Is the tian app running?"
            )
        }

        let env = ProcessInfo.processInfo.environment
        return TianEnvironment(
            socketPath: socketPath,
            paneId: env["TIAN_PANE_ID"] ?? "00000000-0000-0000-0000-000000000000",
            tabId: env["TIAN_TAB_ID"] ?? "00000000-0000-0000-0000-000000000000",
            spaceId: env["TIAN_SPACE_ID"] ?? "00000000-0000-0000-0000-000000000000",
            workspaceId: env["TIAN_WORKSPACE_ID"] ?? "00000000-0000-0000-0000-000000000000"
        )
    }
}

// MARK: - Ping Command

struct Ping: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Test connectivity to the tian app."
    )

    func run() throws {
        let env = try TianEnvironment.fromEnvironment()
        let client = IPCClient(socketPath: env.socketPath)

        let request = IPCRequest(
            version: ipcProtocolVersion,
            command: "ping",
            params: [:],
            env: env.ipcEnv
        )

        let response = try client.send(request)

        if response.ok {
            let message = response.result?["message"]?.stringValue ?? "pong"
            print(message)
        } else if let error = response.error {
            throw CLIError.fromIPCError(error)
        } else {
            throw CLIError.general("Unexpected response from tian")
        }
    }
}

// MARK: - Command Context

/// Shared mutable state for capturing command results (single-threaded CLI).
enum CommandContext {
    nonisolated(unsafe) static var lastCreateId: String?
}

// MARK: - Entry Point

let cliStartTime = ContinuousClock.now
let commandString = ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " ")

do {
    var command = try TianCLI.parseAsRoot()
    try command.run()
    CommandLogger.log(command: commandString, exitCode: 0,
                      result: CommandContext.lastCreateId, error: nil,
                      startTime: cliStartTime)
} catch let error as CLIError {
    CommandLogger.log(command: commandString, exitCode: error.exitCode,
                      result: nil, error: error.localizedDescription,
                      startTime: cliStartTime)
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(error.exitCode)
} catch {
    let cleanExit = error is CleanExit
    CommandLogger.log(command: commandString, exitCode: cleanExit ? 0 : 1,
                      result: nil, error: cleanExit ? nil : error.localizedDescription,
                      startTime: cliStartTime)
    TianCLI.exit(withError: error)
}
