import Foundation

// MARK: - Session State (Top-Level)

/// The complete persisted state of an aterm session.
/// Maps 1:1 to the JSON schema defined in the M5 persistence spec.
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
}

// MARK: - Window Frame

struct WindowFrame: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Space State

struct SpaceState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let activeTabId: UUID
    let defaultWorkingDirectory: String?
    let tabs: [TabState]
}

// MARK: - Tab State

struct TabState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String?
    let activePaneId: UUID
    let root: PaneNodeState
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
    func toState() -> PaneNodeState {
        switch self {
        case .leaf(let paneID, let workingDirectory):
            return .pane(PaneLeafState(paneID: paneID, workingDirectory: workingDirectory))
        case .split(_, let direction, let ratio, let first, let second):
            return .split(PaneSplitState(
                direction: direction.stateValue,
                ratio: ratio,
                first: first.toState(),
                second: second.toState()
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
