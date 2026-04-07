import ArgumentParser
import Foundation

// MARK: - Helpers

/// Sends an IPC request and returns the response, throwing on error.
private func sendRequest(command: String, params: [String: IPCValue] = [:], timeout: Int? = nil) throws -> IPCResponse {
    let env = try AtermEnvironment.fromEnvironment()
    let client = IPCClient(socketPath: env.socketPath)
    let request = IPCRequest(
        version: ipcProtocolVersion,
        command: command,
        params: params,
        env: env.ipcEnv
    )
    return try client.send(request, timeout: timeout)
}

/// Processes a response that should contain an ID in the result (create commands).
private func handleCreateResponse(_ response: IPCResponse, resultKey: String = "id") throws {
    if response.ok {
        if let id = response.result?[resultKey]?.stringValue {
            CommandContext.lastCreateId = id
            print(id)
        }
    } else if let error = response.error {
        throw CLIError.fromIPCError(error)
    } else {
        throw CLIError.general("Unexpected response from aterm")
    }
}

/// Processes a response that has no meaningful result (focus/close commands).
private func handleVoidResponse(_ response: IPCResponse) throws {
    if !response.ok {
        if let error = response.error {
            throw CLIError.fromIPCError(error)
        }
        throw CLIError.general("Unexpected response from aterm")
    }
}

/// Processes a list response, formatting output as table or JSON.
private func handleListResponse(
    _ response: IPCResponse,
    arrayKey: String,
    headers: [String],
    rowBuilder: (IPCValue) -> [String],
    activeKey: String,
    format: OutputFormat
) throws {
    if response.ok {
        guard let result = response.result,
              let array = result[arrayKey],
              case .array(let items) = array else {
            print("No results.")
            return
        }

        switch format {
        case .json:
            print(OutputFormatter.formatJSON(array))
        case .table:
            var rows: [[String]] = []
            var activeIndex: Int?
            for (i, item) in items.enumerated() {
                rows.append(rowBuilder(item))
                if case .object(let obj) = item,
                   obj[activeKey]?.boolValue == true {
                    activeIndex = i
                }
            }
            print(OutputFormatter.formatTable(headers: headers, rows: rows, activeIndex: activeIndex))
        }
    } else if let error = response.error {
        throw CLIError.fromIPCError(error)
    } else {
        throw CLIError.general("Unexpected response from aterm")
    }
}

// MARK: - Workspace

struct WorkspaceGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workspace",
        abstract: "Manage workspaces.",
        subcommands: [
            WorkspaceCreate.self,
            WorkspaceList.self,
            WorkspaceClose.self,
            WorkspaceFocus.self,
        ]
    )
}

struct WorkspaceCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new workspace."
    )

    @Argument(help: "Name for the new workspace.")
    var name: String

    @Option(name: .long, help: "Working directory for the workspace.")
    var directory: String?

    func run() throws {
        var params: [String: IPCValue] = ["name": .string(name)]
        if let directory { params["directory"] = .string(directory) }
        let response = try sendRequest(command: "workspace.create", params: params)
        try handleCreateResponse(response)
    }
}

struct WorkspaceList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all workspaces."
    )

    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .table

    func run() throws {
        let response = try sendRequest(command: "workspace.list")
        try handleListResponse(
            response,
            arrayKey: "workspaces",
            headers: ["ID", "NAME", "SPACES", "ACTIVE"],
            rowBuilder: { item in
                guard case .object(let obj) = item else { return [] }
                return [
                    obj["id"]?.stringValue ?? "",
                    obj["name"]?.stringValue ?? "",
                    obj["spaceCount"]?.intValue.map(String.init) ?? "",
                    obj["active"]?.boolValue == true ? "yes" : "",
                ]
            },
            activeKey: "active",
            format: format
        )
    }
}

struct WorkspaceClose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close a workspace."
    )

    @Argument(help: "Workspace ID (UUID).")
    var id: String

    @Flag(name: .long, help: "Force close even if processes are running.")
    var force: Bool = false

    func run() throws {
        var params: [String: IPCValue] = ["id": .string(id)]
        if force { params["force"] = .bool(true) }
        let response = try sendRequest(command: "workspace.close", params: params)
        try handleVoidResponse(response)
    }
}

struct WorkspaceFocus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus a workspace."
    )

    @Argument(help: "Workspace ID (UUID).")
    var id: String

    func run() throws {
        let response = try sendRequest(command: "workspace.focus", params: ["id": .string(id)])
        try handleVoidResponse(response)
    }
}

// MARK: - Space

struct SpaceGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "space",
        abstract: "Manage spaces within a workspace.",
        subcommands: [
            SpaceCreate.self,
            SpaceList.self,
            SpaceClose.self,
            SpaceFocus.self,
        ]
    )
}

