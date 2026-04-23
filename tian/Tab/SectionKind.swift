import Foundation

/// Discriminator identifying whether a Section holds Claude panes or Terminal panes.
enum SectionKind: String, Sendable, Codable, Equatable, CaseIterable {
    case claude
    case terminal
}
