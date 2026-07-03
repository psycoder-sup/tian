import Foundation

/// Placement of the attached terminal panel relative to the Claude pane.
enum DockPosition: String, Sendable, Codable, Equatable {
    case right
    case bottom
}
