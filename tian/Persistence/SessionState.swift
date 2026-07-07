import Foundation

// MARK: - Session State (Top-Level)

/// The complete persisted state of a tian session.
struct SessionState: Codable, Sendable, Equatable {
    let version: Int
    let savedAt: Date
    let activeWorkspaceId: UUID
    let workspaces: [WorkspaceState]
}

// MARK: - Workspace State (v7)
//
// v7 flattens the Workspace → Space → Section → Tab hierarchy into a flat list
// of Sessions. `spaces` becomes `sessions`, `activeSpaceId` becomes
// `activeSessionId`. The v6 shape is rewritten by
// `SessionStateMigrator.migrations[6]`.

struct WorkspaceState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let activeSessionId: UUID
    let defaultWorkingDirectory: String?
    let sessions: [SessionRecord]
    let windowFrame: WindowFrame?
    let isFullscreen: Bool?
    /// Added in schema v5. Optional so v4 records decode without migration.
    /// Defaults applied at runtime: visible = true, width = 320.
    let inspectPanelVisible: Bool?
    let inspectPanelWidth: Double?
    /// Added in schema v6. Optional so v5 records decode without migration.
    /// Default applied at runtime: activeTab = .files. This is the inspect
    /// panel's selected tab (files / diff / branch), unrelated to the removed
    /// terminal tab bar.
    let activeTab: String?
    /// Added in schema v8. The SSH target when this is a remote workspace; nil
    /// (absent key) for a local one, so pre-v8 records decode without migration.
    let remote: RemoteConnectionState?

    init(
        id: UUID,
        name: String,
        activeSessionId: UUID,
        defaultWorkingDirectory: String?,
        sessions: [SessionRecord],
        windowFrame: WindowFrame?,
        isFullscreen: Bool?,
        inspectPanelVisible: Bool? = nil,
        inspectPanelWidth: Double? = nil,
        activeTab: String? = nil,
        remote: RemoteConnectionState? = nil
    ) {
        self.id = id
        self.name = name
        self.activeSessionId = activeSessionId
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.sessions = sessions
        self.windowFrame = windowFrame
        self.isFullscreen = isFullscreen
        self.inspectPanelVisible = inspectPanelVisible
        self.inspectPanelWidth = inspectPanelWidth
        self.activeTab = activeTab
        self.remote = remote
    }
}

// MARK: - Window Frame

struct WindowFrame: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Session Record (v7)
//
// A Session is one Claude pane plus an optional attached terminal panel. The
// Claude side is a single leaf (`claudePane`); a nil value (an old placeholder
// record, or a v6→v7 terminal-only space) is re-seeded as a fresh Claude pane on
// restore. The terminal side is a full split tree (`terminalRoot`), nil when no
// terminal panel exists yet. Readers are not persisted, so there are no reader
// records here.

struct SessionRecord: Codable, Sendable, Equatable {
    let id: UUID
    /// User-assigned name, or `nil` for the auto-derived name. Optional so a
    /// pre-rename v7 file (which carried a non-optional `name` key) decodes as
    /// `nil` → auto. Was `name` in the initial v7 shape.
    let customName: String?
    let defaultWorkingDirectory: String?
    let worktreePath: String?
    /// The single Claude pane leaf. `nil` when the session had no live Claude
    /// process at save time; on restore this is re-seeded as a fresh Claude pane.
    let claudePane: PaneLeafState?
    /// The attached terminal panel's split tree, or `nil` when no terminal
    /// panel has been created.
    let terminalRoot: PaneNodeState?
    /// Focused pane within `terminalRoot`; `nil` when there is no terminal.
    let terminalFocusedPaneId: UUID?
    let terminalVisible: Bool
    let dockPosition: DockPosition
    let splitRatio: Double
    /// Which area (claude / terminal) had focus. Was `focusedSectionKind`.
    let focusedArea: PaneKind
    /// Orchestrator → implementer link (sidebar nesting). Was `parentSpaceID`.
    let parentSessionID: UUID?

