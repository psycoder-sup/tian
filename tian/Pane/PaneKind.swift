import Foundation

/// Discriminator identifying whether a pane holds a Claude session or a plain
/// terminal shell. Raw values are persisted (session state) and emitted over
/// IPC, so they must stay `"claude"` / `"terminal"`.
enum PaneKind: String, Codable, Sendable, CaseIterable, Equatable {
    case claude
    case terminal
}
