import ArgumentParser
import Foundation

struct AtermCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aterm",
        abstract: "Control the aterm terminal emulator from within its shell sessions.",
        discussion: "Run commands from within an aterm terminal session to manage workspaces, spaces, tabs, and panes. Requires the ATERM_SOCKET environment variable set by the aterm app.",
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

struct AtermEnvironment {
    let socketPath: String
    let paneId: String
    let tabId: String
    let spaceId: String
    let workspaceId: String

    var ipcEnv: IPCEnv {
        IPCEnv(paneId: paneId, tabId: tabId, spaceId: spaceId, workspaceId: workspaceId)
    }

    static func fromEnvironment() throws -> AtermEnvironment {
        guard let socketPath = ProcessInfo.processInfo.environment["ATERM_SOCKET"] else {
            throw CLIError.connection(
                "Not running inside aterm.\n"
                + "The aterm CLI can only be used from within an aterm terminal session."
            )
        }

        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw CLIError.connection(
                "Socket not found at \(socketPath). Is the aterm app running?"
            )
        }

        let env = ProcessInfo.processInfo.environment
        return AtermEnvironment(
            socketPath: socketPath,
            paneId: env["ATERM_PANE_ID"] ?? "00000000-0000-0000-0000-000000000000",
            tabId: env["ATERM_TAB_ID"] ?? "00000000-0000-0000-0000-000000000000",
            spaceId: env["ATERM_SPACE_ID"] ?? "00000000-0000-0000-0000-000000000000",
            workspaceId: env["ATERM_WORKSPACE_ID"] ?? "00000000-0000-0000-0000-000000000000"
        )
    }
}

// MARK: - Ping Command

struct Ping: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Test connectivity to the aterm app."
    )

    func run() throws {
        let env = try AtermEnvironment.fromEnvironment()
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
            throw CLIError.general("Unexpected response from aterm")
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
    var command = try AtermCLI.parseAsRoot()
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
    AtermCLI.exit(withError: error)
}