struct SpaceCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new space."
    )

    @Argument(help: "Optional name for the new space.")
    var name: String?

    @Option(name: .long, help: "Workspace ID (defaults to current workspace).")
    var workspace: String?

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let name { params["name"] = .string(name) }
        if let workspace { params["workspaceId"] = .string(workspace) }
        let response = try sendRequest(command: "space.create", params: params)
        try handleCreateResponse(response)
    }
}

struct SpaceList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List spaces in a workspace."
    )

    @Option(name: .long, help: "Workspace ID (defaults to current workspace).")
    var workspace: String?

    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .table

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let workspace { params["workspaceId"] = .string(workspace) }
        let response = try sendRequest(command: "space.list", params: params)
        try handleListResponse(
            response,
            arrayKey: "spaces",
            headers: ["ID", "NAME", "TABS", "ACTIVE"],
            rowBuilder: { item in
                guard case .object(let obj) = item else { return [] }
                return [
                    obj["id"]?.stringValue ?? "",
                    obj["name"]?.stringValue ?? "",
                    obj["tabCount"]?.intValue.map(String.init) ?? "",
                    obj["active"]?.boolValue == true ? "yes" : "",
                ]
            },
            activeKey: "active",
            format: format
        )
    }
}

struct SpaceClose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close a space."
    )

    @Argument(help: "Space ID (UUID).")
    var id: String

    @Option(name: .long, help: "Workspace ID (defaults to current workspace).")
    var workspace: String?

    @Flag(name: .long, help: "Force close even if processes are running.")
    var force: Bool = false

    func run() throws {
        var params: [String: IPCValue] = ["id": .string(id)]
        if let workspace { params["workspaceId"] = .string(workspace) }
        if force { params["force"] = .bool(true) }
        let response = try sendRequest(command: "space.close", params: params)
        try handleVoidResponse(response)
    }
}

struct SpaceFocus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus a space."
    )

    @Argument(help: "Space ID (UUID).")
    var id: String

    @Option(name: .long, help: "Workspace ID (defaults to current workspace).")
    var workspace: String?

    func run() throws {
        var params: [String: IPCValue] = ["id": .string(id)]
        if let workspace { params["workspaceId"] = .string(workspace) }
        let response = try sendRequest(command: "space.focus", params: params)
        try handleVoidResponse(response)
    }
}

// MARK: - Tab

struct TabGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tab",
        abstract: "Manage tabs within a space.",
        subcommands: [
            TabCreate.self,
            TabList.self,
            TabClose.self,
            TabFocus.self,
        ]
    )
}

struct TabCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new tab."
    )

    @Option(name: .long, help: "Space ID (defaults to current space).")
    var space: String?

    @Option(name: .long, help: "Working directory for the new tab.")
    var directory: String?

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let space { params["spaceId"] = .string(space) }
        if let directory { params["directory"] = .string(directory) }
        let response = try sendRequest(command: "tab.create", params: params)
        try handleCreateResponse(response)
    }
}

struct TabList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tabs in a space."
    )

    @Option(name: .long, help: "Space ID (defaults to current space).")
    var space: String?

    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .table

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let space { params["spaceId"] = .string(space) }
        let response = try sendRequest(command: "tab.list", params: params)
        try handleListResponse(
            response,
            arrayKey: "tabs",
            headers: ["ID", "TITLE", "PANES", "ACTIVE"],
            rowBuilder: { item in
                guard case .object(let obj) = item else { return [] }
                return [
                    obj["id"]?.stringValue ?? "",
                    obj["title"]?.stringValue ?? "",
                    obj["paneCount"]?.intValue.map(String.init) ?? "",
                    obj["active"]?.boolValue == true ? "yes" : "",
                ]
            },
            activeKey: "active",
            format: format
        )
    }
}

struct TabClose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close a tab."
    )

    @Argument(help: "Tab ID (UUID). Defaults to current tab.")
    var id: String?

    @Flag(name: .long, help: "Force close even if processes are running.")
    var force: Bool = false

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let id { params["id"] = .string(id) }
        if force { params["force"] = .bool(true) }
        let response = try sendRequest(command: "tab.close", params: params)
        try handleVoidResponse(response)
    }
}

struct TabFocus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus a tab by ID or 1-based index."
    )

    @Argument(help: "Tab ID (UUID) or 1-based index (1-9).")
    var target: String

    func run() throws {
        let response = try sendRequest(command: "tab.focus", params: ["target": .string(target)])
        try handleVoidResponse(response)
    }
}

// MARK: - Pane

struct PaneGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pane",
        abstract: "Manage panes within a tab.",
        subcommands: [
            PaneSplit.self,
            PaneList.self,
            PaneClose.self,
            PaneFocus.self,
        ]
    )
}

struct PaneSplit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "split",
        abstract: "Split a pane."
    )

    @Option(name: .long, help: "Pane ID to split (defaults to current pane).")
    var pane: String?

    @Option(name: .long, help: "Split direction: horizontal or vertical.")
    var direction: String?

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let pane { params["paneId"] = .string(pane) }
        if let direction { params["direction"] = .string(direction) }
        let response = try sendRequest(command: "pane.split", params: params)
        try handleCreateResponse(response)
    }
}

