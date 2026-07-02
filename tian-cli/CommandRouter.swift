import ArgumentParser
import Foundation

// MARK: - Helpers

/// Sends an IPC request and returns the response, throwing on error.
private func sendRequest(command: String, params: [String: IPCValue] = [:], timeout: Int? = nil) throws -> IPCResponse {
    let env = try TianEnvironment.fromEnvironment()
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
        throw CLIError.general("Unexpected response from tian")
    }
}

/// Processes a response that has no meaningful result (focus/close commands).
private func handleVoidResponse(_ response: IPCResponse) throws {
    if !response.ok {
        if let error = response.error {
            throw CLIError.fromIPCError(error)
        }
        throw CLIError.general("Unexpected response from tian")
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
        throw CLIError.general("Unexpected response from tian")
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

    @Flag(name: .long, help: "Create the space in the background without switching to it.")
    var background: Bool = false

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let name { params["name"] = .string(name) }
        if let workspace { params["workspaceId"] = .string(workspace) }
        if background { params["background"] = .bool(true) }
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

    @Flag(name: .long, help: "Create the tab in the background without switching to it.")
    var background: Bool = false

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let space { params["spaceId"] = .string(space) }
        if let directory { params["directory"] = .string(directory) }
        if background { params["background"] = .bool(true) }
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

    @Option(name: .long, help: "Filter by section: claude or terminal (defaults to both).")
    var section: String?

    @Option(name: .long, help: "Output format.")
    var format: OutputFormat = .table

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let space { params["spaceId"] = .string(space) }
        if let section { params["section"] = .string(section) }
        let response = try sendRequest(command: "tab.list", params: params)
        try handleListResponse(
            response,
            arrayKey: "tabs",
            headers: ["ID", "SECTION", "TITLE", "PANES", "ACTIVE"],
            rowBuilder: { item in
                guard case .object(let obj) = item else { return [] }
                return [
                    obj["id"]?.stringValue ?? "",
                    obj["section"]?.stringValue ?? "",
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
            PaneSend.self,
            PaneCapture.self,
            PaneSetRestoreCommand.self,
            PaneSetDirectory.self,
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

    @Flag(name: .long, help: "Create the pane without moving keyboard focus to it.")
    var background: Bool = false

    func run() throws {
        var params: [String: IPCValue] = [:]
        if let pane { params["paneId"] = .string(pane) }
        if let direction { params["direction"] = .string(direction) }
        if background { params["background"] = .bool(true) }
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
            headers: ["ID", "SECTION", "DIRECTORY", "STATE", "SESSION", "LABEL", "FOCUSED"],
            rowBuilder: { item in
                guard case .object(let obj) = item else { return [] }
                return [
                    obj["id"]?.stringValue ?? "",
                    obj["section"]?.stringValue ?? "",
                    obj["workingDirectory"]?.stringValue ?? "",
                    obj["state"]?.stringValue ?? "",
                    obj["sessionState"]?.stringValue ?? "",
                    obj["label"]?.stringValue ?? "",
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

struct PaneSend: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send text/input to a pane's terminal (as if pasted).",
        discussion: """
        Input is delivered via the terminal's paste path: multi-line text is framed as \
        a single bracketed paste when the running program supports it (e.g. an \
        interactive Claude session or a shell line editor), so it is not run line by \
        line. By default the input is then submitted with Enter; use --no-enter to \
        stage it without submitting. Pass '-' as the text to read it from stdin.
        """
    )

    @Argument(help: "Text to send. Use '-' to read it from stdin.")
    var text: String

    @Option(name: .long, help: "Target pane ID (defaults to current pane).")
    var pane: String?

    @Flag(inversion: .prefixedNo, help: "Submit the input with Enter.")
    var enter: Bool = true

    func run() throws {
        let payload: String
        if text == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            payload = String(decoding: data, as: UTF8.self)
        } else {
            payload = text
        }

        var params: [String: IPCValue] = [
            "text": .string(payload),
            "enter": .bool(enter),
        ]
        if let pane { params["paneId"] = .string(pane) }
        let response = try sendRequest(command: "pane.send", params: params)
        try handleVoidResponse(response)
    }
}

struct PaneCapture: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Capture a pane's terminal output to stdout.",
        discussion: """
        Prints the pane's visible screen (or the full scrollback with --scrollback). \
        Useful for reading the output/logs of another session.
        """
    )

    @Option(name: .long, help: "Target pane ID (defaults to current pane).")
    var pane: String?

    @Flag(name: .long, help: "Include the full scrollback, not just the visible viewport.")
    var scrollback: Bool = false

    @Flag(inversion: .prefixedNo, help: "Strip ANSI escape sequences.")
    var strip: Bool = true

    func run() throws {
        var params: [String: IPCValue] = [
            "scrollback": .bool(scrollback),
            "strip": .bool(strip),
        ]
        if let pane { params["paneId"] = .string(pane) }
        // Large scrollback reads can exceed the default 5s timeout.
        let response = try sendRequest(command: "pane.capture", params: params, timeout: 15)
        if response.ok {
            let text = response.result?["text"]?.stringValue ?? ""
            // Print exactly once, ensuring a single trailing newline.
            print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
            if response.result?["truncated"]?.boolValue == true {
                FileHandle.standardError.write(Data("Note: output truncated to the most recent ~900 KB.\n".utf8))
            }
        } else if let error = response.error {
            throw CLIError.fromIPCError(error)
        } else {
            throw CLIError.general("Unexpected response from tian")
        }
    }
}

struct PaneSetRestoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-restore-command",
        abstract: "Set a command to replay when this pane is restored."
    )

    @Option(name: .long, help: "Command to replay on restore.")
    var command: String

    func run() throws {
        let response = try sendRequest(command: "pane.set-restore-command", params: ["command": .string(command)])
        try handleVoidResponse(response)
    }
}

struct PaneSetDirectory: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-directory",
        abstract: "Associate a pane with a working directory (e.g. a worktree a Claude session entered), so the sidebar shows that directory's branch."
    )

    @Argument(help: "Absolute path of the directory the pane is working in.")
    var directory: String

    @Option(name: .long, help: "Pane ID (defaults to current pane).")
    var pane: String?

    func run() throws {
        var params: [String: IPCValue] = ["directory": .string(directory)]
        if let pane { params["paneId"] = .string(pane) }
        let response = try sendRequest(command: "pane.set-directory", params: params)
        try handleVoidResponse(response)
    }
}

