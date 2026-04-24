import SwiftUI

extension SectionKind {
    /// Per-section tint used by tab pills, glyphs, and placeholder accents.
    var tint: Color {
        switch self {
        case .claude:   .orange
        case .terminal: .accentColor
        }
    }
}
