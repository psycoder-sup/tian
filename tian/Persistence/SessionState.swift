import Foundation

// MARK: - Session State (Top-Level)

/// The complete persisted state of a tian session.
struct SessionState: Codable, Sendable, Equatable {
    let version: Int
    let savedAt: Date
    let activeWorkspaceId: UUID
    let workspaces: [WorkspaceState]
}

// MARK: - Workspace State

struct WorkspaceState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let activeSpaceId: UUID
    let defaultWorkingDirectory: String?
    let spaces: [SpaceState]
    let windowFrame: WindowFrame?
    let isFullscreen: Bool?
    /// Added in schema v5. Optional so v4 records decode without migration.
    /// Defaults applied at runtime: visible = true, width = 320.
    let inspectPanelVisible: Bool?
    let inspectPanelWidth: Double?

    init(
        id: UUID,
        name: String,
        activeSpaceId: UUID,
        defaultWorkingDirectory: String?,
        spaces: [SpaceState],
        windowFrame: WindowFrame?,
        isFullscreen: Bool?,
        inspectPanelVisible: Bool? = nil,
        inspectPanelWidth: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.activeSpaceId = activeSpaceId
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.spaces = spaces
        self.windowFrame = windowFrame
        self.isFullscreen = isFullscreen
        self.inspectPanelVisible = inspectPanelVisible
        self.inspectPanelWidth = inspectPanelWidth
    }
}

// MARK: - Window Frame

struct WindowFrame: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Space State (v4)
//
// v4 replaces the flat `tabs: [TabState]` + `activeTabId` pair with two
// sections (Claude + Terminal) plus layout metadata. The v3 shape is
// rewritten by `SessionStateMigrator.migrations[3]`.

struct SpaceState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let defaultWorkingDirectory: String?
    let worktreePath: String?
    let claudeSection: SectionState
    let terminalSection: SectionState
    let terminalVisible: Bool
    let dockPosition: DockPosition
    let splitRatio: Double
    let focusedSectionKind: SectionKind

    init(
        id: UUID,
        name: String,
        defaultWorkingDirectory: String?,
        worktreePath: String? = nil,
        claudeSection: SectionState,
        terminalSection: SectionState,
        terminalVisible: Bool,
        dockPosition: DockPosition,
        splitRatio: Double,
        focusedSectionKind: SectionKind
    ) {
        self.id = id
        self.name = name
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.worktreePath = worktreePath
        self.claudeSection = claudeSection
        self.terminalSection = terminalSection
        self.terminalVisible = terminalVisible
        self.dockPosition = dockPosition
        self.splitRatio = splitRatio
        self.focusedSectionKind = focusedSectionKind
    }
}

// MARK: - Section State (v4)

struct SectionState: Codable, Sendable, Equatable {
    let id: UUID
    let kind: SectionKind
    let activeTabId: UUID?
    let tabs: [TabState]
}

// MARK: - Tab State (v4)

struct TabState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String?
    let activePaneId: UUID
    let root: PaneNodeState
    /// Required in v4 — migration sets it explicitly on every tab, and
    /// freshly-created tabs set it from their owning section (NG5).
    let sectionKind: SectionKind
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