struct PaneList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List panes in a tab."
    )

    @Option(name: .long, help: "Tab ID (defaults to current tab).")
    var tab: String?

    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .table

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let tab { params["tabId"] = .string(tab) }
        let response = try sendRequest(command: "pane.list", params: params)
        try handleListResponse(
            response,
            arrayKey: "panes",
            headers: ["ID", "DIRECTORY", "STATE", "FOCUSED"],
            rowBuilder: { item in
                guard case .object(let obj) = item else { return [] }
                return [
                    obj["id"]?.stringValue ?? "",
                    obj["workingDirectory"]?.stringValue ?? "",
                    obj["state"]?.stringValue ?? "",
                    obj["focused"]?.boolValue == true ? "yes" : "",
                ]
            },
            activeKey: "focused",
            format: format
        )
    }
}

struct PaneClose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "Close a pane."
    )

    @Option(name: .long, help: "Pane ID to close (defaults to current pane).")
    var pane: String?

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let pane { params["paneId"] = .string(pane) }
        let response = try sendRequest(command: "pane.close", params: params)
        try handleVoidResponse(response)
    }
}

struct PaneFocus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus a pane by ID or direction (up/down/left/right)."
    )

    @Argument(help: "Pane ID (UUID) or direction (up, down, left, right).")
    var target: String

    @Option(name: .long, help: "Source pane ID (defaults to current pane).")
    var pane: String?

    func run() throws {
        var params: [String: IPCValue] = ["target": .string(target)]
        if let pane { params["paneId"] = .string(pane) }
        let response = try sendRequest(command: "pane.focus", params: params)
        try handleVoidResponse(response)
    }
}

// MARK: - Status

struct StatusGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Manage pane status labels.",
        subcommands: [
            StatusSet.self,
            StatusClear.self,
        ]
    )
}

struct StatusSet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a status label for the current pane."
    )

    @Option(name: .long, help: "Status label text.")
    var label: String

    func run() throws {
        let response = try sendRequest(command: "status.set", params: ["label": .string(label)])
        try handleVoidResponse(response)
    }
}

struct StatusClear: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear the status label for the current pane."
    )

    func run() throws {
        let response = try sendRequest(command: "status.clear")
        try handleVoidResponse(response)
    }
}

// MARK: - Notify

struct NotifyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send a macOS notification."
    )

    @Argument(help: "Notification message.")
    var message: String

    @Option(name: .long, help: "Notification title.")
    var title: String?

    @Option(name: .long, help: "Notification subtitle.")
    var subtitle: String?

    func run() throws {
        var params: [String: IPCValue] = ["message": .string(message)]
        if let title { params["title"] = .string(title) }
        if let subtitle { params["subtitle"] = .string(subtitle) }
        let response = try sendRequest(command: "notify", params: params)
        try handleVoidResponse(response)
    }
}

// MARK: - Worktree

struct WorktreeGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "worktree",
        abstract: "Manage worktree-backed spaces.",
        subcommands: [
            WorktreeCreate.self,
            WorktreeRemove.self,
        ]
    )
}

struct WorktreeCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new worktree-backed space."
    )

    @Argument(help: "Branch name for the worktree.")
    var branchName: String

    @Flag(name: .long, help: "Check out an existing branch instead of creating a new one.")
    var existing: Bool = false

    @Option(name: .long, help: "Override repo root path.")
    var path: String?

    @Option(name: .long, help: "Target workspace UUID.")
    var workspace: String?

    func run() throws {
        var params: [String: IPCValue] = ["branchName": .string(branchName)]
        if existing { params["existing"] = .bool(true) }
        if let path { params["path"] = .string(path) }
        if let workspace { params["workspaceId"] = .string(workspace) }
        let response = try sendRequest(command: "worktree.create", params: params, timeout: 600)
        if response.ok {
            let spaceId = response.result?["space_id"]?.stringValue ?? ""
            let existed = response.result?["existed"]?.boolValue ?? false
            CommandContext.lastCreateId = spaceId
            print(spaceId)
            if existed {
                FileHandle.standardError.write(Data("Note: Focused existing worktree space.\n".utf8))
            }
        } else if let error = response.error {
            throw CLIError.fromIPCError(error)
        } else {
            throw CLIError.general("Unexpected response from aterm")
        }
    }
}

struct WorktreeRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a worktree-backed space and its git worktree."
    )

    @Argument(help: "Space ID (UUID) of the worktree space to remove.")
    var spaceId: String

    @Flag(name: .long, help: "Force removal even with uncommitted changes.")
    var force: Bool = false

    func run() throws {
        var params: [String: IPCValue] = ["spaceId": .string(spaceId)]
        if force { params["force"] = .bool(true) }
        let response = try sendRequest(command: "worktree.remove", params: params, timeout: 30)
        try handleVoidResponse(response)
    }
}