    init(
        id: UUID,
        customName: String? = nil,
        defaultWorkingDirectory: String?,
        worktreePath: String? = nil,
        claudePane: PaneLeafState?,
        terminalRoot: PaneNodeState? = nil,
        terminalFocusedPaneId: UUID? = nil,
        terminalVisible: Bool,
        dockPosition: DockPosition,
        splitRatio: Double,
        focusedArea: PaneKind,
        parentSessionID: UUID? = nil
    ) {
        self.id = id
        self.customName = customName
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.worktreePath = worktreePath
        self.claudePane = claudePane
        self.terminalRoot = terminalRoot
        self.terminalFocusedPaneId = terminalFocusedPaneId
        self.terminalVisible = terminalVisible
        self.dockPosition = dockPosition
        self.splitRatio = splitRatio
        self.focusedArea = focusedArea
        self.parentSessionID = parentSessionID
    }
}

// MARK: - Pane Node State

/// Codable representation of the pane split tree.
/// Uses a `"type"` discriminator field: `"pane"` for leaf, `"split"` for split.
indirect enum PaneNodeState: Sendable, Equatable {
    case pane(PaneLeafState)
    case split(PaneSplitState)
}

struct PaneLeafState: Codable, Sendable, Equatable {
    let paneID: UUID
    let workingDirectory: String
    let restoreCommand: String?
    let claudeSessionState: ClaudeSessionState?

    init(paneID: UUID, workingDirectory: String, restoreCommand: String? = nil, claudeSessionState: ClaudeSessionState? = nil) {
        self.paneID = paneID
        self.workingDirectory = workingDirectory
        self.restoreCommand = restoreCommand
        self.claudeSessionState = claudeSessionState
    }
}

struct PaneSplitState: Codable, Sendable, Equatable {
    let direction: String
    let ratio: Double
    let first: PaneNodeState
    let second: PaneNodeState
}

// MARK: - PaneNodeState Codable

extension PaneNodeState: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "pane":
            self = .pane(try PaneLeafState(from: decoder))
        case "split":
            self = .split(try PaneSplitState(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown pane node type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let leaf):
            try container.encode("pane", forKey: .type)
            try leaf.encode(to: encoder)
        case .split(let split):
            try container.encode("split", forKey: .type)
            try split.encode(to: encoder)
        }
    }
}

// MARK: - PaneNodeState Traversal

extension PaneNodeState {
    /// The depth-first first leaf (split → first). Used to collapse a stray
    /// Claude split down to its single leaf, and as the fallback focus target
    /// for a restored terminal tree.
    var firstLeaf: PaneLeafState {
        switch self {
        case .pane(let leaf):
            return leaf
        case .split(let split):
            return split.first.firstLeaf
        }
    }
}

// MARK: - Runtime → State Conversion

extension PaneNode {
    /// Converts the runtime PaneNode to its Codable state representation.
    func toState(restoreCommands: [UUID: String] = [:], sessionStates: [UUID: ClaudeSessionState] = [:]) -> PaneNodeState {
        switch self {
        case .leaf(let paneID, let workingDirectory):
            return .pane(PaneLeafState(
                paneID: paneID,
                workingDirectory: workingDirectory,
                restoreCommand: restoreCommands[paneID],
                claudeSessionState: sessionStates[paneID]
            ))
        case .split(_, let direction, let ratio, let first, let second):
            return .split(PaneSplitState(
                direction: direction.stateValue,
                ratio: ratio,
                first: first.toState(restoreCommands: restoreCommands, sessionStates: sessionStates),
                second: second.toState(restoreCommands: restoreCommands, sessionStates: sessionStates)
            ))
        }
    }
}

extension SplitDirection {
    /// The string representation used in the persisted JSON.
    var stateValue: String {
        switch self {
        case .horizontal: "horizontal"
        case .vertical: "vertical"
        }
    }

    /// Creates a SplitDirection from its persisted string representation.
    static func from(stateValue: String) -> SplitDirection? {
        switch stateValue {
        case "horizontal": .horizontal
        case "vertical": .vertical
        default: nil
        }
    }
}