// MARK: - Status

struct StatusGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Manage pane status.",
        subcommands: [
            StatusSet.self,
            StatusClear.self,
        ]
    )
}

struct StatusSet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a status label and/or session state for the current pane."
    )

    @Option(name: .long, help: "Status label text.")
    var label: String?

    @Option(name: .long, help: "Claude session state (active, busy, idle, needs_attention, inactive).")
    var state: String?

    func run() throws {
        guard label != nil || state != nil else {
            throw CLIError.general("At least one of --label or --state must be provided.")
        }

        var params: [String: IPCValue] = [:]
        if let label {
            params["label"] = .string(label)
        }
        if let state {
            params["state"] = .string(state)
        }

        let response = try sendRequest(command: "status.set", params: params)
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

    @Option(name: .long, help: "Base git ref (branch/tag/commit) to create the branch from. Defaults to current HEAD.")
    var base: String?

    @Flag(name: .long, help: "Create the space in the background without switching to it.")
    var background: Bool = false

    @Option(name: .long, help: "Override repo root path.")
    var path: String?

    @Option(name: .long, help: "Target workspace UUID.")
    var workspace: String?

    @Option(name: .long, help: "Output: id (space id), ids (space tab pane), or json.")
    var format: WorktreeCreateOutput = .id

    func run() throws {
        var params: [String: IPCValue] = ["branchName": .string(branchName)]
        if existing { params["existing"] = .bool(true) }
        if let base { params["base"] = .string(base) }
        if background { params["background"] = .bool(true) }
        if let path { params["path"] = .string(path) }
        if let workspace { params["workspaceId"] = .string(workspace) }
        let response = try sendRequest(command: "worktree.create", params: params, timeout: 600)
        if response.ok {
            let spaceId = response.result?["space_id"]?.stringValue ?? ""
            let tabId = response.result?["tab_id"]?.stringValue ?? ""
            let paneId = response.result?["pane_id"]?.stringValue ?? ""
            let existed = response.result?["existed"]?.boolValue ?? false
            CommandContext.lastCreateId = spaceId
            switch format {
            case .id:
                print(spaceId)
            case .ids:
                print([spaceId, tabId, paneId].joined(separator: " "))
            case .json:
                if let result = response.result {
                    print(OutputFormatter.formatJSON(.object(result)))
                }
            }
            if existed {
                let note = background
                    ? "Note: Worktree space already exists (left in background).\n"
                    : "Note: Focused existing worktree space.\n"
                FileHandle.standardError.write(Data(note.utf8))
            }
        } else if let error = response.error {
            throw CLIError.fromIPCError(error)
        } else {
            throw CLIError.general("Unexpected response from tian")
        }
    }
}

enum WorktreeCreateOutput: String, ExpressibleByArgument, CaseIterable {
    case id
    case ids
    case json
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

    @Flag(name: .long, help: "Also delete the branch after removing the worktree (git branch -d; with --force, -D). An unmerged branch is kept.")
    var deleteBranch: Bool = false

    func run() throws {
        var params: [String: IPCValue] = ["spaceId": .string(spaceId)]
        if force { params["force"] = .bool(true) }
        if deleteBranch { params["deleteBranch"] = .bool(true) }
        let response = try sendRequest(command: "worktree.remove", params: params, timeout: 30)
        try handleVoidResponse(response)

        guard deleteBranch else { return }
        let branch = response.result?["branch"]?.stringValue
        let reason = response.result?["branch_kept_reason"]?.stringValue
        if response.result?["branch_deleted"]?.boolValue == true, let branch {
            print("Deleted branch \(branch).")
        } else if let branch {
            switch reason {
            case "unmerged":
                print("Branch \(branch) kept (unmerged — re-run with --force to delete).")
            case "not found":
                print("Branch \(branch) not found (nothing to delete).")
            default:
                print("Branch \(branch) could not be deleted (see tian logs).")
            }
        } else if reason == "no branch" {
            // Worktree removed, but it had no branch checked out (detached HEAD).
            print("No branch deleted (worktree had no branch checked out).")
        }
        // Otherwise (reason nil, no branch): removal was preempted or not a
        // worktree space — nothing branch-related to report.
    }
}

// MARK: - Git

struct GitGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "git",
        abstract: "Refresh git-derived sidebar state.",
        subcommands: [
            GitRefresh.self,
        ]
    )
}

struct GitRefresh: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refresh",
        abstract: "Evict the PR cache and refresh git status for the current Space.",
        discussion: "Intended to run after commands that change PR or branch state without modifying local refs (e.g. `gh pr create` against an already-pushed branch), so the sidebar badge updates without waiting for the cache TTL."
    )

    func run() throws {
        let response = try sendRequest(command: "git.refresh")
        try handleVoidResponse(response)
    }
}
