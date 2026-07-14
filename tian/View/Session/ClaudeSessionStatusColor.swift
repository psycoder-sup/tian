import SwiftUI

extension ClaudeSessionState {
    /// The shared flat swatch color for the four states that have one. The
    /// sidebar status dot (`SessionDotView`) and the overview card border both
    /// read this, so those two can't drift apart. (Not yet the whole app's
    /// single source: `PaneView`'s status border still hardcodes the same
    /// needs-attention orange — a candidate to migrate here too.) `nil` for
    /// `.busy` (whose dot is a rainbow gradient, not a flat swatch) and
    /// `.inactive` (no swatch — the sidebar shows nothing).
    var solidStatusColor: Color? {
        switch self {
        case .needsAttention:  Color(red: 1.0, green: 0.624, blue: 0.039)
        case .failed:          Color(red: 1.0, green: 0.231, blue: 0.188)
        case .active:          Color(red: 0.204, green: 0.78, blue: 0.349)
        case .idle:            Color(red: 0.557, green: 0.557, blue: 0.576)
        case .busy, .inactive: nil
        }
    }

    /// Status color used for the session-overview card border. Delegates to the
    /// shared `solidStatusColor` for every state but two: `.busy` shows a solid,
    /// hand-tuned purple-blue in the spirit of the busy dot's animated gradient
    /// (that dot has no single hue to match; a static border color is enough
    /// here), and `.inactive` is `nil` (the caller substitutes a faint neutral
    /// edge).
    var overviewBorderColor: Color? {
        switch self {
        case .busy:     Color(red: 0.55, green: 0.35, blue: 0.9)
        case .inactive: nil
        default:        solidStatusColor
        }
    }
}
